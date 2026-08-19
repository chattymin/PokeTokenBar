import AppKit
import Foundation

/// 앱이 크래시·강제종료·OOM(SIGKILL)·런치실패로 죽으면 **반드시 로그(AppLog)에 흔적**을 남긴다(전역 처리).
///
/// 세 겹의 방어:
/// 1) **정상종료 마커** — 잡을 수 없는 OOM/SIGKILL/watchdog kill 까지 포함해 *모든* 비정상 종료를
///    **다음 실행 때 감지**한다. 정상 종료(willTerminate) 때만 마커를 지우므로, 다음 실행에 마커가
///    남아 있으면 직전 세션이 비정상 종료된 것. (감지 recall 우선 설계 — SIGTERM(raw `pkill`) 도
///    마커 잔존→비정상으로 잡히지만, 정상 quit·logout·업데이트는 Apple Event→willTerminate 로 clean
///    처리되므로 실사용 오탐 경로는 개발용 pkill 정도라 수용.)
/// 2) **시그널 핸들러** — SIGSEGV/SIGABRT 등 잡을 수 있는 치명 시그널을 *발생 시점*에 기록
///    (async-signal-safe: write()·StaticString 만). 기록 후 기본 핸들러로 재발생시켜 macOS
///    크래시 리포트(.ips)도 생성되게 한다. 기록 대상은 **회전되지 않는 crash.log** — 메인 로그의
///    2MB 회전(rename)이 pre-open fd 를 무효화해 크래시 라인이 엉뚱한 파일로 새던 문제 회피.
/// 3) **NSException 핸들러** — 잡히지 않은 Obj-C 예외 기록.
///
/// crash.log 의 기록은 **다음 실행 때 메인 로그로 합쳐 비운다**(사용자는 PokeDexBar.log 한 곳만 봐도 됨).
enum CrashReporter {
    private static let logsDir: URL =
        AppEnv.userDirectory(.libraryDirectory)
            .appendingPathComponent("Logs")
    private static var markerURL: URL { logsDir.appendingPathComponent("\(AppEnv.storageName).running") }
    /// 크래시-시점 기록 전용(회전 안 함). 시그널/예외 핸들러가 async-signal-safe 하게 append.
    private static var crashLogURL: URL { logsDir.appendingPathComponent("\(AppEnv.storageName).crash.log") }
    /// 위 crash.log 로 미리 연 fd(설치 시 1회 open). 회전 대상이 아니라 세션 내내 유효.
    nonisolated(unsafe) fileprivate static var logFD: Int32 = -1

    /// 앱 기동 최초에 1회 호출(가능한 한 이르게 — 런치 초기 크래시도 잡히게).
    static func install(version: String) {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // 1) 직전 세션 비정상 종료 감지 — 마커가 남아 있으면 정상 종료되지 않은 것.
        let unclean = FileManager.default.fileExists(atPath: markerURL.path)

        // **순서가 load-bearing 이다.** 스냅샷을 먼저 뜨고 그 다음에 비운다 — 뒤집으면 빈 기록이
        // 남고, 그 결함은 "이슈에 빵부스러기가 없다"로만 보여 원인을 못 찾는다.
        let crashLines = readCrashLog()
        captureLastCrash(version: version, afterUncleanShutdown: unclean, crashLines: crashLines)

        // 직전 세션의 크래시-시점 기록(있으면)을 메인 로그로 합치고 비운다.
        drainCrashLog(crashLines)
        if unclean {
            AppLog.write("⚠️ 직전 세션이 정상 종료되지 않았습니다(크래시·OOM·강제종료 추정). "
                + "원인 스택은 ~/Library/Logs/DiagnosticReports/PokeDexBar-*.ips 참조.")
        }
        if let trail = drainBreadcrumbs(afterUncleanShutdown: unclean) {
            AppLog.write("직전 세션이 하던 일:\n\(trail)")
        }
        try? Data().write(to: markerURL, options: .atomic)   // 이번 세션 running 마커
        AppLog.write("launch: PokeDexBar \(version) 시작")

        // 3) 정상 종료 시 마커 제거(다음 실행이 '비정상'으로 오인하지 않게).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in markClean() }

        // 2) 치명 시그널 → crash.log 에 발생 시점 기록(async-signal-safe).
        logFD = open(crashLogURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, CrashReporter.signalHandler)
        }

