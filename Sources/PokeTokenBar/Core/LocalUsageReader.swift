import Foundation

/// 로컬 AI 코딩 도구 사용 로그를 직접 파싱해 토큰/비용을 집계한다(ccusage CLI 대체).
///
/// - Claude: `~/.claude/projects/**/*.jsonl` 의 `type:"assistant"` 라인
///   (`message.usage` 4종 토큰, `message.model`, `message.id`+`requestId`, `timestamp`).
///   세션 재개/sidechain 으로 같은 메시지가 여러 파일에 중복 → `(message.id, requestId)` 로 dedup.
/// - Codex: `~/.codex/sessions/**/rollout-*.jsonl` 및 보관된
///   `~/.codex/archived_sessions/rollout-*.jsonl` 의
///   `event_msg.payload.type:"token_count"` (`info.last_token_usage` 턴 델타) 합산.
/// - Pi: `~/.pi/agent/sessions/**/*.jsonl` 의 message/compaction/branch-summary direct usage.
///   reasoning 은 output 에 이미 포함되며, fork 가 복사한 entry id 는 전역 중복 제거한다.
///
/// 성능: mtime 윈도우로 스캔 파일을 한정(범위 시작 이전에 수정된 파일은 범위 내 엔트리가 없음).
enum LocalUsageReader {

    /// 활성 블록(번 레이트)과 enrichment 스캔 하한이 공유하는 5시간 롤링 윈도우 길이.
    static let blockWindow: TimeInterval = 5 * 3600
    /// Fork replay는 수 ms 간격으로 기록된다. 이보다 긴 첫 공백부터는 실제 child turn으로 본다.
    private static let forkReplayMaximumGap: TimeInterval = 1

    // MARK: 정규화 레코드

    struct Entry: Sendable, Codable {
        let id: String
        let date: Date
        let localDay: String
        let model: String
        let input, output, cacheWrite, cacheRead: Int
        /// Some agents persist the exact charge alongside token usage. Prefer it over
        /// model-table pricing when present so local reports match the source of truth.
        var explicitCost: Double? = nil
        var total: Int { input + output + cacheWrite + cacheRead }
    }

    struct Bucket {
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        var cost = 0.0
        var total: Int { input + output + cacheWrite + cacheRead }
        mutating func add(_ e: Entry) {
            input += e.input; output += e.output; cacheWrite += e.cacheWrite; cacheRead += e.cacheRead
            cost += e.explicitCost.flatMap { $0 > 0 ? $0 : nil }
                ?? ModelPricing.cost(model: e.model, input: e.input, output: e.output,
                                     cacheWrite: e.cacheWrite, cacheRead: e.cacheRead)
        }
    }

    // MARK: 경로

    /// CLI 기본 위치의 홈 기준 상대 경로 — `claudeProjectsDir` 와 루트 목록이 같은 문자열을 공유한다
    /// (양쪽에 리터럴을 따로 쓰면 한쪽만 바뀌어도 테스트가 못 잡는다).
    static let defaultRelativeProjectsPath = ".claude/projects"
    static let configRelativeProjectsPath = ".config/claude/projects"

