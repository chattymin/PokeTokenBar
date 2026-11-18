import SwiftUI

/// 업적 화면 (진화의 돌, 체육관 배지, 전설의 유물): 도감 수집 조건을 달성하면 아이템을 무료로 획득.
/// 획득한 아이템은 가방(인벤토리)으로 들어간다: 돌은 소모품 5개, 배지와 유물은 상시 패시브 효과.
@MainActor
struct AchievementsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    /// What `BagHubView` leaves under its switch.
    let height: CGFloat

    enum AchievementCategory: Hashable, CaseIterable {
        case evolutionStones
        case gymBadges
        case legendaryArtifacts
        case forms

        var collectorGroup: CollectorGroup {
            switch self {
            case .evolutionStones: return .evolutionStones
            case .gymBadges: return .gymBadges
            case .legendaryArtifacts: return .legendaryArtifacts
            case .forms: return .forms
            }
        }
    }

    @State private var selectedCategory: AchievementCategory
    /// The page shown, nil until the first draw pins the opening one (`openingPage`).
    @State private var page: Int?
    /// The achievement opened from Home, lit for a moment.
    @State private var litItem: ItemKind?

    /// Opens on `category`, on the section of the achievement Home opened (`PopoverNavigation.achievementFocus`), or
    /// on the first section with a reward ready to claim (Stones when none is).
    init(store: CompanionStore, nav: PopoverNavigation, category: AchievementCategory? = nil, height: CGFloat = 520) {
        self.store = store
        self.nav = nav
        self.height = height
        _selectedCategory = State(initialValue: category ?? nav.achievementFocus.flatMap(Self.category(of:))
            ?? Self.firstCategoryWithRewards(store) ?? .evolutionStones)
    }

    /// The section an achievement is listed in.
    static func category(of kind: ItemKind) -> AchievementCategory? {
        AchievementCategory.allCases.first { $0.collectorGroup == kind.collectorGroup }
    }

    /// Rewards ready to claim in one section: unlocked and not claimed yet (each badge region counts).
    static func readyCount(_ category: AchievementCategory, _ store: CompanionStore) -> Int {
        store.achievementTally(in: category.collectorGroup).ready
    }

    /// Each section's rewards ready to claim, from one count of them all.
    static func readyCounts(_ tallies: [CollectorGroup: CompanionStore.AchievementTally]) -> [AchievementCategory: Int] {
        Dictionary(uniqueKeysWithValues: AchievementCategory.allCases.map { ($0, tallies[$0.collectorGroup]?.ready ?? 0) })
    }

    /// The first section, in tab order, with a reward ready to claim.
    static func firstCategoryWithRewards(_ store: CompanionStore) -> AchievementCategory? {
        let ready = readyCounts(store.achievementTallies().byGroup)
        return AchievementCategory.allCases.first { (ready[$0] ?? 0) > 0 }
    }

    /// Where the claim banner leads: the next section after `current` with a reward ready, wrapping around,
    /// so tapping it again walks through every section that has one.
    static func nextCategoryWithRewards(after current: AchievementCategory, _ store: CompanionStore) -> AchievementCategory? {
        nextCategoryWithRewards(after: current, ready: readyCounts(store.achievementTallies().byGroup))
    }

    static func nextCategoryWithRewards(after current: AchievementCategory,
                                        ready: [AchievementCategory: Int]) -> AchievementCategory? {
        let all = AchievementCategory.allCases
        let start = all.firstIndex(of: current) ?? 0
        return (1...all.count).lazy.map { all[(start + $0) % all.count] }.first { (ready[$0] ?? 0) > 0 }
    }

    /// Segment label: the section and the rewards waiting there ("Stones ●2"). Never claimed/total, which
    /// read as a number to claim; the section's progress has its own line under the picker.
    static func tabTitle(_ category: AchievementCategory, _ store: CompanionStore) -> String {
        tabTitle(category, ready: readyCount(category, store), store.l)
    }

    static func tabTitle(_ category: AchievementCategory, ready: Int, _ l: L) -> String {
        let title = l.collectorGroupTitle(category.collectorGroup)
        return ready > 0 ? "\(title) ●\(ready)" : title
    }

    // MARK: Pages (#183)

    /// Stone rows on a page.
    static let stonesPerPage = 4
    /// Cards on a page of the other sections, a tall card counting for two.
    static let cardsPerPage = 2

    /// A section cut into pages, in the section's order: the stones four rows a page, then the Excavation on a page of
    /// its own (its eggs and fossil lines fill one); the other sections two cards a page, a card as tall as two alone.
    static func pages(_ items: [ItemKind], _ category: AchievementCategory) -> [[ItemKind]] {
        var pages: [[ItemKind]] = []
        if category == .evolutionStones {
            let stones = items.filter { $0 != .excavation }
            pages = stride(from: 0, to: stones.count, by: stonesPerPage).map {
                Array(stones[$0..<min(stones.count, $0 + stonesPerPage)])
            }
            if items.contains(.excavation) { pages.append([.excavation]) }
        } else {
            var current: [ItemKind] = []
            var room = cardsPerPage
            for kind in items {
                let weight = isTall(kind) ? cardsPerPage : 1
                if weight > room, !current.isEmpty {
                    pages.append(current)
                    current = []
                    room = cardsPerPage
                }
                current.append(kind)
                room -= weight
            }
            if !current.isEmpty { pages.append(current) }
        }
        return pages.isEmpty ? [[]] : pages
    }

    /// A card that takes a page of its own: a medal listing more than four steps, an item asking for one of more than
    /// two goals.
    static func isTall(_ kind: ItemKind) -> Bool {
        if kind.isPlayMedal { return (kind.regionGoals?.count ?? 0) > 4 }
        // A badge's regions and the Legendary Egg's are goals too, drawn three to a row.
        if !kind.isRegional, case .species(let goals) = kind.unlock { return goals.count > 2 }
        return false
    }

    /// The page holding `kind`.
    static func page(of kind: ItemKind, in pages: [[ItemKind]]) -> Int? {
        pages.firstIndex { $0.contains(kind) }
    }

    /// A reward ready to claim on this achievement: one of its regions or steps, or the item itself.
    static func isReady(_ kind: ItemKind, _ store: CompanionStore) -> Bool {
        if kind.isRegional { return store.regionTiers(kind).contains(where: \.isReady) }
        return !store.isClaimed(kind) && store.isUnlocked(kind)
    }

    /// Where a section opens: on the achievement Home opened, else on the first page holding a reward ready, else on
    /// the first page.
    static func openingPage(_ pages: [[ItemKind]], focus: ItemKind?, store: CompanionStore) -> Int {
        if let focus, let page = page(of: focus, in: pages) { return page }
        return pages.firstIndex { $0.contains { isReady($0, store) } } ?? 0
    }

    var body: some View {
        let l = store.l
        // Counted once per draw, for the tabs, the banner and the progress line.
        let tallies = store.achievementTallies()
        let ready = Self.readyCounts(tallies.byGroup)
        let pages = Self.pages(store.achievementItems(in: selectedCategory.collectorGroup), selectedCategory)
        let current = min(max(0, page ?? Self.openingPage(pages, focus: nav.achievementFocus, store: store)),
                          pages.count - 1)
        let turn = Binding<Int>(get: { current }, set: { page = $0 })
        VStack(alignment: .leading, spacing: 6) {
            header(tallies.all, ready: ready)

            PillPicker(selection: $selectedCategory,
                       options: AchievementCategory.allCases.map { ($0, Self.tabTitle($0, ready: ready[$0] ?? 0, l)) })

            VStack(alignment: .leading, spacing: 2) {
                categoryProgress(tallies.byGroup[selectedCategory.collectorGroup] ?? .init(), l)
                if let intro = intro(selectedCategory, l) {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Scrolls only a page taller than the room left (the fossil lines open, a long language).
            PagedArea(page: turn, pageCount: pages.count) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pages[current], id: \.self) { kind in
                        AchievementCard(store: store, nav: nav, kind: kind)
                            .overlay {
                                RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
                                    .strokeBorder(Design.actionColor, lineWidth: 2)
                                    .opacity(litItem == kind ? 1 : 0)
                                    .allowsHitTesting(false)
                            }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .id("\(selectedCategory)-\(current)")

            PageControl(page: turn, pageCount: pages.count, l: l)
                .frame(maxWidth: .infinity)
        }
        .frame(height: height)
        .onChange(of: selectedCategory) { page = firstPageWithReward(selectedCategory) }
        .task {
            // The opening page is kept: claiming a reward must not send the page to the next one with a reward.
            if page == nil { page = current }
            // Home opened one achievement: its page, lit, then the light fades.
            guard let focus = nav.achievementFocus else { return }
            nav.achievementFocus = nil
            litItem = focus
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.6)) { litItem = nil }
        }
    }

    /// Where a section opens when picked: on its first page holding a reward ready, else on its first page.
    private func firstPageWithReward(_ category: AchievementCategory) -> Int {
        Self.openingPage(Self.pages(store.achievementItems(in: category.collectorGroup), category), focus: nil, store: store)
    }

    /// Said once above a section whose cards all say the same: the stones' eggs and goal, the badges' regions. The
    /// cards no longer repeat it.
    private func intro(_ category: AchievementCategory, _ l: L) -> String? {
        switch category {
        case .evolutionStones:
            let pokemon = ItemKind.leafStone.unlock.flatMap { unlock -> Int? in
                if case .species(let goals) = unlock { return goals.first?.needed }
                return nil
            } ?? 3
            return l.achievementsStonesIntro(eggs: ItemKind.leafStone.achievementRewardCount, pokemon: pokemon)
        case .gymBadges:
            return l.achievementsBadgesIntro(CollectorBonus.badgeRegionBonus * 100)
        case .legendaryArtifacts, .forms:
            return nil
        }
    }

    /// Progress of the section on screen ("1 of 10 completed"), and what counts: graduated Pokémon, not the one
    /// being raised nor those sent off, which stay in the Pokédex.
    private func categoryProgress(_ tally: CompanionStore.AchievementTally, _ l: L) -> some View {
        Text("\(l.achievementsProgress(tally.claimed, tally.total)) · \(l.achievementsGraduatedOnly)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// "Stones 1, Artifacts 2": the sections holding a reward, in tab order.
    private func readyBreakdown(_ ready: [AchievementCategory: Int], _ l: L) -> String {
        AchievementCategory.allCases.compactMap { category in
            let count = ready[category] ?? 0
            return count > 0 ? "\(l.collectorGroupTitle(category.collectorGroup)) \(count)" : nil
        }.joined(separator: ", ")
    }

    /// The rewards ready, where they wait and "Claim all". The whole count ("88/298") is on the Bag's switch above.
    @ViewBuilder
    private func header(_ all: CompanionStore.AchievementTally, ready: [AchievementCategory: Int]) -> some View {
        let l = store.l
        let unclaimed = all.ready
        if unclaimed > 0 {
            HStack(spacing: 8) {
                // Says where the rewards wait and takes you there: each tap opens the next section with one, on the
                // page holding it.
                Button {
                    if let next = Self.nextCategoryWithRewards(after: selectedCategory, ready: ready) {
                        selectedCategory = next
                        // Also when the section stays: its reward may wait on another page (the Excavation's).
                        page = firstPageWithReward(next)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.caption)
                        Text(l.readyToClaimSummary(unclaimed, readyBreakdown(ready, l)))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(l.claimAll) { store.claimAllAchievements() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// 개별 업적 카드: 아이콘, 이름, 효과 설명, 도감 달성 조건 및 [받기 / 획득함] 버튼.
@MainActor
private struct AchievementCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind

    private var isClaimed: Bool {
        store.isClaimed(kind)
    }

    private var canClaim: Bool {
        if kind.isRegional { return readyTiers > 0 }
        return !isClaimed && store.isUnlocked(kind)
    }

    private var readyTiers: Int { store.regionTiers(kind).filter(\.isReady).count }

    var body: some View {
        if kind.stoneType != nil {
            stoneRow(store.l)
        } else {
            card(store.l)
        }
    }

    /// The section's intro says it for every stone and every badge but the Plain Badge (Normal, which no type is
    /// weak to): their cards no longer repeat it.
    private var showsDescription: Bool { kind.badgeType == nil || kind == .plainBadge }

    private func card(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                    .grayscale(isClaimed || canClaim ? 0 : 1)
                    .opacity(isClaimed || canClaim ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind))
                            .font(.callout.weight(.semibold))

                        if let type = kind.badgeType ?? kind.stoneType {
                            Badge(l.typeName(type).uppercased(), tint: .type(type))
                        }
                        if kind.achievementRewardCount > 1 {
                            Text("×\(kind.achievementRewardCount)").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }

                        Spacer(minLength: 4)

                        statusAction(l)
                    }

                    if showsDescription {
                        Text(l.itemDescription(kind, rareCandyXP: store.rareCandyXP))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let type = kind.badgeType {
                        let maximum = Double(PokemonTypeData.badgeGenerations(for: type).count)
                        Text(l.badgeBonus(Double(store.claimedBadgeTierCount(type)) * CollectorBonus.badgeRegionBonus * 100,
                                          of: maximum * CollectorBonus.badgeRegionBonus * 100))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.claimedBadgeTierCount(type) > 0 ? Design.actionColor : .secondary)
                            .monospacedDigit()
                    }
                }
            }

            if kind == .excavation {
                ExcavationPanel(store: store)
            } else if let tier = kind.dungeonTier {
                DungeonMedalPanel(store: store, tier: tier)
            } else if kind == .battleFormsMedal {
                BattleFormsMedalPanel(store: store)
            } else if kind.isCostumeMedal {
                CostumeMedalPanel(store: store, kind: kind)
            } else if kind.isRegional {
                RegionGrid(store: store, kind: kind)
            } else {
                UnlockRequirementView(store: store, kind: kind, compact: isClaimed)
            }
        }
        .padding(12)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

    /// A stone on one row (#183): its icon, name, type and eggs, where it stands, then its Pokémon at 40 pt, in black
    /// until they graduated, and their count. What a stone gives is said once, above the stones.
    private func stoneRow(_ l: L) -> some View {
        let progress = store.unlockProgress(of: kind).first
        return HStack(alignment: .center, spacing: 8) {
            ItemIconView(kind: kind, size: 30)
                .grayscale(isClaimed || canClaim ? 0 : 1)
                .opacity(isClaimed || canClaim ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(l.itemName(kind))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    if let type = kind.stoneType {
                        Badge(l.typeName(type).uppercased(), tint: .type(type))
                    }
                    Text("×\(kind.achievementRewardCount)").font(.caption.weight(.bold))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                statusAction(l)
            }
            Spacer(minLength: 4)
            if let progress {
                HStack(spacing: 1) {
                    ForEach(progress.goal.species, id: \.self) { id in
                        // Still to graduate: its shape in black, as in the Pokédex.
                        SpriteView(speciesID: id, size: 40, isSilhouette: !progress.registered.contains(id), sameScale: true)
                            .speciesNameTooltip(id, language: store.language)
                    }
                }
                Text("\(progress.count)/\(progress.goal.needed)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(progress.isMet ? .primary : .secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

    @ViewBuilder
    private func statusAction(_ l: L) -> some View {
        if isClaimed {
            // Blue with its seal, never green alone (#183).
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text(l.claimed)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Design.actionColor)
        } else if canClaim {
            Button(readyTiers > 1 ? "\(l.claim) (\(readyTiers))" : l.claim) {
                store.claimAchievement(kind)
            }
            .buttonStyle(.pill(prominent: true))
        } else if kind == .excavation {
            // Its eggs say where it stands, under the description.
            EmptyView()
        } else if kind.isRegional {
            // A regional achievement is never locked as a whole: show how many of its regions are claimed.
            let tiers = store.regionTiers(kind)
            Label("\(tiers.filter(\.isDone).count)/\(tiers.count)", systemImage: "map")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Label(l.lockedLabel, systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// The regions of a regional achievement: claimed ones checked, complete ones ready to claim, the others with their
/// progress. Each region is one generation: a badge type's Pokémon from it, or all of its species.
@MainActor
private struct RegionGrid: View {
    let store: CompanionStore
    let kind: ItemKind

    var body: some View {
        grid(store.regionTiers(kind), store.l)
    }

    private func grid(_ tiers: [CompanionStore.RegionTier], _ l: L) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), alignment: .leading, spacing: 4) {
            ForEach(tiers, id: \.generation) { tier in
                HStack(spacing: 3) {
                    Text(l.regionName(generation: tier.generation))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    status(tier)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(background(tier)))
                .hoverTip("\(tier.progress.registered.count)/\(tier.progress.goal.needed)")
            }
        }
    }

    @ViewBuilder
    private func status(_ tier: CompanionStore.RegionTier) -> some View {
        if tier.isClaimed {
            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Design.actionColor)
        } else if tier.isReady {
            Image(systemName: "gift.fill").font(.caption2).foregroundStyle(Color.accentColor)
        } else {
            Text("\(tier.progress.count)/\(tier.progress.goal.needed)")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func background(_ tier: CompanionStore.RegionTier) -> Color {
        if tier.isClaimed { return Design.actionColor.opacity(0.14) }
        if tier.isReady { return Color.accentColor.opacity(0.22) }
        return .secondary.opacity(0.08)
    }
}

/// The digs told as a row of eggs, as the Pokémon a goal asks for: 15, one per fossil line, in the digs' order, each
/// state its own badge. The fossil lines fold away under it: they are what the eggs give, not what the digs ask for,
/// and shown first they read as a goal.
@MainActor
private struct ExcavationPanel: View {
    let store: CompanionStore
    @State private var showsLines = false

    enum Egg: CaseIterable { case opened, inBag, ready, next, toEarn }

    /// The eggs in the digs' order: claimed (opened, then in the Bag), ready, the next one, those to earn. A dig with
    /// nothing to claim (its line had before the digs) reads as opened: there is nothing left to do with it.
    static func eggs(_ progress: CompanionStore.ExcavationProgress) -> [Egg] {
        var eggs = Array(repeating: Egg.opened, count: progress.opened + progress.notClaimable)
        eggs += Array(repeating: .inBag, count: progress.inBag) + Array(repeating: .ready, count: progress.ready)
        if progress.toEarn > 0 {
            eggs += (progress.towardNext != nil ? [.next] : [.toEarn])
            eggs += Array(repeating: .toEarn, count: progress.toEarn - 1)
        }
        return eggs
    }

    var body: some View {
        let l = store.l
        let progress = store.excavationProgress
        let eggs = Self.eggs(progress)
        let toward = progress.towardNext ?? 0
        // Out of the 15 digs, as every regional card counts its regions: those claimed, a dig with nothing to claim
        // among them.
        let claimed = eggs.count { $0 == .opened || $0 == .inBag }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7), alignment: .leading,
                          spacing: 4) {
                    ForEach(Array(eggs.enumerated()), id: \.offset) { _, egg in
                        let lit = egg == .opened || egg == .inBag || egg == .ready
                        eggSprite(30)
                            .grayscale(lit ? 0 : 1)
                            .opacity(lit ? (egg == .opened ? 0.55 : 1) : 0.35)
                            .overlay(alignment: .bottomTrailing) { badge(egg) }
                            .hoverTip(egg == .next ? l.excavationNextEgg(toward, of: FossilDig.rockPerDig) : name(egg, l))
                    }
                }
                Spacer(minLength: 4)
                Text("\(claimed)/\(eggs.count)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            }
            if progress.towardNext != nil {
                HStack(spacing: 6) {
                    Text(l.excavationNextEgg(toward, of: FossilDig.rockPerDig)).font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: Double(toward), total: Double(FossilDig.rockPerDig)).controlSize(.small)
                }
            }
            legend(eggs, l)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsLines.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(l.excavationLines(progress.linesGraduated, of: FossilDig.lines.count))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showsLines ? 90 : 0))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsLines { lines }
        }
    }

    private func name(_ egg: Egg, _ l: L) -> String {
        switch egg {
        case .opened: l.excavationEggOpened
        case .inBag: l.excavationEggInBag
        case .ready: l.excavationEggReady
        case .next, .toEarn: l.excavationEggToEarn
        }
    }

    private func eggSprite(_ size: CGFloat) -> some View {
        SpriteView(speciesID: nil, size: size, egg: .fossil)
    }

    @ViewBuilder
    private func badge(_ egg: Egg) -> some View {
        switch egg {
        case .opened: Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Design.actionColor)
        case .inBag: Image(systemName: "bag.circle.fill").font(.system(size: 11)).foregroundStyle(Color.readableOrange)
        case .ready: Image(systemName: "gift.circle.fill").font(.system(size: 11)).foregroundStyle(Color.accentColor)
        case .next, .toEarn: EmptyView()
        }
    }

    /// The states the eggs show, named once.
    private func legend(_ eggs: [Egg], _ l: L) -> some View {
        let named = Egg.allCases.filter { kind in kind != .next && eggs.contains { $0 == kind || ($0 == .next && kind == .toEarn) } }
        return WrappingHStack(spacing: 10, lineSpacing: 4) {
            ForEach(named, id: \.self) { egg in
                HStack(spacing: 3) {
                    badge(egg)
                    if egg == .toEarn {
                        eggSprite(12).grayscale(1).opacity(0.35)
                    }
                    Text(name(egg, l)).font(.caption2).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
    }

    /// The fossil lines, those graduated in color, the others in black as in the Pokédex.
    private var lines: some View {
        let graduated = store.graduatedSpeciesIDs
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
            ForEach(FossilDig.lines, id: \.self) { line in
                let owned = graduated.contains(line)
                SpriteView(speciesID: line, size: 26, isSilhouette: !owned, sameScale: true)
                    .frame(width: 28, height: 28)
                    .speciesNameTooltip(line, language: store.language)
            }
        }
    }
}
