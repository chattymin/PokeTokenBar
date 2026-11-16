import SwiftUI

/// Home while a team explores, as Prof. Oak's card (the owner, 2026-11-10, choice C with his notes): the dungeon's
/// diorama with a guide at its foot telling in a bubble how it goes, a track of one circle a floor showing what happened
/// there (its journal line on hover, nothing for a floor still ahead), the team in rings of their HP.
@MainActor
struct ExpeditionGuideHeader: View {
    let store: CompanionStore
    let e: Expedition

    /// The guide's render (Pokémon Masters EX's Hiker, as the merchants'), cached under the stones merchant's name.
    static let guidePortrait = "merchant-stones"
    private static let tail: CGFloat = 6

    var body: some View {
        let l = store.l
        HStack(alignment: .top, spacing: 4) {
            // The dungeon itself (the owner: "on ne voit jamais le donjon"), the guide at its foot.
            DungeonIcon(id: e.dungeon, size: 80, boss: e.dungeon.isChallenge ? e.boss : nil, animated: true)
                .shadow(color: DungeonCard.colors(e.dungeon)[0].opacity(0.55), radius: 10)
                .overlay(alignment: .bottomTrailing) {
                    PortraitBust(name: Self.guidePortrait, width: 50, symbol: "figure.hiking")
                        .frame(width: 50, height: 62, alignment: .top).clipped()
                        .offset(x: 10, y: 50)
                }
                .padding(.bottom, 44)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(l.dungeonName(e.dungeon))
                    .font(.system(size: 16, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                // The team down to the heal: an alert in place of the path (the owner, 2026-11-10).
                if case .awaitingHeal = e.phase {
                    Label(l.guideKOAlert.uppercased(), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.readableOrange.opacity(0.3)))
                        .foregroundStyle(Color.readableOrange)
                } else {
                    Text(l.dungeonPath(risky: e.risky).uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((e.risky ? Color.readableOrange : Design.actionColor).opacity(0.22)))
                        .foregroundStyle(e.risky ? Color.readableOrange : Design.actionColor)
                        .hoverTip(l.dungeonPathRule)
                }
                Text(Self.words(store, e)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8).padding(.trailing, 10).padding(.leading, 10 + Self.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpeechBubble(tail: Self.tail).fill(Color(nsColor: .textBackgroundColor).opacity(0.85)))
        }
    }

    /// What the guide says: the floors behind, who is down, who is weak, where the boss waits.
    static func words(_ store: CompanionStore, _ e: Expedition) -> String {
        let l = store.l
        func name(_ m: ExpeditionMember) -> String {
            if let entry = store.state.dex.first(where: { $0.id == m.entryID }) { return store.dexEntryName(entry) }
            let item = PokemonNameItem(resource: PokemonNameResource(kind: .pokemonSpecies, name: String(m.spec.speciesID)))
            return PokemonNameText(items: [item], language: store.language, names: PokemonNameDisplayStore.shared.names).text
        }
        let fainted = e.team.filter(\.isFainted).map(name)
        let weak = e.team.filter { !$0.isFainted && Double($0.spec.hp) < Double($0.spec.stats.hp) * 0.25 }.map(name)
        var parts = [l.guideFloors(done: min(e.floor, e.floors) - 1)]
        if !fainted.isEmpty { parts.append(l.guideFainted(fainted)) }
        if !weak.isEmpty { parts.append(l.guideWeak(weak)) }
        if case .awaitingHeal = e.phase { parts.append(l.guideNeedsHeal) } else { parts.append(l.guideBoss(at: e.floors)) }
        return parts.joined(separator: " ")
    }
}

/// One circle a floor, the line through them filled as the team walks: passed floors show what happened there, the
/// current one the team's leader, the boss's floor its crown. On the return, every floor walked shows its event.
@MainActor
struct ExpeditionFloorTrack: View {
    let store: CompanionStore
    let log: [ExpeditionLogEntry]
    let floors: Int
    /// The floor being crossed, past the last once the run is over.
    let floor: Int
    let progress: Double
    let lead: ExpeditionMember?

