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

    // MARK: 정규화 레코드

    struct Entry: Sendable, Codable {
        let id: String
        let date: Date
        let localDay: String
        let model: String
        let input, output, cacheWrite, cacheRead: Int
        var total: Int { input + output + cacheWrite + cacheRead }
    }

    struct Bucket {
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        var cost = 0.0
        var total: Int { input + output + cacheWrite + cacheRead }
        mutating func add(_ e: Entry) {
            input += e.input; output += e.output; cacheWrite += e.cacheWrite; cacheRead += e.cacheRead
            cost += ModelPricing.cost(model: e.model, input: e.input, output: e.output,
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
        var model = "gpt-5.5"   // 세션 모델(없으면 기본)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            autoreleasepool {   // JSONSerialization 의 autoreleased 객체를 라인마다 배출(콜드 파싱 피크 억제)
                if line.contains("\"model\""), let m = codexModel(String(line)) { model = m }
                guard line.contains("token_count") else { return }
                guard let e = parseCodexLine(String(line), file: url.lastPathComponent, turn: turn, model: model, fmt: fmt) else { return }
                turn += 1
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
            id: "codex|\(file)|\(turn)", date: date, localDay: fmt.string(from: date), model: model,
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
        let windowStart = now.addingTimeInterval(-5 * 3600)
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
            endTime: iso.string(from: first.date.addingTimeInterval(5 * 3600)),
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
}
