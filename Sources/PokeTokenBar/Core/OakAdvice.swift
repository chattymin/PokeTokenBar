import Foundation

/// What Prof. Oak makes of the Pokémon being raised, for the Form Pokédex.
enum ActiveVerdict: Equatable, Sendable {
    /// Species of its line no graduated Pokémon holds, in any form.
    case lineToComplete(newSpecies: ClosedRange<Int>)
    /// Every species of its line graduated, not all in its form: the first it brings in it.
    case newForm(speciesID: Int)
    /// A Pikachu still ahead in its line brings a costume missing (`ActiveNews.costume`).
    case costume
    /// Its Pokémon GO costume, at a stage it reached or will reach, is missing from the collection (`ActiveNews.newCostume`).
    case newCostume
    /// Nothing new but its first shiny in this form (`ActiveNews.firstShiny`).
    case shinyToKeep
    /// A Spare whose graduation unlocks an achievement that counts copies.
    case keptForAchievement(ItemKind)
    /// Its form is still hidden and decides what it brings: wait for the stage that shows it.
    case formMystery(FormMystery)
    /// It brings nothing new (`CompanionStore.ActiveNews.isDuplicate`).
    case spare
}

/// What Prof. Oak does with a Spare: the egg it goes for, with the odds that what hatches brings something new
/// (`newOdds`), or its graduation.
enum OakRelease: Equatable, Sendable {
    /// An egg the Bag holds.
    case bag(ItemKind, odds: Double)
    /// An event egg waiting to be claimed, then used from the Bag.
    case claim(EventEgg, odds: Double)
    /// The most selective Shop egg that beats the Pokémon Egg, bought now then used from the Bag.
    case buy(Rarity?, odds: Double)
    /// That egg once the balance holds its price, `short` tokens away: the Spare is raised meanwhile.
    case wait(Rarity?, odds: Double, short: Int)
    /// The Spare raised to graduation, `left` growth away.
    case finish(left: Int, why: OakFinish)

    /// The egg the Spare goes for now, nil while it is raised.
    var egg: ItemKind? {
        switch self {
        case .bag(let kind, _): return kind
        case .claim(let event, _): return event.item
        case .buy(let tier, _): return ItemKind(shopEgg: tier)
        case .wait, .finish: return nil
        }
    }

    /// Whether the Spare goes now, leaving its Rare Candies to the one that hatches.
    var sendsOffNow: Bool { egg != nil }

    /// Whether the Spare is sent off, now or once its egg is affordable, rather than raised to graduation.
    var sendsOff: Bool {
        if case .finish = self { return false }
        return true
    }
}

/// Why Prof. Oak leaves a Spare to finish rather than send it off.
enum OakFinish: Equatable, Sendable {
    /// No egg brings something more often than the Pokémon Egg its graduation gives.
    case noBetterEgg
    /// Sent off, it would lose more growth than it has left to graduate.
    case tooFarAlong
    /// It would be too far along by the time the balance holds its egg.
    case outgrowsTheWait
}

/// What Prof. Oak puts the balance into once the Spare's egg is paid: a stock of the egg to buy, the rest in Rare Candies.
struct OakBudget: Equatable, Sendable {
    /// The most selective Shop egg that beats the Pokémon Egg a graduation gives, nil when none does.
    let egg: ItemKind?
    /// Its odds of something new.
    let odds: Double
    /// The eggs worth holding (`stockTarget`).
    let target: Int
    /// The Bag's eggs at least as likely to bring something, once the Spare is sent off.
    let held: Int
    /// Bought now toward the target.
    let buyAhead: Int
    /// Whether none is bought ahead because what comes next may take the last new Pokémon it brings.
    let waitsForNext: Bool
    /// The tokens kept for the rest of the target.
    let reserve: Int
    /// The Rare Candies the rest of the balance buys.
    let candies: Int
    var takesTheLast = false

    /// An egg that brings something new one time in 1/p takes 1/p eggs on average: three at most.
    static func stockTarget(odds: Double) -> Int { min(3, Int((1 / odds).rounded())) }
}

/// One of Prof. Oak's steps, in order: a line of his card, explained on its details page.
enum OakStep: Equatable, Sendable {
    /// Keep raising the Pokémon: it brings something new.
    case raise
    case release(OakRelease)
    /// Eggs to buy ahead, or to set the balance aside for.
    case stock(OakBudget)
    /// Rare Candies to buy, then to give the Pokémon raised or to keep, the Bag's included.
    case candies(buy: Int, give: Int, keep: Int)
    case dungeon(OakDungeon)
}

