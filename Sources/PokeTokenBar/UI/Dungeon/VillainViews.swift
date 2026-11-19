import SwiftUI

extension VillainTeam {
    var color: Color { Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

/// The thefts on Home (issue #180), the latest first, one card each.
@MainActor
struct VillainAmbushCards: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        ForEach(store.villainAmbushes) { ambush in
            VillainAmbushCard(store: store, nav: nav, ambush: ambush)
        }
    }
}

/// A theft, laid out as Prof. Oak's card: the grunt's bust, their words in a bubble, what they took and their three
/// Pokémon; then the chase, won or lost, and the way to the hideout. "Later" folds it to a low banner that opens again
/// with a click: it never goes before the theft is settled (the owner, 2026-11-10).
@MainActor
struct VillainAmbushCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let ambush: VillainAmbush

    /// Team Rocket chased: never caught, Giovanni laughs instead of a fight (`defendAgainstAmbush`).
    private var rocketTaunts: Bool { ambush.team == .rocket && ambush.won == false && ambush.battle == nil }

    private static let bustWidth: CGFloat = 84
    private static let bustHeight: CGFloat = 96
    private static let tail: CGFloat = 6

    var body: some View {
        if let kind = ambush.kind {
            let l = store.l
            if ambush.collapsed == true, ambush.won == nil {
                banner(kind, l)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    title(l)
                    bubble(kind, l)
                        .frame(minHeight: Self.bustHeight, alignment: .top)
                        .padding(.leading, Self.bustWidth + 4)
                        .background(alignment: .topLeading) {
                            // Team Rocket chased: Giovanni himself answers (the owner, 2026-11-19).
                            PortraitBust(name: rocketTaunts ? ambush.team.leaderPortrait : ambush.team.gruntPortrait,
                                         width: Self.bustWidth, symbol: "exclamationmark.triangle")
                                .frame(width: Self.bustWidth).frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                                .clipped()
                        }
                    actions(l)
                }
                .heroCard(colors: [ambush.won == true ? .gray : ambush.team.color])
            }
        }
    }

    private func title(_ l: L) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ambush.won == nil ? "exclamationmark.triangle.fill" : ambush.won == true
                  ? "checkmark.seal.fill" : "xmark.seal.fill")
            Text(l.villainAmbushTitle(ambush.team).uppercased()).kerning(0.6)
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(ambush.team.color)
    }

    private func itemLine(_ kind: ItemKind, _ l: L) -> String {
        l.itemName(kind) + (ambush.count > 1 ? " ×\(ambush.count)" : "")
    }

    /// The folded theft: one line, the grunt, what they took; a click opens it again.
    private func banner(_ kind: ItemKind, _ l: L) -> some View {
        Button { store.setVillainAmbushCollapsed(ambush.id, false) } label: {
            HStack(spacing: 8) {
                PortraitBust(name: ambush.team.gruntPortrait, width: 30, symbol: "exclamationmark.triangle")
                    .frame(width: 30, height: 30, alignment: .top).clipped()
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.villainAmbushTitle(ambush.team).uppercased()).font(.system(size: 10, weight: .heavy)).kerning(0.5)
                        .foregroundStyle(ambush.team.color)
                    HStack(spacing: 4) {
                        ItemIconView(kind: kind, size: 16)
                        Text(itemLine(kind, l)).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(l.villainDefend).font(.caption.weight(.semibold)).foregroundStyle(Design.actionColor)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ambush.team.color.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ambush.team.color.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bubble(_ kind: ItemKind, _ l: L) -> some View {
        let item = itemLine(kind, l)
        return VStack(alignment: .leading, spacing: 6) {
            switch ambush.won {
            case true?: Text(l.villainBeaten(ambush.team, item: item)).font(.callout.weight(.semibold))
            case false? where rocketTaunts:
                Text(l.villainRocketTaunt).font(.callout.weight(.semibold))
                Text(l.villainGotAway(ambush.team, item: item)).font(.caption).foregroundStyle(.secondary)
            case false?: Text(l.villainGotAway(ambush.team, item: item)).font(.callout.weight(.semibold))
            case nil: Text(l.villainAmbushBubble).font(.callout)
            }
            HStack(spacing: 6) {
                ItemIconView(kind: kind, size: 22)
                Text(item).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    ForEach(Array(ambush.grunts.enumerated()), id: \.offset) { _, id in
                        SpriteView(speciesID: id, size: 30, sameScale: true).frame(width: 30, height: 30)
                    }
                }
                .hoverTip(l.villainTheirPokemon)
            }
            .grayscale(ambush.won == true ? 0.6 : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8).padding(.trailing, 10).padding(.leading, 10 + Self.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpeechBubble(tail: Self.tail).fill(Color(nsColor: .textBackgroundColor).opacity(0.85)))
    }

    @ViewBuilder
    private func actions(_ l: L) -> some View {
        if ambush.won == nil {
            HStack(alignment: .center, spacing: 8) {
                Text(l.villainDefendWith).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                // Not now: folded to a banner, never gone.
                Button(l.villainLater) { store.setVillainAmbushCollapsed(ambush.id, true) }
                    .buttonStyle(.borderless).controlSize(.small).font(.caption).foregroundStyle(.secondary)
                Button(l.villainDefend) {
                    store.defendAgainstAmbush(ambush.id)
                    nav.replayBattle = store.villainAmbushes.first { $0.id == ambush.id }?.battle
                    nav.replayStart = 0
                }
                .buttonStyle(.pill(prominent: true))
                .disabled(store.expedition != nil)
                .hoverTip(store.expedition != nil ? l.dungeonOneAtATime : nil)
            }
        } else {
            HStack(spacing: 8) {
                if let battle = ambush.battle {
                    Button(l.villainSeeFight) {
                        nav.replayBattle = battle
                        nav.replayStart = 0
                    }
                    .buttonStyle(.borderless).controlSize(.small).font(.caption.weight(.semibold))
                }
                Spacer(minLength: 4)
                if ambush.won == false {
                    Button(l.villainToHideout) {
                        store.dismissVillainAmbush(ambush.id)
                        nav.tab = .dungeons
                    }
                    .buttonStyle(.pill())
                }
                Button(l.close) { store.dismissVillainAmbush(ambush.id) }.buttonStyle(.pill(prominent: true))
            }
        }
    }
}

/// A hideout in the Dungeons tab (issue #180), on top while its team keeps something: its diorama with the leader
/// under it, what they keep, who waits at the end, the way to its team screen. A hero card in the team's color.
@MainActor
struct HideoutCard: View {
    let store: CompanionStore
    let team: VillainTeam
    let onPrepare: () -> Void
    /// "Abandon" asks once more before the items are lost for good.
    @State private var confirmingAbandon = false

    var body: some View {
        if let stash = store.villainStash(team) {
            let l = store.l
            let id = team.hideoutID
            VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // The leader under the diorama, large (the owner, 2026-11-10: there was a void under them).
                VStack(spacing: -10) {
                    DungeonIcon(id: id, size: 96)
                        .shadow(color: team.color.opacity(0.6), radius: 10)
                    PortraitBust(name: team.leaderPortrait, width: 92, symbol: "person.fill")
                        .frame(width: 96, height: 118, alignment: .top).clipped()
                }
                .frame(width: 96)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Badge("T\(team.tier.rawValue)", tint: .secondary, style: .tinted, size: 10)
                        Text(l.villainTeamName(team).uppercased()).font(.system(size: 10, weight: .heavy)).kerning(0.6)
                            .foregroundStyle(team.color)
                    }
                    Text(l.villainHideoutName(team)).font(.system(size: 19, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l.villainKeeps).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    WrappingHStack(spacing: 6, lineSpacing: 4) {
                        ForEach(stash.items.sorted { $0.key < $1.key }, id: \.key) { key, count in
                            if let kind = ItemKind(rawValue: key) {
                                HStack(spacing: 3) {
                                    ItemIconView(kind: kind, size: 20)
                                    Text(count > 1 ? "\(l.itemName(kind)) ×\(count)" : l.itemName(kind))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(team.leaderTeam.enumerated()), id: \.offset) { i, species in
                            SpriteView(speciesID: species, size: 34, form: team.leaderForms[i], sameScale: true)
                                .frame(width: 34, height: 34)
                        }
                    }
                    Text(l.villainWaitsAtTheEnd(team)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if confirmingAbandon {
                        Text(l.villainAbandonConfirm).font(.caption.weight(.semibold)).foregroundStyle(Color.readableOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
                HStack(spacing: 8) {
                    // Giving up what they took (the owner, 2026-11-16), never an artifact: bottom left, in blue, on
                    // the buttons' line (the owner: a grey line under the text was not readable).
                    if stash.items.keys.contains(where: { ItemKind(rawValue: $0).map(VillainRules.canAbandon) ?? true }) {
                        if confirmingAbandon {
                            Button(l.cancel) { confirmingAbandon = false }
                                .buttonStyle(.borderless).font(.callout).foregroundStyle(.secondary)
                            Button(l.villainAbandon) {
                                store.abandonStolen(team)
                                confirmingAbandon = false
                            }
                            .buttonStyle(.borderless).font(.callout.weight(.semibold)).foregroundStyle(Design.actionColor)
                        } else {
                            Button(l.villainAbandon) { confirmingAbandon = true }
                                .buttonStyle(.borderless).font(.callout.weight(.semibold)).foregroundStyle(Design.actionColor)
                                .hoverTip(l.villainAbandonHint)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(TokenFormatter.compact(store.dungeonCost(id))).font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button(l.dungeonPrepare, action: onPrepare)
                        .buttonStyle(.pill(prominent: true))
                        .disabled(!store.canEnter(id))
                        .hoverTip(store.expedition != nil ? l.dungeonOneAtATime : nil)
                }
            }
            .heroCard(colors: [team.color])
        }
    }
}
