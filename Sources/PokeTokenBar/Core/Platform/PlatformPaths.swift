import Foundation

/// Storage-location seam — the one place `~/Library/…` (macOS) and XDG (Linux) diverge.
///
/// **The macOS expressions are copied verbatim from the old code.** "Tidying" a path here would
/// strand every shipped user's save, cache and dex (moving data is `SaveTransfer`'s job, not this
/// seam's). So the macOS branch is a fixed contract, not a refactoring target.
///
/// Linux follows the XDG Base Directory spec. It computes the paths itself rather than trusting
/// corelibs-foundation's `.applicationSupportDirectory` mapping, because that mapping varies by
/// distribution and version — the same machine could resolve to a different directory after an
/// update, which is not a risk worth taking with save data.
enum PlatformPaths {
    #if os(macOS)
    /// The **parent** of the app's data directory. Callers append `PokeTokenBar/…`.
    static let appSupportRoot: URL =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// Log directory (callers are responsible for creating it — preserves existing behaviour).
    static let logsDirectory: URL =
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")

    /// State that only means anything while the process is alive (the single-instance lock).
    static let runtimeDirectory: URL = FileManager.default.temporaryDirectory
    #else
    static let appSupportRoot: URL = xdg("XDG_DATA_HOME", default: ".local/share")
    static let logsDirectory: URL = xdg("XDG_STATE_HOME", default: ".local/state")
        .appendingPathComponent("PokeTokenBar")
    static let runtimeDirectory: URL = {
        // XDG_RUNTIME_DIR only exists inside a login session (it is absent under cron or
        // `systemd --system`). Falling back to /tmp is better than losing the lock entirely.
        if let raw = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"], !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }()

    /// `$VAR` when it is absolute, otherwise `$HOME/<fallback>`. The XDG spec says to ignore
    /// relative values.
    private static func xdg(_ variable: String, default fallback: String) -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let raw = ProcessInfo.processInfo.environment[variable],
              raw.hasPrefix("/") else {
            return home.appendingPathComponent(fallback)
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }
    #endif

    /// The app's own data directory, created if missing.
    /// `…/Application Support/PokeTokenBar` on macOS, `…/.local/share/PokeTokenBar` on Linux.
    static func appDirectory(_ subpath: String? = nil) -> URL {
        var dir = appSupportRoot.appendingPathComponent("PokeTokenBar")
        if let subpath { dir = dir.appendingPathComponent(subpath) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Other apps' data directories (the usage logs we read)

    /// An Electron app's `userData` directory — Claude Desktop, Cursor and friends.
    ///
    /// Electron picks a different location per platform (`app.getPath("userData")`):
    /// `~/Library/Application Support/<app>` on macOS, `$XDG_CONFIG_HOME/<app>` on Linux.
    /// This is **the app we are reading from** dictating the convention, not ours — changing it
    /// means finding no logs at all.
    static func electronAppData(_ name: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if os(macOS)
        return home.appendingPathComponent("Library/Application Support/\(name)")
        #else
        if let raw = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true).appendingPathComponent(name)
        }
        return home.appendingPathComponent(".config/\(name)")
        #endif
    }

    /// The data directory of a **CLI tool** that follows XDG (kiro-cli and similar).
    /// Unlike Electron this is `$XDG_DATA_HOME` (`~/.local/share`) — folding the two into one
    /// helper would put one of them in the wrong place.
    static func cliToolData(_ name: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if os(macOS)
        return home.appendingPathComponent("Library/Application Support/\(name)")
        #else
        if let raw = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true).appendingPathComponent(name)
        }
        return home.appendingPathComponent(".local/share/\(name)")
        #endif
    }
}
