import Foundation

/// The app version — Info.plist on macOS, a compile-time constant on Linux.
///
/// Linux has no bundle: `Bundle.main` points at the executable's directory and there is no
/// Info.plist. So the version is baked into the source, but **the single source of truth is still
/// `VERSION` in `scripts/build-app.sh`** — `make version-sync` reads it from there and rewrites
/// `compiled` below. Keeping two places in sync by hand guarantees they drift (each release bumps
/// only one), so the Makefile build regenerates it and the release gate compares them.
enum AppVersion {
    /// Synced with `VERSION` in scripts/build-app.sh — do not edit by hand (`make version-sync`).
    static let compiled = "2.5.1"

    /// The version used for display, update comparison and the User-Agent.
    static var current: String {
        #if os(macOS)
        // Info.plist wins for a real install; running without a bundle (dev) falls back to `compiled`.
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? compiled
        #else
        compiled
        #endif
    }
}
