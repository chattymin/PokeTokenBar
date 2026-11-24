import SwiftUI

/// Every Mega, Primal and Gigantamax form, the won ones in color (the owner, 2026-11-24: "l'écran comme costumés", to
/// see every Mega and Gigantamax won). Laid out like `CostumeCollectionScreen`: a ring per kind, then each kind's
/// forms, five to a row. A won form opens its species' page in that form, and Back from there returns here.
@MainActor
struct BattleFormsScreen: View {
    let store: CompanionStore
    @Binding var wonOnly: Bool
    let onBack: () -> Void
    let onOpen: (BattleForm, String) -> Void

    /// A sprite's size, five to a row with their names, as on the Costumes screen.
    private static let cell: CGFloat = 40

    var body: some View {
        let l = store.l
        let won = store.dungeonProgress.battleForms
        let catalog = BattleForms.sections(won: won, wonOnly: false).filter { $0.kind != .armor }
        let sections = BattleForms.sections(won: won, wonOnly: wonOnly)
        let links = store.dexLinkTargets
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "atom").foregroundStyle(.secondary)
                Text(l.battleFormsTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                wonOnlyChip(l)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(catalog, id: \.kind) { section in
                            StatsRing(title: l.battleFormKindName(section.kind), owned: section.won, total: section.total,
                                      color: CollectionStatsScreen.done)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if sections.isEmpty {
                        Text(l.battleFormsNoneWon).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(sections, id: \.kind) { section in
                        kindSection(section, won: won, links: links, l)
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    /// Filled or not says it, not the color alone.
    private func wonOnlyChip(_ l: L) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { wonOnly.toggle() }
        } label: {
            Image(systemName: wonOnly ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12, weight: wonOnly ? .bold : .regular))
                .foregroundStyle(wonOnly ? Design.actionColor : Color.secondary)
                .frame(width: 16, height: 16)
                .modifier(CapsuleFilterChip(active: wonOnly, tint: Design.actionColor))
        }
        .buttonStyle(.plain)
        .hoverTip(l.battleFormsWonOnly)
        .accessibilityLabel(l.battleFormsWonOnly)
        .accessibilityAddTraits(wonOnly ? .isSelected : [])
    }

    /// A kind's forms: its name and count, then its forms.
    private func kindSection(_ section: BattleFormSection, won: Set<String>, links: [Int: String], _ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(l.battleFormKindName(section.kind)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(section.won)/\(section.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), alignment: .leading,
                      spacing: 2) {
                ForEach(section.forms, id: \.key) { form in
                    cell(form, won: won.contains(form.key), collectionID: links[form.speciesID], l)
                }
            }
        }
    }

    /// A form: in color and named once won ("Charizard X" under the Megas), its shape and "???" until then. A won
    /// form of a species in the Pokédex opens its page.
    @ViewBuilder
    private func cell(_ form: BattleForm, won: Bool, collectionID: String?, _ l: L) -> some View {
        if won, let collectionID {
            Button { onOpen(form, collectionID) } label: { cellLabel(form, won: true, l) }
                .buttonStyle(.plain)
                .speciesNameTooltip(form.speciesID, form: form.form, language: store.language)
        } else {
            cellLabel(form, won: won, l)
                .speciesNameTooltip(form.speciesID, form: form.form, language: store.language)
        }
    }

    private func cellLabel(_ form: BattleForm, won: Bool, _ l: L) -> some View {
        VStack(spacing: 0) {
            SpriteView(speciesID: form.speciesID, size: Self.cell, form: form.form, isSilhouette: !won, sameScale: true)
                .frame(width: Self.cell, height: Self.cell)
                .opacity(won ? 1 : 0.45)
            Group {
                if won {
                    PokemonNameLabel(.pokemonSpecies, String(form.speciesID), language: store.language,
                                     suffix: l.megaSuffix(form))
                } else {
                    Text("???")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(won ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
