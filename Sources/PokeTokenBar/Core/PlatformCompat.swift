import Foundation

// Cross-platform shims for APIs that exist on Apple's Foundation but not on
// swift-corelibs-foundation (Windows/Linux).

#if !canImport(Darwin)
/// `autoreleasepool` is an Objective-C runtime construct with no equivalent on
/// non-Darwin platforms. On Darwin it caps memory peaks in tight parsing loops by
/// draining autoreleased objects; elsewhere there is no autorelease pool, so this
/// no-op shim just runs the body — same result, matching the Darwin signature.
@inline(__always)
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif
