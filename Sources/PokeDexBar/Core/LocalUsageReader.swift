import Foundation

/// Claude/Codex 로컬 사용 로그를 직접 파싱해 토큰/비용을 집계한다(ccusage CLI 대체).
///
/// - Claude: `~/.claude/projects/**/*.jsonl` 의 `type:"assistant"` 라인
///   (`message.usage` 4종 토큰, `message.model`, `message.id`+`requestId`, `timestamp`).
///   세션 재개/sidechain 으로 같은 메시지가 여러 파일에 중복 → `(message.id, requestId)` 로 dedup.
/// - Codex: `~/.codex/sessions/**/rollout-*.jsonl` 의 `event_msg.payload.type:"token_count"`
///   (`info.last_token_usage` 턴 델타) 합산.
///
/// 성능: mtime 윈도우로 스캔 파일을 한정(범위 시작 이전에 수정된 파일은 범위 내 엔트리가 없음).
enum LocalUsageReader {

    /// 활성 블록(번 레이트)과 enrichment 스캔 하한이 공유하는 5시간 롤링 윈도우 길이.
    static let blockWindow: TimeInterval = 5 * 3600
    /// "지금 돌아가고 있나"를 재는 짧은 창(`recentRate`). 5분인 이유: 에이전트가 생각하거나
    /// 사용자가 타이핑하는 수십 초 공백에는 안 식고, 손을 뗀 뒤엔 5분 안에 0으로 돌아온다.
    static let recentWindow: TimeInterval = 5 * 60
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

