import Foundation

/// ~/Library/Logs/PokeTokenBar.log 단순 append 로거 (디버깅/장애 추적용)
enum AppLog {
    /// 로그 파일 경로 — 설정의 "로그 파일 보기"(Finder 표시)에서 사용.
    static var logFileURL: URL { url }

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PokeTokenBar.log")
    }()

    /// 로그 상한 — 초과 시 .old 로 1세대 회전(무한 증가 방지, 디스크 상한 ≈ 2×maxBytes = 4MB).
    /// 24/7 메뉴바 앱이라 회전이 잦아 진단 이력이 금방 사라지던 것 완화(장애 직전 컨텍스트 보존).
    /// 레퍼런스(size-capped 회전, 수 MB)에 맞춤 — 일자별 폴더는 무한 성장/정리 필요라 채택 안 함.
    private static let maxBytes = 2 * 1024 * 1024

    private static let backend = AsyncLineLog(queue: DispatchQueue(label: "poketokenbar.log")) { line in
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > maxBytes {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// 큐에 쌓인 기록이 파일에 닿을 때까지 기다린다 — **곧 프로세스가 끝나는 자리에서만** 쓴다.
    /// `write` 는 async 라, 기록 직후 `NSApp.terminate` 이 `exit(0)` 에 닿으면 그 줄이 통째로 사라진다.
    /// serial 큐라 빈 블록을 sync 로 넣으면 앞서 넣은 기록이 모두 끝난 뒤에 돌아온다.
    static func flush() {
        backend.flush()
    }

    /// Exit-path pair: enqueue, then wait until the line has been sunk.
    /// Routes through the tested `backend.writeAndFlush` — a second
    /// `write()`+`flush()` pair is untested and reintroduces #174.
    static func writeAndFlush(_ message: String) {
        guard AppEnv.isBundledApp else { return }
        backend.writeAndFlush(formatted(message))
    }

    /// 상태가 그대로면 억제하고, 바뀌면 즉시 기록하는 `write` — 폴마다 반복되는 상태 줄 전용.
    /// 판정은 `LogRepeatSuppressor`(순수)에 있고 여기서는 잠금만 책임진다.
    /// 값이 매 틱 변하는 줄(토큰 수·합계)에는 쓰지 말 것 — 억제가 걸리지 않아 이득 없이 잠금만 든다.
    static func writeIfChanged(_ key: String, _ message: String, repeatAfter: TimeInterval = 3600) {
        guard AppEnv.isBundledApp else { return }
        suppressorLock.lock()
        let shouldWrite = suppressor.shouldWrite(key: key, message: message, repeatAfter: repeatAfter)
        suppressorLock.unlock()
        guard shouldWrite else { return }
        backend.write(formatted(message))
    }

    /// 딕셔너리 변이라 Bool 플래그와 달리 실제 경합이 위험하다 — 잠금으로 감싼다.
    nonisolated(unsafe) private static var suppressor = LogRepeatSuppressor()
    private static let suppressorLock = NSLock()

    static func write(_ message: String) {
        // 실제 .app 실행에서만 기록 — swift test / 로우 바이너리 실행이 프로덕션 로그를 오염시키지
        // 않게(형제 write 경로 writeParitySnapshot·checkLimitNotifications 와 동일 가드). 테스트가
        // 크래시 진단 로그에 fixture 값을 남기고 회전으로 실이력을 밀어내던 결함 차단.
        guard AppEnv.isBundledApp else { return }
        backend.write(formatted(message))
    }

    private static func formatted(_ message: String) -> String {
        "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    }
}

/// Serial line sink. `write` enqueues; `flush` waits until every earlier write
/// has been sunk. An async logger is not a logger on an exit path (#174) —
/// any caller that reaches `exit()` in the same turn must flush.
///
/// The sink is injected so tests can prove the drain without opening the
/// production log (`AppLog.write` is a no-op under `swift test`).
struct AsyncLineLog: Sendable {
    let queue: DispatchQueue
    let sink: @Sendable (String) -> Void

    func write(_ line: String) {
        queue.async { self.sink(line) }
    }

    func flush() {
        queue.sync {}
    }

    func writeAndFlush(_ line: String) {
        write(line)
        flush()
    }
}
