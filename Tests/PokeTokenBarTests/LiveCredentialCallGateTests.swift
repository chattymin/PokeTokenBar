import XCTest
@testable import PokeTokenBar

/// The suite must never call a live limits endpoint with the real login found on the machine.
///
/// `UsageStore.init` defaults every limits provider to the real one, so any test that does not inject
/// a stub runs the real provider. The automatic path reads no Keychain item, which made this look
/// harmless, but credentials are also plain files: with `~/.claude/.credentials.json`, the Antigravity
/// token file, or a Cursor login in `state.vscdb`, the no-prompt path succeeds and the suite calls
/// Anthropic, Google or Cursor with the user's account (spending its rate limit, and for Antigravity
/// its refresh token). The gate sits at the network boundary, not before the credential read, so
/// `KeychainAutoPathTests` still observes real reads.
final class LiveCredentialCallGateTests: XCTestCase {
    /// Holds on every machine: the per-provider tests below skip where no credential exists (CI).
    func testGateIsClosedUnderSwiftTest() throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        XCTAssertFalse(AppEnv.isBundledApp, "swift test is not an app bundle")
        XCTAssertFalse(AppEnv.allowsLiveLimitsFetch)
    }

    /// The automatic path (`allowKeychainPrompt: false`) is the real trigger and never raises a dialog.
    func testClaudeLimitsFetchDoesNotReachTheNetwork() async throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        do {
            _ = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("a live Claude limits call ran inside swift test")
        } catch LimitsError.liveFetchNotPermitted {
            // Expected: a credential was found and the call stopped at the gate.
        } catch {
            // No credential on this machine: the fetch ended before the gate, so there is nothing to
            // check here. Counting that as a pass would overstate coverage.
            throw XCTSkip("no credential available, the network boundary was not reached: \(error)")
        }
    }

    func testAntigravityLimitsFetchDoesNotReachTheNetwork() async throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        do {
            _ = try await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("a live Antigravity limits call ran inside swift test")
        } catch LimitsError.liveFetchNotPermitted {
            // Expected.
        } catch {
            throw XCTSkip("no credential available, the network boundary was not reached: \(error)")
        }
    }

    /// Keeps the next provider from shipping without the gate. Per-provider tests alone only cover the
    /// providers someone remembered; this scan runs on every machine.
    func testEveryNetworkingLimitsProviderIsGated() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar/Core")
        var scanned: [String] = []
        var offenders: [String] = []

        for name in try FileManager.default.contentsOfDirectory(atPath: core.path)
        where name.hasSuffix("LimitsProvider.swift") {
            let source = try String(contentsOf: core.appendingPathComponent(name), encoding: .utf8)
            // Providers that never touch the network (Codex reads a local binary) are out of scope.
            guard source.contains("URLSession") else { continue }
            scanned.append(name)
            // Comment lines do not count: a commented-out guard must not satisfy the scan.
            let gated = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { !$0.hasPrefix("//") && $0.contains("AppEnv.allowsLiveLimitsFetch") }
            if !gated { offenders.append(name) }
        }

        XCTAssertFalse(scanned.isEmpty, "nothing scanned — did the file naming convention change?")
        XCTAssertTrue(offenders.isEmpty, """
            These limits providers can send the user's credentials to a live endpoint without a gate. \
            Add `guard AppEnv.allowsLiveLimitsFetch else { … }` right before the network call: \
            \(offenders.joined(separator: ", "))
            """)
    }
}
