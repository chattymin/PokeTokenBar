import SwiftUI

/// The Trainer tab: the Bag, what the player holds, and the achievements, earned or not, under one switch ("Bag |
/// Achievements"). Six tabs left the labels no room; achievements not earned yet are not in a bag, hence the trainer's.
/// `PopoverTab.bag` is this tab on its Bag, `.achievements` on its achievements, so Home's goals and the claim notices
/// still open them.
@MainActor
struct BagHubView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    /// The switch's height and the gap under it, taken from the tab's 520 pt.
    static let switchHeight: CGFloat = 30
    static let gap: CGFloat = 8

    var body: some View {
        let l = store.l
        // One count for the rewards waiting and the progress ("88/298"), which the switch carries since #183.
        let tally = store.achievementTally()
        let height = 520 - Self.switchHeight - Self.gap
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: 0) {
                part(.bag, title: l.bag, icon: "bag.fill", count: 0)
                part(.achievements, title: l.achievements, icon: "trophy.fill", count: tally.ready,
                     progress: "\(tally.claimed)/\(tally.total)",
                     progressLabel: l.achievementsProgress(tally.claimed, tally.total))
            }
            .frame(height: Self.switchHeight)
            if nav.tab == .achievements {
                AchievementsView(store: store, nav: nav, height: height)
            } else {
                BagView(store: store, nav: nav, height: height)
            }
        }
    }

    /// One half of the switch: its icon and title, the achievements' progress ("88/298"), the rewards waiting as a
    /// count, a line under the one shown.
    private func part(_ tab: PopoverTab, title: String, icon: String, count: Int, progress: String? = nil,
                      progressLabel: String? = nil) -> some View {
        let selected = nav.tab == tab
        func row(shrinking: Bool) -> some View {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    .minimumScaleFactor(shrinking ? 0.8 : 1)
                    .fixedSize(horizontal: !shrinking, vertical: false)
                if let progress {
                    Text(progress)
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .accessibilityLabel(progressLabel ?? progress)
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                }
            }
        }
        return Button { nav.tab = tab } label: {
            VStack(spacing: 4) {
                // The title at its size when the counts leave it room; shrunk only when not (English): beside the
                // counts, a shrinkable title shrank even with room to spare.
                ViewThatFits(in: .horizontal) {
                    row(shrinking: false)
                    row(shrinking: true)
                }
                .foregroundStyle(selected ? AnyShapeStyle(Design.actionColor) : AnyShapeStyle(.secondary))
                Capsule().fill(selected ? Design.actionColor : Color.primary.opacity(0.08)).frame(height: selected ? 2.5 : 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
