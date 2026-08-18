#if os(macOS)
import ServiceManagement
#else
import Foundation
#endif

/// 로그인 시 실행 + **크래시/비정상 종료 시 자동 재실행**(launchd KeepAlive).
///
/// 배경: `SMAppService.mainApp`(로그인아이템)은 **크래시 시 시스템이 재실행하지 않는다**(Apple 명시).
/// 그래서 KeepAlive 를 가진 LaunchAgent 로 대체한다 — launchd 가 워치독으로 동작해 앱이 비정상
/// 종료(크래시·OOM SIGKILL 등 exit≠0)되면 자동 재실행하고, **정상 종료(exit 0: 사용자 종료·업데이트)
/// 시엔 재실행하지 않는다**(`KeepAlive.SuccessfulExit=false`). ThrottleInterval 10s 로 폭주 방지.
///
/// plist 는 앱 번들 `Contents/Library/LaunchAgents/<plistName>` 에 있어야 한다(build-app.sh 가 생성).
/// 크래시-재실행은 launchd 가 프로세스를 소유해야 가능하므로, 로그인 실행도 이 에이전트가 담당한다
/// (= 로그인 실행과 크래시-재실행이 한 토글로 묶임 — 메뉴바 앱엔 자연스러운 결합).
@MainActor
enum LoginItem {
    #if os(macOS)
    static let plistName = "io.github.chattymin.poketokenbar.login.plist"
    static let label = "io.github.chattymin.poketokenbar.login"
    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }

    /// Whether "launch at login (+ restart on crash)" is currently enabled.
    static var isEnabled: Bool { agent.status == .enabled }

    /// 토글 — 켜면 에이전트 등록(로그인 실행+KeepAlive), 끄면 해제. 실패 시 throw(호출부가 표면화).
    static func setEnabled(_ on: Bool) throws {
        if on { try agent.register() } else { try agent.unregister() }
    }

    /// 구버전(`SMAppService.mainApp` 로그인아이템) → KeepAlive 에이전트로 **1회 이관**.
    /// 안전: mainApp 이 켜져 있을 때만 이관하고, **에이전트 등록이 성공한 뒤에만 mainApp 을 해제**한다
    /// (등록 실패 시 mainApp 을 유지 → 구동작 보존, "로그인 실행"을 잃지 않는다). 멱등(반복 호출 무해).
    static func migrateFromLegacyLoginItemIfNeeded() {
        let legacy = SMAppService.mainApp
        guard legacy.status == .enabled else { return }   // 구 로그인아이템 미사용 → 이관 불필요
        do {
            if agent.status != .enabled { try agent.register() }   // 에이전트 먼저 등록
            try legacy.unregister()                                 // 성공 후에만 구 항목 해제
            AppLog.write("login item migrated: mainApp → KeepAlive agent")
        } catch {
            AppLog.write("login item migration failed (mainApp 유지): \(error)")
        }
    }
    #else
    // MARK: Linux — systemd --user unit

    private static let unitName = "poketokenbar.service"
    private static var unitURL: URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return home.appendingPathComponent(".config/systemd/user/\(unitName)")
    }

    /// Whether "launch at login (+ restart on crash)" is currently enabled.
    static var isEnabled: Bool { systemctl(["is-enabled", "--quiet", unitName]) == 0 }

    /// Toggle — writes and enables the unit, or disables it. Throws on failure so the caller can surface it.
    ///
    /// `Restart=on-failure` is the direct translation of launchd's `KeepAlive.SuccessfulExit=false`:
    /// it comes back from a crash or OOM (exit ≠ 0) but not from a clean exit (user Quit, update).
    /// `RestartSec=10` matches `ThrottleInterval` 10s and stops a restart storm.
    static func setEnabled(_ on: Bool) throws {
        if on {
            try writeUnit()
            _ = systemctl(["daemon-reload"])   // make systemd pick up the unit just written
            guard systemctl(["enable", unitName]) == 0 else {
                throw AutostartError.commandFailed("systemctl --user enable \(unitName)")
            }
        } else {
            guard systemctl(["disable", unitName]) == 0 else {
                throw AutostartError.commandFailed("systemctl --user disable \(unitName)")
            }
        }
    }

    /// The macOS-only migration (legacy login item → agent). Linux has no such legacy form, so no-op.
    static func migrateFromLegacyLoginItemIfNeeded() {}

    enum AutostartError: Error, CustomStringConvertible {
        case commandFailed(String)
        case executablePathUnavailable

        var description: String {
            switch self {
            case .commandFailed(let command): return "failed: \(command)"
            case .executablePathUnavailable: return "could not determine the executable path"
            }
        }
    }

    /// Write the unit file. `ExecStart` embeds **the real path of the running binary**.
    /// Using a bare name would depend on PATH, and in the common case of a `~/.local/bin` copy
    /// alongside a system one, login would start the wrong binary.
    ///
    /// It hangs off `graphical-session.target` because a tray icon cannot appear without a display
    /// (under `default.target` it would start before the session, die immediately, and spin on
    /// Restart). Plasma 6 raises that target by default — on desktops that do not, the toggle will
    /// not actually autostart anything, so an XDG autostart `.desktop` fallback is still needed
    /// (roadmap Phase 8).
    private static func writeUnit() throws {
        guard let executable = executablePath else { throw AutostartError.executablePathUnavailable }
        let unit = """
        [Unit]
        Description=PokeTokenBar — Pokémon usage tray
        PartOf=graphical-session.target
        After=graphical-session.target

        [Service]
        Type=simple
        ExecStart=\(executable)
        Restart=on-failure
        RestartSec=10

        [Install]
        WantedBy=graphical-session.target

        """
        try FileManager.default.createDirectory(
            at: unitURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try unit.write(to: unitURL, atomically: true, encoding: .utf8)
    }

    private static var executablePath: String? {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe"))
            ?? CommandLine.arguments.first
    }

    @discardableResult
    private static func systemctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemctl")
        process.arguments = ["--user"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
    #endif
}