    init(store: CompanionStore, e: Expedition) {
        self.store = store
        log = e.log
        floors = e.floors
        floor = min(e.floor, e.floors)
        progress = Double(e.floorTokens) / Double(max(1, e.floorCost))
        lead = e.team.first { !$0.isFainted } ?? e.team.first
    }

    /// The floor the team fell on, crossed in orange (a lost run).
    var fellOn: Int? = nil

    /// The return: the floors the team reached, each with what happened there; a defeat's floor crossed.
    init(store: CompanionStore, result r: ExpeditionResult) {
        self.store = store
        log = r.log
        floors = DungeonCatalog.dungeon(r.dungeon).floors
        floor = (r.log.map(\.floor).max() ?? 0) + 1
        progress = 0
        lead = nil
        fellOn = !r.won && !r.roped ? r.log.map(\.floor).max() : nil
    }

    var body: some View {
        let width = PopoverMetrics.scrollContentWidth - Design.cardPadding * 2
        let spacing: CGFloat = 3
        // Fifteen floors in one row: the current one larger, the others share what is left.
        let current: CGFloat = lead == nil ? 0 : 30
        let size = min(26, (width - current - spacing * CGFloat(floors - 1)) / CGFloat(max(1, floors - (lead == nil ? 0 : 1))))
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                let share = (Double(floor - 1) + progress) / Double(max(1, floors - 1))
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 3)
                    .frame(maxHeight: .infinity)
                Capsule().fill(Design.actionColor).frame(width: geo.size.width * min(1, share), height: 3)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, size / 2)
            HStack(spacing: spacing) {
                ForEach(1...max(1, floors), id: \.self) { n in
                    if n == floor, let lead {
                        node(n, size: current) {
                            SpriteView(speciesID: lead.spec.speciesID, size: current - 6, shiny: lead.spec.isShiny,
                                       form: lead.spec.form, sameScale: true)
                        }
                    } else {
                        node(n, size: size) { glyph(n, size: size) }
                    }
                }
            }
        }
        .frame(height: max(current, size))
    }

    private func node(_ n: Int, size: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        let passed = n < floor, here = n == floor && lead != nil, fell = n == fellOn
        let tip = passed || here ? ExpeditionLogText.floor(n, log: log, floors: floors, store: store) : nil
        return ZStack {
            Circle().fill(here ? Design.actionColor.opacity(0.28) : fell ? Color.readableOrange.opacity(0.3)
                : passed ? Color(nsColor: .textBackgroundColor).opacity(0.9) : Color.primary.opacity(0.05))
            Circle().strokeBorder(here ? Design.actionColor : fell ? Color.readableOrange : Color.primary.opacity(passed ? 0.35 : 0.2),
                                  style: StrokeStyle(lineWidth: here || fell ? 2 : 1.2, dash: passed || here ? [] : [2, 2]))
            if fell {
                Image(systemName: "xmark").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(Color.readableOrange)
            } else {
                content()
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        // The floor's journal on hover; a floor still ahead says nothing (the owner).
        .hoverTip(tip?.isEmpty == false ? tip : nil)
    }

    @ViewBuilder
    private func glyph(_ n: Int, size: CGFloat) -> some View {
        let font = Font.system(size: size * 0.48, weight: .bold)
        if n >= floor {
            if n == floors { Image(systemName: "crown.fill").font(font).foregroundStyle(.secondary) }
        } else if let (symbol, color) = ExpeditionLogText.symbol(floor: n, log: log) {
            Image(systemName: symbol).font(font).foregroundStyle(color)
        } else {
            Image(systemName: "footprints").font(font).foregroundStyle(.secondary)
        }
    }
}

/// The team in rings of their HP (blue, orange with "!" under a quarter, grey and crossed once down), one row.
@MainActor
struct ExpeditionTeamRings: View {
    let team: [ExpeditionMember]

    var body: some View {
        let size = min(46, (PopoverMetrics.scrollContentWidth - Design.cardPadding * 2 - 5 * 5) / CGFloat(max(1, team.count)))
        HStack(spacing: 5) {
            ForEach(Array(team.enumerated()), id: \.offset) { _, member in ring(member, size: size) }
        }
        .frame(maxWidth: .infinity)
    }

    private func ring(_ member: ExpeditionMember, size: CGFloat) -> some View {
        let share = Double(max(0, member.spec.hp)) / Double(max(1, member.spec.stats.hp))
        let color: Color = member.isFainted ? .gray : share < 0.25 ? .readableOrange : Design.actionColor
        return ZStack {
            Circle().fill(Color.primary.opacity(0.06))
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle().trim(from: 0, to: share).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            SpriteView(speciesID: member.spec.speciesID, size: size - 10, shiny: member.spec.isShiny, form: member.spec.form,
                       sameScale: true)
                .grayscale(member.isFainted ? 1 : 0).opacity(member.isFainted ? 0.4 : 1)
            if member.isFainted {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.secondary)
            } else if share < 0.25 {
                Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 15, height: 15).background(Circle().fill(Color.readableOrange))
                    .offset(x: size / 2 - 6, y: -size / 2 + 6)
            }
        }
        .frame(width: size, height: size)
        .hoverTip("\(Int((share * 100).rounded())) %")
    }
}

