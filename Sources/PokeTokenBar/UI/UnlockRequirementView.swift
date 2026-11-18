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
            case .allSpecies, .allForms:
                let progress = store.graduatedCollectionProgress
                let isSpecies = kind.unlock == .allSpecies
                let count = isSpecies ? progress.species : progress.forms
                let needed = isSpecies ? progress.speciesTotal : progress.formsTotal
                counterRow(isSpecies ? l.allSpeciesGoal : l.allFormsGoal, count: count, needed: needed, met: count >= needed)
                if !compact {
                    ProgressView(value: Double(min(count, needed)), total: Double(max(1, needed))).controlSize(.small)
                }
            case .allPikachuCostumes:
                let count = store.state.pikachuCostumes.count, needed = PikachuCostume.allCases.count
                counterRow(l.allPikachuCostumesGoal, count: count, needed: needed, met: count >= needed)
                if !compact {
                    ProgressView(value: Double(min(count, needed)), total: Double(needed)).controlSize(.small)
                }
            case .silvallyMemories:
                let won = store.state.graduatedSilvallyMemoryTypes
                let needed = PokemonForm.memoryTypes.count
                counterRow(l.silvallyMemoriesGoal, count: won.count, needed: needed, met: won.count >= needed)
                if !compact {
                    // Which Memories are still missing: each type, faded until a legendary of it has graduated.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 3)], alignment: .leading, spacing: 3) {
                        ForEach(PokemonForm.memoryTypes, id: \.self) { type in
                            Badge(l.typeName(type).uppercased(), tint: .type(type))
                                .opacity(won.contains(type) ? 1 : 0.3)
                                .accessibilityLabel(l.typeName(type))
                                .accessibilityValue(won.contains(type) ? "" : l.formNotCollected)
                        }
                    }
                }
            case .forms(let goal):
                formsGoalView(store.formProgress(goal), l)
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
                .designSurface(cornerRadius: 10)
        }
    }

    @ViewBuilder
    private func goalView(_ progress: CompanionStore.GoalProgress, _ l: L) -> some View {
        let goal = progress.goal
        if goal.species.count > Self.spriteRowLimit {
            VStack(alignment: .leading, spacing: 3) {
                counterRow(longGoalLabel(goal, l), count: progress.count, needed: goal.needed,
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
                        // Still to graduate: its shape in black, as in the Pokédex.
                        SpriteView(speciesID: id, size: spriteSize(count: goal.species.count), isSilhouette: !has,
                                   sameScale: true)
                            .speciesNameTooltip(id, language: store.language)
                    }
                    Spacer(minLength: 4)
                    counter(progress.count, needed: goal.needed)
                }
            }
        }
    }

    /// A forms achievement: each form's sprite, faded until it graduated, or a bar for the long collections
    /// (Furfrou's trims, Vivillon's patterns, Unown's letters, Alcremie's sweets).
    @ViewBuilder
    private func formsGoalView(_ progress: CompanionStore.FormProgress, _ l: L) -> some View {
        let goal = progress.goal
        let needed = goal.forms.count
        if needed > Self.spriteRowLimit {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    SpriteView(speciesID: goal.speciesID, size: compact ? 18 : 24, form: goal.forms.first)
                    counterRow(l.allFormsOfSpeciesGoal, count: progress.count, needed: needed, met: progress.isMet)
                }
                if !compact {
                    ProgressView(value: Double(progress.count), total: Double(max(1, needed))).controlSize(.small)
                }
            }
            // Too many to draw: the ones still missing, named on hover, with their names loaded here.
            .hoverTip(missingForms(progress).isEmpty ? nil
                      : HoverTip(id: "forms:\(goal.speciesID)", title: l.missingFormsHint(missingForms(progress))))
            .loadsFormNames(goal.speciesID)
        } else {
            HStack(spacing: compact ? 2 : 3) {
                if compact && progress.isMet { checkmark }
                ForEach(goal.forms, id: \.self) { form in
                    let has = progress.graduated.contains(form)
                    // Faded until it graduated, as the Pokédex's form picker: in black, the forms of one species
                    // would all look alike.
                    SpriteView(speciesID: goal.speciesID, size: spriteSize(count: needed), form: form)
                        .grayscale(has ? 0 : 1).opacity(has ? 1 : 0.35)
                        .speciesNameTooltip(goal.speciesID, form: form, language: store.language)
                }
                Spacer(minLength: 4)
                counter(progress.count, needed: needed)
            }
        }
    }

    /// The forms of a goal not graduated yet, by name, in the goal's order.
    private func missingForms(_ progress: CompanionStore.FormProgress) -> [String] {
        progress.goal.forms.filter { !progress.graduated.contains($0) }.map {
            PokemonForm.label(speciesID: progress.goal.speciesID, form: $0, language: store.language) ?? $0.rawValue
        }
    }

    /// Label of a goal too long for a sprite row: a badge's type list, or one of the named groups.
    private func longGoalLabel(_ goal: SpeciesGoal, _ l: L) -> String {
        if let type = kind.badgeType {
            return l.badgeGoal(type, generation: PokemonTypeData.badgeGeneration(for: type))
        }
        switch goal.species {
        case SpeciesGoal.fossils:
            return goal.needed < goal.species.count ? l.fossilsGoal(goal.needed) : l.allFossilsGoal(goal.needed)
        case SpeciesGoal.ultraBeasts: return l.ultraBeastsGoal(goal.needed)
        case SpeciesGoal.paradoxes: return l.paradoxesGoal(goal.needed)
        default: return l.anyOfGoal(goal.needed)
        }
    }

    private func spriteSize(count: Int) -> CGFloat {
        compact ? (count > 6 ? 16 : 18) : (count > 6 ? 24 : 40)
    }

    /// Only on a met goal: an item can be owned without its goal (bought before the goal existed).
    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Design.actionColor)
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
