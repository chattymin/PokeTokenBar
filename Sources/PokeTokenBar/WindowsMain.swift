#if os(Windows)
import Foundation
import WinSDK

/// Windows console entry point — Windows-port milestones ("functionality first").
///
/// Exercises the portable core on Windows without any AppKit/SwiftUI/Keychain:
///  - Claude / Codex / Gemini usage via `LocalUsageReader` (file parsing, cross-platform).
///  - Codex rate limits via `CodexRateLimitsProvider` (spawns the `codex` CLI; nil if absent).
@main
struct PTBWindowsCLI {
    static func main() async {
        // GUI-first: no args (double-click) or `--tray` launches the system tray. Diagnostic/CLI
        // modes are opt-in flags (each needs a console); `--report` prints the usage report that used
        // to be the default. The exe links /SUBSYSTEM:WINDOWS so the tray path never flashes a console.
        let args = CommandLine.arguments.dropFirst()
        let cliFlags: Set<String> = ["--report", "--icon-test", "--update-check", "--autostart-test"]
        guard args.contains(where: cliFlags.contains) else {
            WindowsTray.run()
            return
        }
        // A CLI/diagnostic flag is present → re-attach the launching terminal's console (or alloc one)
        // so printed output is visible.
        ensureConsole()
        if CommandLine.arguments.contains("--icon-test") {
            await iconTest()
            return
        }
        if CommandLine.arguments.contains("--update-check") {
            print("[update-check] current baked version: \(WindowsUpdate.currentVersion)")
            if let upd = await WindowsUpdate.check() {
                print("  newer release available: \(upd.version)")
                print("  \(upd.url)")
            } else {
                print("  up to date (or check failed / private repo without a token)")
            }
            return
        }
        if CommandLine.arguments.contains("--autostart-test") {
            print("autostart enabled (before): \(WindowsAutostart.isEnabled())")
            print("command: \(WindowsAutostart.command)")
            print("enable() -> \(WindowsAutostart.enable()); enabled=\(WindowsAutostart.isEnabled())")
            print("disable() -> \(WindowsAutostart.disable()); enabled=\(WindowsAutostart.isEnabled())")
            return
        }
        // --report: today/week/month usage report for each provider (the old default behavior).
        let now = Date()
        let fmt = LocalUsageReader.localDayFormatter()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let weekStart = LocalUsageReader.startOfWeek(now)

        print("PokeTokenBar — Windows CLI")
        print("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")
        print(String(repeating: "=", count: 52))

        report("Claude", dir: LocalUsageReader.claudeProjectsDir,
               entries: LocalUsageReader.claudeEntries(modifiedSince: monthStart),
               now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart)
        report("Codex", dir: LocalUsageReader.codexSessionsDir,
               entries: LocalUsageReader.codexEntries(modifiedSince: monthStart),
               now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart)
        report("Gemini", dir: LocalUsageReader.geminiTmpDir,
               entries: LocalUsageReader.geminiEntries(modifiedSince: monthStart),
               now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart)
        // OpenCode/Hermes read local SQLite DBs — only where a SQLite module is importable
        // (system SQLite3 on macOS, vendored CSQLite on Windows).
        #if canImport(SQLite3) || canImport(CSQLite)
        let ocRoot = LocalAdditionalUsageReader.defaultOpenCodeRoots.first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")
        report("OpenCode", dir: ocRoot,
               entries: LocalAdditionalUsageReader.openCodeEntries(modifiedSince: monthStart),
               now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart)
        let hermesRoot = ProcessInfo.processInfo.environment["HERMES_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")
        report("Hermes", dir: hermesRoot,
               entries: LocalAdditionalUsageReader.hermesEntries(modifiedSince: monthStart),
               now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart)
        #endif

        await reportClaudeLimits()
        await reportCodexLimits()
    }

    /// Query Claude official limits via `~/.claude/.credentials.json` OAuth token + HTTP endpoint.
    /// Proves the Keychain-free credential path + FoundationNetworking work on Windows.
    private static func reportClaudeLimits() async {
        print("\n[Claude limits]")
        do {
            let status = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
            print("  \(status)")
        } catch LimitsError.credentialUnavailable {
            print("  no ~/.claude/.credentials.json (log in with Claude Code first)")
        } catch {
            print("  fetch failed: \(error)")
        }
    }

