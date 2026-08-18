import Foundation

/// The settings store, pinned to a stable identity on every platform.
///
/// macOS keys `UserDefaults.standard` on the bundle identifier, so preferences follow the app
/// wherever it is installed. **corelibs-foundation keys it on the executable's filename** and
/// writes `~/.config/<name>.plist`, which means the same app answers to a different settings file
/// depending on how it was launched: `.build/debug/PokeTokenBar` and an installed `poketokenbar`
/// would each keep their own language, interval and toggles, and `make run` would appear to forget
/// everything the installed copy was told.
///
/// Naming the suite explicitly removes the dependence on the filename. The identifier matches the
/// macOS bundle id so the two platforms describe the same product.
enum PlatformDefaults {
    static let suiteName = "io.github.chattymin.poketokenbar"

    // `UserDefaults` is thread-safe by contract but not marked `Sendable`, and this is a
    // read-only handle resolved once at startup.
    nonisolated(unsafe) static let standard: UserDefaults = {
        #if os(macOS)
        return .standard
        #else
        // A named suite cannot fail for a plain identifier, but falling back to `.standard` keeps
        // settings working rather than crashing if it ever did.
        return UserDefaults(suiteName: suiteName) ?? .standard
        #endif
    }()
}