/// The journal said in words, for the floors' tooltips.
@MainActor
enum ExpeditionLogText {
    /// What happened on a floor, a line an event; empty when nothing was written there.
    static func floor(_ n: Int, of e: Expedition, store: CompanionStore) -> String {
        floor(n, log: e.log, floors: e.floors, store: store)
    }

    static func floor(_ n: Int, log: [ExpeditionLogEntry], floors: Int, store: CompanionStore) -> String {
        log.filter { $0.floor == n }.compactMap { line($0, floors: floors, store: store) }.joined(separator: "\n")
    }

    /// The floor's main event, as its circle shows it: a shiny or a find first, then a fight, then the rest.
    static func symbol(floor n: Int, log: [ExpeditionLogEntry]) -> (String, Color)? {
        let kinds = log.filter { $0.floor == n }.map(\.kind)
        let ranked: [(rank: Int, symbol: String, color: Color)] = kinds.compactMap { kind in
            switch kind {
            case .shiny: (0, "sparkles", .yellow)
            case .secretPassage: (1, "door.left.hand.open", .purple)
            case .chest(let loot): (2, loot.isEmpty ? "shippingbox" : "shippingbox.fill", .brown)
            case .bossReached: (3, "crown.fill", .yellow)
            case .battle(let b):
                (4, b.kind == .trainer ? "person.fill" : b.kind == .horde ? "pawprint.fill" : "bolt.fill",
                 b.won ? Design.actionColor : Color.readableOrange)
            case .trap: (5, "exclamationmark.triangle.fill", Color.readableOrange)
            case .lost: (6, "questionmark.circle.fill", .secondary)
            case .spring: (7, "drop.fill", .cyan)
            case .center: (8, "cross.case.fill", .pink)
            default: nil
            }
        }
        return ranked.min { $0.rank < $1.rank }.map { ($0.symbol, $0.color) }
    }

