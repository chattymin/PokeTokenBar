import Foundation

// Minimal fill-ins for things Darwin Foundation has and corelibs-foundation does not.
//
// Everything here is an API whose **meaning is macOS-specific, leaving Linux with nothing to do**.
// A harmless no-op beats sprinkling `#if` through the call sites: conditional compilation in the
// middle of a scan loop hurts to read, and invites fixing only one branch later.

#if !canImport(ObjectiveC)
/// Obj-C autorelease pool — Linux has no Obj-C runtime, so there is no pool.
///
/// The callers (log scan loops) use it to **release one iteration's temporaries promptly**, and on
/// Linux Swift objects are already freed by ARC as they leave scope. So this no-op is not a feature
/// removed; it is a property that already holds on that platform.
@inline(__always)
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif

/// App Nap suppression — stops macOS throttling a background app until the ccusage subprocess
/// times out.
///
/// Linux has no equivalent behaviour (its scheduler does not put apps to sleep this way), so the
/// token is empty and ending it is a no-op — there is nothing to suppress, not something we fail
/// to suppress.
enum PlatformActivity {
    #if os(macOS)
    typealias Token = NSObjectProtocol

    static func beginUserInitiated(reason: String) -> Token {
        ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: reason)
    }

    static func end(_ token: Token) {
        ProcessInfo.processInfo.endActivity(token)
    }
    #else
    typealias Token = Void

    static func beginUserInitiated(reason: String) -> Token {}

    static func end(_ token: Token) {}
    #endif
}