extension CompanionStore {
    /// Nil for an egg.
    var activeVerdict: ActiveVerdict? {
        guard let news = activeNews else { return nil }
        if let mystery = news.mystery { return .formMystery(mystery) }
        let unseen = Set(news.newSpecies.filter { !graduatedSpeciesIDs.contains($0) })
        if !unseen.isEmpty {
            let counts = activeWays.map { unseen.intersection($0).count }
            return .lineToComplete(newSpecies: (counts.min() ?? 0)...(counts.max() ?? 0))
        }
        if let first = news.newSpecies.first { return .newForm(speciesID: first) }
        if news.costume { return .costume }
        if news.newCostume { return .newCostume }
        if news.firstShiny { return .shinyToKeep }
        if let achievement = copyAchievement { return .keptForAchievement(achievement) }
        return .spare
    }

    /// The Rare Candies to give the Pokémon being raised, those the balance buys included: as many as its growth to
    /// graduation takes whole, a last one losing a tenth of its XP at most, the rest kept for the next one.
    /// `maxRareCandyUseCount` rounds up, and graduation loses the XP over. None to a Spare sent off, now or once its egg
    /// is affordable: it would lose them with its growth.
    var candiesToGive: Int {
        let release = oakRelease
        return candiesToGive(after: release, budget: oakBudget(after: release))
    }

    func candiesToGive(after release: OakRelease?, budget: OakBudget?) -> Int {
        guard let verdict = activeVerdict else { return 0 }
        if verdict == .spare, release?.sendsOff != false { return 0 }
        let need = growthToGraduation
        let xp = rareCandyXP
        return min(rareCandyCount + (budget?.candies ?? 0), need / xp + (need % xp * 10 >= xp * 9 ? 1 : 0))
    }

    var oakSteps: [OakStep] {
        let release = oakRelease
        return oakSteps(after: release, budget: oakBudget(after: release))
    }

    /// None for a Spare before the index is loaded: what becomes of it is not known yet.
    func oakSteps(after release: OakRelease?, budget: OakBudget?) -> [OakStep] {
        let verdict = activeVerdict
        if verdict == .spare, release == nil { return [] }
        var steps: [OakStep] = []
        if let verdict, verdict != .spare { steps.append(.raise) }
        if let release { steps.append(.release(release)) }
        if let budget, budget.egg != nil, budget.buyAhead > 0 || budget.reserve > 0 || budget.takesTheLast {
            steps.append(.stock(budget))
        }
        let buy = budget?.candies ?? 0
        let held = rareCandyCount + buy
        var waitsForReveal = false
        if case .formMystery? = verdict { waitsForReveal = true }
        if held > 0, !waitsForReveal {
            let give = candiesToGive(after: release, budget: budget)
            steps.append(.candies(buy: buy, give: give, keep: held - give))
        }
        if let dungeon = oakDungeon { steps.append(.dungeon(dungeon)) }
        return steps
    }

    /// What to send the Pokémon raised off for: a Spare only, nil for any other and before the index is loaded. Only
    /// for an egg that brings something more often than the Pokémon Egg its graduation gives, and while it has grown
    /// less than it has left to grow, what the Old Amber carries to that egg's draws aside. The Bag's egg with the best odds, an event egg to
    /// claim included, the first in the Bag on a tie; else the most selective Shop egg, bought or awaited.
    var oakRelease: OakRelease? {
        guard activeVerdict == .spare, let index = hatchIndex, let growth = spareGrowth else { return nil }
        let left = growth.total - growth.grown
        func sendsOff(for egg: ItemKind, grown: Int) -> Bool {
            growth.sendsOffAt(grown) { amberCarry(of: $0, to: egg, index: index) }
        }
        let news = hatchNews
        let claimable = Set(eventEggs.map(\.egg))
        var best: OakRelease?
        var bestOdds = newOdds(.pokemonEgg, index: index, news: news) ?? 0
        for kind in ItemKind.allCases where !kind.isRetired {
            let held = canSendOff(for: kind)
            let event = EventEgg(item: kind)
            guard held || event.map(claimable.contains) == true,
                  let odds = newOdds(kind, index: index, news: news), odds > bestOdds else { continue }
            if !held, let event { best = .claim(event, odds: odds) } else { best = .bag(kind, odds: odds) }
            bestOdds = odds
        }
        if let best, let egg = best.egg {
            return sendsOff(for: egg, grown: growth.grown) ? best : .finish(left: left, why: .tooFarAlong)
        }
        guard let (tier, odds) = shopEgg(index: index, news: news), let egg = ItemKind(shopEgg: tier) else {
            return .finish(left: left, why: .noBetterEgg)
        }
        guard sendsOff(for: egg, grown: growth.grown) else { return .finish(left: left, why: .tooFarAlong) }
        let short = price(of: .egg(tier)) - availableTokens
        guard short > 0 else { return .buy(tier, odds: odds) }
        return sendsOff(for: egg, grown: growth.grown + Int(Double(short) * growth.perToken))
            ? .wait(tier, odds: odds, short: short) : .finish(left: left, why: .outgrowsTheWait)
    }