    static var claudeProjectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
    static var codexSessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
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
    static func claudeEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        let fmt = localDayFormatter()
        var all: [Entry] = []
        for file in jsonlFiles(in: root ?? claudeProjectsDir, modifiedSince: modifiedSince) {
            all.append(contentsOf: parseClaudeFile(file, fmt: fmt))
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

    // MARK: Codex 파싱

    /// Codex 사용 엔트리. token_count 이벤트의 last_token_usage(턴 델타)를 4종 토큰으로 매핑.
    /// - input(비캐시) = input_tokens − cached_input_tokens, cacheRead = cached_input_tokens
    /// - output = output_tokens (reasoning 은 output 에 이미 포함), cacheWrite = 0
    /// Codex 파일 하나를 파싱(세션 단위 — token_count 이벤트의 턴 델타). 캐시가 파일 단위로 호출.
    static func parseCodexFile(_ url: URL, fmt: DateFormatter) -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var entries: [Entry] = []
        var turn = 0
        var isScanningInitialMetadata = true
        var isForked = false
        var replayTimestamp: Date?
        // 실모델은 아래 codexModel 이 로그에서 동적 추출(신모델 자동 대응). 이 값은 세션에 model 라인이
        // 아예 없을 때만 쓰는 버전무관 폴백 — Codex 비용은 항상 0이라 표시 숫자엔 영향 없다(업데이트 불필요).
        var model = "codex"
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            autoreleasepool {   // JSONSerialization 의 autoreleased 객체를 라인마다 배출(콜드 파싱 피크 억제)
                let record = String(line)
                if isScanningInitialMetadata, isForkedSessionMeta(record) {
                    isForked = true   // child meta 뒤 parent meta가 재삽입돼도 fork 판정을 되돌리지 않는다.
                }
                if line.contains("\"model\""), let m = codexModel(record) { model = m }
                guard line.contains("token_count") else { return }
                guard let e = parseCodexLine(record, file: url.lastPathComponent, turn: turn, model: model, fmt: fmt) else { return }
                defer { turn += 1 }

                // forked rollout의 첫 token_count는 부모 이력 replay다. session_meta 기록 시각은 디스크 지연에
                // 영향받으므로 anchor로 쓰지 않는다. replay 내부는 수 ms 간격이고, 첫 1초 이상 공백부터는
                // 실제 child turn으로 간주해 이후의 빠른 turn도 모두 보존한다.
                if isScanningInitialMetadata {
                    isScanningInitialMetadata = false
                    if isForked {
                        replayTimestamp = e.date
                        return
                    }
                }
                if let previous = replayTimestamp {
                    if e.date.timeIntervalSince(previous) < Self.forkReplayMaximumGap {
                        replayTimestamp = e.date
                        return
                    }
                    replayTimestamp = nil
                }
                entries.append(e)
            }
        }
        return entries
    }

    static func codexEntries(modifiedSince: Date, root: URL? = nil) -> [Entry] {
        let fmt = localDayFormatter()
        var entries: [Entry] = []
        for file in jsonlFiles(in: root ?? codexSessionsDir, modifiedSince: modifiedSince) {
            entries.append(contentsOf: parseCodexFile(file, fmt: fmt))
        }
        return entries
    }

    private static func isForkedSessionMeta(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              ((payload["forked_from_id"] as? String)?.isEmpty == false
                  || (payload["parent_thread_id"] as? String)?.isEmpty == false) else { return false }
        return true
    }

    private static func parseCodexLine(_ line: String, file: String, turn: Int, model: String, fmt: DateFormatter) -> Entry? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
        return Entry(
            id: "codex|\(file)|\(turn)",
            date: date, localDay: fmt.string(from: date), model: model,
            input: nonCachedInput, output: output, cacheWrite: 0, cacheRead: cached)
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
        var entries: [Entry] = []
        for file in jsonlFiles(in: root ?? geminiTmpDir, modifiedSince: modifiedSince, allowJSON: true) {
            entries.append(contentsOf: parseGeminiFile(file, fmt: fmt))
        }
        return entries
    }

    // MARK: Grok 파싱

    /// 세션 디렉토리에서 토큰이 담긴 유일한 파일. `chat_history.jsonl` 의 대화 아이템엔 usage 필드가
    /// 없고 `events.jsonl` 은 턴 결과만 남기므로, 같이 스캔하면 빈 blob 으로 캐시만 불린다.
    static let grokUpdatesFileName = "updates.jsonl"

    /// Grok CLI 세션 루트. CLI 와 같은 규칙으로 `$GROK_HOME` 을 우선한다.
    static var grokSessionsDir: URL {
        if let home = ProcessInfo.processInfo.environment["GROK_HOME"]?
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
        var entries: [Entry] = []
        for file in jsonlFiles(in: root ?? grokSessionsDir, modifiedSince: modifiedSince)
        where isGrokUsageFile(file) {
            entries.append(contentsOf: parseGrokFile(file, fmt: fmt))
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

    private static func codexModel(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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

    /// 지금 돌아가고 있나 — **짧은 창**의 분당 토큰. 플로팅 펫 재생 속도가 이 값을 탄다.
    ///
    /// `activeBlock` 의 `tokensPerMinute` 를 안 쓰는 이유: 그건 5시간 창의 평균이라 한도 소진
    /// 예측에는 맞지만 "지금 세션이 돌아가나"에는 못 쓴다. 방금 폭주해도 5시간 평균은 거의 안
    /// 움직이고, 손을 뗀 뒤에도 몇 시간 높은 채로 남는다.
    ///
    /// 나누는 값은 *창 길이*지 첫 항목 이후 경과가 아니다(`activeBlock` 과 다른 점). 방금 한 건만
    /// 찍힌 순간 "1분에 30만" 같은 값이 튀지 않게 — 창을 다 채운 만큼만 빠르다.
    static func recentRate(entries: [Entry], now: Date, window: TimeInterval = recentWindow) -> Double {
        guard window > 0 else { return 0 }
        let start = now.addingTimeInterval(-window)
        var b = Bucket()
        for e in entries where e.date >= start && e.date <= now { b.add(e) }
        return Double(b.total) / (window / 60)
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

    private static func intValue(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }

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
        return d >= Double(Int.max) ? Int.max : Int(d)            // 비정상 큰 값에 트랩되지 않게
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
