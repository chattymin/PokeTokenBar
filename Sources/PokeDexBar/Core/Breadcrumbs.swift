import Foundation

/// 크래시 직전에 무엇을 하고 있었는지. **동기로 쓴다** — 이것이 이 타입의 존재 이유다.
///
/// **왜 `AppLog` 로 안 되나.** `AppLog.write` 는 `queue.async` 로 넘긴다. 상세 화면을 여는 바로
/// 그 런루프에서 죽으면 비동기 기록은 아직 도착하지 않았고, 진단이 필요한 정확히 그 순간에
/// 없어진다.
///
/// **왜 시그널 핸들러에서 만들 수 없나.** `CrashReporter.signalHandler` 는 async-signal-safe 여야
/// 해서 `write()` 와 `StaticString` 밖에 못 쓴다. 죽는 순간에 `"species=133"` 을 조립하는 것은
/// 불가능하다. 그래서 **미리, 동기로** 디스크에 둔다.
///
/// 덮어쓰기라 파일이 안 자란다(회전 없음). 원자적 write 라 쓰는 도중에 죽어도 안 찢어진다 —
/// `CrashReporter` 의 running 마커가 이미 같은 방식을 쓴다.
enum Breadcrumbs {
    /// 들고 있을 줄 수. 크래시 직전 몇 분을 재구성하기에 충분하고, 파일은 2KB 아래로 유지된다.
    static let capacity = 20

    /// 기본 자리는 `AppEnv` 로 가른다 — 배포 앱만 실제 Logs 디렉터리에 쓴다.
    ///
    /// `AppLog` 처럼 `isBundledApp` 가드를 함수 안에 걸면 **동기 write 라는 성질 자체를 테스트할
    /// 수 없다**(테스트에서는 아무것도 안 쓰이므로). 경로를 갈라 두면 테스트는 임시 파일에
    /// 실제로 쓰면서 사용자의 진짜 파일은 안 건드린다.
    nonisolated(unsafe) static var fileURL: URL = defaultURL()

    private nonisolated(unsafe) static var ring: [String] = []
    private static let lock = NSLock()

    /// 한 줄 남긴다. **돌아왔을 때 이미 디스크에 있다.**
    ///
    /// 사용자 동작·상태 전이에서만 부른다. 사용량 틱처럼 자주 도는 자리에 걸면 링 20칸이
    /// 즉시 밀려 정작 필요한 행동이 사라지고, 메뉴바 앱의 idle 규율(CLAUDE.md)도 깨진다.
    static func record(_ line: String) {
        // 개행을 지운다 — 파일을 줄 단위로 읽으므로 한 항목이 여러 줄이 되면 링이 어긋난다.
        let flat = line.replacingOccurrences(of: "\n", with: " ")
        let stamped = "[\(ISO8601DateFormatter().string(from: Date()))] \(flat)"

        lock.lock()
        ring.append(stamped)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        let snapshot = ring.joined(separator: "\n")
        let target = fileURL
        lock.unlock()

        // 동기·원자적. 실패하면 조용히 넘어간다 — 진단이 앱을 죽이면 본말이 뒤집힌다.
        try? Data(snapshot.utf8).write(to: target, options: .atomic)
    }

    /// 지금까지의 줄들. 파일이 없으면 빈 배열(첫 실행).
    ///
    /// **파일에서 읽는다** — 메모리 링이 아니라. 크래시 다음 기동에는 링이 비어 있고 파일에만
    /// 직전 세션의 흔적이 남아 있는데, 그게 정확히 우리가 원하는 것이다.
    static func read() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// 링과 파일을 함께 비운다.
    static func clear() {
        lock.lock()
        ring = []
        let target = fileURL
        lock.unlock()
        try? FileManager.default.removeItem(at: target)
    }

    /// 테스트 격리용 — `clear()` 와 같지만 의도가 드러나는 이름.
    static func reset() { clear() }

    private static func defaultURL() -> URL {
        guard AppEnv.isBundledApp,
              let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("PokeDexBar.breadcrumbs")
        }
        let dir = logs.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(AppEnv.storageName).breadcrumbs")
    }
}