    /// The Spare's growth over its whole line, its stages' thresholds as `stageThreshold` sets them.
    private struct SpareGrowth {
        let thresholds: [Int]
        let grown: Int
        /// The growth a token brings (`applyUsage`).
        let perToken: Double

        var total: Int { thresholds.reduce(0, +) }

        /// Whether sending it off once grown so far loses less than it has left to grow, what `carried` takes of its
        /// stage's growth going to the one that hatches.
        func sendsOffAt(_ grown: Int, carried: (Int) -> Int) -> Bool {
            var atStage = grown
            for threshold in thresholds.dropLast() {
                guard atStage >= threshold else { break }
                atStage -= threshold
            }
            return grown - carried(atStage) < total - grown
        }
    }

    private var spareGrowth: SpareGrowth? {
        guard var mon = state.active else { return nil }
        let used = mon.usedAtStage
        let stage = mon.stageIndex
        let thresholds = (0..<max(1, mon.totalForms)).map { index in
            mon.stageIndex = index
            return stageThreshold(for: mon)
        }
        mon.stageIndex = stage
        let thresholdSpeed = 1 + Self.bonusSum(thresholdGrowthFactors(for: mon))
        return SpareGrowth(thresholds: thresholds, grown: thresholds.prefix(stage).reduce(used, +),
                           // A team in a dungeon takes the tokens: the Pokémon raised does not grow meanwhile (Q1).
                           perToken: growthPaused ? 0 : (thresholdSpeed + Self.bonusSum(tokenGrowthFactors)) / thresholdSpeed)
    }

    /// What the Old Amber carries on average to what `egg` hatches, `stage` grown at the Spare's stage: half of it, short
    /// of each draw's first evolution (`hatch`), weighed like the odds. None without the Old Amber.
    private func amberCarry(of stage: Int, to egg: ItemKind, index: [BaseSpecies]) -> Int {
        guard itemCount(.oldAmber) > 0, let hatches = hatches(egg, index: index) else { return 0 }
        let half = max(0, stage) / 100 * CollectorBonus.oldAmberKeptPercent
        let total = hatches.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        return Int(hatches.reduce(0) { $0 + $1.weight * Double(min(half, max(0, firstStage(of: $1) - 1))) } / total)
    }

    /// The first stage of what a draw hatches, its longest branch counted, its repeat boost included.
    private func firstStage(of hatch: Hatch) -> Int {
        stageThreshold(for: MonState(baseID: hatch.id, pathIDs: [hatch.id], stageIndex: 0, usedAtStage: 0,
                                     rarity: hatch.rarity, totalForms: Self.stages(from: hatch.id, form: hatch.form),
                                     hasGrowthBoost: state.hasCollectedFinal(forBaseID: hatch.id, form: hatch.form),
                                     form: hatch.form))
    }

    private static func stages(from id: Int, form: PokemonForm?) -> Int {
        1 + (PokemonEvolutionData.children(of: id, form: form).map { stages(from: $0, form: form) }.max() ?? 0)
    }

    var oakBudget: OakBudget? { oakBudget(after: oakRelease) }

