import SwiftUI
import PokeTokenBarShared

struct SettingsView: View {
    @Environment(PhonePayloadStore.self) private var store
    @State private var hostInput: String = ""
    @State private var connectionCheckResult: String?
    @State private var isChecking = false
    @State private var iCloudAvailable = false

    var body: some View {
        Form {
            Section("Appearance") {
                @Bindable var store = store
                Picker("Theme", selection: $store.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
            }

            Section("iCloud Sync") {
                HStack {
                    Label("iCloud", systemImage: "icloud")
                    Spacer()
                    if iCloudAvailable {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Available", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Local Network (Optional)") {
                HStack {
                    Label("Mac IP Address", systemImage: "desktopcomputer")
                    TextField("192.168.1.42", text: $hostInput)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { saveHost() }
                }

                if isChecking {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking connection...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let result = connectionCheckResult {
                    HStack {
                        Image(systemName: store.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(store.isConnected ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Test Connection") {
                    hostInput = hostInput.trimmingCharacters(in: .whitespaces)
                    store.host = hostInput
                    isChecking = true
                    connectionCheckResult = nil
                    Task {
                        await store.checkConnection()
                        isChecking = false
                        connectionCheckResult = store.isConnected ? String(localized: "Connected!") : String(localized: "Cannot reach Mac")
                    }
                }
                .disabled(hostInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Refresh") {
                @Bindable var store = store
                Picker("Auto-refresh", selection: $store.refreshInterval) {
                    Text("Off (manual only)").tag(TimeInterval(0))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                    Text("5 minutes").tag(TimeInterval(300))
                }
            }

            Section {
                Button("Refresh Now") {
                    Task { await store.fetch() }
                }
            }

            Section {
                if let payload = store.payload {
                    LabeledContent("Today", value: TokenFormatter.compact(payload.todayTokens))
                    LabeledContent("Cost", value: TokenFormatter.cost(payload.todayCost))
                    LabeledContent("Last Update", value: payload.lastUpdated.formatted(.relative(presentation: .named)))
                }
            } header: {
                Text("Current Data")
            } footer: {
                Text("Data syncs via iCloud. Local network is used as fallback when iCloud is unavailable.")
            }
        }
        .navigationTitle("Settings")
        .onAppear { hostInput = store.host }
        .task { iCloudAvailable = await CloudKitSync.isAvailable() }
    }

    private func saveHost() {
        hostInput = hostInput.trimmingCharacters(in: .whitespaces)
        store.host = hostInput
    }
}
