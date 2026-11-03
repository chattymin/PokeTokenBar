import SwiftUI

/// The card look shared by every Settings section: a small grey title over a rounded card of rows.
/// Lives outside `SettingsView` so a section can be its own view (and be rendered on its own).
@MainActor
enum SettingsCard {
    /// 섹션 = 소문자 회색 타이틀 + 라운드 카드 (macOS inset grouped 룩).
    @ViewBuilder
    static func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor),
                           in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }

    /// 카드 내부 한 줄 — 좌 라벨 / 우 컨트롤.
    static func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }

    static func toggleRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
        row {
            Text(label)
            Spacer()
            Toggle(label, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// Settings → Floating Pet. A view of its own so tests can render the section alone.
@MainActor
struct FloatingPetSettingsSection: View {
    @Environment(UsageStore.self) private var usage
    @Environment(CompanionStore.self) private var companion
    private var l: L { companion.l }

    var body: some View {
        @Bindable var store = usage
        SettingsCard.section(l.floatingPetSectionTitle) {
            SettingsCard.row {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.floatingPetEnableLabel)
                    Text(l.floatingPetHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle(l.floatingPetEnableLabel, isOn: $store.floatingPetEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            SettingsCard.row {
                // Also reachable from both right-click menus. Applies to every surface, not only the pet.
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.backViewLabel)
                    Text(l.backViewHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle(l.backViewLabel, isOn: $store.alwaysFacesBack)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if store.floatingPetEnabled {
                Divider()
                SettingsCard.row {
                    Text(l.floatingPetSizeLabel).font(.callout)
                    Slider(value: $store.floatingPetSize, in: 48...384, step: 8)
                        .accessibilityLabel(l.floatingPetSizeLabel)
                    Text("\(Int(store.floatingPetSize))px")
                        .font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Divider()
                SettingsCard.toggleRow(l.floatingPetBubbleAlertsLabel, $store.floatingPetBubbleAlerts)
            }
        }
    }
}