        // 4) 잡히지 않은 NSException — 동기 write(비-시그널 컨텍스트라 문자열 포맷 가능).
        //
        // **한 번 더 건다.** `NSApplication` 은 기동을 마치며 자기 핸들러를 설치할 수 있고,
        // 그러면 여기서 건 것이 조용히 덮인다. 첫 제보(2026-08-19)가 SIGABRT 인데 예외 줄이
        // 하나도 없어 원인을 못 좁혔던 것이 이 경로로 설명된다 — 예외였다면 이름이 남았어야 했다.
        // 앞서 걸려 있던 핸들러가 있으면 **사슬로 잇는다**(그쪽 동작을 뺏지 않는다).
        installExceptionHandler()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in reinstallAfterLaunch() }
    }

    /// 예외 핸들러 설치 — 이미 우리 것이 걸려 있으면 아무것도 안 한다.
    ///
    /// C 함수 포인터는 비교할 수 없어(`Equatable` 아님) 우리가 걸었는지를 **플래그로** 기억한다.
    private static func installExceptionHandler() {
        guard !installedOurs else { return }
        previous = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(ours)
        installedOurs = true
    }

    /// AppKit 이 덮어썼는지 알 길이 없으므로, 기동 완료 뒤 한 번 더 걸 때는 이 플래그를 푼다.
    private static func reinstallAfterLaunch() {
        installedOurs = false
        installExceptionHandler()
    }

    nonisolated(unsafe) private static var installedOurs = false
    nonisolated(unsafe) private static var previous: (@convention(c) (NSException) -> Void)?

    private static let ours: @convention(c) (NSException) -> Void = { ex in
        let line = "[CRASH] uncaught exception: \(ex.name.rawValue) — \(ex.reason ?? "")\n"
        if let d = line.data(using: .utf8) {
            d.withUnsafeBytes { _ = write(CrashReporter.logFD, $0.baseAddress, $0.count) }
        }
        CrashReporter.previous?(ex)
    }

    /// 정상 종료 — running 마커 제거 + 기록. (크래시/강제종료 땐 호출 안 됨 → 마커 잔존 → 다음 실행 감지.)
    static func markClean() {
        try? FileManager.default.removeItem(at: markerURL)
        AppLog.write("clean shutdown")
    }

    /// crash.log 의 줄들. **지우지 않는다** — 스냅샷과 로그 합치기가 같은 내용을 봐야 하므로
    /// 읽기와 지우기를 갈라 뒀다.
    private static func readCrashLog() -> [String] {
        guard let data = try? Data(contentsOf: crashLogURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 직전 세션이 crash.log 에 남긴 크래시-시점 기록을 메인 로그로 합치고 crash.log 를 비운다.
    private static func drainCrashLog(_ lines: [String]) {
        if !lines.isEmpty {
            AppLog.write("직전 세션 크래시-시점 기록: \(lines.joined(separator: " / "))")
        }
        try? FileManager.default.removeItem(at: crashLogURL)
    }

    /// 직전 세션의 빵부스러기를 메인 로그용 문자열로 내고 링·파일을 비운다.
    ///
    /// **정상 종료였으면 nil.** 매번 합치면 메인 로그가 잡음으로 차서 2MB 회전이 빨라지고
    /// 정작 필요한 이력이 밀려난다. 어느 쪽이든 **비우는 것은 같다** — 이번 세션의 흔적에
    /// 직전 세션이 섞이면 안 된다.
    static func drainBreadcrumbs(afterUncleanShutdown unclean: Bool) -> String? {
        let lines = Breadcrumbs.read()
        Breadcrumbs.clear()
        guard unclean, !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// 크래시 시점의 문맥을 **다음 크래시가 덮을 때까지** 보존한다.
    ///
    /// `Breadcrumbs.clear()` **전에** 불러야 한다 — `LastCrash` 주석 참고.
    /// 정상 종료였으면 아무것도 안 만든다(옛 기록은 그대로 둔다 — 아직 제보 안 했을 수 있다).
    @discardableResult
    static func captureLastCrash(version: String, afterUncleanShutdown unclean: Bool,
                                 crashLines: [String] = []) -> LastCrashRecord? {
        guard unclean else { return nil }
        // macOS 리포트는 **크래시 직후 몇 초 뒤에** 써진다(실측). 기동이 빠르면 아직 없을 수
        // 있으므로 없어도 기록은 남긴다 — 스택은 있으면 좋은 것이지 전제가 아니다.
        let record = LastCrashRecord(at: Date(), version: version, crashLines: crashLines,
                                     breadcrumbs: Breadcrumbs.read(),
                                     stack: CrashStack.latestSummary() ?? [],
                                     acknowledged: false)
        LastCrash.save(record)
        return record
    }

    /// 치명 시그널 핸들러 — async-signal-safe 만 사용(write/signal/raise, StaticString=무할당).
    /// 캡처 없는 c-convention 클로저(전역 static logFD 참조는 캡처 아님). 기록 후 기본 핸들러 재발생.
    private static let signalHandler: @convention(c) (Int32) -> Void = { received in
        let m: StaticString
        switch received {
        case SIGSEGV: m = "\n[CRASH] fatal signal SIGSEGV (bad memory access)\n"
        case SIGABRT: m = "\n[CRASH] fatal signal SIGABRT (abort/assert)\n"
        case SIGBUS:  m = "\n[CRASH] fatal signal SIGBUS (bus error)\n"
        case SIGILL:  m = "\n[CRASH] fatal signal SIGILL (illegal instruction)\n"
        case SIGFPE:  m = "\n[CRASH] fatal signal SIGFPE (arithmetic)\n"
        case SIGTRAP: m = "\n[CRASH] fatal signal SIGTRAP\n"
        default:      m = "\n[CRASH] fatal signal received\n"
        }
        m.withUTF8Buffer { buf in _ = write(CrashReporter.logFD, buf.baseAddress, buf.count) }
        signal(received, SIG_DFL)   // 기본 핸들러 복원
        raise(received)             // 재발생 → macOS .ips 크래시 리포트 생성
    }
}