    static func line(_ entry: ExpeditionLogEntry, floors: Int, store: CompanionStore) -> String? {
        let l = store.l
        func items(_ loot: ExpeditionLoot) -> String {
            var parts: [String] = []
            if loot.candies > 0 { parts.append("\(l.itemName(.rareCandy)) ×\(loot.candies)") }
            for (key, count) in loot.items.sorted(by: { $0.key < $1.key }) {
                if let kind = ItemKind(rawValue: key) { parts.append(count > 1 ? "\(l.itemName(kind)) ×\(count)" : l.itemName(kind)) }
            }
            if !loot.eggs.isEmpty { parts.append(l.itemName(.pokemonEgg) + " ×\(loot.eggs.count)") }
            return parts.joined(separator: ", ")
        }
        switch entry.kind {
        case .battle(let b):
            let foes = b.setup.sides.count > 1 ? b.setup.sides[1].battlers.count : 0
            return "\(l.battleKind(b.kind)) · \(l.guideFoes(foes)) · \(b.won ? l.battleWon : l.battleLost)"
        case .chest(let loot): return loot.isEmpty ? l.dungeonLogEmptyChest : "\(l.dungeonLogChest) · \(items(loot))"
        case .trap(let percent, let item):
            return item.flatMap(ItemKind.init(rawValue:)).map { l.dungeonLogTrapItem(l.itemName($0)) } ?? l.dungeonLogTrap(percent: percent)
        case .spring(let percent): return l.dungeonLogSpring(percent: percent)
        case .center: return l.dungeonLogCenter
        case .lost(_, let percent, let loot):
            let found = items(loot)
            return l.dungeonLogLost(percent: percent) + (found.isEmpty ? "" : " · \(found)")
        case .shiny(_, let caught): return l.dungeonLogShiny(caught: caught)
        case .secretPassage(let skipped, let loot):
            return (skipped ? l.dungeonLogSecretSkip(entry.floor + 1) : l.dungeonLogSecretRoom)
                + (loot.map { " · " + items($0) } ?? "")
        case .branch(let roll, let risky):
            return l.dungeonLogBranch(roll: roll, risky: risky, until: min(entry.floor + 3, floors - 1))
        case .revive(_, let max): return l.dungeonLogItemUsed(l.itemName(max ? .maxRevive : .revive))
        case .emergencyHeal(let paid): return l.dungeonLogHeal(TokenFormatter.compact(paid))
        case .bossReached(_, _, _, let secret): return secret == true ? l.dungeonLogSecretBoss : l.dungeonLogBoss
        case .capture(let attempt, let ball, let caught):
            return l.dungeonLogThrow(attempt, ball: ball.flatMap(ItemKind.init(rawValue:)).map(l.itemName) ?? l.dungeonPokeBall,
                                     caught: caught)
        case .victory: return l.dungeonLogVictory
        case .defeat: return l.dungeonLogDefeat
        case .abandon: return l.dungeonLogLeft
        }
    }
}

/// The return. Won: its prize large, the egg it gave (drawn, moving), else the form or the boss beaten (the owner,
/// 2026-11-10). Lost or left: the guide says where, against what, what is kept and what to try.
@MainActor
struct ExpeditionResultGuide: View {
    let store: CompanionStore
    let r: ExpeditionResult
    private static let tail: CGFloat = 6

    var body: some View {
        if r.won { prize } else { guide }
    }

    /// The egg the boss gave, its own or the one in its place; nil when it gave none (a challenge, a hideout, a legendary
    /// whose egg was won once, a boss not caught).
    static func egg(_ r: ExpeditionResult) -> (kind: EggKind, item: ItemKind?, speciesID: Int?)? {
        guard r.won, !r.dungeon.isChallenge, !r.dungeon.isHideout else { return nil }
        // A secret boss's egg first: the rarest prize of all (the Origin trio's after Arceus included).
        if let secret = r.loot.eggs.first(where: { $0.isSecret == true }) {
            return (.secret, nil, secret.sourceSpeciesID)
        }
        if let own = r.loot.eggs.first(where: { $0.sourceSpeciesID == r.boss.speciesID }) {
            return (own.eggKind, nil, own.sourceSpeciesID)
        }
        let tier = DungeonCatalog.dungeon(r.dungeon).tier
        guard r.caught, let item = ExpeditionEngine.eggInPlace(r.bossReward, tier: tier) else { return nil }
        let kind: EggKind = switch item {
        case .legendaryEgg: .tier(.legendary)
        case .rareEgg: .tier(.rare)
        case .uncommonEgg: .tier(.uncommon)
        default: .plain
        }
        return (kind, item, nil)
    }

    /// The boss fell, its throws all missed: it got away (the owner, 2026-11-12: shown large in color, it looked caught).
    static func missedCapture(_ r: ExpeditionResult) -> Bool {
        guard r.won, !r.caught, !r.dungeon.isChallenge, !r.dungeon.isHideout else { return false }
        return r.log.contains { if case .capture = $0.kind { return true }; return false }
    }

