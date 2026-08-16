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
/// crash.log 의 기록은 **다음 실행 때 메인 로그로 합쳐 비운다**(사용자는 PokeTokenBar.log 한 곳만 봐도 됨).
enum CrashReporter {
    private static let logsDir: URL =
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
    private static var markerURL: URL { logsDir.appendingPathComponent("PokeTokenBar.running") }
    /// 크래시-시점 기록 전용(회전 안 함). 시그널/예외 핸들러가 async-signal-safe 하게 append.
    private static var crashLogURL: URL { logsDir.appendingPathComponent("PokeTokenBar.crash.log") }
    /// 위 crash.log 로 미리 연 fd(설치 시 1회 open). 회전 대상이 아니라 세션 내내 유효.
    nonisolated(unsafe) fileprivate static var logFD: Int32 = -1

    /// 앱 기동 최초에 1회 호출(가능한 한 이르게 — 런치 초기 크래시도 잡히게).
    static func install(version: String) {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // 직전 세션의 크래시-시점 기록(있으면)을 메인 로그로 합치고 비운다.
        drainCrashLog()

        // 1) 직전 세션 비정상 종료 감지 — 마커가 남아 있으면 정상 종료되지 않은 것.
        if FileManager.default.fileExists(atPath: markerURL.path) {
            AppLog.write("⚠️ 직전 세션이 정상 종료되지 않았습니다(크래시·OOM·강제종료 추정). "
                + "원인 스택은 ~/Library/Logs/DiagnosticReports/PokeTokenBar-*.ips 참조.")
        }
        try? Data().write(to: markerURL, options: .atomic)   // 이번 세션 running 마커
        AppLog.write("launch: PokeTokenBar \(version) 시작")

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
        NSSetUncaughtExceptionHandler { ex in
            let line = "[CRASH] uncaught exception: \(ex.name.rawValue) — \(ex.reason ?? "")\n"
            if let d = line.data(using: .utf8) {
                d.withUnsafeBytes { _ = write(CrashReporter.logFD, $0.baseAddress, $0.count) }
            }
        }
    }

    /// 정상 종료 — running 마커 제거 + 기록. (크래시/강제종료 땐 호출 안 됨 → 마커 잔존 → 다음 실행 감지.)
    /// `writeAndFlush`: AppKit posts `willTerminate` and then exits, so a bare
    /// `write` races teardown and `clean shutdown` is usually lost (#174).
    /// The marker file itself is removed synchronously above — detection is
    /// unaffected; this is the human-readable half of the shutdown record.
    static func markClean() {
        try? FileManager.default.removeItem(at: markerURL)
        AppLog.writeAndFlush("clean shutdown")
    }

    /// 직전 세션이 crash.log 에 남긴 크래시-시점 기록을 메인 로그로 합치고 crash.log 를 비운다.
    private static func drainCrashLog() {
        guard let data = try? Data(contentsOf: crashLogURL), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { AppLog.write("직전 세션 크래시-시점 기록: \(trimmed)") }
        try? FileManager.default.removeItem(at: crashLogURL)
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
