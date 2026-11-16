import SwiftUI

/// Prof. Oak's advice, at the top of the Shop under the balance card: one sentence in his bubble, then the steps in
/// order, one line each. His details page explains each step. Nothing runs from the card: a step done in another tab
/// links to it.
@MainActor
struct OakAdviceCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    static let bustWidth: CGFloat = 84
    /// Head and chest at least, beside a short bubble.
    private static let bustHeight: CGFloat = 90
    private static let tail: CGFloat = 6

    var body: some View {
        let l = store.l
        let words = OakWords(store)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: l.oakAdviceTitle)
            bubble(words)
                .frame(minHeight: Self.bustHeight, alignment: .top)
                .padding(.leading, Self.bustWidth + 4)
                .background(alignment: .topLeading) {
                    PortraitBust(name: SpriteStore.oakPortrait, width: Self.bustWidth)
                        .frame(width: Self.bustWidth).frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
            if let pause = words.pauseNote {
                Label(pause, systemImage: "pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            stepList(l, words)
            Button { nav.showingOakDetails = true } label: {
                HStack(spacing: 4) {
                    Text(l.recapDetails)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .heroCard(colors: store.themeColors)
    }

    private func bubble(_ words: OakWords) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OakVerdictLabel(store: store, verdict: words.verdict)
            Text(words.bubble)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8).padding(.trailing, 10).padding(.leading, 10 + Self.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpeechBubble(tail: Self.tail).fill(Color(nsColor: .textBackgroundColor).opacity(0.85)))
    }

    @ViewBuilder
    private func stepList(_ l: L, _ words: OakWords) -> some View {
        if !words.steps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(words.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        OakStepNumber(index + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words.title(step)).font(.caption.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let note = words.note(step) {
                                Text(note).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 4)
                        switch words.place(step) {
                        case .bag?:
                            link(l.treasureOpenBag) { nav.tab = .bag }
                        case .home?:
                            link(l.home) { nav.tab = .home }
                        case .dungeons?:
                            link(l.dungeonsTab) { nav.tab = .dungeons }
                        case nil:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    /// A step's link to the tab where it is done.
    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Design.actionColor)
            .lineLimit(1).fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

/// A character from the top (Prof. Oak, the travelling merchant), cut by the bottom of its bubble, breathing as the
/// Pokémon's sprites move (`OakIdle`). A view of its own: each frame redraws the portrait, not the card. Still with
/// Reduce Motion.
@MainActor
struct PortraitBust: View {
    let name: String
    let width: CGFloat
    var symbol = "graduationcap.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var oak: NSImage?
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0

    init(name: String, width: CGFloat, symbol: String = "graduationcap.fill") {
        self.name = name
        self.width = width
        self.symbol = symbol
        _oak = State(initialValue: SpriteLoader.cachedItemImage(name: name))
    }

    var body: some View {
        Group {
            if let oak {
                let image = frames.isEmpty ? oak : frames[frameIndex % frames.count].image
                Image(nsImage: image)
                    .resizable()
                    .frame(width: width, height: width * image.size.height / max(1, image.size.width))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: "\(name)-\(reduceMotion)") {
            if oak == nil { oak = await SpriteLoader.itemImage(name: name) }
            guard let oak, !reduceMotion else {
                frames = []
                return
            }
            frames = OakIdle.frames(oak, width: width)
            // Cancelled with the view (the Shop left, the popover closed), as `SpriteView.playFrames`.
            while !Task.isCancelled, !frames.isEmpty {
                try? await Task.sleep(for: .seconds(frames[frameIndex % frames.count].delay))
                if Task.isCancelled { break }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }
}

/// Prof. Oak's idle loop, drawn from his still render as the eggs' are (`EggRenderer.idleFrames`): he breathes in and
/// out, his figure stretched up a little from his feet, the chest a third as much in width. Made once per portrait.
@MainActor
enum OakIdle {
    static let frameCount = 24
    /// One breath every three seconds.
    static let frameDelay: TimeInterval = 0.125
    /// The height a breath adds, in parts of his figure: his head rises about 3 pt in the card.
    static let breath: CGFloat = 0.015

    private static var cache: (portrait: ObjectIdentifier, width: CGFloat, frames: [(image: NSImage, delay: TimeInterval)])?

    /// The frames at `width` points, drawn at twice the pixels for a Retina screen, a breath taller than the portrait:
    /// his hair touches its top. None for an empty image.
    static func frames(_ portrait: NSImage, width: CGFloat) -> [(image: NSImage, delay: TimeInterval)] {
        if let cache, cache.portrait == ObjectIdentifier(portrait), cache.width == width { return cache.frames }
        guard portrait.size.width > 0, let source = portrait.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }
        let figure = width * portrait.size.height / portrait.size.width
        let size = CGSize(width: width, height: (figure * (1 + breath)).rounded(.up))
        let pixels = (width: Int(size.width * 2), height: Int(size.height * 2))
        let frames = (0..<frameCount).compactMap { i -> (image: NSImage, delay: TimeInterval)? in
            // 0 breathed out, 1 breathed in, eased both ways.
            let inhale = (1 - cos(2 * Double.pi * Double(i) / Double(frameCount))) / 2
            let stretch = breath * CGFloat(inhale)
            guard let context = CGContext(data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            // Anchored at his feet, the bottom middle of the image: the drawing grows up and a little sideways.
            let w = CGFloat(pixels.width) * (1 + stretch / 3)
            let h = figure * 2 * (1 + stretch)
            context.draw(source, in: CGRect(x: (CGFloat(pixels.width) - w) / 2, y: 0, width: w, height: h))
            guard let image = context.makeImage() else { return nil }
            return (NSImage(cgImage: image, size: size), frameDelay)
        }
        cache = (ObjectIdentifier(portrait), width, frames)
        return frames
    }
}

/// Prof. Oak's advice in full, opened from his card: the verdict, each step with its why, the Shiny Charm, then why
/// overall. It takes over the popover like the Bonuses page.
@MainActor
struct OakAdviceScreen: View {
    let store: CompanionStore
    let onBack: () -> Void

    var body: some View {
        let l = store.l
        let words = OakWords(store)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.oakAdviceTitle).font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        OakVerdictLabel(store: store, verdict: words.verdict)
                        Text(words.verdictInFull).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if let pause = words.pauseNote {
                            Label(pause, systemImage: "pause.circle")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(Array(words.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            OakStepNumber(index + 1)
                            explained(words.title(step), words.explanation(step))
                        }
                    }
                    if store.proposesShinyCharm, let price = store.price(of: .shinyCharm) {
                        let odds = store.shinyCharmOdds
                        explained(l.oakShinyCharm(l.itemName(.shinyCharm)),
                                  l.oakShinyCharmWhy(TokenFormatter.compact(price)) + " "
                                      + l.shinyOddsChange(from: odds.now, to: odds.withCharm))
                    }
                    SectionTitle(text: l.oakWhyTitle)
                    let eggs = l.oakWhyEgg(rare: l.eggName(.rare), uncommon: l.eggName(.uncommon), amber: l.itemName(.oldAmber))
                    let dungeons = l.oakWhyDungeons(win: l.oddsPercent(50, share: CompanionStore.oakDungeonWin),
                                                    hall: l.oddsPercent(10, share: CompanionStore.oakHallWin),
                                                    hallName: l.dungeonName(.hallOfOrigin),
                                                    share: l.oddsPercent(15, share: CompanionStore.oakDungeonShare))
                    ForEach([l.oakWhy(flute: l.itemName(.legendCharm)), eggs, l.oakWhyStock, l.oakWhyCandies, dungeons],
                            id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private func explained(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The tab where a step is done, when it is not the Shop.
private enum OakPlace {
    case bag, home, dungeons
}

/// Prof. Oak's advice read once: the verdict on the Pokémon raised, what a Spare goes for, the balance's plan and the
/// steps (`CompanionStore.oakSteps`), with their words.
@MainActor
private struct OakWords {
    let store: CompanionStore
    let verdict: ActiveVerdict?
    let release: OakRelease?
    let budget: OakBudget?
    let steps: [OakStep]

    init(_ store: CompanionStore) {
        self.store = store
        verdict = store.activeVerdict
        release = store.oakRelease
        budget = store.oakBudget(after: release)
        steps = store.oakSteps(after: release, budget: budget)
    }

    private var l: L { store.l }
    private var name: String { store.displayName }

    /// While a team explores, what Oak says of the growth: paused until it is back (Q1).
    var pauseNote: String? {
        guard store.growthPaused, let dungeon = store.expedition?.dungeon else { return nil }
        return verdict == nil ? l.oakDungeonPauseEgg(l.dungeonName(dungeon)) : l.oakDungeonPause(name, l.dungeonName(dungeon))
    }

    /// One sentence: what to do with a Spare, else what the Pokémon brings.
    var bubble: String {
        if let release { return l.oakReleaseBubble(release) }
        return verdict.map(said) ?? l.oakEggBubble
    }

    var verdictInFull: String {
        guard let verdict else { return l.oakEggBubble }
        return release.map { said(verdict) + " " + l.oakReleaseBubble($0) } ?? said(verdict)
    }

    private func said(_ verdict: ActiveVerdict) -> String {
        var reveal = ""
        if case .formMystery(let mystery) = verdict { reveal = store.activeSpeciesName(mystery.revealSpeciesID) }
        return l.oakBubble(verdict, name: name, newFormName: newFormName(verdict), revealName: reveal)
    }

    /// The species it brings in its form, named in it ("Ninetales [Alolan Form]").
    private func newFormName(_ verdict: ActiveVerdict) -> String {
        guard case .newForm(let id) = verdict else { return "" }
        return store.activeSpeciesName(id)
    }

    func title(_ step: OakStep) -> String {
        switch step {
        case .raise:
            return l.oakRaise(name)
        case .release(let release):
            switch release {
            case .bag(let kind, _): return l.oakUseFromBag(l.itemName(kind))
            case .claim(let egg, _): return l.oakClaimThenUse(l.itemName(egg.item))
            case .buy(let tier, _): return l.oakBuyThenUse(l.eggName(tier))
            case .wait(let tier, _, _): return l.oakKeepThenBuy(name, l.eggName(tier))
            case .finish(let left, _): return l.oakLetFinish(name, left: TokenFormatter.compact(left))
            }
        case .stock(let budget):
            let egg = l.eggName(budget.egg?.bagEggTier)
            if budget.takesTheLast {
                return l.oakBagCoversTheNextOnly(egg, price: TokenFormatter.compact(store.price(of: .egg(budget.egg?.bagEggTier))))
            }
            return budget.buyAhead > 0
                ? l.oakBuyAhead(budget.buyAhead, egg)
                : l.oakSetAside(TokenFormatter.compact(budget.reserve), count: budget.target - budget.held, egg: egg)
        case .candies(let buy, let give, let keep):
            if buy > 0 { return give > 0 ? l.oakBuyAndGiveCandies(buy, give, to: name) : l.oakBuyAndKeepCandies(buy) }
            return give > 0 ? l.oakGiveCandies(give, to: name) : l.oakKeepCandies(keep)
        case .dungeon(let dungeon):
            let name = l.dungeonName(dungeon.id)
            if case .key = dungeon.reason { return l.oakExploreForKey(name, key: l.itemName(.legendaryKey)) }
            return l.oakExplore(name)
        }
    }

    func note(_ step: OakStep) -> String? {
        if case .dungeon(let dungeon) = step { return gear(dungeon) }
        guard store.oakWaitsForTheTeam(step) else { return nil }
        if case .candies = step { return l.oakGiveOnReturn }
        return l.oakUseOnReturn
    }

    func explanation(_ step: OakStep) -> String? {
        if case .dungeon = step { return [detail(step), note(step)].compactMap { $0 }.joined(separator: "\n") }
        let parts = [note(step), detail(step)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func detail(_ step: OakStep) -> String? {
        switch step {
        case .raise: return nil
        case .release(let release): return releaseDetail(release)
        case .stock(let budget): return stockDetail(budget)
        case .candies(let buy, let give, let keep): return candiesDetail(buy: buy, give: give, keep: keep)
        case .dungeon(let dungeon): return dungeonDetail(dungeon)
        }
    }

    func place(_ step: OakStep) -> OakPlace? {
        switch step {
        case .raise, .release(.wait), .release(.finish), .stock: return nil
        case .release(.bag), .release(.buy): return .bag
        case .release(.claim): return .home
        case .candies(_, let give, _): return give > 0 ? .bag : nil
        case .dungeon: return .dungeons
        }
    }

    private func percent(_ p: Double) -> String { l.oddsPercent(Int((p * 100).rounded()), share: p) }

    private func releaseDetail(_ release: OakRelease) -> String {
        func price(_ tier: Rarity?) -> String { TokenFormatter.compact(store.price(of: .egg(tier))) }
        let amber = store.itemCount(.oldAmber) > 0 ? " " + l.oakAmberKeeps(l.itemName(.oldAmber), name: name) : ""
        switch release {
        case .bag(_, let p):
            return l.oakSendsOff(name, odds: percent(p)) + amber
        case .claim(_, let p):
            return l.oakClaimWaits + " " + l.oakSendsOff(name, odds: percent(p)) + amber
        case .buy(let tier, let p):
            return l.oakEggCosts(price(tier)) + " " + l.oakSendsOff(name, odds: percent(p)) + amber
        case .wait(let tier, let p, let short):
            let eta = store.timeToEarn(short).map { l.oakAtYourPace(l.shortDuration($0)) } ?? ""
            return l.oakWaitForEgg(price: price(tier), short: TokenFormatter.compact(short), eta: eta, odds: percent(p))
                + amber
        case .finish(_, .noBetterEgg):
            return l.oakNoEggBeatsGraduation
        case .finish(_, .tooFarAlong):
            return l.oakTooFarAlong + (amber.isEmpty ? "" : " " + l.oakEvenWithAmber(l.itemName(.oldAmber)))
        case .finish(_, .outgrowsTheWait):
            return l.oakOutgrowsTheWait
        }
    }

    private func dungeonDetail(_ dungeon: OakDungeon) -> String {
        let why: String
        switch dungeon.reason {
        case .firstWin: why = l.oakDungeonFirstWin
        case .challenge: why = l.oakDungeonChallenge
        case .boss: why = l.oakDungeonBoss
        case .coronetDoor: why = l.oakDungeonCoronetDoor(l.dungeonName(.mtCoronet))
        case .coronet: why = l.oakDungeonCoronet(l.dungeonName(.hallOfOrigin))
        case .hall: why = l.oakDungeonHall(least: l.oddsPercent(10, share: CompanionStore.oakHallWin))
        case .key(let waiting): why = l.oakDungeonKey(l.dungeonName(waiting), key: l.itemName(.legendaryKey))
        }
        let cost = l.dungeonCost(TokenFormatter.compact(dungeon.tokens))
        let wait = verdict == nil ? l.oakDungeonWaitEgg(cost: cost) : l.oakDungeonWait(name, cost: cost)
        return why + " " + l.oakDungeonOdds(percent(dungeon.win)) + " " + wait
    }

    private func gear(_ dungeon: OakDungeon) -> String? {
        func name(_ entryID: String) -> String {
            guard let entry = store.state.dex.first(where: { $0.id == entryID }) else { return "" }
            return store.dexEntryName(entry) + (entry.isShiny ? " ✨" : "")
        }
        let forms = dungeon.forms.map { planned in
            let species = store.state.dex.first { $0.id == planned.entryID }.map(store.dexEntryName) ?? ""
            return l.oakSetBattleForm(l.battleFormName(planned.form, species: species), on: name(planned.entryID))
        }
        let capsules = dungeon.capsules.map { capsule in
            let gift = l.oakGiveCapsule(l.itemName(capsule.kind), to: name(capsule.entryID))
            return capsule.stat.map { gift + " (" + l.statLabel(PokemonStatCalculator.order[$0]) + ")" } ?? gift
        }
        let parts = forms + capsules
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func stockDetail(_ budget: OakBudget) -> String {
        var detail = l.oakStockFor(budget.target, takes: Int((1 / budget.odds).rounded()), odds: percent(budget.odds))
        if budget.held > 0, !budget.takesTheLast { detail += " " + l.oakStockHeld(budget.held) }
        if budget.buyAhead > 0, budget.reserve > 0 { detail += " " + l.oakAlsoSetAside(TokenFormatter.compact(budget.reserve)) }
        if budget.waitsForNext { detail += " " + l.oakNotYet }
        return detail
    }

    /// Where the candies bought come from, then why they are given or kept.
    private func candiesDetail(buy: Int, give: Int, keep: Int) -> String? {
        var parts: [String] = []
        if buy > 0 { parts.append(budget?.egg == nil ? l.oakNoShopEggBeatsGraduation : l.oakCandiesFromTheRest) }
        let need = store.growthToGraduation
        if verdict == nil {
            parts.append(l.oakCandiesForTheHatch)
        } else if verdict == .spare, release?.sendsOff != false {
            parts.append(l.oakNoCandyBeforeRelease)
        } else if need > 0 {
            let xp = TokenFormatter.compact(store.rareCandyXP)
            if give > 0 {
                parts.append(l.oakCandiesGoIn(give, need: TokenFormatter.compact(need), xp: xp))
                if give * store.rareCandyXP > need { parts.append(l.oakLastCandyLosesLittle) }
                if keep > 0 { parts.append(l.oakKeepOtherCandies(keep)) }
            } else {
                parts.append(l.oakCandyWouldLose(need: TokenFormatter.compact(need), xp: xp, name: name))
            }
            if store.reinsCandyOnGraduation { parts.append(l.oakReinsCandy(l.itemName(.reinsOfUnity))) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Oak's verdict on the Pokémon raised, as a badge. Nothing for an egg.
@MainActor
private struct OakVerdictLabel: View {
    let store: CompanionStore
    let verdict: ActiveVerdict?

    var body: some View {
        // The badge alone: the bubble names the Pokémon already.
        if let verdict {
            Badge(store.l.oakVerdictLabel(verdict).uppercased(), tint: tint(verdict), style: .tinted)
                .lineLimit(1).fixedSize()
        }
    }

    private func tint(_ verdict: ActiveVerdict) -> BadgeTint {
        switch verdict {
        case .spare: return .secondary
        case .newForm, .formMystery: return .blue
        case .lineToComplete, .costume, .newCostume, .shinyToKeep, .keptForAchievement: return .green
        }
    }
}

@MainActor
private struct OakStepNumber: View {
    let number: Int

    init(_ number: Int) { self.number = number }

    var body: some View {
        Text("\(number)")
            .font(.caption2.weight(.bold)).monospacedDigit()
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(0.1)))
    }
}

/// A rounded bubble whose tail points left, to the one speaking.
struct SpeechBubble: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height),
                        cornerRadius: 10, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + tail, y: rect.minY + 12))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 18))
        path.addLine(to: CGPoint(x: rect.minX + tail, y: rect.minY + 24))
        path.closeSubpath()
        return path
    }
}