    /// The balance once `release`'s egg is paid: eggs bought ahead up to the stock's target, the Bag's as good counted,
    /// only of an egg that still brings something whatever hatches next; their price kept aside short of that; the rest
    /// in Rare Candies. Nothing while the Spare's egg is awaited. Nil before the index is loaded.
    func oakBudget(after release: OakRelease?) -> OakBudget? {
        guard let index = hatchIndex, let candy = price(of: .rareCandy) else { return nil }
        let news = hatchNews
        var wallet = availableTokens
        switch release {
        case .buy(let tier, _)?, .wait(let tier, _, _)?: wallet -= price(of: .egg(tier))
        default: break
        }
        guard let (tier, odds) = shopEgg(index: index, news: news), let kind = ItemKind(shopEgg: tier) else {
            return OakBudget(egg: nil, odds: 0, target: 0, held: 0, buyAhead: 0, waitsForNext: false, reserve: 0,
                             candies: max(0, wallet) / candy)
        }
        let target = OakBudget.stockTarget(odds: odds)
        let held = eggsHeld(atLeast: odds, after: release, index: index, news: news)
        let need = max(0, target - held)
        let eggPrice = price(of: .egg(tier))
        let waits = need > 0 && !staysWorthBuying(kind, after: release, index: index, news: news)
        var awaitsEgg = false
        if case .wait? = release { awaitsEgg = true }
        let buyAhead = waits || awaitsEgg ? 0 : min(need, max(0, wallet) / eggPrice)
        let reserve = awaitsEgg ? 0 : (need - buyAhead) * eggPrice
        return OakBudget(egg: kind, odds: odds, target: target, held: held, buyAhead: buyAhead, waitsForNext: waits,
                         reserve: reserve, candies: max(0, wallet - buyAhead * eggPrice - reserve) / candy,
                         takesTheLast: need == 0 && held == 1 && release?.egg == nil)
    }

    func oakWaitsForTheTeam(_ step: OakStep) -> Bool {
        guard expedition != nil else { return false }
        switch step {
        case .release(let release): return release.sendsOffNow
        case .candies(_, let give, _): return give > 0
        case .raise, .stock, .dungeon: return false
        }
    }

    /// The Shiny Charm brings no species nor form, but first shinies more often: proposed until bought, or until the
    /// Glimmering Charm makes every hatch shiny.
    var proposesShinyCharm: Bool { !ownsShinyCharm && !ownsGlimmeringCharm }

    /// The odds that what an egg of the Bag hatches, with the Pokémon raised sent off now, brings the Form Pokédex
    /// something as `activeNews` would judge it, over the egg's lines and the forms they roll: a species or a form new,
    /// else a first shiny as often as a hatch shines. Nil for an item that is no egg, or before the index is loaded.
    func newOdds(item: ItemKind) -> Double? {
        hatchIndex.flatMap { newOdds(item, index: $0, news: hatchNews) }
    }

    /// The time the balance takes to gain `tokens` at the player's pace, nil while it is unknown (`timeToNext`).
    func timeToEarn(_ tokens: Int) -> TimeInterval? {
        guard let pace = usagePacePerDay, pace > 0 else { return nil }
        return Double(tokens) / pace * 86_400
    }

    /// Whether graduating the Pokémon being raised adds a Rare Candy: the Reins of Unity's, but not for a Common.
    var reinsCandyOnGraduation: Bool { ownsReinsOfUnity && state.active.map { $0.rarity != .common } == true }

    /// Whether this item of the Bag sends the Pokémon raised off for an egg, now or once the team exploring is back.
    private func canSendOff(for kind: ItemKind) -> Bool {
        switch kind {
        case .fossilEgg: return canUseFossilEgg(onReturn: true)
        case .typeNullEgg: return canUseTypeNullEgg(onReturn: true)
        case .legendaryEgg: return canUseLegendaryEgg(onReturn: true)
        case .birthdayEgg: return canUseBirthdayEgg(onReturn: true)
        default:
            return EventEgg(item: kind).map { canUseEventEgg($0, onReturn: true) }
                ?? (canUseStone(kind, onReturn: true) || canUseBagEgg(kind, onReturn: true))
        }
    }

    /// The most selective Shop egg that brings something more often than the Pokémon Egg a graduation gives, with its
    /// odds.
    private func shopEgg(index: [BaseSpecies], news: HatchNews) -> (tier: Rarity?, odds: Double)? {
        let plain = newOdds(.pokemonEgg, index: index, news: news) ?? 0
        for tier in FreshEgg.shopTiers.reversed() {
            guard let kind = ItemKind(shopEgg: tier), let odds = newOdds(kind, index: index, news: news), odds > plain
            else { continue }
            return (tier, odds)
        }
        return nil
    }

    /// The Bag's eggs as likely as `odds` to bring something, once the Spare is sent off: without the one it goes for,
    /// with the Fossil Egg its Pokémon gives back (`replaceActiveWithEgg`).
    private func eggsHeld(atLeast odds: Double, after release: OakRelease?, index: [BaseSpecies], news: HatchNews) -> Int {
        ItemKind.allCases.filter { !$0.isRetired }.reduce(0) { sum, kind in
            var count = itemCount(kind)
            if case .bag(kind, _)? = release { count -= 1 }
            if kind == .fossilEgg, release?.sendsOffNow == true, isRaisingFossilEggPokemon { count += 1 }
            guard count > 0, let eggOdds = newOdds(kind, index: index, news: news), eggOdds >= odds else { return sum }
            return sum + count
        }
    }