    static var claudeProjectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultRelativeProjectsPath)
    }

    /// Claude 사용 로그(`<root>/**/*.jsonl`)가 있을 수 있는 **모든** projects 루트.
    /// 새 위치를 지원할 땐 이 한 곳에만 추가한다 — 스캔·캐시·테스트가 이 단일 소스를 공유한다.
    ///
    /// - `CLAUDE_CONFIG_DIR`: 사용자가 설정 위치를 옮긴 경우. 콤마로 여러 개를 줄 수 있고 각각 `<값>/projects`.
    /// - `~/.config/claude/projects`, `~/.claude/projects`: CLI 기본 위치(전자는 XDG 스타일 설치).
    /// - 사용자 지정 스캔 폴더(설정): 기본 위치 밖의 로그. `CustomScanRoots.union` 으로
    ///   기본 루트에 *더하기만* 한다. 조상 경로는 기본 루트를 접어 없애지 못하게 버린다.
    /// - Claude Desktop 임베디드 세션: 세션 디렉터리마다 CLI 와 같은 모양의 `.claude/projects` 를 갖는다.
    ///   Desktop 으로 일한 사용량이 여기에만 남으므로 빼면 조용히 누락된다.
    /// 계산에 파일시스템 탐색 + (GUI 앱에선) 로그인 셸 조회가 들어가는데 새로고침은 분 단위로 돈다.
    /// 루트 구성은 Desktop 세션이 새로 생길 때만 바뀌므로 TTL 캐시로 재계산을 접는다.
    static var claudeProjectRoots: [URL] { rootsCache.roots() }

    /// 테스트·진단용 — 캐시를 무시하고 지금 상태로 계산한다.
    static func computeClaudeProjectRoots(
        configDirValue: String? = shellAwareClaudeConfigDir(),
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL]
    {
        var roots: [URL] = []
        if let raw = configDirValue {
            for part in raw.split(separator: ",") {
                let path = part.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { continue }
                roots.append(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
                    .appendingPathComponent("projects"))
            }
        }
        roots.append(home.appendingPathComponent(Self.configRelativeProjectsPath))
        roots.append(home.appendingPathComponent(Self.defaultRelativeProjectsPath))

        let desktop = home.appendingPathComponent("Library/Application Support/Claude")
        for store in ["local-agent-mode-sessions", "claude-code-sessions"] {
            roots.append(contentsOf: embeddedClaudeProjectRoots(under: desktop.appendingPathComponent(store)))
        }
        // Custom roots are unioned *after* curated defaults so an ancestor extra cannot
        // evict `~/.claude/projects` (#162-B / #177).
        return CustomScanRoots.union(defaults: roots, extraRaw: customRootsValue)
    }

    /// Setting change must not wait for the 300s TTL — the next refresh should see the folder.
    static func invalidateProjectRootsCache() { rootsCache.invalidate() }

    static func codexSessionRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        CustomScanRoots.union(
            defaults: computeCodexScanRoots(home: home),
            extraRaw: customRootsValue)
    }

    static func geminiScanRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        CustomScanRoots.union(
            defaults: [home.appendingPathComponent(".gemini/tmp")],
            extraRaw: customRootsValue)
    }

    static func grokSessionRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let curated: URL
        if home == FileManager.default.homeDirectoryForCurrentUser,
           let env = UsageEnvironment.value("GROK_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            curated = URL(fileURLWithPath: env).appendingPathComponent("sessions")
        } else {
            curated = home.appendingPathComponent(".grok/sessions")
        }
        return CustomScanRoots.union(defaults: [curated], extraRaw: customRootsValue)
    }

    /// `CLAUDE_CONFIG_DIR` 값. Finder/launchd 로 뜬 `.app` 은 셸 환경을 상속하지 않으므로
    /// 프로세스 환경에 없으면 로그인 셸에 한 번 물어본다(`BinaryLocator` 가 PATH 에 쓰는 것과 같은 수법).
    /// 이 조회가 없으면 설정 위치를 옮긴 사용자는 앱에서만 0 토큰을 보고, CLI·테스트에서는 정상이라
    /// 재현이 안 된다.
    /// 조회·캐시는 `UsageEnvironment` 가 담당한다 — 같은 문제를 가진 프로바이더 override 변수를
    /// 한 곳에 모아 셸 spawn(실측 ~0.44s)을 이름 수와 무관하게 1회로 묶기 위해서다.
    static func shellAwareClaudeConfigDir() -> String? {
        UsageEnvironment.value("CLAUDE_CONFIG_DIR")
    }

    private static let rootsCache = RootsCache()

    final class RootsCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [URL]?
        private var computedAt: Date?
        /// 새 Desktop 세션이 생겨도 이 시간 안에는 반영된다. 새로고침 주기(분 단위)보다 넉넉히 길게.
        private let ttl: TimeInterval = 300

        /// 락은 캐시 필드 접근에만 쥔다. 계산은 락 **밖에서** 한다 — 첫 호출은 로그인 셸 spawn(최대 8초
        /// 대기)과 파일시스템 탐색을 포함하는데, 그 동안 락을 쥐면 동시 호출자가 통째로 막힌다
        /// (`UsageStore` 는 프로바이더를 taskGroup 으로 병렬 fetch 한다). 결과가 idempotent 하므로
        /// 경합 시 중복 계산이 나는 편이 블로킹보다 낫다.
        func roots() -> [URL] {
            lock.lock()
            let hit = (cached, computedAt)
            lock.unlock()
            if let cached = hit.0, let at = hit.1, Date().timeIntervalSince(at) < ttl { return cached }

            let fresh = computeClaudeProjectRoots(
                customRootsValue: CustomScanRoots.storedValue(for: "claude_code"))
            lock.lock()
            cached = fresh
            computedAt = Date()
            lock.unlock()
            return fresh
        }

        func invalidate() {
            lock.lock()
            cached = nil
            computedAt = nil
            lock.unlock()
        }
    }

    /// Claude Desktop 임베디드 세션 스토어에서 `.claude/projects` 디렉터리를 찾는다.
    /// 세션 경로는 `<store>/<uuid>/<uuid>/local_<uuid>/.claude/projects` 처럼 UUID 단계가 여러 겹이라
    /// 고정 경로로는 못 잡고 탐색해야 한다. `.claude` 는 hidden 이므로 `skipsHiddenFiles` 를 쓰면 안 된다.
    /// 탐색 중 내려가지 않는 디렉터리. **패키지·VCS 내부처럼 사용자 작업 트리가 아닌 것만** 넣는다.
    ///
    /// 이름 기반 가지치기는 *조상* 이름 하나로 그 아래 전부를 잘라내므로, 정당한 작업 디렉터리 이름을
    /// 넣으면 원래 막으려던 "조용한 0건"을 그대로 재생산한다. 실측: 세션 레이아웃에 `uploads`·`outputs`
    /// 가 실제로 존재하고(`local_<uuid>/uploads`, `/outputs`) 그 아래에서 돌린 Claude 세션은 정당한
    /// 루트다. `build`·`target` 역시 흔한 프로젝트 이름이라 뺐다. 폭 제어의 주 수단은 깊이 상한이고,
    /// 이 목록은 보조다. 가드: `testEmbeddedRootsFindRootsUnderWorkDirectoryNames`.
    private static let rootScanSkippedDirectories: Set<String> =
        ["node_modules", ".git", "venv", ".venv"]

    /// 기본 깊이 7의 근거(실측): 세션 기본 루트는 깊이 5(`<uuid>/<uuid>/local_<uuid>/.claude/projects`),
    /// 세션 작업 디렉터리 아래 저장소(`outputs/myrepo/.claude/projects`)는 깊이 7이다. 6 이면 후자를 놓치고,
    /// 8·9 로 올려도 방문 수는 그대로였다(100 고정) — 폭은 깊이가 아니라 `node_modules` 류 가지치기가
    /// 잡고 있다. 즉 7 이 "놓치지 않는 최소값"이면서 비용이 늘지 않는 지점이다.
    static func embeddedClaudeProjectRoots(under base: URL, maxDepth: Int = 7) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        var prunedByDepth = false
        for case let url as URL in en {
            let name = url.lastPathComponent
            if name == "projects", url.deletingLastPathComponent().lastPathComponent == ".claude",
               (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                out.append(url)
                en.skipDescendants()   // 이 아래는 프로젝트 로그 — 루트 탐색 대상이 아니다.
                continue
            }
            // 이 항목 자체는 위에서 검사한 뒤에 가지치기한다. `> maxDepth` 로 자르면 한 단계 더
            // 내려간 뒤에야 멈춰 실제 탐색 폭이 의도보다 넓어진다.
            if en.level >= maxDepth {
                prunedByDepth = true
                en.skipDescendants()
            } else if rootScanSkippedDirectories.contains(name) {
                en.skipDescendants()
            }
        }
        // 깊이로 잘렸으면 무엇을 찾았든 남긴다. `out.isEmpty` 를 조건에 넣으면 **부분 절단**
        // (세션 루트는 찾고 더 깊은 작업 디렉터리만 놓친 경우)이 조용히 지나가는데, 그게 가장 흔한 형태다.
        if prunedByDepth {
            AppLog.write("claude desktop scan: depth \(maxDepth) reached under \(base.lastPathComponent), found \(out.count) root(s) — deeper roots may be missed")
        }
        return out
    }

    /// 중복·중첩 루트를 제거한다. `CLAUDE_CONFIG_DIR=~/.claude` 처럼 기본 루트와 겹치게 지정하면
    /// 같은 파일을 두 번 스캔한다 — 전역 dedup 이 합계는 바로잡지만 스캔 비용은 그대로 두 배다.
    static func normalizedRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [String] = []
        for root in roots {
            // 심볼릭 링크를 풀어서 비교한다(`~/.config/claude` → `~/.claude` 링크가 흔한 XDG 구성).
            // `standardizedFileURL` 은 `..`·`.` 만 정리할 뿐 링크는 그대로 둬서 같은 트리를 두 번 훑게 된다.
            // 비교는 소문자로 — macOS 기본 APFS 볼륨은 대소문자를 구분하지 않는다.
            let path = root.resolvingSymlinksInPath().standardizedFileURL.path
            if seen.insert(path.lowercased()).inserted { unique.append(path) }
        }
        // 짧은 경로부터 확정하고, 이미 확정된 루트의 하위면 버린다.
        // 중첩 비교도 중복 비교와 같은 소문자 기준이어야 한다 — 한쪽만 대소문자를 무시하면
        // `CLAUDE_CONFIG_DIR=~/.Claude` 같은 표기에서 두 검사가 엇갈려 중복 루트가 살아남는다.
        var kept: [String] = []
        for path in unique.sorted(by: { $0.count < $1.count })
        where !kept.contains(where: {
            let (p, k) = (path.lowercased(), $0.lowercased())
            return p == k || p.hasPrefix(k + "/")
        }) {
            kept.append(path)
        }
        // 원래 순서(우선순위)를 보존해 돌려준다.
        return unique.filter(kept.contains).map { URL(fileURLWithPath: $0) }
    }
    /// Codex 기본 경로는 이 두 상대 경로로만 정의한다.
    /// `codexScanRoots`를 직접 조립하는 코드가 늘어나면 활성 세션과 보관 세션 중
    /// 한쪽만 캐시·스캐너·테스트에 반영되는 회귀가 생기기 쉬우므로, 기본 목록은
    /// `computeCodexScanRoots(home:)` 한 곳에서 만든다.
    static let codexSessionsRelativePath = ".codex/sessions"
    static let codexArchivedSessionsRelativePath = ".codex/archived_sessions"

    static var codexSessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(codexSessionsRelativePath)
    }

    /// Codex가 보관한 세션은 원본 rollout을 유지한 채 이 루트로 이동한다.
    /// 활성 세션만 읽으면 보관 직후 당일 사용량이 감소하므로, 두 루트를 하나의 논리적
    /// 세션 집합으로 읽고 아래 resolver의 안정적인 이벤트 ID로 중복을 제거해야 한다.
    static var codexArchivedSessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(codexArchivedSessionsRelativePath)
    }

    /// 테스트 가능한 Codex 기본 스캔 루트 계산기.
    /// 앱과 캐시는 아래의 `codexScanRoots`를 사용하고, 테스트는 가짜 home을 주입해
    /// 실제 사용자 디렉터리나 로그인 환경에 의존하지 않고 두 기본 경로의 구성을 고정한다.
    static func computeCodexScanRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        normalizedRoots([
            home.appendingPathComponent(codexSessionsRelativePath),
            home.appendingPathComponent(codexArchivedSessionsRelativePath),
        ])
    }

    /// 스캐너·캐시가 공유하는 Codex 기본 루트 목록.
    static var codexScanRoots: [URL] {
        computeCodexScanRoots()
    }

    static let defaultPiSessionsPath = ".pi/agent/sessions"

    static var piSessionRoots: [URL] {
        computePiSessionRoots(
            agentDirValue: UsageEnvironment.value("PI_CODING_AGENT_DIR"),
            sessionDirValue: UsageEnvironment.value("PI_CODING_AGENT_SESSION_DIR"))
    }

    static func computePiSessionRoots(
        agentDirValue: String? = UsageEnvironment.value("PI_CODING_AGENT_DIR"),
        sessionDirValue: String? = UsageEnvironment.value("PI_CODING_AGENT_SESSION_DIR"),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var roots = [home.appendingPathComponent(defaultPiSessionsPath)]
        if let agentDirValue, !agentDirValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: agentDirValue).expandingTildeInPath)
                .appendingPathComponent("sessions"))
        }
        if let sessionDirValue, !sessionDirValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: sessionDirValue).expandingTildeInPath))
        }
        return normalizedRoots(roots)
    }

    static var geminiTmpDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp")
    }

    // MARK: 스캔 (mtime 윈도우)

    /// `root` 하위(재귀)의 `.jsonl` 파일 중 `modifiedSince` 이후 수정된 것.
    static func jsonlFiles(in root: URL, modifiedSince: Date, allowJSON: Bool = false) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            // 기본 .jsonl. .json 은 Gemini 전용(allowJSON) — Claude 루트 .meta.json 스캔 방지.
            guard url.pathExtension == "jsonl" || (allowJSON && url.pathExtension == "json") else { continue }
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let m = v?.contentModificationDate, m >= modifiedSince { out.append(url) }
        }
        return out
    }

    // MARK: Claude 파싱

    /// 같은 `(message.id, requestId)` 가 스트리밍/재개로 여러 번 로깅될 때 cacheRead/input 은 고정이나
    /// output 은 증가하므로, **id 별 total 이 가장 큰(=완성된) 항목**을 남긴다(전역 dedup).
    /// (first-occurrence 를 남기면 부분 output 만 잡혀 비용이 크게 과소집계됨.)
    static func dedupKeepMax(_ entries: [Entry]) -> [Entry] {
        var byID: [String: Entry] = [:]
        for e in entries {
            if let ex = byID[e.id] { if e.total > ex.total { byID[e.id] = e } }
            else { byID[e.id] = e }
        }
        return Array(byID.values)
    }

    /// Claude 파일 하나를 파싱(파일 내 dedup). 캐시가 파일 단위로 호출.
    static func parseClaudeFile(_ url: URL, fmt: DateFormatter) -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage\""), line.contains("\"assistant\"") else { continue }
            // 라인마다 autoreleasepool — JSONSerialization 이 만드는 autoreleased NSDictionary/NSString 가
            // 수천 파일·수만 라인에 걸쳐 배출 없이 누적돼 콜드 파싱 피크를 키우던 것을 즉시 배출.
            autoreleasepool {
                if let e = parseClaudeLine(String(line), fmt: fmt) { out.append(e) }
            }
        }
        return dedupKeepMax(out)
    }

    /// `modifiedSince` 이후 파일에서 Claude 사용 엔트리(전역 dedup) — 테스트/캐시 미사용 경로.
    /// `root` 를 주지 않으면 `claudeProjectRoots` 전체를 훑는다. 같은 턴이 여러 루트에 복사돼 있어도
    /// `(message.id, requestId)` 전역 dedup 이 한 번만 세므로 루트가 겹쳐도 합계는 부풀지 않는다.
    static func claudeEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        claudeEntries(modifiedSince: modifiedSince, roots: root.map { [$0] } ?? claudeProjectRoots)
    }

    static func claudeEntries(modifiedSince: Date, roots: [URL]) -> [Entry] {
        let fmt = localDayFormatter()
        var all: [Entry] = []
        for root in roots {
            for file in jsonlFiles(in: root, modifiedSince: modifiedSince) {
                all.append(contentsOf: parseClaudeFile(file, fmt: fmt))
            }
        }
        return dedupKeepMax(all)
    }

    private static func parseClaudeLine(_ line: String, fmt: DateFormatter) -> Entry? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let date = ISO8601Parser.date(from: ts) else { return nil }
        let model = msg["model"] as? String ?? "unknown"
        let id = (msg["id"] as? String ?? "") + "|" + (obj["requestId"] as? String ?? "")
        return Entry(
            id: id, date: date, localDay: fmt.string(from: date), model: model,
            input: intValue(usage["input_tokens"]),
            output: intValue(usage["output_tokens"]),
            cacheWrite: intValue(usage["cache_creation_input_tokens"]),
            cacheRead: intValue(usage["cache_read_input_tokens"]))
    }

    static func parsePiFile(_ url: URL, fmt: DateFormatter) -> [Entry]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var out: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage\"") else { continue }
            autoreleasepool {
                guard let data = String(line).data(using: .utf8),
                      let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = envelope["id"] as? String, !id.isEmpty,
                      let type = envelope["type"] as? String else { return }

                let usage: [String: Any]?
                let date: Date?
                switch type {
                case "message":
                    guard let message = envelope["message"] as? [String: Any],
                          message["stopReason"] as? String != "aborted",
                          message["stopReason"] as? String != "error",
                          let messageUsage = message["usage"] as? [String: Any] else { return }
                    usage = messageUsage
                    date = piMessageDate(message, envelope: envelope)
                case "compaction", "branch_summary":
                    usage = envelope["usage"] as? [String: Any]
                    date = piEnvelopeDate(envelope)
                default:
                    return
                }
                guard let usage, let date,
                      let entry = piEntry(id: id, date: date, usage: usage, fmt: fmt) else { return }
                out.append(entry)
            }
        }
        return dedupKeepMax(out)
    }

    static func piEntries(modifiedSince: Date, roots: [URL] = piSessionRoots) -> [Entry] {
        var all: [Entry] = []
        let fmt = localDayFormatter()
        for root in normalizedRoots(roots) {
            for file in jsonlFiles(in: root, modifiedSince: modifiedSince) {
                all.append(contentsOf: parsePiFile(file, fmt: fmt) ?? [])
            }
        }
        return dedupKeepMax(all)
    }

    private static func piEntry(
        id: String, date: Date, usage: [String: Any], fmt: DateFormatter
    ) -> Entry? {
        let names = ["input", "output", "cacheWrite", "cacheRead"]
        let hasGranularUsage = names.contains { intOrNil(usage[$0]) != nil }
        let input: Int
        let output: Int
        let cacheWrite: Int
        let cacheRead: Int
        if hasGranularUsage {
            input = intOrNil(usage["input"]) ?? 0
            output = intOrNil(usage["output"]) ?? 0 // Pi reasoning is already a subset of output.
            cacheWrite = intOrNil(usage["cacheWrite"]) ?? 0
            cacheRead = intOrNil(usage["cacheRead"]) ?? 0
        } else if let total = intOrNil(usage["totalTokens"]) {
            // Malformed total-only usage has no recoverable bucket split; preserve its aggregate total.
            input = total
            output = 0
            cacheWrite = 0
            cacheRead = 0
        } else {
            return nil
        }
        return Entry(
            id: id, date: date, localDay: fmt.string(from: date), model: "pi",
            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
    }

    private static func piMessageDate(_ message: [String: Any], envelope: [String: Any]) -> Date? {
        if let milliseconds = doubleOrNil(message["timestamp"]), milliseconds > 0 {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        return piEnvelopeDate(envelope)
    }

    private static func piEnvelopeDate(_ envelope: [String: Any]) -> Date? {
        guard let timestamp = envelope["timestamp"] as? String else { return nil }
        return ISO8601Parser.date(from: timestamp)
    }

    // MARK: Codex 파싱

    struct CodexUsageVector: Equatable, Codable, Sendable {
        let input: Int
        let cachedInput: Int
        let cacheWriteInput: Int
        let output: Int
        let reasoningOutput: Int
        let total: Int

        /// 누적 usage 는 `intOrNil` 로 읽는다 — `intValue` 의 `Int(d)` 는 `1e30` 같은 값에서 트랩(크래시)
        /// 하고, 그 파일은 디스크에 남아 실행할 때마다 다시 죽인다. 클램프가 크래시보다 안전한 열화다.
        init(_ raw: [String: Any]) {
            input = intOrNil(raw["input_tokens"]) ?? 0
            cachedInput = intOrNil(raw["cached_input_tokens"]) ?? 0
            cacheWriteInput = intOrNil(raw["cache_write_input_tokens"]) ?? 0
            output = intOrNil(raw["output_tokens"]) ?? 0
            reasoningOutput = intOrNil(raw["reasoning_output_tokens"]) ?? 0
            total = intOrNil(raw["total_tokens"]) ?? 0
        }

        var fingerprint: String {
            "\(input),\(cachedInput),\(cacheWriteInput),\(output),\(reasoningOutput),\(total)"
        }

        func isLower(than previous: Self) -> Bool {
            input < previous.input
                || cachedInput < previous.cachedInput
                || cacheWriteInput < previous.cacheWriteInput
                || output < previous.output
                || reasoningOutput < previous.reasoningOutput
                || total < previous.total
        }
    }

    struct CodexUsageState: Equatable, Codable, Sendable {
        let cumulative: CodexUsageVector
        let last: CodexUsageVector

        var fingerprint: String {
            "\(cumulative.fingerprint)|\(last.fingerprint)"
        }
    }

    private struct ParsedCodexToken {
        let entry: Entry
        /// 구형 레코드는 cumulative 사용량이 없을 수 있음. 그런 레코드는 동일 상태 판정을 하지 않는다.
        let usageState: CodexUsageState?
    }

    private struct CodexSessionMeta {
        let id: String?
        let parentID: String?
        let date: Date?
        let isSubagent: Bool
    }

    struct CodexUsageEvent: Codable, Sendable {
        let entry: Entry
        let usageState: CodexUsageState?
        let sessionID: String?
    }

    struct CodexParsedRollout: Codable, Sendable {
        let path: String
        let sessionID: String?
        let parentSessionID: String?
        let forkedAt: Date?
        let isSubagent: Bool
        let events: [CodexUsageEvent]
    }

    private struct CodexResolvedEvent {
        let entry: Entry
        let usageState: CodexUsageState?
    }

    private struct CodexResolvedRollout {
        let history: [CodexResolvedEvent]
        let ownedEntries: [Entry]
    }

    /// Codex 사용 엔트리. token_count 이벤트의 last_token_usage(턴 델타)를 4종 토큰으로 매핑.
    /// - input(비캐시) = input_tokens − cached_input_tokens, cacheRead = cached_input_tokens
    /// - output = output_tokens (reasoning 은 output 에 이미 포함), cacheWrite = 0
    /// Codex 파일 하나를 파싱(세션 단위 — token_count 이벤트의 턴 델타). 캐시가 파일 단위로 호출.
    static func parseCodexFile(_ url: URL, fmt: DateFormatter) -> [Entry] {
        let rollout = parseCodexRollout(url, fmt: fmt)
        return resolveCodexRollouts([rollout], includedPaths: [rollout.path])
    }

    /// 파일 내부 정보만 파싱. fork replay 여부는 다른 rollout과 대조.
    static func parseCodexRollout(_ url: URL, fmt: DateFormatter) -> CodexParsedRollout {
        func emptyRollout() -> CodexParsedRollout {
            return CodexParsedRollout(
                path: url.path,
                sessionID: nil,
                parentSessionID: nil,
                forkedAt: nil,
                isSubagent: false,
                events: []
            )
        }

        var events: [CodexUsageEvent] = []
        var turn = 0
        var sessionID: String?
        var parentSessionID: String?
        var forkedAt: Date?
        var isSubagent = false
        var currentSessionID: String?
        var previousUsageState: (sessionID: String, state: CodexUsageState)?
        // 실모델은 아래 codexModel 이 로그에서 동적 추출(신모델 자동 대응). 이 값은 세션에 model 라인이
        // 아예 없을 때만 쓰는 버전무관 폴백 — Codex 비용은 항상 0이라 표시 숫자엔 영향 없다(업데이트 불필요).
        var model = "codex"
        do {
            try forEachCodexLine(in: url) { line in
                autoreleasepool {   // JSONSerialization 의 autoreleased 객체를 라인마다 배출(콜드 파싱 피크 억제)
                    // Data.range 는 바이트 탐색이라 String.contains 의 grapheme 스캔과 달리
                    // 비대상 라인을 값싼 비용으로 건너뛸 수 있다. 대형 rollout 의 대부분은
                    // response_item/delta 이며, 사용량 집계에 필요한 세 종류만 JSON 파싱한다.
                    if line.range(of: codexSessionMetaMarker) != nil,
                       let meta = codexSessionMeta(line) {
                        if sessionID == nil {
                            // subagent meta는 `id`가 child이고 `session_id`가 parent일 수 있으므로 id 우선.
                            sessionID = meta.id
                            parentSessionID = meta.parentID
                            forkedAt = meta.date
                            isSubagent = meta.isSubagent
                        }
                        if let id = meta.id, id != currentSessionID {
                            currentSessionID = id
                            previousUsageState = nil
                        }
                    }
                    if line.range(of: codexModelMarker) != nil, let m = codexModel(line) { model = m }
                    guard line.range(of: codexTokenCountMarker) != nil else { return }
                    guard let parsed = parseCodexLine(
                        line, file: url.lastPathComponent, turn: turn, model: model, fmt: fmt
                    ) else { return }
                    defer { turn += 1 }

                    // Codex는 같은 cumulative/last usage 상태를 그대로 다시 기록할 수 있음. replay trimming을
                    // 하기 전에 파일 내부에서 정규화한다. 같은 세션의 연속 token_count 상태가 full vector까지
                    // 같으면 새 토큰 기여가 없는 동일 snapshot이므로 한 번만 남긴다.
                    if let state = parsed.usageState, let sessionID = currentSessionID {
                        if let previous = previousUsageState,
                           previous.sessionID == sessionID,
                           previous.state == state {
                            return
                        }
                        previousUsageState = (sessionID, state)
                    } else {
                        previousUsageState = nil
                    }
                    events.append(CodexUsageEvent(
                        entry: parsed.entry,
                        usageState: parsed.usageState,
                        sessionID: currentSessionID
                    ))
                }
            }
        } catch {
            return emptyRollout()
        }
        return CodexParsedRollout(
            path: url.path,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            forkedAt: forkedAt,
            isSubagent: isSubagent,
            events: events
        )
    }

    /// 대형 JSONL 을 파일 크기와 무관한 메모리로 순회한다. 완성된 한 줄만
    /// 소유하므로 피크는 파일 전체가 아니라 가장 긴 라인 + 청크 크기에 비례한다.
    private static func forEachCodexLine(in url: URL, body: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)

        while true {
            let readChunk = try autoreleasepool { () throws -> Bool in
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    return false
                }

                buffer.append(chunk)
                var lineStart = buffer.startIndex
                while lineStart < buffer.endIndex,
                      let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                    if lineStart < newline {
                        body(Data(buffer[lineStart..<newline]))
                    }
                    lineStart = buffer.index(after: newline)
                }
                if lineStart != buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<lineStart)
                }
                // FileHandle 의 Data bridge가 만든 autoreleased backing storage도 청크마다 배출한다.
                // 이 경계가 없으면 청크 크기는 작아도 전체 파일을 다 읽을 때까지 RSS가 누적될 수 있다.
                return true
            }
            if !readChunk { break }
        }

        if !buffer.isEmpty { body(buffer) }
    }

    private static let codexSessionMetaMarker = Data("session_meta".utf8)
    private static let codexModelMarker = Data("\"model\"".utf8)
    private static let codexTokenCountMarker = Data("token_count".utf8)

    /// 부모 탐색이 다루는 rollout 파일. 캐시는 `(path, mtime, size)` 로 blob 을 무효화하고 reader 는
    /// mtime 으로 조회 윈도우만 나누므로, 두 경로가 같은 표현을 공유한다.
    struct CodexRolloutFile {
        let url: URL
        let mtime: Date
        let size: Int
        var path: String { url.path }
    }

    /// 세션 id 조회 상태. `known(nil)`은 probe를 마쳤지만 id를 찾지 못한 상태이며,
    /// `unknown`과 구분해야 같은 파일을 매 새로고침마다 다시 열지 않는다.
    enum CodexSessionIDKnowledge {
        case unknown
        case known(String?)
    }

    /// Codex 루트의 rollout 파일 전체(mtime·size 포함). 조회 윈도우 밖 파일도 부모 후보라 걸러내지 않는다.
    static func codexRolloutFiles(in root: URL) -> [CodexRolloutFile] {
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [CodexRolloutFile] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate else { continue }
            out.append(CodexRolloutFile(url: url, mtime: mtime, size: values.fileSize ?? 0))
        }
        return out
    }

    /// 활성·보관 루트처럼 여러 디렉터리를 하나의 Codex 파일 집합으로 합친다.
    /// 먼저 공통 루트 정규화로 심볼릭 링크·중첩 루트를 접고, 이동 중 같은 rollout이
    /// 두 루트에 잠시 동시에 보여도 실제 이벤트 중복 제거는
    /// `resolveCodexRollouts`의 session/state ID가 담당한다.
    static func codexRolloutFiles(in roots: [URL]) -> [CodexRolloutFile] {
        normalizedRoots(roots)
            .flatMap { codexRolloutFiles(in: $0) }
            .sorted { $0.path < $1.path }
    }

    /// 조회 윈도우 안 rollout 에서 시작해, replay 대조에 필요한 부모(그 부모의 부모까지)를 dependency 로
    /// 끌어온다. Codex 는 fork 파일 하나만 보고는 자기 usage 를 확정할 수 없기 때문이다.
    ///
    /// reader(직접 파싱)와 cache(blob 재사용)가 **같은 확장 규칙**을 쓰도록 파일 표현만 공유하고,
    /// 달라지는 세 가지 — 파싱, 이미 아는 세션 id, 파일 내용 probe — 만 주입받는다. 규칙이 양쪽에
    /// 복제돼 있으면 한쪽만 고쳐도 나머지 테스트가 초록으로 남는다.
    /// (클로저는 non-escaping — 캐시는 actor 격리 상태를 만지며 호출한다.)
    static func expandCodexParentClosure(
        windowFiles: [CodexRolloutFile],
        allFiles: [CodexRolloutFile],
        load: (CodexRolloutFile) -> CodexParsedRollout,
        sessionIDKnowledge: (CodexRolloutFile) -> CodexSessionIDKnowledge,
        probeSessionID: (CodexRolloutFile) -> String?
    ) -> (rollouts: [CodexParsedRollout], includedPaths: Set<String>) {
        var rolloutsByPath = Dictionary(
            uniqueKeysWithValues: windowFiles.map { file in
                let rollout = load(file)
                return (rollout.path, rollout)
            }
        )
        let includedPaths = Set(windowFiles.map(\.path))

        var pendingParentIDs = Set(rolloutsByPath.values.compactMap(\.parentSessionID))
        var searchedParentIDs: Set<String> = []
        while let parentID = pendingParentIDs.subtracting(searchedParentIDs).first {
            searchedParentIDs.insert(parentID)
            if rolloutsByPath.values.contains(where: { $0.sessionID == parentID }) { continue }

            // 힌트는 후보를 고를 뿐이고, 채택은 실제 payload 의 세션 id 로만 판정한다.
            func adopt(_ candidates: [CodexRolloutFile]) -> Bool {
                var resolved = false
                for candidate in candidates {
                    let parent = load(candidate)
                    guard parent.sessionID == parentID else { continue }
                    rolloutsByPath[parent.path] = parent
                    resolved = true
                    if let ancestorID = parent.parentSessionID {
                        pendingParentIDs.insert(ancestorID)
                    }
                }
                return resolved
            }

            let unresolved = allFiles.filter { !rolloutsByPath.keys.contains($0.path) }
            // 이미 아는 세션 id 와 파일명으로 후보를 좁혀 먼저 확인한다(파일을 열지 않는다).
            let hinted = unresolved.filter {
                switch sessionIDKnowledge($0) {
                case .known(let id):
                    // 세션 id 를 아는 파일은 그 값으로만 판정한다. 파일명까지 보면 id 가 다른데도
                    // 후보로 뽑혀, 인덱스가 warm 이어도 매 새로고침 같은 파일을 다시 full-parse 한다.
                    return id == parentID
                case .unknown:
                    return isUsableFilenameHint(parentID)
                        && $0.url.lastPathComponent.contains(parentID)
                }
            }
            if adopt(hinted) { continue }

            // 힌트가 없었거나 전부 검증에 실패했으면 내용을 봐야 아는 파일만 연다.
            // 세션 id 를 이미 아는 파일은 그 값이 parentID 가 아니므로 다시 열 이유가 없다.
            let hintedPaths = Set(hinted.map(\.path))
            _ = adopt(unresolved.filter {
                guard !hintedPaths.contains($0.path),
                      case .unknown = sessionIDKnowledge($0) else { return false }
                return probeSessionID($0) == parentID
            })
        }
        return (Array(rolloutsByPath.values), includedPaths)
    }

    static func codexEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        let fmt = localDayFormatter()
        let roots = root.map { [$0] } ?? codexSessionRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "codex"))
        let allFiles = codexRolloutFiles(in: roots)
        // 테스트/캐시 미사용 경로 — 아는 세션 id 가 없으니 파일명 힌트와 probe 만으로 부모를 찾는다.
        let (rollouts, includedPaths) = expandCodexParentClosure(
            windowFiles: allFiles.filter { $0.mtime >= modifiedSince },
            allFiles: allFiles,
            load: { parseCodexRollout($0.url, fmt: fmt) },
            sessionIDKnowledge: { _ in .unknown },
            probeSessionID: { codexRolloutSessionID(at: $0.url) }
        )
        return resolveCodexRollouts(rollouts, includedPaths: includedPaths)
    }

    /// 파일명 부분일치로 부모 후보를 좁힐 때 쓸 수 있는 id 인가.
    /// 퇴화된 값(빈 문자열·`"-"` 같은 구분자만)은 거의 모든 rollout 파일명에 걸려 후보 필터가
    /// 아무것도 걸러내지 못하고 전 rollout 을 full-parse 시킨다 — 실측 300파일 기준 0.009s → 18.2s.
    /// 이건 파일을 열지 않는 값싼 사전 필터일 뿐이라, 통과해도 내용 대조는 그대로 수행된다.
    static func isUsableFilenameHint(_ id: String) -> Bool {
        id.count >= 4 && id.contains { $0.isLetter || $0.isNumber }
    }

    private static func codexSessionMeta(_ line: Data) -> CodexSessionMeta? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (obj["type"] as? String) == "session_meta",
              let payload = obj["payload"] as? [String: Any] else { return nil }
        let id = (payload["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (payload["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let parentID = (payload["forked_from_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (payload["parent_thread_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let date = (obj["timestamp"] as? String).flatMap { ISO8601Parser.date(from: $0) }
        let source = payload["source"] as? [String: Any]
        let isSubagent = (payload["thread_source"] as? String) == "subagent"
            || source?["subagent"] != nil
        return CodexSessionMeta(id: id, parentID: parentID, date: date, isSubagent: isSubagent)
    }

    /// probe 가 읽는 총 바이트 상한. 한 줄을 다 못 채운 채 상한에 닿아도 여기서 끊기므로
    /// (buffer ⊆ 읽은 바이트) 비정상적으로 긴 단일 라인도 같은 예산 안에 갇힌다.
    /// 상한을 넘는 metadata 는 nil → 부모를 못 찾고 timing fallback 으로 강등된다. 실측 `session_meta`
    /// 첫 줄이 중앙값 ~22KB·최대 ~46KB(대부분 `dynamic_tools`·`base_instructions`)라 1MiB 는 ~22배 여유.
    static let codexProbeByteLimit = 1 << 20

    private static let codexProbeChunkSize = 64 * 1024

    private enum CodexProbeOutcome {
        case sessionID(String?)   // session_meta 발견 — id 가 비어 있으면 nil(기존 동작 유지)
        case stop                 // token_count 도달 — 그 앞에 meta 가 없었다
        case invalid              // 비어 있지 않은 줄이 UTF-8이 아님 — 이후 metadata로 오인하지 않음
        case keepScanning
    }

    /// 오래된 parent dependency를 찾기 위한 metadata-only probe. 대형 rollout 전체를 읽지 않는다.
    ///
    /// **고정 크기 prefix 를 통째로 디코드하면 안 된다.** 컷이 멀티바이트 문자 중간에 떨어지면
    /// `String(data:encoding:)` 이 통째로 nil 이 되어(실측: 로컬 rollout 109개 중 14개가 64KB 경계에서
    /// strict 디코드 실패) "세션 id 없음"으로 잘못 보고하고, 첫 줄이 컷보다 길어도 같은 결과가 된다.
    /// → chunk 를 읽되 **개행으로 완성된 줄만** 디코드한다.
    /// 결과가 `nil` 이면 **정상적으로 읽었지만 쓸 수 있는 metadata 가 없다**는 뜻이다(meta 부재·
    /// token_count 선행·손상된 줄·상한 초과 — 모두 파일 내용의 결정적 속성이라 재시도해도 같다).
    /// 파일을 열거나 읽지 못한 경우는 throw 한다. 그 둘을 합치면 일시적인 I/O 실패가 "세션 id 없음"
    /// 으로 캐시에 굳어, 파일의 mtime·size 가 바뀔 때까지 잘못된 판정이 유지된다.
    static func probeCodexRolloutSessionID(
        at url: URL,
        byteLimit: Int = codexProbeByteLimit
    ) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var read = 0
        while read < byteLimit {
            // 남은 예산까지만 읽어 상한을 정확히 지킨다(0 바이트 요청 = EOF 오인 방지).
            guard let chunk = try handle.read(upToCount: min(codexProbeChunkSize, byteLimit - read)),
                  !chunk.isEmpty else {
                // EOF — 개행 없이 끝나는 마지막 줄도 완성된 줄로 취급한다.
                if case .sessionID(let id) = codexProbeOutcome(of: buffer) { return id }
                return nil
            }
            read += chunk.count
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while lineStart < buffer.endIndex,
                  let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let line = Data(buffer[lineStart..<newline])
                let nextLineStart = buffer.index(after: newline)
                switch codexProbeOutcome(of: line) {
                case .sessionID(let id): return id
                case .stop, .invalid: return nil
                case .keepScanning: lineStart = nextLineStart
                }
            }
            // 줄마다 남은 buffer 전체를 복사하지 않고, 이번 chunk에서 소비한 prefix를 한 번만 제거.
            if lineStart != buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
        }
        // 파일이 개행 없이 정확히 byteLimit에서 끝난 경우에도 완성된 JSON 한 줄이면 인정한다.
        if case .sessionID(let id) = codexProbeOutcome(of: buffer) { return id }
        return nil   // 상한 도달 — 아직 meta 를 못 찾았거나 줄이 완성되지 않았다
    }

    /// 읽기 실패를 "metadata 없음"과 같은 `nil` 로 합치는 편의 API.
    /// **결과를 영속화하는 호출자는 `probeCodexRolloutSessionID` 를 써야 한다** — 이 래퍼로 얻은
    /// `nil` 을 캐시에 남기면 일시적 I/O 실패가 그대로 굳는다.
    static func codexRolloutSessionID(at url: URL, byteLimit: Int = codexProbeByteLimit) -> String? {
        try? probeCodexRolloutSessionID(at: url, byteLimit: byteLimit)
    }

    private static func codexProbeOutcome(of line: Data) -> CodexProbeOutcome {
        guard !line.isEmpty else { return .keepScanning }
        // 손상된 줄을 건너뛰면 뒤에 재삽입된 parent meta를 이 파일의 id로
        // 오인할 수 있으므로 중단한다. probe 는 1MiB 상한이 있어 UTF-8 검증 비용이 제한된다.
        guard String(data: line, encoding: .utf8) != nil else { return .invalid }
        if line.range(of: codexSessionMetaMarker) != nil,
           let meta = codexSessionMeta(line) { return .sessionID(meta.id) }
        if line.range(of: codexTokenCountMarker) != nil { return .stop }
        return .keepScanning
    }

    /// 부모 관계가 확인된 rollout끼리 usage-state prefix를 대조해 실제로 복사된 replay만 제거.
    /// 부모를 찾을 수 없는 manual fork만 기존 1초 trimming을 fallback으로 사용.
    /// 실제 fixture에서 replay가 없다고 확인된 subagent는 부모 파일 유무와 관계없이 모두 보존.
    static func resolveCodexRollouts(
        _ rollouts: [CodexParsedRollout],
        includedPaths: Set<String>
    ) -> [Entry] {
        let bySession = Dictionary(grouping: rollouts.compactMap { rollout in
            rollout.sessionID.map { ($0, rollout) }
        }, by: \.0).mapValues { $0.map(\.1).sorted { $0.path < $1.path } }
        let byPath = Dictionary(uniqueKeysWithValues: rollouts.map { ($0.path, $0) })
        var memo: [String: CodexResolvedRollout] = [:]

        func resolve(_ rollout: CodexParsedRollout, visiting: inout Set<String>) -> CodexResolvedRollout {
            if let cached = memo[rollout.path] { return cached }
            guard visiting.insert(rollout.path).inserted else {
                return resolveOwnedEvents(rollout, replayCount: fallbackReplayCount(rollout))
            }
            defer { visiting.remove(rollout.path) }

            var bestParentMatch: (replayCount: Int, history: [CodexResolvedEvent])?
            if let parentID = rollout.parentSessionID {
                for candidate in bySession[parentID] ?? [] where candidate.path != rollout.path {
                    let resolvedParent = resolve(candidate, visiting: &visiting)
                    // prefix 가 하나도 안 겹치면(=0) 부모를 찾았어도 대조할 근거가 없다. 후보로 세면
                    // replayCount 0 으로 아무것도 못 자르고 시간 fallback 도 건너뛰어 부모를 못 찾은
                    // 경우보다 나빠진다(CLI 가 바뀌어 첫 vector 부터 어긋나는 fork). 여기서 걸러
                    // `bestParentMatch` 는 "실제로 겹치는 prefix 를 가진 부모"만 담게 한다.
                    guard let replayCount = comparableUsagePrefixCount(
                        rollout.events,
                        resolvedParent.history
                    ), replayCount > 0 else { continue }
                    if let current = bestParentMatch {
                        if replayCount > current.replayCount {
                            bestParentMatch = (replayCount, resolvedParent.history)
                        }
                    } else {
                        bestParentMatch = (replayCount, resolvedParent.history)
                    }
                }
            }

            let resolved: CodexResolvedRollout
            if let bestParentMatch {
                resolved = resolveOwnedEvents(
                    rollout,
                    replayCount: bestParentMatch.replayCount,
                    inheritedHistory: Array(
                        bestParentMatch.history.prefix(bestParentMatch.replayCount)
                    )
                )
            } else if rollout.parentSessionID != nil {
                // 부모를 못 찾았거나 구형 usage에 cumulative state가 없어 구조 비교가 불가능.
                // 실제 subagent는 fallbackReplayCount에서 보존하고 manual fork만 기존 시간 fallback.
                resolved = resolveOwnedEvents(rollout, replayCount: fallbackReplayCount(rollout))
            } else {
                resolved = resolveOwnedEvents(rollout, replayCount: 0)
            }
            memo[rollout.path] = resolved
            return resolved
        }

        var result: [Entry] = []
        for path in includedPaths.sorted() {
            guard let rollout = byPath[path] else { continue }
            var visiting: Set<String> = []
            result.append(contentsOf: resolve(rollout, visiting: &visiting).ownedEntries)
        }
        return dedupCodexCanonicalEntries(result)
    }

    /// 동일 canonical state가 여러 파일에 남아도 원래 시각에 가까운 가장 이른 기록을 보존.
    /// token vector가 ID에 포함되므로 keep-max가 아니라 keep-earliest가 Codex의 날짜 의미에 적절한듯.
    private static func dedupCodexCanonicalEntries(_ entries: [Entry]) -> [Entry] {
        var byID: [String: Entry] = [:]
        var order: [String] = []
        for entry in entries {
            if let existing = byID[entry.id] {
                if entry.date < existing.date { byID[entry.id] = entry }
            } else {
                byID[entry.id] = entry
                order.append(entry.id)
            }
        }
        return order.compactMap { byID[$0] }
    }

    /// 비교 가능한 full usage state의 공통 prefix 길이. `nil`은 prefix 0이 아니라
    /// cumulative state 부재로 구조 비교 자체가 불가능함을 의미.
    private static func comparableUsagePrefixCount(
        _ child: [CodexUsageEvent],
        _ parent: [CodexResolvedEvent]
    ) -> Int? {
        if child.isEmpty { return 0 }
        guard !parent.isEmpty else { return nil }
        var count = 0
        while count < child.count, count < parent.count {
            guard let childState = child[count].usageState,
                  let parentState = parent[count].usageState else { return nil }
            guard childState == parentState else { break }
            count += 1
        }
        return count
    }

    private static func fallbackReplayCount(_ rollout: CodexParsedRollout) -> Int {
        // 확인된 0.142.5/0.145.0 subagent는 parent metadata만 삽입하고 token_count는 replay하지 않음.
        // parent 파일이 삭제됐다는 이유만으로 첫 실제 subagent 턴을 timing heuristic으로 버리면 안 됨.
        if rollout.isSubagent { return 0 }
        let events = rollout.events
        guard events.count > 1 else { return events.isEmpty ? 0 : 1 }
        var count = 1
        while count < events.count {
            let gap = events[count].entry.date.timeIntervalSince(events[count - 1].entry.date)
            guard gap < forkReplayMaximumGap else { break }
            count += 1
        }
        return count
    }

    private static func resolveOwnedEvents(
        _ rollout: CodexParsedRollout,
        replayCount: Int,
        inheritedHistory: [CodexResolvedEvent] = []
    ) -> CodexResolvedRollout {
        var history = inheritedHistory
        var ownedEntries: [Entry] = []
        var epoch = 0
        var previousCumulative: CodexUsageVector?
        var previousOwner: String?

        for event in rollout.events.dropFirst(replayCount) {
            // fork 파일의 unmatched suffix는 embedded parent meta 뒤에 있어도 child 소유이므로.
            // non-fork 파일의 실제 session 전환은 event 시점 session id를 따름.
            let owner = rollout.parentSessionID == nil
                ? (event.sessionID ?? rollout.sessionID)
                : rollout.sessionID
            if owner != previousOwner {
                epoch = 0
                previousCumulative = nil
                previousOwner = owner
            }
            if let cumulative = event.usageState?.cumulative {
                if let previousCumulative, cumulative.isLower(than: previousCumulative) {
                    epoch += 1
                }
                previousCumulative = cumulative
            } else {
                previousCumulative = nil
            }

            let entry: Entry
            if let owner, let state = event.usageState {
                entry = replacingID(
                    of: event.entry,
                    with: "codex|\(owner)|\(epoch)|\(state.fingerprint)"
                )
            } else {
                // 누적 usage 또는 session id가 없는 구형 레코드는 기존 positional id를 유지.
                entry = event.entry
            }
            ownedEntries.append(entry)
            history.append(CodexResolvedEvent(entry: entry, usageState: event.usageState))
        }
        return CodexResolvedRollout(history: history, ownedEntries: ownedEntries)
    }

    private static func replacingID(of entry: Entry, with id: String) -> Entry {
        Entry(
            id: id,
            date: entry.date,
            localDay: entry.localDay,
            model: entry.model,
            input: entry.input,
            output: entry.output,
            cacheWrite: entry.cacheWrite,
            cacheRead: entry.cacheRead,
            explicitCost: entry.explicitCost
        )
    }

    private static func parseCodexLine(
        _ line: Data, file: String, turn: Int, model: String, fmt: DateFormatter
    ) -> ParsedCodexToken? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let date = ISO8601Parser.date(from: ts) else { return nil }
        let inputTotal = intValue(last["input_tokens"])
        let cached = intValue(last["cached_input_tokens"])
        let output = intValue(last["output_tokens"])
        let nonCachedInput = max(0, inputTotal - cached)
        let entry = Entry(
            id: "codex|\(file)|\(turn)",
            date: date, localDay: fmt.string(from: date), model: model,
            input: nonCachedInput, output: output, cacheWrite: 0, cacheRead: cached)
        let usageState = (info["total_token_usage"] as? [String: Any]).map {
            CodexUsageState(cumulative: CodexUsageVector($0), last: CodexUsageVector(last))
        }
        return ParsedCodexToken(entry: entry, usageState: usageState)
    }

    // MARK: Gemini 파싱

    /// Gemini CLI 세션 파일(~/.gemini/tmp/<hash>/chats/session-*.jsonl 및 레거시 .json) 파싱.
    /// - 신규 .jsonl: 라인 단위 레코드 — type=="gemini" 메시지의 인라인 tokens, 또는
    ///   type=="message_update" 의 tokens (같은 id 는 마지막 값이 최종).
    /// - 레거시 .json: 단일 ConversationRecord { messages: [...] } 의 message.tokens.
    /// 토큰 매핑(usageMetadata 의미 보존, Entry.total == totalTokenCount):
    ///   input = (input − cached) + tool(toolUsePrompt, 입력측) / cacheRead = cached
    ///   output = output + thoughts(출력측 reasoning) / cacheWrite = 0
    static func parseGeminiFile(_ url: URL, fmt: DateFormatter) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let file = url.lastPathComponent
        // 메시지 id → (레코드, 토큰) — message_update 가 나중에 오면 갱신
        var byID: [String: Entry] = [:]
        var order: [String] = []

        func absorb(_ obj: [String: Any], fallbackTimestamp: Date?) {
            guard let tokens = obj["tokens"] as? [String: Any] else { return }
            let id = (obj["id"] as? String) ?? UUID().uuidString
            let ts = (obj["timestamp"] as? String).flatMap { ISO8601Parser.date(from: $0) } ?? fallbackTimestamp
            guard let date = ts else { return }
            let input = intValue(tokens["input"])
            let cached = intValue(tokens["cached"])
            let entry = Entry(
                id: "gemini|\(file)|\(id)", date: date, localDay: fmt.string(from: date),
                model: (obj["model"] as? String) ?? "gemini",
                input: max(0, input - cached) + intValue(tokens["tool"]),
                output: intValue(tokens["output"]) + intValue(tokens["thoughts"]),
                cacheWrite: 0, cacheRead: cached)
            if byID[id] == nil { order.append(id) }
            byID[id] = entry   // update 레코드가 최종값
        }

        if url.pathExtension == "jsonl" {
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            var lastTimestamp: Date?
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                autoreleasepool {   // JSONSerialization 의 autoreleased 객체를 라인마다 배출(콜드 파싱 피크 억제)
                    guard line.contains("\"tokens\"") || line.contains("\"timestamp\"") else { return }
                    guard let d = String(line).data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
                    if let ts = (obj["timestamp"] as? String).flatMap({ ISO8601Parser.date(from: $0) }) {
                        lastTimestamp = ts
                    }
                    absorb(obj, fallbackTimestamp: lastTimestamp)
                }
            }
        } else {
            // 레거시 단일 JSON — messages 배열
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = obj["messages"] as? [[String: Any]] else { return [] }
            let sessionStart = (obj["startTime"] as? String).flatMap { ISO8601Parser.date(from: $0) }
            for m in messages { absorb(m, fallbackTimestamp: sessionStart) }
        }
        return order.compactMap { byID[$0] }
    }

    static func geminiEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        let fmt = localDayFormatter()
        let roots = root.map { [$0] } ?? geminiScanRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "gemini"))
        var entries: [Entry] = []
        for scanRoot in roots {
            for file in jsonlFiles(in: scanRoot, modifiedSince: modifiedSince, allowJSON: true) {
                entries.append(contentsOf: parseGeminiFile(file, fmt: fmt))
            }
        }
        return dedupKeepMax(entries)
    }

    // MARK: Grok 파싱

    /// 세션 디렉토리에서 토큰이 담긴 유일한 파일. `chat_history.jsonl` 의 대화 아이템엔 usage 필드가
    /// 없고 `events.jsonl` 은 턴 결과만 남기므로, 같이 스캔하면 빈 blob 으로 캐시만 불린다.
    static let grokUpdatesFileName = "updates.jsonl"

    /// Grok CLI 세션 루트. CLI 와 같은 규칙으로 `$GROK_HOME` 을 우선한다.
    /// GUI 앱은 셸 환경을 상속하지 않으므로 `UsageEnvironment` 를 통해 읽는다 — 프로세스 환경만
    /// 보면 `~/.zshrc` 에 export 해 둔 사용자가 앱에서만 조용히 0 을 본다.
    static var grokSessionsDir: URL {
        if let home = UsageEnvironment.value("GROK_HOME")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("sessions")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions")
    }

    /// Grok CLI 세션 파일(`~/.grok/sessions/<id>/updates.jsonl`) 파싱.
    ///
    /// 턴이 끝날 때마다 durable 로 append 되는 `sessionUpdate:"turn_completed"` 라인의 `usage`
    /// (= 그 프롬프트 한 턴의 사용량)만 읽는다. 라인 봉투는
    /// `{"timestamp":<초>,"method":"_x.ai/session/update","params":{"sessionId":…,"update":{…},"_meta":{…}}}`.
    ///
    /// 같은 파일의 다른 토큰 필드(`_meta.totalTokens`, auto-compact/subagent 진행 이벤트)는 *컨텍스트
    /// 창 크기*라 사용량이 아니다 — 섞으면 합계가 크게 부풀어 오른다. `turn_completed` 의 `usage` 만 본다.
    /// rewind 로 버려진 분기의 턴도 그대로 센다: 되돌려도 그 토큰은 이미 청구됐다(대화 재생과 다른 질문).
    ///
    /// 토큰 매핑 — `Entry.total == usage.totalTokens` 가 성립하게 맞춘다:
    /// - `inputTokens`(camelCase)는 **캐시 읽기를 포함한** 전체 프롬프트 →
    ///   `input = inputTokens − cachedReadTokens`, `cacheRead = cachedReadTokens`.
    /// - `input_tokens`(snake_case)는 **이미 캐시 제외** → 그대로 input. 두 표기의 의미가 서로
    ///   달라서 값 스펠링으로 분기한다(같은 값으로 취급하면 캐시분을 두 번 뺀다).
    /// - `output = outputTokens` (reasoning 은 output 에 포함), `cacheWrite = 0`
    ///   (Grok 은 캐시 쓰기를 prompt 토큰에 접어 넣는다).
    static func parseGrokFile(_ url: URL, fmt: DateFormatter) -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // updates.jsonl 은 스트리밍 청크까지 전부 라인으로 남는다(세션당 수만 라인) →
            // JSON 파싱 전에 문자열로 걸러낸다.
            guard line.contains("turn_completed") else { continue }
            autoreleasepool {   // JSONSerialization 의 autoreleased 객체를 라인마다 배출
                if let e = parseGrokLine(String(line), fmt: fmt) { out.append(e) }
            }
        }
        return dedupKeepMax(out)
    }

    static func grokEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        let fmt = localDayFormatter()
        let roots = root.map { [$0] } ?? grokSessionRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "grok"))
        var entries: [Entry] = []
        for scanRoot in roots {
            for file in jsonlFiles(in: scanRoot, modifiedSince: modifiedSince)
            where isGrokUsageFile(file) {
                entries.append(contentsOf: parseGrokFile(file, fmt: fmt))
            }
        }
        // fork 세션이 부모 updates 를 복사해도 턴 id 가 같아 한 번만 남는다(전역 dedup).
        return dedupKeepMax(entries)
    }

    /// 집계 대상 파일인가 — 사용량이 담긴 `updates.jsonl` 이고, 서브에이전트 세션이 아닌 것.
    ///
    /// 서브에이전트 세션의 토큰은 부모 턴 usage 에 이미 접혀 들어오므로(RecordSubagentUsage) 여기서
    /// 또 세면 이중 집계다. CLI 가 세션 목록에서 숨기는 것과 같은 판정(`session_kind` 접두사)을 쓴다.
    ///
    /// **파일 선택 단계에서 판정한다** — 파싱 결과 캐시(blob)는 `updates.jsonl` 의 mtime·size 로만
    /// 무효화되는데 이 판정의 근거는 옆 파일(`summary.json`)이다. 파싱 안에서 걸러내면 "summary 가
    /// 아직 session_kind 를 못 쓴 시점에 파싱된" 서브에이전트 세션이 blob 에 그대로 굳어 이중집계가
    /// 영구화된다(파일이 더 안 바뀌므로 캐시가 계속 히트). 선택 단계는 매 새로고침 재평가돼 자연 복구된다.
    ///
    /// 알려진 한계: 부모 턴이 끝난 뒤 완료된 서브에이전트는 부모 프롬프트 원장이 아니라 세션 원장에만
    /// 접히므로 그만큼 과소집계된다. 매 턴 도는 이중집계보다 작아서 택한 쪽이고, 그 경우 CLI 는 부모
    /// bill 에 usageIsIncomplete 를 세워 비용도 신뢰 대상에서 빠진다.
    static func isGrokUsageFile(_ url: URL) -> Bool {
        guard url.lastPathComponent == grokUpdatesFileName else { return false }
        return !grokSessionIsSubagent(url.deletingLastPathComponent())
    }

    /// `summary.json` 의 `session_kind` 가 서브에이전트 계열(subagent/subagent_fork/subagent_resume)인가.
    /// 파일이 없거나 못 읽으면 사용자 세션으로 본다 — CLI 는 세션 생성 시 summary 를 먼저 쓰므로
    /// 부재는 "턴이 아직 없는 새 세션"(= 셀 것도 없음)이다.
    private static func grokSessionIsSubagent(_ sessionDir: URL) -> Bool {
        // `hidden` 은 쓰지 않는다 — 사용자가 직접 숨긴 정상 세션까지 빠져 과소집계가 된다.
        // 서브에이전트는 생성 시점에 session_kind 가 반드시 찍히므로 이 신호만으로 충분하다.
        guard let data = try? Data(contentsOf: sessionDir.appendingPathComponent("summary.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["session_kind"] as? String else { return false }
        return kind.hasPrefix("subagent")
    }

    private static func parseGrokLine(_ line: String, fmt: DateFormatter) -> Entry? {
        // 디스크 라인은 봉투 → 알림 → 업데이트 세 겹이다:
        //   {timestamp:<초>, method:"_x.ai/session/update", params:{sessionId, update:{sessionUpdate,…}, _meta}}
        // `method` 없는 구형 라인은 알림 그 자체(봉투 없음)라 한 겹으로 받는다.
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let notification = (envelope["params"] as? [String: Any]) ?? envelope
        guard let update = notification["update"] as? [String: Any],
              (update["sessionUpdate"] as? String) == "turn_completed",
              let usage = update["usage"] as? [String: Any] else { return nil }
        let meta = notification["_meta"] as? [String: Any]
        // 재생 표시가 붙은 라인은 건너뛴다. 주 방어는 아래 턴 id dedup 이고 이건 보조다
        // (재생은 대개 전송 경로에만 표시가 붙어 디스크엔 안 남는다).
        if boolValue(meta?["isReplay"]) { return nil }
        // 턴 식별자는 `prompt_id` 뿐이다. 세션 경로를 섞지 않아 fork 가 부모 updates 를 복사해도
        // 같은 턴이 하나로 접힌다(전역 유일한 uuid — 합성 턴은 접두사 붙은 uuid). `_meta.eventId`
        // 같은 대체 키는 쓰지 않는다: 전역 유일성이 보장되지 않아 서로 다른 세션의 턴을 합쳐버릴 수 있다.
        guard let turnID = nonEmpty(update["prompt_id"] as? String),
              let date = grokDate(envelope: envelope, meta: meta) else { return nil }

        // `null` 을 "값 있음"으로 착각하면 캐시분을 잘못 빼거나 토큰을 0으로 만든다 → intOrNil.
        let output = intOrNil(usage["outputTokens"]) ?? intOrNil(usage["output_tokens"]) ?? 0
        let reportedCacheRead = intOrNil(usage["cachedReadTokens"]) ?? intOrNil(usage["cached_read_tokens"]) ?? 0
        let (input, cacheRead): (Int, Int)
        if let full = intOrNil(usage["inputTokens"]) {
            // 캐시 읽기는 프롬프트의 부분집합이라 전체보다 클 수 없다. clamp 로 identity 를 지킨다
            // (max(0,·) 로 뭉개면 input+cacheRead 가 inputTokens 를 넘어 total 이 조용히 부풀었다).
            let clamped = min(reportedCacheRead, full)
            (input, cacheRead) = (full - clamped, clamped)
        } else {
            // 헤드리스 투영은 input_tokens 가 이미 캐시 제외값이다.
            (input, cacheRead) = (intOrNil(usage["input_tokens"]) ?? 0, reportedCacheRead)
        }
        // 소스가 말하는 total 과 어긋나면 남는 분을 output 에 귀속시켜 identity 를 맞춘다
        // (모델별 행 합산 방식이 바뀌어 부분합이 어긋나도 합계는 소스를 따르게 — 다른 리더와 같은 규칙).
        if let reportedTotal = intOrNil(usage["totalTokens"]) ?? intOrNil(usage["total_tokens"]) {
            let parts = input + output + cacheRead
            if reportedTotal > parts { return grokEntry(turnID: turnID, date: date, fmt: fmt, usage: usage,
                                                        input: input, output: output + (reportedTotal - parts),
                                                        cacheRead: cacheRead) }
        }
        return grokEntry(turnID: turnID, date: date, fmt: fmt, usage: usage,
                         input: input, output: output, cacheRead: cacheRead)
    }

    private static func grokEntry(turnID: String, date: Date, fmt: DateFormatter, usage: [String: Any],
                                  input: Int, output: Int, cacheRead: Int) -> Entry? {
        guard input + output + cacheRead > 0 else { return nil }   // 0 토큰 턴(취소 등)은 기록하지 않는다
        return Entry(
            id: "grok|\(turnID)", date: date, localDay: fmt.string(from: date),
            model: grokModel(usage) ?? "grok",
            input: input, output: output, cacheWrite: 0, cacheRead: cacheRead,
            explicitCost: grokCost(usage))
    }

    /// 표시용 모델명 — per-model 내역의 키에서 고른다. 토큰이 가장 많은 행이 대표(동수는 이름 순).
    /// 숫자는 항상 totals 로 집계한다(행 합계와 totals 가 어긋날 여지를 만들지 않는다).
    private static func grokModel(_ usage: [String: Any]) -> String? {
        guard let byModel = (usage["modelUsage"] as? [String: Any])
                ?? (usage["model_usage"] as? [String: Any]) else { return nil }
        var best: (model: String, total: Int)?
        for (model, raw) in byModel.sorted(by: { $0.key < $1.key }) {
            let fields = raw as? [String: Any] ?? [:]
            let total = intOrNil(fields["totalTokens"]) ?? intOrNil(fields["total_tokens"]) ?? 0
            if best == nil || total > best!.total { best = (model, total) }
        }
        return best.flatMap { nonEmpty($0.model) }
    }

    /// 서버가 계산한 비용만 쓴다(1e10 ticks = $1). 부분합·불완전 집계 플래그가 서 있으면 버린다
    /// (Grok 모델 단가표가 없으므로 추정 대신 0 — 금액 오표시를 만들지 않는다).
    private static func grokCost(_ usage: [String: Any]) -> Double? {
        if boolValue(usage["usageIsIncomplete"]) || boolValue(usage["usage_is_incomplete"]) { return nil }
        if boolValue(usage["costIsPartial"]) || boolValue(usage["cost_is_partial"]) { return nil }
        let ticks = doubleOrNil(usage["costUsdTicks"]) ?? doubleOrNil(usage["cost_usd_ticks"]) ?? 0
        return ticks > 0 ? ticks / 1e10 : nil
    }

    /// 턴 시각은 `_meta.agentTimestampMs`(에이전트가 그 턴에 찍은 시각)를 **우선**한다.
    /// 봉투 `timestamp` 는 *기록* 시각(Unix 초)이고 fork 가 부모 updates 를 복사할 때 새로 찍히므로,
    /// 그것만 쓰면 포크된 세션의 과거 사용량이 전부 포크 시점 날짜로 몰린다(주·월·오늘 합계 왜곡).
    /// `_meta` 는 복사 시 sessionId 만 교체되고 그대로 보존돼 원래 턴 시각을 지킨다.
    private static func grokDate(envelope: [String: Any], meta: [String: Any]?) -> Date? {
        let ms = doubleOrNil(meta?["agentTimestampMs"]) ?? 0
        if ms > 0 { return Date(timeIntervalSince1970: ms / 1000) }
        let raw = doubleOrNil(envelope["timestamp"]) ?? 0
        // 봉투는 초 단위지만, 밀리초로 오는 변형도 흡수한다(다른 로컬 리더와 같은 임계).
        if raw > 0 { return Date(timeIntervalSince1970: raw >= 100_000_000_000 ? raw / 1_000 : raw) }
        if let ts = envelope["timestamp"] as? String { return ISO8601Parser.date(from: ts) }
        return nil
    }

    private static func codexModel(_ line: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }
        if let m = payload["model"] as? String { return m }
        if let tc = payload["turn_context"] as? [String: Any], let m = tc["model"] as? String { return m }
        return nil
    }

    // MARK: 집계

    /// 특정 로컬 날짜의 합계 → DailyUsage. 해당 날짜 데이터 없으면 nil.
    static func daily(entries: [Entry], localDay: String) -> DailyUsage? {
        var b = Bucket()
        for e in entries where e.localDay == localDay { b.add(e) }
        guard b.total > 0 else { return nil }
        return DailyUsage(date: localDay, inputTokens: b.input, outputTokens: b.output,
                          cacheCreationTokens: b.cacheWrite, cacheReadTokens: b.cacheRead,
                          totalTokens: b.total, totalCost: b.cost)
    }

    /// 로컬 날짜 [start, end] (포함) 범위 합계 → PeriodUsage.
    static func period(entries: [Entry], periodKey: String, fromDay: String, toDay: String) -> PeriodUsage {
        var b = Bucket()
        for e in entries where e.localDay >= fromDay && e.localDay <= toDay { b.add(e) }
        return PeriodUsage(period: periodKey, totalTokens: b.total, totalCost: b.cost)
    }

    /// 최근 5시간 롤링 윈도우 기반 활성 블록(번 레이트 추정용).
    static func activeBlock(entries: [Entry], now: Date) -> BlockUsage? {
        let windowStart = now.addingTimeInterval(-blockWindow)
        let recent = entries.filter { $0.date >= windowStart }.sorted { $0.date < $1.date }
        guard let first = recent.first else { return nil }
        var b = Bucket()
        for e in recent { b.add(e) }
        let minutes = max(1, now.timeIntervalSince(first.date) / 60)
        let tpm = Double(b.total) / minutes
        let iso = ISO8601DateFormatter()
        return BlockUsage(
            id: "block-\(Int(first.date.timeIntervalSince1970))",
            startTime: iso.string(from: first.date),
            endTime: iso.string(from: first.date.addingTimeInterval(blockWindow)),
            isActive: true, totalTokens: b.total, costUSD: b.cost, tokensPerMinute: tpm)
    }

    // MARK: 유틸

    static func startOfMonth(_ date: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: date)) ?? date
    }

    static func startOfWeek(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// enrichment(활성 블록·이번 주·이번 달)를 한 번의 스캔에서 모두 도출하므로, mtime 하한은
    /// 그 세 윈도우 중 **가장 이른 시작**이어야 한다. append-only 로그에서 "범위 시작 이전에 수정된
    /// 파일엔 범위 내 엔트리가 없다"는 전제가 성립하려면 스캔 하한 ≤ 모든 표시 윈도우의 시작이어야 하기 때문.
    ///
    /// 함정: monthStart 만 하한으로 쓰면 **월초**에 이번 주 시작(weekStart)이 지난달로 넘어가고
    /// (2026년 12개월 중 11개월이 그렇다) 자정 직후엔 5h 블록이 어제로 넘어가, 지난달에 수정된 세션
    /// 파일이 스캔에서 빠지며 주간 합계·번레이트가 며칠간 과소집계된다. min 으로 그 경계를 흡수한다.
    /// (OpenCode/Hermes 경로엔 이미 `now-7일` 하한이 있었으나 Claude/Codex/Gemini 경로엔 없어
    /// 드리프트했다 — 네 프로바이더가 이 단일 소스를 공유하게 통일.)
    static func enrichmentScanStart(now: Date) -> Date {
        min(startOfMonth(now), startOfWeek(now), now.addingTimeInterval(-blockWindow))
    }

    static func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"; f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static func todayKey() -> String { localDayFormatter().string(from: Date()) }

    static func localDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// 파싱 상한 — 실사용(수십억)의 10만 배라 정상 사용량을 자르지 않는다.
    /// `Int.max` 로 잡지 않는 이유: 클램프 자체는 되지만 `output + thoughts` 처럼 **파싱 직후 더하는**
    /// 지점에서 다시 오버플로 트랩이 난다. 이 값끼리 여러 번 더해도 Int64 안에 머무는 상한이어야 한다.
    static let maxParsedTokenValue = 1_000_000_000_000_000

    /// 숫자를 안전한 Int 로. 값이 없거나 숫자가 아니면 0.
    ///
    /// 예전엔 `Int(d)` 를 직접 불러 `1e30` 같은 값에서 **트랩(크래시)** 했다. 사용량 로그는 앱 밖에서
    /// 오고(손편집·전송 손상·업스트림 버그) 그 파일은 디스크에 남으므로, 한 번 들어오면 새로고침마다
    /// 그리고 재기동마다 다시 죽는다 — 사용자가 파일을 손으로 지우기 전까지 앱을 못 쓴다.
    /// 클램프는 크래시보다 안전한 열화다. `intOrNil` 과 같은 규칙을 쓰되 부재를 0 으로 접는다.
    private static func intValue(_ v: Any?) -> Int { intOrNil(v) ?? 0 }

    /// 숫자가 실제로 있을 때만 값을 준다. JSON `null`(=`NSNull`)·문자열·키 부재는 모두 nil —
    /// `usage["x"] != nil` 로 존재를 판정하면 null 이 "값 있음"으로 통과해 0 으로 뭉개진다.
    private static func doubleOrNil(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, !(v is NSNull) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    private static func intOrNil(_ v: Any?) -> Int? {
        guard let d = doubleOrNil(v) else { return nil }
        guard d > 0 else { return 0 }                            // 음수 토큰은 없다
        // 비정상 큰 값에 트랩되지 않게. 상한이 maxParsedTokenValue 인 이유는 그 정의 주석 참조.
        return d >= Double(maxParsedTokenValue) ? maxParsedTokenValue : Int(d)
    }

    private static func boolValue(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    private static func nonEmpty(_ v: String?) -> String? {
        guard let t = v?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
