import Foundation

/// 파일별 증분 캐시 — `(path, mtime, size)` 가 같으면 재파싱하지 않는다. 디스크에 영속화한다.
///
/// 사용자가 매일 코딩하면 사실상 모든 세션 파일이 "이번 달 수정"(수백 MB)이라 mtime 필터만으론
/// 매 새로고침마다 전수 파싱을 피할 수 없다. 변경된 파일만 다시 읽도록 캐시하고(정상 상태 ~0.1s),
/// 캐시를 디스크에 저장해 **콜드 스타트(전체 파싱 ~수십초)를 최초 1회로** 제한한다(배터리).
actor LocalUsageCache {
    static let shared = LocalUsageCache()

    private struct Blob: Codable { let mtime: Date; let size: Int; let entries: [LocalUsageReader.Entry] }
    private struct CodexBlob: Codable {
        let mtime: Date
        let size: Int
        let rollout: LocalUsageReader.CodexParsedRollout
    }

    /// rollout 파일의 세션 id 만 담는 경량 항목 — blob 없이도 부모 후보를 가려내기 위한 인덱스.
    /// `sessionID == nil`(= 이 파일엔 세션 id 가 없다)도 저장한다. 그 부정 결과를 안 남기면
    /// 부모가 사라진 fork 하나 때문에 매 새로고침마다 전 rollout 을 다시 열게 된다.
    private struct CodexSessionProbe: Codable {
        let mtime: Date
        let size: Int
        let sessionID: String?
    }

    private struct Snapshot: Codable {
        var claude: [String: Blob]
        var codex: [String: CodexBlob]
        var codexSessionIDs: [String: CodexSessionProbe]
        var gemini: [String: Blob]
        var grok: [String: Blob]
        var pi: [String: Blob]
        var codexParserVersion: Int
        var codexSessionIndexVersion: Int
        var grokParserVersion: Int
        var piParserVersion: Int

        init(claude: [String: Blob], codex: [String: CodexBlob],
             codexSessionIDs: [String: CodexSessionProbe], gemini: [String: Blob],
             grok: [String: Blob], pi: [String: Blob], codexParserVersion: Int,
             codexSessionIndexVersion: Int, grokParserVersion: Int, piParserVersion: Int) {
            self.claude = claude
            self.codex = codex
            self.codexSessionIDs = codexSessionIDs
            self.gemini = gemini
            self.grok = grok
            self.pi = pi
            self.codexParserVersion = codexParserVersion
            self.codexSessionIndexVersion = codexSessionIndexVersion
            self.grokParserVersion = grokParserVersion
            self.piParserVersion = piParserVersion
        }

        // 하위호환: gemini/grok/codexSessionIDs 키가 없는 구버전 스냅샷도 로드(콜드 스타트 재발 방지).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            claude = try c.decodeIfPresent([String: Blob].self, forKey: .claude) ?? [:]
            // parser v3 이하는 Codex blob에 최종 Entry 배열을 저장. 새 parsed-rollout 형태와
            // 호환되지 않으므로 해당 필드만 비우고 다른 provider 캐시는 그대로 살림.
            codex = (try? c.decode([String: CodexBlob].self, forKey: .codex)) ?? [:]
            codexSessionIDs = (try? c.decode([String: CodexSessionProbe].self, forKey: .codexSessionIDs)) ?? [:]
            gemini = try c.decodeIfPresent([String: Blob].self, forKey: .gemini) ?? [:]
            grok = try c.decodeIfPresent([String: Blob].self, forKey: .grok) ?? [:]
            pi = try c.decodeIfPresent([String: Blob].self, forKey: .pi) ?? [:]
            codexParserVersion = try c.decodeIfPresent(Int.self, forKey: .codexParserVersion) ?? 0
            codexSessionIndexVersion = try c.decodeIfPresent(Int.self, forKey: .codexSessionIndexVersion) ?? 0
            grokParserVersion = try c.decodeIfPresent(Int.self, forKey: .grokParserVersion) ?? 0
            piParserVersion = try c.decodeIfPresent(Int.self, forKey: .piParserVersion) ?? 0
        }
    }

    /// fork replay 및 동일 상태 재기록 처리 변경 시 Codex blob만 재파싱한다.
    private static let codexParserVersion = 4
    /// **세션 id 추출 규칙**(`session_meta` 의 id/session_id 해석·probe 종료 조건)이 바뀔 때만 올린다.
    /// resolver 변경으로 오르는 `codexParserVersion` 과 분리 — 같이 묶으면 replay 로직을 고칠 때마다
    /// 인덱스가 통째로 날아가 다음 고아 조회에서 전수 probe 가 되살아난다.
    /// v2: 읽기 실패를 "세션 id 없음"으로 저장하던 v1 항목을 버린다(구분이 불가능해 신뢰할 수 없음).
    private static let codexSessionIndexVersion = 2
    /// Grok 토큰 매핑(캐시분 분리·비용 신뢰 조건) 변경 시 Grok blob만 재파싱한다.
    private static let grokParserVersion = 1
    /// Pi usage mapping/dedup semantics. Bump when the direct usage paths or bucket mapping changes.
    private static let piParserVersion = 2

    private var claudeCache: [String: Blob] = [:]
    private var codexCache: [String: CodexBlob] = [:]
    private var codexSessionIDs: [String: CodexSessionProbe] = [:]
    private var geminiCache: [String: Blob] = [:]
    private var grokCache: [String: Blob] = [:]
    private var piCache: [String: Blob] = [:]
    private var loaded = false
    private var dirty = false
    private var lastSave: Date?

    // 테스트 시임 — 기본값은 실환경(실 로그 루트·Application Support·실시간).
    private let claudeRoot: URL?
    private let codexRoot: URL?
    private let codexRoots: [URL]?
    private let geminiRoot: URL?
    private let grokRoot: URL?
    private let geminiRoots: [URL]?
    private let grokRoots: [URL]?
    private let piRoots: [URL]?
    private let fileURL: URL
    private let now: @Sendable () -> Date
    /// throwing probe 를 쓴다 — 읽기 실패(throw)와 "metadata 없음"(`nil`)은 인덱스에 남길지가 다르다.
    private let codexProbe: @Sendable (URL) throws -> String?

    /// 다중 루트 시임. `claudeRoot` 단일 지정과 배타적이며, 프로덕션의 다중 루트 순회 브랜치를
    /// 테스트가 실제로 밟게 하려고 둔다(단일 루트만 주면 루프가 1회로 단락돼 그 브랜치가 안 덮인다).
    private let claudeRoots: [URL]?

    init(claudeRoot: URL? = nil, claudeRoots: [URL]? = nil,
         codexRoot: URL? = nil, codexRoots: [URL]? = nil,
         geminiRoot: URL? = nil, grokRoot: URL? = nil,
         geminiRoots: [URL]? = nil, grokRoots: [URL]? = nil,
         piRoots: [URL]? = nil,
         fileURL: URL? = nil, now: @escaping @Sendable () -> Date = Date.init,
         codexProbe: @escaping @Sendable (URL) throws -> String? = {
             try LocalUsageReader.probeCodexRolloutSessionID(at: $0)
         }) {
        // 둘 다 주는 호출은 없다(프로덕션은 둘 다 nil, 테스트는 하나씩). precondition 으로 막지 않는 이유는
        // 릴리스 빌드에서도 살아 있어, 잘못 써도 결과가 "테스트가 엉뚱한 루트를 본다"에 그치는 실수를
        // 앱 종료로 키우기 때문이다. 우선순위는 claudeRoots.
        self.claudeRoots = claudeRoots
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.codexRoots = codexRoots
        self.geminiRoot = geminiRoot
        self.geminiRoots = geminiRoots
        self.grokRoot = grokRoot
        self.grokRoots = grokRoots
        self.piRoots = piRoots
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.now = now
        self.codexProbe = codexProbe
    }

    private static let defaultFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    func claudeEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        // 루트가 여럿이다(CLI 기본 위치 + CLAUDE_CONFIG_DIR + Claude Desktop 임베디드 세션).
        // blob 캐시 키가 절대경로라 루트가 늘어도 캐시는 그대로 재사용되고, 같은 턴이 여러 루트에
        // 복사돼 있어도 전역 dedup 이 한 번만 센다.
        let roots = claudeRoots ?? claudeRoot.map { [$0] } ?? LocalUsageReader.claudeProjectRoots
        var all: [LocalUsageReader.Entry] = []
        for root in roots {
            all += collect(root: root, since: modifiedSince, cache: &claudeCache) {
                LocalUsageReader.parseClaudeFile($0, fmt: fmt)
            }
        }
        saveIfNeeded()
        return LocalUsageReader.dedupKeepMax(all)
    }

    func codexEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        let roots = codexRoots ?? codexRoot.map { [$0] } ?? LocalUsageReader.codexSessionRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "codex"))
        let (rollouts, includedPaths) = collectCodexRollouts(
            roots: roots,
            since: modifiedSince,
            fmt: fmt
        )
        let entries = LocalUsageReader.resolveCodexRollouts(rollouts, includedPaths: includedPaths)
        saveIfNeeded()
        return entries
    }

    /// 테스트 관측용 — 삭제된 rollout 의 항목이 인덱스에 남아 무한히 쌓이지 않는지 확인한다.
    func codexSessionIndexCount() -> Int {
        ensureLoaded()
        return codexSessionIDs.count
    }

    func geminiEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        let roots = geminiRoots ?? geminiRoot.map { [$0] } ?? LocalUsageReader.geminiScanRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "gemini"))
        var all: [LocalUsageReader.Entry] = []
        for root in roots {
            all += collect(root: root, since: modifiedSince,
                           cache: &geminiCache, allowJSON: true) {
                LocalUsageReader.parseGeminiFile($0, fmt: fmt)
            }
        }
        saveIfNeeded()
        return LocalUsageReader.dedupKeepMax(all)
    }

    func grokEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        // updates.jsonl 만, 그리고 서브에이전트 세션은 제외한다(부모 턴에 이미 포함). 이 판정은
        // 파싱 캐시 **앞**에 있어야 한다 — blob 은 updates.jsonl 의 mtime·size 로만 무효화되는데
        // 서브에이전트 판정 근거는 옆 파일(summary.json)이라, 파싱 안에서 걸러내면 늦게 쓰인
        // session_kind 가 blob 에 굳어 이중집계가 영구화된다.
        let roots = grokRoots ?? grokRoot.map { [$0] } ?? LocalUsageReader.grokSessionRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "grok"))
        var all: [LocalUsageReader.Entry] = []
        for root in roots {
            all += collect(root: root, since: modifiedSince,
                           cache: &grokCache, include: LocalUsageReader.isGrokUsageFile) {
                LocalUsageReader.parseGrokFile($0, fmt: fmt)
            }
        }
        saveIfNeeded()
        // fork 세션이 부모 updates 를 복사해도 같은 턴은 한 번만(전역 dedup).
        return LocalUsageReader.dedupKeepMax(all)
    }

    func piEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        ensureLoaded()
        let fmt = LocalUsageReader.localDayFormatter()
        let roots = LocalUsageReader.normalizedRoots(piRoots ?? LocalUsageReader.piSessionRoots)
        var all: [LocalUsageReader.Entry] = []
        for root in roots {
            all += collect(root: root, since: modifiedSince, cache: &piCache) {
                LocalUsageReader.parsePiFile($0, fmt: fmt)
            }
        }
        saveIfNeeded()
        return LocalUsageReader.dedupKeepMax(all)
    }

    /// `include` 는 blob 캐시 조회 **전에** 평가된다 — 파일 밖 상태(옆 파일 등)에 의존하는 판정을
    /// 캐시에 굳히지 않기 위해서다.
    private func collect(root: URL, since: Date, cache: inout [String: Blob],
                         allowJSON: Bool = false, include: ((URL) -> Bool)? = nil,
                         parse: (URL) -> [LocalUsageReader.Entry]?) -> [LocalUsageReader.Entry] {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [LocalUsageReader.Entry] = []
        for case let url as URL in en {
            // 기본 .jsonl. .json 은 Gemini 루트에서만(allowJSON) — Claude 루트의 대량
            // .meta.json 등을 스캔/빈 blob 으로 캐시하지 않도록 스코프 제한.
            guard url.pathExtension == "jsonl" || (allowJSON && url.pathExtension == "json") else { continue }
            if let include, !include(url) { continue }
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = v.contentModificationDate, mtime >= since else { continue }
            let size = v.fileSize ?? 0
            let key = url.path
            if let blob = cache[key], blob.mtime == mtime, blob.size == size {
                result.append(contentsOf: blob.entries)            // 변경 없음 → 재파싱 안 함
            } else if let entries = parse(url) {
                cache[key] = Blob(mtime: mtime, size: size, entries: entries)
                dirty = true
                result.append(contentsOf: entries)
            } else if let blob = cache[key] {
                // 일시적 읽기 실패는 현재 signature에 굳히지 않는다. 이전 blob을 쓰되,
                // signature는 옛 상태로 남겨 다음 refresh에서 다시 읽게 한다.
                result.append(contentsOf: blob.entries)
            }
        }
        return result
    }

    /// Codex는 fork 파일을 단독으로 확정할 수 없으므로 final Entry 대신 parsed rollout을 캐시.
    /// 조회 범위 밖 부모도 replay 판정에는 필요해 session id로 찾아 dependency로 함께 반환.
    private func collectCodexRollouts(
        roots: [URL],
        since: Date,
        fmt: DateFormatter
    ) -> (rollouts: [LocalUsageReader.CodexParsedRollout], includedPaths: Set<String>) {
        let files = LocalUsageReader.codexRolloutFiles(in: roots)

        func rememberSessionID(_ id: String?, of file: LocalUsageReader.CodexRolloutFile) {
            codexSessionIDs[file.path] = CodexSessionProbe(
                mtime: file.mtime,
                size: file.size,
                sessionID: id
            )
            dirty = true
        }

        // 파싱만 캐시 blob 을 재사용한다. 확장 규칙 자체는 reader 와 공유(LocalUsageReader).
        func load(_ file: LocalUsageReader.CodexRolloutFile) -> LocalUsageReader.CodexParsedRollout {
            if let blob = codexCache[file.path], blob.mtime == file.mtime, blob.size == file.size {
                if codexSessionIDs[file.path]?.mtime != file.mtime
                    || codexSessionIDs[file.path]?.size != file.size {
                    rememberSessionID(blob.rollout.sessionID, of: file)
                }
                return blob.rollout
            }
            let rollout = LocalUsageReader.parseCodexRollout(file.url, fmt: fmt)
            codexCache[file.path] = CodexBlob(
                mtime: file.mtime,
                size: file.size,
                rollout: rollout
            )
            dirty = true
            // blob 은 40일 prune 대상이라 오래된 부모는 곧 사라진다. 세션 id 만 인덱스에 남겨
            // 그 뒤로도 파일을 다시 열지 않고 후보를 가릴 수 있게 한다.
            rememberSessionID(rollout.sessionID, of: file)
            return rollout
        }

        /// 파일을 열지 않고 아는 세션 id — 유효한 blob → 인덱스 순. `known(nil)`도 유효한 결과다.
        func sessionIDKnowledge(
            _ file: LocalUsageReader.CodexRolloutFile
        ) -> LocalUsageReader.CodexSessionIDKnowledge {
            if let blob = codexCache[file.path], blob.mtime == file.mtime, blob.size == file.size {
                return .known(blob.rollout.sessionID)
            }
            if let probe = codexSessionIDs[file.path], probe.mtime == file.mtime, probe.size == file.size {
                return .known(probe.sessionID)
            }
            return .unknown
        }

        // 이번 호출에서 읽기에 실패한 파일. 인덱스에는 남기지 않으므로(다음 새로고침에 재시도)
        // 고아 부모가 여러 개일 때 같은 파일을 부모 id 마다 다시 여는 것만 막는다.
        var temporarilyFailedPaths: Set<String> = []

        // parent가 오래돼 조회 mtime 범위에서 빠졌어도 child replay와 대조할 수 있도록 closure를 확장.
        let result = LocalUsageReader.expandCodexParentClosure(
            windowFiles: files.filter { $0.mtime >= since },
            allFiles: files,
            load: load,
            sessionIDKnowledge: sessionIDKnowledge,
            probeSessionID: { file in
                if temporarilyFailedPaths.contains(file.path) { return nil }
                do {
                    let id = try codexProbe(file.url)
                    rememberSessionID(id, of: file)   // nil = "이 파일엔 세션 id 가 없다"(확정)
                    return id
                } catch {
                    temporarilyFailedPaths.insert(file.path)
                    return nil
                }
            }
        )

        // 사라진 rollout 의 인덱스 항목 정리. 시간이 아니라 **파일 존재**가 기준이다(오래된 부모를
        // 찾으려고 만든 인덱스라 40일 prune 에 얹으면 목적이 사라진다). 열거가 통째로 실패한
        // 경우(루트 부재·권한 순간 실패)는 0개를 "전부 삭제됨"으로 오해하지 않도록 건너뛴다.
        if !files.isEmpty {
            let existing = Set(files.map(\.path))
            let survivors = codexSessionIDs.filter { existing.contains($0.key) }
            if survivors.count != codexSessionIDs.count {
                codexSessionIDs = survivors
                dirty = true
            }
        }
        return result
    }

    // MARK: 영속화

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        // zlib 압축 스냅샷(현행) → 실패 시 평문 JSON(구버전 캐시) 폴백
        let data = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        claudeCache = snap.claude
        codexCache = snap.codex
        codexSessionIDs = snap.codexSessionIDs
        geminiCache = snap.gemini
        grokCache = snap.grok
        piCache = snap.pi

        if snap.codexParserVersion != Self.codexParserVersion {
            codexCache = [:]
            dirty = true
        }
        if snap.codexSessionIndexVersion != Self.codexSessionIndexVersion {
            codexSessionIDs = [:]
            dirty = true
        }
        if snap.grokParserVersion != Self.grokParserVersion {
            grokCache = [:]
            dirty = true
        }
        if snap.piParserVersion != Self.piParserVersion {
            piCache = [:]
            dirty = true
        }
    }

    /// 어떤 조회 윈도우(오늘/주/월)에도 들지 않는 오래된 파일 blob 을 제거해 캐시 무한 증가를 막는다.
    /// (가장 넓은 윈도우는 월·주 시작이라 40일이면 충분한 여유. 삭제된 세션 파일 blob 도 함께 정리.)
    /// `codexSessionIDs` 는 여기서 건드리지 않는다 — 40일보다 오래된 부모를 찾는 게 그 인덱스의 목적이다.
    private func prune() {
        let cutoff = now().addingTimeInterval(-40 * 86400)
        claudeCache = claudeCache.filter { $0.value.mtime >= cutoff }
        codexCache = codexCache.filter { $0.value.mtime >= cutoff }
        geminiCache = geminiCache.filter { $0.value.mtime >= cutoff }
        grokCache = grokCache.filter { $0.value.mtime >= cutoff }
        piCache = piCache.filter { $0.value.mtime >= cutoff }
    }

    /// 변경이 있으면 디스크에 저장(최소 60초 간격으로 throttle — 잦은 쓰기 방지).
    private func saveIfNeeded() {
        guard dirty else { return }
        if let last = lastSave, now().timeIntervalSince(last) < 60 { return }
        prune()
        let snap = Snapshot(
            claude: claudeCache,
            codex: codexCache,
            codexSessionIDs: codexSessionIDs,
            gemini: geminiCache,
            grok: grokCache,
            pi: piCache,
            codexParserVersion: Self.codexParserVersion,
            codexSessionIndexVersion: Self.codexSessionIndexVersion,
            grokParserVersion: Self.grokParserVersion,
            piParserVersion: Self.piParserVersion)
        if let data = try? JSONEncoder().encode(snap) {
            // JSON 은 zlib 로 크게 압축됨(수 MB → 수백 KB). 실패 시 평문 저장(로드가 양쪽 다 처리).
            let out = (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
            try? out.write(to: fileURL, options: .atomic)
            dirty = false
            lastSave = now()
        }
    }
}