    /// Whether an egg still brings something new whatever hatches next: from the egg the Spare goes for or the one
    /// incubating, or the Pokémon raised once graduated.
    private func staysWorthBuying(_ kind: ItemKind, after release: OakRelease?, index: [BaseSpecies],
                                  news: HatchNews) -> Bool {
        var fresh = newHatches(hatches(kind, index: index) ?? [], news: news)
        var next: [Hatch] = []
        if let egg = release?.egg {
            next = hatches(egg, index: index) ?? []
        } else if let raised = state.active {
            fresh.remove(DexSpeciesKey(speciesID: raised.baseID, form: raised.form))
        } else if state.eggFromTypeNullEgg {
            next = hatches(.typeNullEgg, index: index) ?? []
        } else if state.eggFromBirthdayEgg {
            next = hatches(.birthdayEgg, index: index) ?? []
        } else if state.eggFromFossilEgg {
            next = hatches(.fossilEgg, index: index) ?? []
        } else if let egg = state.eggFromDungeon {
            next = [Hatch(id: egg.baseID, form: egg.form, weight: 1, rarity: SpeciesInfo.lineRarity(of: egg.baseID),
                          alwaysShiny: egg.isShiny)]
        } else if let egg = state.eggFromCostume {
            next = hatchDraw.outcomes(.costume(code: egg.code, speciesID: egg.speciesID), index: index)
        } else {
            next = hatches(incubatingEgg, index: index)
        }
        let nextFresh = newHatches(next, news: news)
        return fresh.count > 1 || fresh.contains { !nextFresh.contains($0) }
    }

    /// A line hatched in a form, weighed among the egg's other draws.
    private typealias Hatch = HatchDraw.Outcome

    /// What a hatch brings the Form Pokédex: a species or a form new, else a first shiny when it shines.
    private struct HatchNews {
        let new: (_ baseID: Int, _ form: PokemonForm?) -> Bool
        let firstShiny: (_ baseID: Int, _ form: PokemonForm?) -> Bool
        /// The odds a hatch shines.
        let shiny: Double

        func odds(_ hatch: Hatch) -> Double {
            new(hatch.id, hatch.form) ? 1 : firstShiny(hatch.id, hatch.form) ? (hatch.alwaysShiny ? 1 : shiny) : 0
        }
    }

    private var hatchNews: HatchNews {
        HatchNews(new: hatchBringsNew(), firstShiny: hatchBringsFirstShiny(),
                  shiny: ownsGlimmeringCharm ? 1 : 1 / Double(shinyDenominator))
    }

    /// `index` is the hatch index and `news` the state's (`hatchNews`): the odds are kept until either changes.
    private func newOdds(_ item: ItemKind, index: [BaseSpecies], news: HatchNews) -> Double? {
        if let odds = oakOddsCache[item] { return odds }
        let odds = hatches(item, index: index).map { hatches -> Double in
            let total = hatches.reduce(0) { $0 + $1.weight }
            return total > 0 ? hatches.reduce(0) { $0 + $1.weight * news.odds($1) } / total : 0
        }
        oakOddsCache.updateValue(odds, forKey: item)
        return odds
    }

    /// The lines and forms that bring a species or a form new, else those that may bring a first shiny.
    private func newHatches(_ hatches: [Hatch], news: HatchNews) -> Set<DexSpeciesKey> {
        let drawn = hatches.filter { $0.weight > 0 }
        let fresh = drawn.filter { news.new($0.id, $0.form) }
        let keys = fresh.isEmpty ? drawn.filter { news.firstShiny($0.id, $0.form) } : fresh
        return Set(keys.map { DexSpeciesKey(speciesID: $0.id, form: $0.form) })
    }

    /// The draws each egg makes (`HatchDraw.outcomes`); nil for an item that is no egg.
    private func hatches(_ item: ItemKind, index: [BaseSpecies]) -> [Hatch]? {
        HatchEgg(item: item).map { hatchDraw.outcomes($0, index: index) }
    }

    private func hatches(_ egg: EggSpec, index: [BaseSpecies]) -> [Hatch] {
        hatchDraw.outcomes(egg, index: index)
    }

    /// The one achievement that counts copies: a legendary graduated a second time unlocks the Azure Flute. A Spare
    /// already has a graduated copy of each final it can reach. Every other achievement counts species or forms.
    private var copyAchievement: ItemKind? {
        guard state.active?.rarity == .legendary, !isUnlocked(.legendCharm) else { return nil }
        return .legendCharm
    }
}
