import SwiftUI

/// Pokédex goal of an item: its Pokémon (greyed until registered) with a counter, or a progress
/// bar for the long type lists of the gym badges. Once the item is unlocked the goal stays visible in a
/// `compact` line (smaller sprites, a check, no box), limited to the goal that was met.
@MainActor
struct UnlockRequirementView: View {
    let store: CompanionStore
    let kind: ItemKind
    var compact = false

    /// Above this many species a sprite row no longer fits the card: show a bar instead.
    private static let spriteRowLimit = 9

    var body: some View {
        let l = store.l
        let content = VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            switch kind.unlock {
            case .duplicateLegendary:
                let copies = min(store.graduatedLegendaryCopies, 2)
                counterRow(l.duplicateLegendaryGoal, count: copies, needed: 2, met: copies >= 2)
            case .species:
                let goals = store.unlockProgress(of: kind)
                // Compact: only the goal that unlocked the item (all of them if none is met, e.g. an owned
                // item bought before the goal existed).
                let shown = compact && goals.contains(where: \.isMet) ? goals.filter(\.isMet) : goals
                ForEach(Array(shown.enumerated()), id: \.offset) { index, progress in
                    if index > 0 {
                        Text(l.unlockOr).font(.caption2).foregroundStyle(.tertiary)
                    }
                    goalView(progress, l)
                }
            case nil:
                EmptyView()
            }
        }
        if compact {
            content
        } else {
            content
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func goalView(_ progress: CompanionStore.GoalProgress, _ l: L) -> some View {
        let goal = progress.goal
        if goal.species.count > Self.spriteRowLimit {
            VStack(alignment: .leading, spacing: 3) {
                counterRow(kind.badgeType.map(l.typeGoal) ?? "", count: progress.count, needed: goal.needed,
                           met: progress.isMet)
                if !compact {
                    ProgressView(value: Double(progress.count), total: Double(max(1, goal.needed)))
                        .controlSize(.small)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if goal.needed < goal.species.count {
                    Text(l.anyOfGoal(goal.needed)).font(.caption2).foregroundStyle(compact ? .tertiary : .secondary)
                }
                HStack(spacing: compact ? 2 : 3) {
                    if compact && progress.isMet { checkmark }
                    ForEach(goal.species, id: \.self) { id in
                        let has = progress.registered.contains(id)
                        SpriteView(speciesID: id, size: spriteSize(count: goal.species.count))
                            .grayscale(has ? 0 : 1).opacity(has ? 1 : 0.35)
                            .help("#\(id)")
                    }
                    Spacer(minLength: 4)
                    counter(progress.count, needed: goal.needed)
                }
            }
        }
    }

    private func spriteSize(count: Int) -> CGFloat {
        compact ? (count > 6 ? 16 : 18) : (count > 6 ? 24 : 30)
    }

    /// Only on a met goal: an item can be owned without its goal (bought before the goal existed).
    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
    }

    private func counter(_ count: Int, needed: Int) -> some View {
        Text("\(count)/\(needed)")
            .font(.caption2.weight(.semibold)).foregroundStyle(compact ? .tertiary : .secondary).monospacedDigit()
    }

    private func counterRow(_ text: String, count: Int, needed: Int, met: Bool) -> some View {
        HStack(spacing: 4) {
            if compact && met { checkmark }
            Text(text).font(.caption2).foregroundStyle(compact ? .tertiary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            counter(count, needed: needed)
        }
    }
}
