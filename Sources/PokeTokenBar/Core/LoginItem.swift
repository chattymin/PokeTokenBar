import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
struct LoginItem {
    private static let legacyLabel = "io.github.chattymin.poketokenbar.login"

    let mainApp: any LoginItemService
    let legacyAgent: any LoginItemService
    let launchedByLegacyAgent: Bool
    let openLoginItemsSettings: () -> Void

    static var system: LoginItem {
        LoginItem(
            mainApp: SMAppService.mainApp,
            legacyAgent: SMAppService.agent(plistName: "\(legacyLabel).plist"),
            launchedByLegacyAgent: AppEnv.xpcServiceName == legacyLabel,
            openLoginItemsSettings: SMAppService.openSystemSettingsLoginItems
        )
    }

    var status: SMAppService.Status { mainApp.status }
    var isEnabled: Bool { status == .enabled || legacyAgent.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if !enabled {
            // Unregistering the legacy agent can terminate the process it launched.
            if !launchedByLegacyAgent { try unregisterIfNeeded(legacyAgent) }
            try unregisterIfNeeded(mainApp)
            if launchedByLegacyAgent { try unregisterIfNeeded(legacyAgent) }
            return
        }

        do {
            try registerMainAppIfNeeded()
        } catch {
            // register() can report a denial when the system already requires approval.
            guard status == .requiresApproval else { throw error }
        }
        if status == .requiresApproval {
            openLoginItemsSettings()
        } else {
            try removeLegacyAgentAfterActivation()
        }
    }

    func migrateFromLegacyAgentIfNeeded() {
        do {
            // A denied legacy registration does not imply consent to start the app.
            if legacyAgent.status == .enabled { try registerMainAppIfNeeded() }
            try removeLegacyAgentAfterActivation()
        } catch {
            AppLog.write("login item migration failed: \(error)")
        }
    }

    private func registerMainAppIfNeeded() throws {
        if !isRegistered(status) { try mainApp.register() }
    }

    func removeLegacyAgentAfterActivation() throws {
        // If the old agent owns this process, defer cleanup to the next ordinary launch.
        guard status == .enabled, !launchedByLegacyAgent else { return }
        try unregisterIfNeeded(legacyAgent)
    }

    private func unregisterIfNeeded(_ service: any LoginItemService) throws {
        if isRegistered(service.status) { try service.unregister() }
    }

    private func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
