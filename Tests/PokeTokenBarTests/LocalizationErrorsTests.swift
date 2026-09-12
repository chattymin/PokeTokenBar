import XCTest
@testable import PokeTokenBar

private struct ErrorUsageProvider: UsageProvider {
    let id = "test"
    let displayName = "Test"
    func fetchDaily() async throws -> DailyUsage? { throw URLError(.notConnectedToInternet) }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
}
private struct ErrorClaudeProvider: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LimitsError.sessionKeyInvalid }
}
private struct ErrorCodexProvider: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct ErrorAntigravityProvider: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus { throw URLError(.notConnectedToInternet) }
}
private struct ErrorSessionKeys: SessionKeyManaging {
    func credential() -> SessionKeyCredential? { nil }
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { [] }
    func save(key: String, organizationID: String?) throws { }
    func clear() { }
}

final class LocalizationErrorsTests: XCTestCase {
    func testErrorsHaveSelectedLanguageMessagesWithoutSystemDescription() {
        let errors: [any Error] = [URLError(.notConnectedToInternet),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAW SYSTEM MESSAGE"])]
        for error in errors {
            let messages = AppLanguage.allCases.map { L($0).userFacingError(error) }
            XCTAssertEqual(Set(messages).count, AppLanguage.allCases.count)
            XCTAssertTrue(messages.allSatisfy { !$0.isEmpty && !$0.contains("RAW SYSTEM MESSAGE") })
        }
        XCTAssertTrue(L(.ko).userFacingError(errors[0]).contains("네트워크"))
        XCTAssertTrue(L(.en).userFacingError(errors[1]).contains("access was denied"))
        XCTAssertTrue(L(.en).userFacingError(errors[2]).contains("disk space"))
    }

    @MainActor func testStoredErrorsFollowLanguageChangesAndKeepDiagnostics() async {
        let suite = "localization-errors-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: "refreshInterval")
        defaults.set(false, forKey: "statusChecksEnabled")
        let store = UsageStore(providers: [ErrorUsageProvider()],
            claudeLimitsProvider: ErrorClaudeProvider(), codexLimitsProvider: ErrorCodexProvider(),
            antigravityLimitsProvider: ErrorAntigravityProvider(), sessionKeys: ErrorSessionKeys(),
            autoRefresh: false, defaults: defaults)
        XCTAssertNil(store.lastErrorMessage(L(.ko)))
        store.localizationLanguage = .ko
        await store.saveSessionKey("not-a-key")
        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(store.sessionKeyError, L(.ko).sessionKeyMalformedError)
        XCTAssertEqual(store.limitTokenRefreshError, L(.ko).sessionKeyExpiredError)
        store.localizationLanguage = .ja
        XCTAssertEqual(store.sessionKeyError, L(.ja).sessionKeyMalformedError)
        XCTAssertEqual(store.limitTokenRefreshError, L(.ja).sessionKeyExpiredError)
        await store.refresh(scheduleEmptyRetry: false)
        let diagnostic = store.lastErrorDescription!
        XCTAssertEqual(store.lastErrorMessage(L(.ko)), L(.ko).usageRefreshError + "\n" + diagnostic)
        XCTAssertEqual(store.lastErrorMessage(L(.de)), L(.de).usageRefreshError + "\n" + diagnostic)
        XCTAssertEqual(store.lastErrorDescription, diagnostic)
    }
}
