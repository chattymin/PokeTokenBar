import ServiceManagement
import XCTest
@testable import PokeTokenBar

final class LoginItemTests: XCTestCase {
    @MainActor
    func testEnablingRegistersMainAppWithoutOpeningSettings() throws {
        let main = Service(.notRegistered)
        let legacy = Service(.notRegistered)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {
            XCTFail("An enabled login item does not require settings")
        }

        try item.setEnabled(true)

        XCTAssertEqual(item.status, .enabled)
        XCTAssertEqual(main.registrations, 1)
        XCTAssertEqual(legacy.registrations, 0)
    }

    @MainActor
    func testApprovalOpensSettingsAndKeepsLegacyRegistrationUntilActivated() throws {
        let main = Service(.notRegistered, afterRegistration: .requiresApproval)
        let legacy = Service(.enabled)
        var settingsOpens = 0
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {
            settingsOpens += 1
        }

        try item.setEnabled(true)
        try item.setEnabled(true)

        XCTAssertEqual(item.status, .requiresApproval)
        XCTAssertEqual(settingsOpens, 2)
        XCTAssertEqual(main.registrations, 1, "A pending item is already registered")
        XCTAssertEqual(legacy.status, .enabled)
        XCTAssertTrue(item.isEnabled, "The remaining legacy agent must be possible to turn off")

        main.status = .enabled
        try item.removeLegacyAgentAfterActivation()
        XCTAssertEqual(legacy.status, .notRegistered)
    }

    @MainActor
    func testStartupMigratesEnabledLegacyAgentButDoesNotOverrideRevokedConsent() {
        for previous in [SMAppService.Status.enabled, .requiresApproval, .notRegistered] {
            let main = Service(.notRegistered)
            let legacy = Service(previous)
            let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {
                XCTFail("Startup should not open System Settings")
            }

            item.migrateFromLegacyAgentIfNeeded()
            item.migrateFromLegacyAgentIfNeeded()

            XCTAssertEqual(item.status, previous == .enabled ? .enabled : .notRegistered)
            XCTAssertEqual(legacy.status, previous == .enabled ? .notRegistered : previous)
            XCTAssertEqual(main.registrations, previous == .enabled ? 1 : 0)
        }
    }

    @MainActor
    func testMigrationDefersUnregisteringTheAgentThatLaunchedThisProcess() {
        let main = Service(.notRegistered)
        let legacy = Service(.enabled)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: true) {}

        item.migrateFromLegacyAgentIfNeeded()

        XCTAssertEqual(item.status, .enabled)
        XCTAssertEqual(legacy.status, .enabled)
    }

    @MainActor
    func testDisablingClearsLegacyRegistrationSoNextLaunchStaysOff() throws {
        let main = Service(.requiresApproval)
        let legacy = Service(.enabled)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {}

        try item.setEnabled(false)
        item.migrateFromLegacyAgentIfNeeded()

        XCTAssertEqual(item.status, .notRegistered)
        XCTAssertEqual(legacy.status, .notRegistered)
        XCTAssertFalse(item.isEnabled)
    }

    @MainActor
    private final class Service: LoginItemService {
        var status: SMAppService.Status
        let afterRegistration: SMAppService.Status
        private(set) var registrations = 0

        init(_ status: SMAppService.Status, afterRegistration: SMAppService.Status = .enabled) {
            self.status = status
            self.afterRegistration = afterRegistration
        }

        func register() throws {
            registrations += 1
            status = afterRegistration
        }

        func unregister() throws {
            status = .notRegistered
        }
    }
}
