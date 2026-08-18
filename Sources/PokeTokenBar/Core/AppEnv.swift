import Foundation

/// Execution-environment checks — defined in one place so duplicated gates cannot drift apart.
enum AppEnv {
    /// Whether this is a real, installed app. The single gate for "real app only" side effects —
    /// notifications, keychain reads, sprite prefetch, production logging — so `swift test` and
    /// dev runs stay out of the user's data.
    ///
    /// - macOS: is it a proper `.app` bundle (bundleIdentifier + path suffix — both true only for
    ///   a real install).
    /// - Linux: there is no bundle, so this asks **are we running out of the SwiftPM build
    ///   directory**. `swift run` / `swift test` products always live under `.build/`, so dev runs
    ///   are filtered exactly, while installed copies (`/usr/bin`, `~/.local/bin`) are not — the
    ///   same meaning as the macOS branch, at the same precision.
    static var isProductionInstall: Bool {
        #if os(macOS)
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
        #else
        !executablePath.contains("/.build/")
        #endif
    }

    #if !os(macOS)
    /// The executable's real path (`/proc/self/exe`), resolved through any install symlink.
    private static let executablePath: String = {
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
            return resolved
        }
        return CommandLine.arguments.first ?? ""
    }()
    #endif
}