    /// Make CLI output work under the /SUBSYSTEM:WINDOWS build. If stdout is already inherited
    /// (redirected pipe/file, or a parent console), wire CRT fd 1/2 to those OS handles so
    /// print() reaches the capture. Otherwise attach/allocate a console and target CONOUT$.
    private static func ensureConsole() {
        let out = GetStdHandle(STD_OUTPUT_HANDLE)
        let err = GetStdHandle(STD_ERROR_HANDLE)
        if let out, out != INVALID_HANDLE_VALUE {
            rewire(out, toFD: 1)
            if let err, err != INVALID_HANDLE_VALUE { rewire(err, toFD: 2) }
            return
        }
        if !AttachConsole(DWORD(bitPattern: -1)) { _ = AllocConsole() }   // ATTACH_PARENT_PROCESS
        _ = "CONOUT$".withCString { p in "w".withCString { m in freopen(p, m, stdout) } }
        _ = "CONOUT$".withCString { p in "w".withCString { m in freopen(p, m, stderr) } }
    }

    /// Point a C runtime fd (1=stdout, 2=stderr) at an inherited Win32 handle.
    private static func rewire(_ handle: HANDLE, toFD fd: Int32) {
        let osfd = _open_osfhandle(Int(bitPattern: handle), 0)
        if osfd >= 0 { _ = _dup2(osfd, fd) }
    }

    /// Exercise the sprite→HICON pipeline (WIC decode + GDI icon) end-to-end and report.
    private static func iconTest() async {
        print("[icon-test] fetching sprite #25 (Pikachu)…")
        guard let png = await SpriteStore.shared.data(speciesID: 25, animated: false, shiny: false) else {
            print("  sprite fetch failed (offline?)"); return
        }
        print("  PNG bytes: \(png.count)")
        guard let img = WindowsImaging.decodePNG(png) else { print("  WIC decode failed"); return }
        let opaque = stride(from: 3, to: img.bgra.count, by: 4).lazy.filter { img.bgra[$0] > 0 }.count
        print("  decoded \(img.width)x\(img.height), \(img.bgra.count) BGRA bytes, \(opaque) non-transparent px")
        let icon = WindowsImaging.makeHICON(width: img.width, height: img.height, bgra: img.bgra)
        print("  HICON: \(icon != nil ? "created ✓" : "nil ✗")")
        if let icon { DestroyIcon(icon) }
    }

    /// Print one provider's today/week/month totals from its parsed entries.
    private static func report(_ name: String, dir: URL, entries: [LocalUsageReader.Entry],
                               now: Date, fmt: DateFormatter, weekStart: Date, monthStart: Date) {
        print("\n[\(name)]  \(dir.path)")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            print("  (not found — CLI not installed or unused on this machine)")
            return
        }
        print("  parsed \(entries.count) entries (month window)")
        func line(_ label: String, _ tokens: Int, _ cost: Double) {
            let padded = label.padding(toLength: 7, withPad: " ", startingAt: 0)
            print("  \(padded) \(TokenFormatter.grouped(tokens)) tokens  (\(TokenFormatter.cost(cost)))")
        }
        if let today = LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey()) {
            line("today:", today.totalTokens, today.totalCost)
        } else {
            print("  today:  no usage")
        }
        let week = LocalUsageReader.period(entries: entries, periodKey: "week",
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        line("week:", week.totalTokens, week.totalCost)
        let month = LocalUsageReader.period(entries: entries, periodKey: "month",
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        line("month:", month.totalTokens, month.totalCost)
    }

    /// Resolve + query the Codex CLI for rate limits. Proves BinaryLocator/ProcessRunner run on Windows.
    private static func reportCodexLimits() async {
        print("\n[Codex rate limits]")
        let provider = CodexRateLimitsProvider()
        guard let bin = provider.resolvedBinary else {
            print("  codex binary not found on PATH (skipping)")
            return
        }
        print("  codex: \(bin)")
        do {
            if let status = try await provider.fetch() {
                print("  \(status)")
            } else {
                print("  no rate-limit data returned")
            }
        } catch {
            print("  fetch failed: \(error)")
        }
    }
}
#endif