    private var prize: some View {
        let l = store.l
        let missed = Self.missedCapture(r)
        let color = missed ? CollectionStatsScreen.left : r.villain.map(\.color) ?? DungeonCard.colors(r.dungeon)[0]
        let form = r.battleForm.flatMap { BattleForms.form(key: $0) }
        let villainForm = r.villain.flatMap { team in team.leaderTeam.first == r.boss.speciesID ? team.leaderForms[0] : nil }
        return VStack(spacing: 4) {
            Group {
                if let egg = Self.egg(r) {
                    SpriteView(speciesID: nil, size: 120, animated: true, egg: egg.kind)
                } else {
                    // Got away: a silhouette, as its place in the dungeon shows it until it is caught there.
                    SpriteView(speciesID: form?.speciesID ?? r.boss.speciesID, size: 120, animated: !missed, shiny: r.boss.isShiny,
                               form: form?.form ?? r.boss.form ?? villainForm, isSilhouette: missed, sameScale: true)
                }
            }
            .frame(width: 132, height: 124)
            .shadow(color: color.opacity(missed ? 0.35 : 0.7), radius: 16)
            .overlay(alignment: .bottom) {
                if missed {
                    Label(l.dungeonBossGotAway, systemImage: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .heavy)).textCase(.uppercase).lineLimit(1).fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(CollectionStatsScreen.left))
                        .offset(y: 6)
                }
            }
            Group {
                if let egg = Self.egg(r) {
                    if let species = egg.speciesID {
                        DungeonEggTitle(speciesID: species, l: l, language: store.language, secret: egg.kind == .secret)
                    } else if let item = egg.item {
                        Text(l.itemName(item))
                    }
                } else if let form {
                    BattleFormTitle(form: form, language: store.language, wrap: l.challengeFormWon)
                } else {
                    PokemonNameLabel(.pokemonSpecies, String(r.boss.speciesID), language: store.language)
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text([l.dungeonName(r.dungeon), TokenFormatter.compact(r.tokens),
                  l.longDuration(r.endedAt.timeIntervalSince(r.startedAt)), l.dungeonBattles(r.battles)].joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var guide: some View {
        let l = store.l
        return HStack(alignment: .top, spacing: 4) {
            DungeonIcon(id: r.dungeon, size: 80, boss: r.dungeon.isChallenge ? r.boss : nil, animated: true)
                .grayscale(0.6)
                .overlay(alignment: .bottomTrailing) {
                    PortraitBust(name: ExpeditionGuideHeader.guidePortrait, width: 50, symbol: "figure.hiking")
                        .frame(width: 50, height: 62, alignment: .top).clipped()
                        .offset(x: 10, y: 50)
                }
                .padding(.bottom, 44)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(l.dungeonName(r.dungeon))
                    .font(.system(size: 16, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text(Self.lostWords(r, l)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8).padding(.trailing, 10).padding(.leading, 10 + Self.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpeechBubble(tail: Self.tail).fill(Color(nsColor: .textBackgroundColor).opacity(0.85)))
        }
    }

    /// Lost: on which floor, against what, what stays, what to try. Left: where it turned back, the loot kept.
    static func lostWords(_ r: ExpeditionResult, _ l: L) -> String {
        let floor = r.log.map(\.floor).max() ?? 1
        let floors = DungeonCatalog.dungeon(r.dungeon).floors
        let kept = !r.loot.isEmpty
        if r.roped { return [l.guideTurnedBack(floor: floor, of: floors), l.guideKept(kept)].joined(separator: " ") }
        let last = r.log.reversed().compactMap { entry -> ExpeditionBattle? in
            if case .battle(let b) = entry.kind, !b.won { return b } else { return nil }
        }.first
        return [l.guideFell(floor: floor, of: floors, against: last?.kind), l.guideKept(kept), l.guideTryAgain]
            .joined(separator: " ")
    }
}
