import Foundation
import Observation
import UserNotifications

/// 게임 상태의 출처. 설치 이후 토큰 사용량으로 포켓몬을 진화시키고, 최종체 + 추가 임계 도달 시
/// 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은 PokeProviding 으로 런타임 주입.
@MainActor
@Observable
final class CompanionStore {
    private(set) var state = CompanionState() {
        didSet {
            dexSpeciesCache = [:]; goalsBySpecies = nil; oakOddsCache = [:]; formSuspenseCache = nil; dungeonCandidatesCache = nil
            graduatedFormsCache = nil; achievementTalliesCache = nil
        }
    }
    private(set) var displayState: CompanionStateKind = .egg
    private(set) var currentLine: EvoLine? { didSet { dexSpeciesCache = [:] } }
    /// `collectedDexSpecies` by `groupForms`, until the state or the line changes: a form species' page read it some
    /// 25 times per draw (`formSpecies`, `dexCover`, the picker), each folding and sorting the whole Pokédex.
    @ObservationIgnored private var dexSpeciesCache: [Bool: [DexSpecies]] = [:]
    /// The forms the Pokédex holds graduated, until the state changes: each of the achievements' form goals read the
    /// whole Pokédex again, and the tab bar's count asked them at each opening of the popover (#183, the owner's "ça
    /// lag un peu quand on l'affiche").
    @ObservationIgnored private var graduatedFormsCache: GraduatedForms?
    /// `achievementTallies()`, until the state changes.
    @ObservationIgnored private var achievementTalliesCache: (all: AchievementTally, byGroup: [CollectorGroup: AchievementTally])?
    /// `goals(counting:)` for every species, until the state changes.
    @ObservationIgnored private var goalsBySpecies: [Int: [ActiveGoal]]?
    /// `dungeonCandidates`, made once per state: the team screen asked it for every row and every member of each
    /// render, 3.2 s a render on a Pokédex of 742 (a player's lag on hovering a Pokémon, 2026-11-06).
    @ObservationIgnored var dungeonCandidatesCache: [DexEntry]?
    /// How many times `dungeonCandidates` was made: the tests check its cache with it.
    @ObservationIgnored var dungeonCandidatesBuilds = 0
    /// `formSuspense`, made once per state: every badge and line of a render asks it, for up to 63 forms.
    @ObservationIgnored private var formSuspenseCache: FormSuspense??
    /// Each egg's odds of something new for Prof. Oak (`newOdds`), until the state or the hatch index changes: his card
    /// reads them several times a draw, each over the egg's whole pool.
    @ObservationIgnored var oakOddsCache: [ItemKind: Double?] = [:]
    @ObservationIgnored var oakDungeonCache: [DungeonID: OakDungeonOdds] = [:]
    @ObservationIgnored var oakWinOdds: (DungeonTeamBuilder.ReachEstimate) -> Double = { $0.run().win } {
        didSet {
            oakDungeonCache = [:]
            oakSearches = [:]
        }
    }
    @ObservationIgnored var oakComposeSearch: @Sendable (DungeonTeamBuilder.ComposeChoice) -> [String] = { $0.run() } {
        didSet { oakSearches = [:] }
    }
    var oakSearches: [DungeonID: OakDungeonOdds] = [:]
    @ObservationIgnored var oakSearchTasks: [DungeonID: (inputs: OakDungeonOdds.Inputs, task: Task<Void, Never>)] = [:]
    /// How many times the Pokédex was folded: the tests check the cache with it.
    @ObservationIgnored private(set) var dexSpeciesFolds = 0
    /// Writes of the save file, for the tests of what writes it.
    @ObservationIgnored private(set) var savesWritten = 0
    /// A usage update writes the save at most this often (0: at once). Live usage updates the companion every few
    /// seconds while tokens flow, and each write is the whole state (about 800 KB): the numbers wait in memory, and any
    /// other change writes them along at once. The app sets `appUsageSaveGap`; tests keep the writes immediate.
    @ObservationIgnored var usageSaveGap: TimeInterval = 0
    static let appUsageSaveGap: TimeInterval = 15
    @ObservationIgnored private var lastSaveWrite: Date?
    @ObservationIgnored private var usageSaveTask: Task<Void, Never>?
    private(set) var representativeSubject = RepresentativeSubject(speciesID: nil, isShiny: false)
    private(set) var isHatching = false
    private var isRevealingDitto = false   // 메타몽 리빌 비동기 중복 방지(isHatching 자매)
    private(set) var justEvolvedTo: String?     // 이름(연출/문구)
    private var justRevealedForm: String?
    private(set) var justGraduated: String?
    private var eventUntil: Date?

    /// 부화/진화 연출 트리거 — seq 증가로 UI 가 감지, 팝오버가 닫혀 있었어도 다음 오픈에 1회 재생.
    enum Celebration: Equatable { case hatch(shiny: Bool), evolve, dittoReveal(shiny: Bool) }
    private(set) var celebration: Celebration?
    private(set) var celebrationSeq = 0
    private func fireCelebration(_ c: Celebration) { celebration = c; celebrationSeq += 1 }
    /// 연출 재생 후 UI 가 호출(1회성 보장).
    func consumeCelebration() { celebration = nil }

    /// 사탕 사용 시 "+XP" 순간 표시 — 진화 없이 부분 진행일 때도 피드백. seq 증가로 CompanionHeader 감지.
    private(set) var candyFeedbackSeq = 0
    private(set) var candyFeedbackAmount = 0
    /// The candies of that use the Shock Drive recharged, shown beside the "+XP".
    private(set) var candyFeedbackRecharged = 0
    /// "+XP" 표시 1회성 보장 — CompanionHeader 가 재생 후 호출한다. 소비하지 않으면 다른 탭에 갔다
    /// 홈으로 재진입할 때(CompanionHeader 재마운트) @State 가 초기화돼 같은 값이 다시 떠오른다(회귀).
    func consumeCandyFeedback() { candyFeedbackAmount = 0 }


    private let provider: any PokeProviding
    private var dexNameRequests: [Int: Task<EvoLine, Error>] = [:]
    private let detailProvider: (any PokemonDetailProviding)?
    private let clock: () -> Date
    private let fileURL: URL
    private var rng: any RandomNumberGenerator
    private let dittoDisguiseRollingEnabled: Bool
    private(set) var pokemonDetailsByID: [Int: PokemonDetails] = [:]
    private(set) var loadingPokemonDetailIDs: Set<Int> = []
    private(set) var failedPokemonDetailIDs: Set<Int> = []
    private let defaults: UserDefaults
    /// The dungeons' in-flight mark (`CompanionStore+Dungeons`).
    var defaultsForDungeons: UserDefaults { defaults }
    var oakAdviceEnabled: Bool {
        didSet { defaults.set(oakAdviceEnabled, forKey: "oakAdviceEnabled") }
    }
    /// The day (`merchantDay`) the player last looked at the travelling merchant: the Shop's arrow wears a dot until then
    /// (2026-11-09). A preference of this Mac, as Prof. Oak's switch.
    var merchantSeenDay: String? {
        didSet { defaults.set(merchantSeenDay, forKey: "merchantSeenDay") }
    }
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    private var activeGeneration = 0
    private var lastAutoSnapshotDate: Date?
    private(set) var availableSnapshots: [SaveSnapshot] = []

    // MARK: 난이도 배율 (설정 — UserDefaults)
    //
    // 세이브(CompanionState)가 아니라 UserDefaults 에 둔다. 이건 진행 상황이 아니라 취향 설정이고
    // (설정창의 다른 슬라이더와 같은 자리), 세이브에 넣으면 남의 세이브를 불러올 때 내 난이도가 조용히
    // 바뀌며 SaveTransfer 의 관대 디코딩·검증까지 새 수치 필드를 떠안는다.

    /// 성장 배율 — 알 부화 임계 + 진화/졸업 임계에 곱한다. 낮을수록 빨리 자란다.
    /// The candy's XP (`RareCandy.xp`) is a common line at the one difficulty, not at this one: scaled with it, a test
    /// store at 1.0 would see 750M candies.
    let growthDifficulty: Double
    /// 상점 배율: 아이템·알 가격에 곱한다. 낮을수록 싸다.
    let shopDifficulty: Double

    init(provider: any PokeProviding = PokeAPIClient.shared,
         detailProvider: (any PokemonDetailProviding)? = nil,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         dittoDisguiseRollingEnabled: Bool = AppEnv.isBundledApp,
         defaults: UserDefaults = .standard,
         difficulty: Double = PokemonBalance.difficulty,
         writer: SaveWriter? = SaveWriter.current) {
        self.writer = writer
        self.provider = provider
        self.detailProvider = detailProvider ?? (provider as? any PokemonDetailProviding)
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.dittoDisguiseRollingEnabled = dittoDisguiseRollingEnabled
        self.defaults = defaults
        oakAdviceEnabled = defaults.object(forKey: "oakAdviceEnabled") as? Bool ?? true
        merchantSeenDay = defaults.string(forKey: "merchantSeenDay")
        // The players' difficulty; tests of the mechanics pass 1, the tables as they are.
        growthDifficulty = difficulty
        shopDifficulty = difficulty
        load()
        migrateToOneDifficultyIfNeeded()
        migrateToAdditiveGrowthIfNeeded()
        migratePokemonProfilesIfNeeded()
        migrateLightBallToRewardsIfNeeded()
        recordFossilLinesBeforeDigsIfNeeded()
        reconcileOverclaimedDigsIfNeeded()
        recoverFromACrashedDungeonStep()
        // A save left waiting at the boss's throws, from before they were automatic, throws them now.
        throwAutomatically()
        refreshRepresentativeSubject()
        refreshSnapshots()
        if state.active != nil { displayState = .idle }
    }

    /// Why the save is not written: it could not be read, or a later build wrote it. Shown above the tabs; nothing is
    /// written meanwhile, so nothing of it is lost.
    enum SaveLock: Equatable, Sendable {
        /// The file is there but cannot be read (permissions, a disk error): it read as a new install, then was
        /// written over.
        case unreadable
        /// A later build wrote it (its commit): this one would drop what it does not know.
        case newerBuild(commit: String)
    }
    private(set) var saveLock: SaveLock?
    /// This build, stamped in the save at each write (`CompanionState.writer`).
    @ObservationIgnored private let writer: SaveWriter?

    static func defaultURL() -> URL {
        // 상태 파일 위치. 기본은 Application Support/PokeTokenBar. `PTB_STATE_DIR` 환경변수가 있으면
        // 그 디렉토리를 쓴다 — 개발/QA 격리용(실제 companion 상태를 건드리지 않고 데모 상태로 실행).
        // 프로덕션은 이 변수가 없어 무영향.
        AppStatePaths.directory().appendingPathComponent("companion-state.json")
    }

    // MARK: 파생값 (UI)

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { state.language = lang; save() }

    // MARK: Difficulty

    /// The growth slider of a previous release, if its value is saved: the progress earned at it keeps its fraction of
    /// the egg or stage at the one difficulty (`PokemonBalance.difficulty`), once. Both sliders' values are then removed.
    /// Without a saved value the save never had progress at another difficulty.
    private func migrateToOneDifficultyIfNeeded() {
        let stored = defaults.object(forKey: "growthDifficulty") as? Double
        defer {
            defaults.removeObject(forKey: "growthDifficulty")
            defaults.removeObject(forKey: "shopDifficulty")
        }
        // Releases before the sliders' 10% to 200% range accepted 0.01% to 2000%.
        guard let stored, stored.isFinite, stored > 0 else { return }
        let previous = min(20, max(0.0001, stored))
        guard previous != growthDifficulty else { return }
        rescaleBankedGrowth(from: previous, to: growthDifficulty)
        save()
    }

    /// The Light Ball used to speed up Pikachu's line, which a player holding every costume no longer raises: it now
    /// gives eggs and candies (`ItemKind.achievementRewards`). A save holding the old item gets them once, and the item
    /// leaves the Bag; the achievement stays claimed.
    private func migrateLightBallToRewardsIfNeeded() {
        guard itemCount(.lightBall) > 0 else { return }
        state.inventory[ItemKind.lightBall.rawValue] = nil
        state.claimedAchievements.insert(ItemKind.lightBall.rawValue)
        for reward in ItemKind.lightBall.achievementRewards {
            state.inventory[reward.kind.rawValue, default: 0] += reward.count
        }
        AppLog.write("light ball: traded for its rewards")
        save()
    }

    /// The fossil lines had before the digs, taken once (`CompanionState.fossilLinesBeforeDigs`). Counting them again
    /// from the lines graduated minus the Fossil Eggs hatched freed a dig as soon as an egg hatched, its line not
    /// graduated yet: a sixth egg for five missing lines. Kept with the next save, not written here: a fresh or reset
    /// state must not touch the file on launch, and until a Fossil Egg hatches it would read the same again.
    ///
    /// Only lines first graduated before the digs came (`FossilDig.introduced`) count: a save that ran the first
    /// version of the digs, or its export imported later, would otherwise count the lines its Fossil Eggs brought.
    /// The same rule mends a set taken that way; the digs it frees come back to claim.
    private func recordFossilLinesBeforeDigsIfNeeded() {
        let had = Set(FossilDig.lines.filter { line in
            guard let first = firstGraduation(ofLine: line) else { return false }
            return first < FossilDig.introduced
        })
        if let taken = state.fossilLinesBeforeDigs {
            let mended = taken.filter { line in firstGraduation(ofLine: line).map { $0 < FossilDig.introduced } ?? true }
            if mended != taken {
                AppLog.write("excavation: \(taken.count - mended.count) line(s) from Fossil Eggs no longer counted as had")
                state.fossilLinesBeforeDigs = mended
            }
            return
        }
        state.fossilLinesBeforeDigs = had
    }

    /// When the first graduated Pokémon of this line graduated (an entry with no date counts as long ago).
    private func firstGraduation(ofLine line: Int) -> Date? {
        let entries = state.dex.filter { !$0.isReleased && $0.chainOrder.contains(line) }
        guard !entries.isEmpty else { return nil }
        return entries.map { $0.caughtAt ?? .distantPast }.min()
    }

    /// Digs claimed beyond the eggs owed, the extra egg the old count gave when a Fossil Egg hatched: the extra Fossil
    /// Eggs still in the Bag leave it, and their digs are done again with nothing to claim. One already used stays used.
    private func reconcileOverclaimedDigsIfNeeded() {
        guard let had = state.fossilLinesBeforeDigs else { return }
        let digs = (ItemKind.excavation.regionGoals ?? []).map(\.generation)
        let claimed = digs.filter { isRegionTierClaimed(.excavation, generation: $0) }
        let extra = min(max(0, claimed.count - (digs.count - had.count)), itemCount(.fossilEgg))
        guard extra > 0 else { return }
        state.inventory[ItemKind.fossilEgg.rawValue] = itemCount(.fossilEgg) - extra
        for generation in claimed.suffix(extra) {
            state.claimedAchievements.remove(CompanionState.regionTierKey(.excavation, generation: generation))
        }
        AppLog.write("excavation: \(extra) extra fossil egg(s) taken back")
        save()
    }

    private func rescaleBankedGrowth(from old: Double, to new: Double) {
        func rescaled(_ credits: Int, base: Int) -> Int {
            // Calculate the old threshold without the new range clamp during migration.
            let oldThreshold = max(1, Int((Double(base) * old).rounded()))
            let newThreshold = max(1, Int((Double(base) * new).rounded()))
            let value = Double(credits) / Double(oldThreshold) * Double(newThreshold)
            let rounded = Int(min(Double(SaveTransfer.maxTokenValue), max(0, value.rounded(.down))))
            // Rounding must never turn an incomplete stage into a completed one.
            return credits < oldThreshold ? min(newThreshold - 1, rounded) : rounded
        }
        if var active = state.active {
            active.usedAtStage = rescaled(active.usedAtStage, base: active.phaseThreshold)
            state.active = active
        } else {
            state.eggUsage = rescaled(state.eggUsage, base: PokemonBalance.eggHatchThreshold)
        }
    }


    /// 난이도를 반영한 알 부화 임계. 첫 실행 안내 문구도 이 값을 보여준다.
    /// Items only halve it, with no floor: a 1M floor made the egg slower with them below difficulty 0.4.
    var eggHatchThreshold: Int {
        var threshold = PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: growthDifficulty)
        if ownsSilverWing {
            threshold /= 2
        }
        // Tera Orb: an egg from an evolution stone hatches twice as fast. An event egg's type or rarity is the
        // event's, not a stone's or the Shop's: neither item speeds it.
        if ownsTeraOrb, state.eggTypeGuarantee != nil, state.eggEvent == nil {
            threshold /= 2
        }
        // Sea Incense: so does an egg of a guaranteed rarity, bought in the Shop or from the Legend Plate.
        if itemCount(.seaIncense) > 0, state.eggTier != nil, state.eggEvent == nil {
            threshold /= 2
        }
        return threshold
    }

    /// 난이도를 반영한 단계 임계. **`PokemonBalance.phaseThreshold` 를 직접 부르지 않는다** —
    /// 배율을 빠뜨린 호출부가 생기면 그 경로만 조용히 기본 난이도로 돌아간다.
    /// The repeat boost is already in `phaseThreshold`; the bonuses divide it by their sum (+33% and +10%: 1.43).
    func stageThreshold(for mon: MonState) -> Int {
        var base = mon.phaseThreshold
        let speed = 1 + Self.bonusSum(thresholdGrowthFactors(for: mon))
        if speed > 1.0 {
            base = max(1, Int((Double(base) / speed).rounded()))
        }
        return PokemonBalance.scaled(base, by: growthDifficulty)
    }

    /// The stage threshold of the rule before bonuses added up, when they multiplied each other. Only
    /// `migrateToAdditiveGrowthIfNeeded` reads it, to keep a stage's progress across the change.
    private func multipliedBonusThreshold(for mon: MonState) -> Int {
        var base = mon.phaseThreshold
        if mon.hasGrowthBoost ? ownsMagmaStone : ownsLibertyPass {
            base = (base * 3) / 4
        }
        let speed = growthSpeedFactors(for: mon).reduce(1) { $0 * $1.multiplier }
        if speed > 1.0 {
            base = max(1, Int((Double(base) / speed).rounded()))
        }
        return PokemonBalance.scaled(base, by: growthDifficulty)
    }

    /// Bonuses used to multiply each other and now add up, which raises the threshold of a Pokémon with two
    /// or more of them (a sum is never more than the product). Its stage keeps the progress it had, once: the
    /// bar does not move back. With fewer than two bonuses both rules give the same threshold and nothing moves.
    private func migrateToAdditiveGrowthIfNeeded() {
        guard !state.additiveGrowthBonuses else { return }
        state.additiveGrowthBonuses = true
        if let active = state.active, thresholdGrowthFactors(for: active).count >= 2, active.usedAtStage > 0 {
            let value = Double(active.usedAtStage) / Double(multipliedBonusThreshold(for: active))
                * Double(stageThreshold(for: active))
            state.active?.usedAtStage = Int(min(Double(SaveTransfer.maxTokenValue), value.rounded(.down)))
        }
        save()
    }

    /// One thing that speeds up a Pokémon's growth, and by how much (1.5 = 50% faster).
    struct GrowthFactor: Equatable, Sendable {
        enum Source: Equatable, Sendable {
            /// The repeat boost: this line already graduated in this form.
            case repeatBoost
            /// The gym badges the species is weak to, together.
            case badges
            case item(ItemKind)
        }
        let source: Source
        let multiplier: Double
    }

    /// How much faster the passive items make this Pokémon grow (1.5 = 50% faster): badges, then the
    /// artifacts that favor a group. They add up. Only growth changes, never the odds of a hatch.
    func growthSpeedMultiplier(for mon: MonState) -> Double {
        1 + Self.bonusSum(growthSpeedFactors(for: mon))
    }

    /// What a set of bonuses adds together: +25% and +25% make 0.5.
    static func bonusSum(_ factors: [GrowthFactor]) -> Double {
        factors.reduce(0) { $0 + $1.multiplier - 1 }
    }

    /// The factors of `growthSpeedMultiplier`, one per badge set or artifact that applies to this Pokémon.
    func growthSpeedFactors(for mon: MonState) -> [GrowthFactor] {
        let types = PokemonTypeData.types(forSpeciesID: mon.currentID, form: mon.form)
        var factors: [GrowthFactor] = []
        func add(_ kind: ItemKind, _ multiplier: Double, if applies: Bool) {
            if applies, itemCount(kind) > 0 { factors.append(GrowthFactor(source: .item(kind), multiplier: multiplier)) }
        }
        add(.silverWing, CollectorBonus.silverWingGrowth, if: true)
        add(.teraOrb, CollectorBonus.teraOrbStoneGrowth, if: mon.fromStoneEgg)
        add(.seaIncense, CollectorBonus.seaIncenseRarityEggGrowth, if: mon.fromRarityEgg)
        let badges = typeBadgeSpeedMultiplier(forSpeciesID: mon.currentID, form: mon.form)
        if badges > 1 { factors.append(GrowthFactor(source: .badges, multiplier: badges)) }
        add(.clearBell, CollectorBonus.clearBellRare, if: mon.rarity == .rare)
        add(.griseousOrb, CollectorBonus.griseousOrbGhostDragon, if: types.contains { $0 == .ghost || $0 == .dragon })
        add(.prisonBottle, CollectorBonus.prisonBottleNewForm, if: mon.hasNewForm)
        add(.sparklingStone, CollectorBonus.sparklingStoneFairy, if: types.contains(.fairy))
        add(.sunFlute, CollectorBonus.sunFluteFinalStage, if: mon.stageIndex >= mon.totalForms - 1)
        // The Sun Flute's mirror: the first stage of a Pokémon that will evolve.
        add(.gracidea, CollectorBonus.gracideaFirstStage, if: mon.stageIndex == 0 && mon.totalForms > 1)
        // A Pokémon that does not evolve: its whole planned line is one species (a Regi, Tauros, a Kanto Farfetch'd).
        add(.relicStatue, CollectorBonus.relicStatueNoEvolution, if: mon.totalForms == 1)
        add(.beastBall, CollectorBonus.beastBallUltraBeast, if: SpeciesGoal.ultraBeasts.contains(mon.currentID))
        add(.rustedSword, CollectorBonus.rustedSwordLegendary, if: mon.rarity == .legendary)
        add(.boosterEnergy, CollectorBonus.boosterEnergyParadox, if: SpeciesGoal.paradoxes.contains(mon.currentID))
        add(.tealMask, CollectorBonus.tealMaskTypes, if: types.contains(where: CollectorBonus.tealMaskTypeList.contains))
        add(.lunarWing, CollectorBonus.lunarWingPsychicDark, if: types.contains { $0 == .psychic || $0 == .dark })
        add(.oaksLetter, CollectorBonus.oaksLetterStarter, if: CollectorBonus.starterLines.contains(mon.currentID))
        add(.zRing, CollectorBonus.zRingSteelElectric, if: types.contains { $0 == .steel || $0 == .electric })
        add(.scrollOfDarkness, CollectorBonus.scrollOfDarknessFighting, if: types.contains(.fighting))
        // Neither the first nor the last stage: only a line of three stages or more has one.
        add(.relicVase, CollectorBonus.relicVaseMiddleStage, if: mon.stageIndex > 0 && mon.stageIndex < mon.totalForms - 1)
        return factors
    }

    /// Items that add to the tokens counted as growth, in the order `applyUsage` applies them.
    var tokenGrowthFactors: [GrowthFactor] {
        var factors: [GrowthFactor] = []
        if ownsOldSeaMap { factors.append(GrowthFactor(source: .item(.oldSeaMap), multiplier: 1.20)) }
        if ownsDnaSplicers { factors.append(GrowthFactor(source: .item(.dnaSplicers), multiplier: 1.50)) }
        if ownsZygardeCube { factors.append(GrowthFactor(source: .item(.zygardeCube), multiplier: zygardeCubeMultiplier)) }
        return factors
    }

    /// The bonuses the stage threshold is divided by: the Magma Stone or the Liberty Pass, then the badges and
    /// artifacts. A Rare Candy gets these; the token items only count tokens.
    func thresholdGrowthFactors(for mon: MonState) -> [GrowthFactor] {
        // Magma Stone speeds up lines already graduated, Liberty Pass the ones never graduated: 25% less to grow.
        let lineItem: ItemKind = mon.hasGrowthBoost ? .magmaStone : .libertyPass
        let line = itemCount(lineItem) > 0 ? [GrowthFactor(source: .item(lineItem), multiplier: 4.0 / 3.0)] : []
        return line + growthSpeedFactors(for: mon)
    }

    /// Everything that speeds up this Pokémon's growth, the repeat boost included: what the Home badge and the
    /// Bonuses page show. Growth difficulty is a setting, not a bonus, and is left out.
    func growthFactors(for mon: MonState) -> [GrowthFactor] {
        var factors: [GrowthFactor] = []
        if mon.hasGrowthBoost {
            factors.append(GrowthFactor(source: .repeatBoost, multiplier: Double(PokemonBalance.repeatGrowthMultiplier)))
        }
        return factors + thresholdGrowthFactors(for: mon) + tokenGrowthFactors
    }

    /// The current Pokémon's growth factors and total; empty and 1 for an egg.
    /// While its form is a mystery, only those that hold for every form it can carry.
    var currentGrowthFactors: [GrowthFactor] {
        guard let a = state.active else { return [] }
        guard let suspense = formSuspense, suspense.isUncertain else { return growthFactors(for: a) }
        var seen = Set<[Bool]>()
        let perForm = suspense.outcomes.filter { seen.insert([$0.isRepeat, $0.isNewForm]).inserted }.map { outcome -> [GrowthFactor] in
            var mon = a
            mon.hasGrowthBoost = outcome.isRepeat
            mon.hasNewForm = outcome.isNewForm
            return growthFactors(for: mon)
        }
        return (perForm.first ?? []).filter { factor in perForm.allSatisfy { $0.contains(factor) } }
    }
    var currentGrowthTotal: Double { Self.growthTotal(currentGrowthFactors) }

    /// The bonuses add up and the repeat boost multiplies their total: 2 × (1 + 0.33 + 0.1) = ×2.87.
    static func growthTotal(_ factors: [GrowthFactor]) -> Double {
        let repeatBoost = factors.filter { $0.source == .repeatBoost }.reduce(1) { $0 * $1.multiplier }
        return repeatBoost * (1 + bonusSum(factors.filter { $0.source != .repeatBoost }))
    }

    /// 상점 표시·결제에 쓰는 실제 가격 — 기본가 × 상점 난이도. 미판매면 nil.
    func price(of kind: ItemKind) -> Int? {
        kind.shopPrice.map { base in
            var p = PokemonBalance.scaled(base, by: shopDifficulty)
            if ownsRainbowWing { p = max(1, Int(Double(p) * 0.75)) }
            return p
        }
    }

    /// The Shop's price before the discounts the player's items give (`price(of:)`): struck beside the price paid.
    func basePrice(of entry: ShopEntry) -> Int { PokemonBalance.scaled(entry.price, by: shopDifficulty) }

    /// The items that lower an entry's price, in the order they apply: the Rainbow Wing on everything, the Jade Orb on
    /// eggs again.
    func discounts(of entry: ShopEntry) -> [ItemKind] {
        var items: [ItemKind] = []
        if ownsRainbowWing { items.append(.rainbowWing) }
        if case .egg = entry, ownsJadeOrb { items.append(.jadeOrb) }
        return items
    }

    /// The shiny odds now and with the Shiny Charm, for its Shop card: 1 in 64 to 1 in 48, or with the Reveal Glass 1
    /// in 32 to 1 in 24.
    var shinyCharmOdds: (now: UInt64, withCharm: UInt64) {
        (shinyDenominator, Self.shinyDenominator(charmOwned: true, revealGlassOwned: ownsRevealGlass))
    }

    /// 알을 포함한 상점 한 줄의 실제 가격.
    func price(of entry: ShopEntry) -> Int {
        var p = PokemonBalance.scaled(entry.price, by: shopDifficulty)
        if ownsRainbowWing { p = max(1, Int(Double(p) * 0.75)) }
        if case .egg = entry, ownsJadeOrb { p = max(1, Int(Double(p) * 0.80)) }
        return p
    }
    /// 앱 전체 UI 문자열 — language 변경 시 자동 재렌더.
    var l: L { L(language) }

    var hasActive: Bool { state.active != nil }
    /// The Pokémon raised hatched from a legendary boss's egg, won once: no egg nor stone sends it off before it
    /// graduates (the owner, 2026-11-04).
    var isRaisingLegendaryBossPokemon: Bool { state.active?.fromLegendaryBossEgg == true }
    /// A Pokémon raised that an egg or a stone may send off: every `canUse…` of them asks this. Not while a team explores:
    /// it is paused until the team is back (the owner, 2026-11-05: an egg used then ended it).
    var canSendOffActive: Bool { canSendOffActive(onReturn: false) }
    func canSendOffActive(onReturn: Bool) -> Bool { hasActive && !isRaisingLegendaryBossPokemon && (onReturn || expedition == nil) }
    var rarity: Rarity? { state.active?.rarity }
    var currentIsShiny: Bool { state.active?.displaysShiny ?? false }   // 위장 중엔 이로치 숨김(리빌 때 공개)
    /// 새 알(리롤) 구매 시 실수로 놓아주지 않도록 2단계 확인이 필요한 고가치 개체인지 판정.
    /// 이로치(shiny)이거나 전설(legendary)인 경우에만 2단계 경고를 띄운다.
    /// 희귀(rare)는 고급/희귀 알의 반복 리롤 피로도(alert fatigue)를 방지하기 위해 일반 확인만 거친다.
    /// 위장 중인 메타몽은 `currentIsShiny`(=false)와 `rarity`(=.common)의 불변식을 그대로 따라
    /// 리빌 전 정체를 누설하지 않는다.
    var isHighValueCompanion: Bool {
        currentIsShiny || rarity == .legendary
    }
    var currentNature: PokemonNature? { state.active?.nature }
    var growthMultiplier: Int? {
        state.active?.hasGrowthBoost == true ? PokemonBalance.repeatGrowthMultiplier : nil
    }

    /// 메뉴바와 플로팅 펫이 그릴 대표 종과 색. nil 선택은 기존 동작(현재 개체/알)을 보존한다.
    /// 저장된 값이라 상시 렌더링 경로가 도감 전체를 다시 접거나 불필요한 상태를 관찰하지 않는다.
    struct RepresentativeSubject: Equatable, Sendable {
        let speciesID: Int?
        let isShiny: Bool
        var form: PokemonForm? = nil
    }

    var representativeSpeciesID: Int? { state.representativeSpeciesID }
    var representativeForm: PokemonForm? { state.representativeForm }

    /// 관련 상태가 바뀌어 저장되는 경계에서만 갱신한다. 고정 종 하나의 이로치 여부만 조회하므로
    /// 이름 해석·정렬을 포함한 `dexSpecies` 계산을 메뉴바/플로팅 펫 렌더마다 반복하지 않는다.
    private func refreshRepresentativeSubject() {
        // Pikachu wears its costume wherever it shows: the menu bar and the pet through this subject, every other
        // sprite through `PikachuCostume.equipped`.
        PikachuCostume.equipped = state.equippedPikachuCostume
        let next: RepresentativeSubject
        if let selected = state.representativeSpeciesID {
            next = RepresentativeSubject(speciesID: selected,
                isShiny: state.ownsShinySpecies(selected, form: state.representativeForm),
                form: PikachuCostume.displayForm(speciesID: selected,
                                                 form: PokemonForm.resolved(speciesID: selected, form: state.representativeForm)))
        } else {
            next = RepresentativeSubject(speciesID: currentSpeciesID, isShiny: currentIsShiny,
                                         form: PikachuCostume.displayForm(speciesID: currentSpeciesID, form: currentSpriteForm))
        }
        if representativeSubject != next { representativeSubject = next }
    }

    /// nil 은 자동 추적. 도감에 없는 id 는 저장하지 않는다 — UI 밖 호출이나 손상된 입력도 같은
    /// 불변식을 지키며, 실패한 요청이 기존 선택을 조용히 해제하지 않도록 false 만 반환한다.
    @discardableResult
    func setRepresentativeSpeciesID(_ id: Int?, form: PokemonForm? = nil) -> Bool {
        if let id, !state.ownsSpecies(id, form: form) { return false }
        state.representativeSpeciesID = id
        state.representativeForm = PokemonForm.resolved(speciesID: id ?? 0, form: form)
        save()
        return true
    }

    func isRepresentative(_ species: DexSpecies) -> Bool {
        state.representativeSpeciesID == species.id
            && (species.form == nil || state.representativeForm == species.form)
    }

    /// Settings describe the selected form, even though the main Pokédex aggregates the species.
    var representativeDexSpecies: DexSpecies? {
        guard let selected = representativeSpeciesID else { return nil }
        let candidates = PokemonForm.hasForms(speciesID: selected) ? formSpecies(speciesID: selected) : dexSpecies
        return candidates.first { isRepresentative($0) }
    }

    // 알 인큐베이션 (active 없을 때)
    var isEgg: Bool { state.active == nil }
    var eggStarted: Bool { state.eggUsage > 0 }
    var eggProgress: Double { min(1, max(0, Double(state.eggUsage) / Double(eggHatchThreshold))) }
    var eggTokensToHatch: Int { max(0, eggHatchThreshold - state.eggUsage) }
    /// 알이 부화 준비(100%)가 되었으나 PokéAPI 요청/후보 선택 실패로 다음 갱신을 기다리는 상태.
    private(set) var isHatchRetryDelayed = false

    var displayName: String {
        guard let a = state.active else { return incubatingEggName }
        guard let line = currentLine else { return "…" }
        return formDisplayName(line.localizedName(a.currentID, state.language),
                               speciesID: a.currentID, form: currentForm)
    }
    var currentSpeciesID: Int? { state.active?.currentID }
    var currentForm: PokemonForm? {
        PokemonForm.resolved(speciesID: currentSpeciesID ?? 0, form: state.active?.form)
    }
    /// The look the growing Pokémon's sprites show (`MonState.spriteForm`).
    var currentSpriteForm: PokemonForm? { state.active?.spriteForm }
    /// The form the evolution track draws every stage in: the individual's own, for its whole line, which each stage's
    /// sprite resolves for its species. Not `currentForm`, resolved for the current species only: once a Galarian
    /// Meowth is a Perrserker, which has no forms, that is nil and its Meowth stage would show a Kantonian one.
    /// The look of the track's stages: a costumed Pokémon's costume, at every stage of its costume's line.
    var evolutionTrackForm: PokemonForm? {
        guard let mon = state.active else { return nil }
        guard let costume = mon.costume else { return mon.form }
        return CostumeCatalog.entry(code: costume, speciesID: mon.currentID, form: mon.form)?.displayForm
            ?? CostumeCatalog.displayForm(code: costume, form: nil)
    }
    var isFinalStage: Bool {
        guard let a = state.active, let line = currentLine else { return false }
        return line.tree.node(withID: a.currentID).map { Self.openChildren($0, form: a.form).isEmpty } ?? true
    }
    var stageText: String {
        guard let a = state.active else { return "" }
        return isFinalStage ? l.finalForm : l.stage(a.stageIndex + 1, a.totalForms)
    }
    var threshold: Int {
        guard let a = state.active else { return 1 }
        return stageThreshold(for: a)
    }
    var progress: Double {
        guard let a = state.active, threshold > 0 else { return 0 }
        return min(1, max(0, Double(a.usedAtStage) / Double(threshold)))
    }
    var tokensToNext: Int { guard let a = state.active else { return 0 }; return max(0, threshold - a.usedAtStage) }

    /// Tokens a day at the user's pace (`UsageStore.dailyPace`), set with each update; nil while unknown.
    var usagePacePerDay: Double?
    /// Each provider's usage today, set before each update: the raising record spreads and prices new tokens with it.
    @ObservationIgnored var todayUsageDetails: [String: TodayUsageDetail] = [:]
    /// The providers' names, for the raising record ("Claude Code").
    var providerNames: [String: String] = [:]

    /// The tokens still to use before the next stage: `tokensToNext` less what the token bonuses add on top
    /// (`applyUsage`), which the threshold does not include.
    var tokensNeededToNext: Int {
        guard let mon = state.active else { return 0 }
        let tokenBonus = Self.bonusSum(tokenGrowthFactors)
        guard tokenBonus > 0 else { return tokensToNext }
        let thresholdSpeed = 1 + Self.bonusSum(thresholdGrowthFactors(for: mon))
        return Int((Double(tokensToNext) * thresholdSpeed / (thresholdSpeed + tokenBonus)).rounded(.up))
    }

    /// The time before the next stage at the user's pace, nil while the pace is unknown.
    var timeToNext: TimeInterval? {
        guard let pace = usagePacePerDay, pace > 0, state.active != nil else { return nil }
        return Double(tokensNeededToNext) / pace * 86_400
    }

    /// 진화 라인 표시용: 실현된 경로 + 다음 단계 미리보기.
    /// 분기 후보가 있는 경우 각 후보(이미 수집된 것은 스프라이트, 미수집은 실루엣/음영)를 모두 표시한다.
    var lineNodes: [EvoLineItem] {
        guard let a = state.active, let line = currentLine else { return [] }
        var out = Self.realizedLineItems(pathIDs: a.pathIDs, stageIndex: a.stageIndex)
        if let current = line.tree.node(withID: a.currentID) {
            var node = current
            var guaranteedPrefix: [EvoNode] = []
            while Self.openChildren(node, form: a.form).count == 1, let child = Self.openChildren(node, form: a.form).first {
                guaranteedPrefix.append(child)
                node = child
            }

            let branches = Self.openChildren(node, form: a.form)
            if branches.count > 1 {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
                let branchItems = branches.map { ch in
                    BranchEvolutionItem(
                        speciesID: ch.speciesID,
                        isCollected: isEvolutionCollected(speciesID: ch.speciesID, baseID: a.baseID, form: a.form)
                    )
                }
                out.append(EvoLineItem(.branch(branchItems), .future))
            } else {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
            }
        }
        return out
    }

    /// One stop of Home's evolution track.
    enum EvolutionTrackStop: Equatable {
        /// A stage this individual went through, or the one it is at.
        case reached(Int, isCurrent: Bool)
        /// A stage it will reach: the line goes on with one species. `isCaught`: graduated already.
        case coming(Int, isCaught: Bool)
        /// Where the line goes several ways: every path from there to a final stage (Wurmple into Silcoon then
        /// Beautifly, or Cascoon then Dustox).
        case branch([[BranchEvolutionItem]])
        /// The end of the line: the final stage graduates.
        case graduation
    }

    /// Home's evolution track: the stages reached, then every coming one up to the graduation, or up to where the
    /// line goes several ways, with all the ways to its end. The individual's planned path stays hidden, and so does
    /// a form no stage reached shows: the stage that shows it stands for each form it can carry. Empty while the line
    /// is not loaded or for the egg.
    var evolutionTrack: [EvolutionTrackStop] {
        guard let a = state.active, let line = currentLine else { return [] }
        var stops = a.pathIDs.prefix(a.stageIndex + 1).enumerated().map { index, id in
            EvolutionTrackStop.reached(id, isCurrent: index == a.stageIndex)
        }
        func caught(_ id: Int, form: PokemonForm?) -> Bool { isEvolutionCollected(speciesID: id, baseID: a.baseID, form: form) }
        func caught(_ id: Int) -> Bool { caught(id, form: a.form) }
        func paths(from node: EvoNode, form: PokemonForm?) -> [[BranchEvolutionItem]] {
            let open = Self.openChildren(node, form: form)
            guard !open.isEmpty else { return [[]] }
            return open.flatMap { child in
                paths(from: child, form: form).map {
                    [BranchEvolutionItem(speciesID: child.speciesID, isCollected: caught(child.speciesID, form: form),
                                         form: form)] + $0
                }
            }
        }
        guard var node = line.tree.node(withID: a.currentID) else { return stops + [.graduation] }
        if let suspense = formSuspense, let reveal = line.tree.node(withID: suspense.revealSpeciesID) {
            while node.speciesID != reveal.speciesID,
                  let child = node.children.first(where: { $0.node(withID: reveal.speciesID) != nil }) {
                if child.speciesID != reveal.speciesID { stops.append(.coming(child.speciesID, isCaught: caught(child.speciesID))) }
                node = child
            }
            stops.append(.branch(suspense.outcomes.flatMap { outcome in
                paths(from: reveal, form: outcome.form).map {
                    [BranchEvolutionItem(speciesID: reveal.speciesID, isCollected: caught(reveal.speciesID, form: outcome.form),
                                         form: outcome.form)] + $0
                }
            }))
            return stops
        }
        while true {
            let open = Self.openChildren(node, form: a.form)
            if open.count > 1 {
                stops.append(.branch(paths(from: node, form: a.form)))
                return stops
            }
            guard let child = open.first else { break }
            stops.append(.coming(child.speciesID, isCaught: caught(child.speciesID)))
            node = child
        }
        return stops + [.graduation]
    }

    static func realizedLineItems(pathIDs: [Int], stageIndex: Int) -> [EvoLineItem] {
        pathIDs.enumerated().map { i, id in
            EvoLineItem(.species(id), i == stageIndex ? .current : .done)
        }
    }
    /// 도감에는 영구 보존된 졸업 개체와 현재 키우는 포켓몬을 함께 표시한다.
    /// 현재 개체는 영속 dex 에 중복 저장하지 않고 화면용 항목으로 합성한다. 졸업 시 active 가 사라지고
    /// 같은 개체의 영구 DexEntry 가 추가되므로 목록 개수는 그대로 유지된다.
    private var activeDexEntry: DexEntry? {
        guard let active = state.active else { return nil }
        return DexEntry(
            id: "active-\(active.baseID)-\(active.currentID)",
            baseID: active.baseID,
            finalID: active.currentID,
            chainOrder: active.pathIDs,
            rarity: active.rarity,
            caughtAt: nil,
            isShiny: currentIsShiny,   // 위장 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스)
            nature: active.nature,
            profile: active.profile,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    active.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
            },
            form: active.form,
            hasNewForm: active.hasNewForm
        ).withRecords(of: active)
    }

    /// 놓아준 개체의 영구 기록 — 알을 새로 사서 육성을 포기하는 순간 만든다.
    ///
    /// **도달한 형태만 담는다**(`pathIDs.prefix(stageIndex + 1)`). 도감이 육성 중 보여주던 범위와
    /// 같아야 놓아준 뒤에도 칸 구성이 그대로 유지된다 — `plannedPathIDs` 나 `pathIDs` 전체를 쓰면
    /// 도달한 적 없는 진화형까지 보유로 잡힌다(`dexSpecies` 가 같은 prefix 규칙을 쓴다).
    ///
    /// 이로치는 `currentIsShiny` — 위장 중인 메타몽은 리빌 전까지 숨긴다(`activeDexEntry` 와 단일 판정).
    /// `caughtAt` 은 놓아준 시각이다: 포획 로그가 그 값으로 정렬하므로 기록이 남은 시점과 일치해야 한다.
    private func releasedDexEntry(from a: MonState) -> DexEntry {
        // stageIndex 가 음수·범위 밖이어도 최소 한 형태는 남긴다(손상 상태 파일 방어 — MonState.currentID 와 같은 태도).
        let reached = Array(a.pathIDs.prefix(max(1, a.stageIndex + 1)))
        let chain = reached.isEmpty ? [a.baseID] : reached
        let now = clock()
        return DexEntry(
            id: a.profile?.instanceID ?? UUID().uuidString,
            baseID: a.baseID,
            finalID: chain.last ?? a.baseID,
            chainOrder: chain,
            rarity: a.rarity,
            caughtAt: now,
            isShiny: currentIsShiny,
            nature: a.nature,
            profile: a.profile,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    chain.compactMap { id in line.names[id].map { (id, $0) } })
            },
            releasedAt: now, form: a.form, hasNewForm: a.hasNewForm).withRecords(of: a)
    }

    var dexEntries: [DexEntry] {
        guard let activeDexEntry else { return state.dex }
        return state.dex + [activeDexEntry]
    }

    /// 합성된 현재 포켓몬 항목인지 판별한다. caughtAt 이 없는 구버전 졸업 항목과 혼동하지 않는다.
    func isActiveDexEntry(_ entry: DexEntry) -> Bool {
        entry.id == activeDexEntry?.id
    }

    /// 포획 로그에서 특정 항목이 중복 포획 개체인지(이전에 동일 진화 라인이나 동일 안농 폼을 이미 잡았는지) 판별한다.
    func isDuplicateCatch(_ entry: DexEntry) -> Bool {
        duplicateCatchEntryIDs.contains(entry.id)
    }

    /// What graduating the current Pokémon would add to the graduated Pokédex: the species of its line it reached, or
    /// can still reach in its form, that no graduated Pokémon holds in that form, and whether it would be the first
    /// shiny of its species. Every branch counts, as on the evolution track, so the hidden route is not given away.
    struct ActiveNews: Equatable, Sendable {
        var newSpecies: [Int]
        var firstShiny: Bool
        /// A Pikachu still ahead in its line while a costume is missing: it brings one when it arrives.
        var costume = false
        /// Its form is still hidden and decides what it brings: nothing here says it brings nothing.
        var mystery: FormMystery?
        /// A costumed Pokémon whose costume, at a stage it reached or will reach, the costumed collection lacks
        /// (`CostumeCatalog`): "New costume" when its species are all held (the owner, 2026-11-13).
        var newCostume = false
        /// Nothing new: sending it off loses nothing the Pokédex and the costumes do not already hold.
        var isDuplicate: Bool { mystery == nil && newSpecies.isEmpty && !firstShiny && !costume && !newCostume }
    }

    /// Nil unless its form is hidden and could be several (`FormSuspense`). The forms it can carry are those its egg
    /// rolled among: an egg's type never narrows them on these lines, whose first stage looks the same in each form, so
    /// only the draw items noted at its roll do. Without a note, every form of its line.
    var formSuspense: FormSuspense? {
        _ = state.dex.count   // observed even from the cache
        if let cached = formSuspenseCache { return cached }
        let suspense = makeFormSuspense()
        formSuspenseCache = .some(suspense)
        return suspense
    }

    private func makeFormSuspense() -> FormSuspense? {
        guard let a = state.active, a.costume == nil,
              PokemonForm.isFormHidden(baseID: a.baseID, reached: a.pathIDs.prefix(a.stageIndex + 1)),
              let reveal = PokemonForm.formSpecies(baseID: a.baseID).first else { return nil }
        // The rules its egg was rolled under, as its items: a form rolled before `missingFormsFirst` kept its odds.
        let draw = HatchDraw(collection: state, items: a.hatch?.rollItems ?? [],
                             rules: HatchRules(rolledAt: a.raising?.hatchedAt))
            .lineFormDraw(baseID: a.baseID, types: [])
        guard draw.forms.count > 1 else { return nil }
        let held = graduatedSpeciesForms, shinyHeld = graduatedShinySpeciesForms
        let repeats = state.collectedFinalForms(forBaseID: a.baseID)
        let weights = PokemonForm.rollWeights(among: draw.forms, collected: draw.collected)
        return FormSuspense(revealSpeciesID: reveal, outcomes: zip(draw.forms, weights).map { form, weight in
            FormSuspense.Outcome(form: form, weight: weight, news: news(of: a, form: form, held: held, shinyHeld: shinyHeld),
                                 isRepeat: repeats.contains(form),
                                 isNewForm: !draw.collected.contains(form))
        })
    }

    /// The Journal keeps quiet about what it brings: the one raised while its form is a mystery, and one sent off
    /// before a stage showed its form, which nobody will ever know.
    func hidesFormNews(_ entry: DexEntry) -> Bool {
        if isActiveDexEntry(entry) { return activeNews?.mystery != nil }
        return entry.isReleased && PokemonForm.isFormHidden(baseID: entry.baseID, reached: entry.chainOrder)
    }

    /// What is left to grow in tokens and time would tell its form while that form is a mystery.
    var hidesGrowthAmounts: Bool { activeNews?.mystery != nil }

    /// A species of the line raised, named in its form unless that form is hidden.
    func activeSpeciesName(_ id: Int) -> String {
        let name = currentLine?.localizedName(id, state.language) ?? "#\(id)"
        return formSuspense == nil ? formDisplayName(name, speciesID: id, form: state.active?.form) : name
    }

    /// Its growth boost is that of a repeat: the boost comes from its line, and it brings nothing new.
    var activeIsRepeat: Bool { state.active?.hasGrowthBoost == true && activeNews?.isDuplicate == true }

    /// Nil for an egg.
    var activeNews: ActiveNews? {
        guard let a = state.active else { return nil }
        return formSuspense?.news ?? news(of: a, form: a.form, held: graduatedSpeciesForms, shinyHeld: graduatedShinySpeciesForms)
    }

    private func news(of a: MonState, form: PokemonForm?, held: Set<DexSpeciesKey>, shinyHeld: Set<DexSpeciesKey>) -> ActiveNews {
        let line = Self.lineAhead(Array(a.pathIDs.prefix(a.stageIndex + 1)), from: a.currentID, form: form)
        let newSpecies = line.filter { !held.contains(DexSpeciesKey(speciesID: $0, form: form)) }
        // A first shiny as the Pokédex counts one: a species of the line, in this form, with no graduated shiny. The
        // shine a disguised Ditto hides stays hidden (`displaysShiny`).
        let firstShiny = a.displaysShiny && line.contains { !shinyHeld.contains(DexSpeciesKey(speciesID: $0, form: form)) }
        // The costume comes on arriving as Pikachu (`grantPikachuCostume`): one already reached brought its own.
        let costume = line.contains(PikachuCostume.speciesID)
            && !a.pathIDs.prefix(a.stageIndex + 1).contains(PikachuCostume.speciesID)
            && PikachuCostume.next(owned: state.pikachuCostumes, seed: 0) != nil
        // Its costume's stages, those reached and those planned: one the collection lacks is new.
        let newCostume = a.costume.map { code in
            let held = ownedCostumeKeys().all
            return a.plannedPathIDs.contains { id in
                CostumeCatalog.entry(code: code, speciesID: id, form: form).map { !held.contains($0.key) } ?? false
            }
        } ?? false
        return ActiveNews(newSpecies: newSpecies, firstShiny: firstShiny, costume: costume, newCostume: newCostume)
    }

    /// What `activeNews` asks of the Pokémon raised, for one an egg would hatch from `baseID` in `form`: whether it
    /// brings something new, its shine aside. Made once for the many lines of an egg.
    func hatchBringsNew() -> (_ baseID: Int, _ form: PokemonForm?) -> Bool {
        let new = hatchDraw.bringsNew()
        let costumeMissing = PikachuCostume.next(owned: state.pikachuCostumes, seed: 0) != nil
        return { baseID, form in
            new(baseID, form)
                || costumeMissing && Self.lineAhead([baseID], from: baseID, form: form).contains(PikachuCostume.speciesID)
        }
    }

    /// What `activeNews` asks of a shiny Pokémon raised, for one an egg would hatch from `baseID` in `form`: whether
    /// shining, it would be the first shiny of a species of its line in that form.
    func hatchBringsFirstShiny() -> (_ baseID: Int, _ form: PokemonForm?) -> Bool {
        let held = graduatedShinySpeciesForms
        return { baseID, form in
            Self.lineAhead([baseID], from: baseID, form: form).contains { !held.contains(DexSpeciesKey(speciesID: $0, form: form)) }
        }
    }

    /// Each species a graduated shiny holds, in its form.
    private var graduatedShinySpeciesForms: Set<DexSpeciesKey> {
        Set(state.dex.filter { !$0.isReleased && $0.isShiny }.flatMap { e in
            e.chainOrder.map { DexSpeciesKey(speciesID: $0, form: e.form) }
        })
    }

    /// Each species a graduated Pokémon holds, in its form.
    private var graduatedSpeciesForms: Set<DexSpeciesKey> {
        Set(state.dex.filter { !$0.isReleased }.flatMap { e in
            e.chainOrder.map { DexSpeciesKey(speciesID: $0, form: e.form) }
        })
    }

    /// The species reached on `path` and those still ahead of `current` in `form`, every branch counted.
    nonisolated static func lineAhead(_ path: [Int], from current: Int, form: PokemonForm?) -> [Int] {
        var line = path
        var next = [current]
        while let id = next.popLast() {
            for child in PokemonEvolutionData.children(of: id, form: form) where !line.contains(child) {
                line.append(child)
                next.append(child)
            }
        }
        return line
    }

    /// A goal the Pokémon raised advances: graduated, it adds `gain` species to it, which stands at `count` of `needed`.
    /// `generation`: a regional achievement's region, or a dig's number.
    struct ActiveGoal: Equatable, Sendable {
        let item: ItemKind
        let generation: Int?
        let gain: Int
        let count: Int
        let needed: Int
    }

    /// Every way to the end of its line the Pokémon raised can still take, with the stages it reached: in any form it
    /// can carry while its form is hidden.
    var activeWays: [[Int]] {
        guard let a = state.active else { return [] }
        guard let suspense = formSuspense else { return ways(of: a, form: a.form) }
        var seen = Set<[Int]>()
        return suspense.outcomes.flatMap { ways(of: a, form: $0.form) }.filter { seen.insert($0).inserted }
    }

    private func ways(of a: MonState, form: PokemonForm?) -> [[Int]] {
        var ways: [[Int]] = []
        func walk(_ id: Int, _ path: [Int]) {
            let children = PokemonEvolutionData.children(of: id, form: form).filter { !path.contains($0) }
            if children.isEmpty { ways.append(path) }
            for child in children { walk(child, path + [child]) }
        }
        walk(a.currentID, Array(a.pathIDs.prefix(a.stageIndex + 1)))
        return ways
    }

    /// The goals not claimed yet that graduating the Pokémon raised would advance, the ones it advances most first: a
    /// gym badge's or the Legendary Egg's region, the next dig (its Rock species in this form), a stone or an artifact
    /// still locked, a species' forms. Empty when it brings nothing new. Helps to choose whether to keep it. While its
    /// form is hidden, the goals every form it can carry advances, with the least any of them adds.
    var activeGoals: [ActiveGoal] {
        guard let a = state.active else { return [] }
        guard let suspense = formSuspense else {
            return goals(of: a, form: a.form, news: news(of: a, form: a.form, held: graduatedSpeciesForms,
                                                         shinyHeld: graduatedShinySpeciesForms))
        }
        var common: [ActiveGoal]?
        var seen = Set<[[Int]]>()
        for outcome in suspense.outcomes {
            let ways = ways(of: a, form: outcome.form)
            let rock = Set(ways.joined()).filter { PokemonTypeData.types(forSpeciesID: $0, form: outcome.form).contains(.rock) }
            guard seen.insert([outcome.news.newSpecies, rock.sorted()] + ways).inserted else { continue }
            let goals = goals(of: a, form: outcome.form, news: outcome.news)
            common = common.map { kept in
                kept.compactMap { goal in
                    goals.first { $0.item == goal.item && $0.generation == goal.generation }.map {
                        ActiveGoal(item: goal.item, generation: goal.generation, gain: min(goal.gain, $0.gain),
                                   count: goal.count, needed: goal.needed)
                    }
                }
            } ?? goals
            if common?.isEmpty == true { return [] }
        }
        return common ?? []
    }

    private func goals(of a: MonState, form: PokemonForm?, news: ActiveNews) -> [ActiveGoal] {
        guard !news.newSpecies.isEmpty else { return [] }
        let new = Set(news.newSpecies)
        // Graduated, it keeps one branch of its line: an Eevee counted Vaporeon, Jolteon and Flareon at once (+4 for
        // Kanto, where it brings 2). A goal counts the branch that advances it most.
        let branches = ways(of: a, form: form).map { Set($0).intersection(new) }
        let registered = graduatedSpeciesIDs
        var goals: [ActiveGoal] = []
        func consider(_ item: ItemKind, _ generation: Int?, _ progress: GoalProgress, counted: [Set<Int>]) {
            guard !progress.isMet else { return }
            let missing = Set(progress.goal.species).subtracting(progress.registered)
            let gain = min(counted.map { missing.intersection($0).count }.max() ?? 0, progress.goal.needed - progress.count)
            guard gain > 0 else { return }
            goals.append(ActiveGoal(item: item, generation: generation, gain: gain, count: progress.count,
                                    needed: progress.goal.needed))
        }
        // The Dungeons medals count dungeons won, not the Pokémon raised.
        for kind in Self.achievementItems where !kind.isPlayMedal {
            if kind == .excavation {
                // The digs add up: only the next one counts, with the species that are Rock in this form.
                let rock = branches.map { $0.filter { PokemonTypeData.types(forSpeciesID: $0, form: form).contains(.rock) } }
                if let next = regionTiers(.excavation).first(where: { !$0.isDone && !$0.progress.isMet }) {
                    consider(kind, next.generation, next.progress, counted: rock)
                }
            } else if kind.isRegional {
                for tier in regionTiers(kind, registered: registered) where !tier.isDone {
                    consider(kind, tier.generation, tier.progress, counted: branches)
                }
            } else if !isClaimed(kind), !isUnlocked(kind, registered: registered) {
                if case .forms(let goal)? = kind.unlock, new.contains(goal.speciesID) {
                    let have = state.graduatedForms(speciesID: goal.speciesID, graduatedFormsIndex)
                        .intersection(goal.forms).count
                    goals.append(ActiveGoal(item: kind, generation: nil, gain: 1, count: have, needed: goal.forms.count))
                    continue
                }
                // Any one goal unlocks it: the one this Pokémon advances most.
                let before = goals.count
                for progress in unlockProgress(of: kind, registered: registered) {
                    consider(kind, nil, progress, counted: branches)
                }
                if goals.count - before > 1 {
                    let best = goals[before...].max { $0.gain < $1.gain || ($0.gain == $1.gain && $0.count < $1.count) }!
                    goals.removeSubrange(before...)
                    goals.append(best)
                }
            }
        }
        // The most species first, then the closest to done.
        return goals.sorted {
            if $0.gain != $1.gain { return $0.gain > $1.gain }
            return Double($0.count + $0.gain) / Double(max(1, $0.needed)) > Double($1.count + $1.gain) / Double(max(1, $1.needed))
        }
    }

    /// How a species not caught yet comes (7.5): from the species it evolves from (`base`: its line's first), a fossil
    /// line's egg, a dungeon's boss alone (Arceus, R13), a legendary's or a mythical's eggs, else any egg.
    enum SpeciesSource: Equatable, Sendable {
        case evolves(from: Int, base: Int)
        case fossil, dungeon(DungeonID), legendary, mythical, egg
    }

    nonisolated static func source(of speciesID: Int) -> SpeciesSource {
        if let parent = PokemonEvolutionData.parents[speciesID] {
            var base = parent
            while let up = PokemonEvolutionData.parents[base] { base = up }
            return .evolves(from: parent, base: base)
        }
        if FossilDig.isFossilLine(speciesID) { return .fossil }
        if PokemonOdds.dungeonOnly.contains(speciesID),
           let dungeon = DungeonCatalog.all.first(where: { $0.bosses.contains(speciesID) }) {
            return .dungeon(dungeon.id)
        }
        if SpeciesGoal.mythicals.contains(speciesID) { return .mythical }
        if SpeciesGoal.legendaries.contains(speciesID) { return .legendary }
        return .egg
    }

    /// The goals not claimed yet a species not graduated counts for, the closest to done first: a gym badge's or the
    /// Legendary Egg's region, a stone or an artifact still locked.
    func goals(counting speciesID: Int) -> [ActiveGoal] {
        _ = state.dex.count   // observed even from the cache
        if goalsBySpecies == nil { goalsBySpecies = indexGoalsBySpecies() }
        return goalsBySpecies?[speciesID] ?? []
    }

    /// Every species not graduated with the goals it counts for, made once per state: a Pokédex page asks it for each
    /// of its silhouettes.
    private func indexGoalsBySpecies() -> [Int: [ActiveGoal]] {
        let registered = graduatedSpeciesIDs
        var index: [Int: [ActiveGoal]] = [:]
        func add(_ item: ItemKind, _ generation: Int?, _ progress: GoalProgress) {
            guard !progress.isMet else { return }
            let goal = ActiveGoal(item: item, generation: generation, gain: 1, count: progress.count,
                                  needed: progress.goal.needed)
            for id in progress.goal.species where !registered.contains(id) {
                // Any one goal unlocks a non-regional item: one entry per item.
                if generation == nil, index[id]?.contains(where: { $0.item == item }) == true { continue }
                index[id, default: []].append(goal)
            }
        }
        for kind in Self.achievementItems where kind != .excavation && !kind.isPlayMedal {
            if kind.isRegional {
                for tier in regionTiers(kind, registered: registered) where !tier.isDone {
                    add(kind, tier.generation, tier.progress)
                }
            } else if !isClaimed(kind), !isUnlocked(kind, registered: registered) {
                for progress in unlockProgress(of: kind, registered: registered) { add(kind, nil, progress) }
            }
        }
        return index.mapValues { goals in
            goals.sorted { Double($0.count) / Double(max(1, $0.needed)) > Double($1.count) / Double(max(1, $1.needed)) }
        }
    }

    /// The hint of the Home badge saying it brings something: what graduating it adds, and a costume it brings.
    var activeNewsHint: String {
        guard let news = activeNews else { return "" }
        if let mystery = news.mystery { return l.formMysteryHint(activeSpeciesName(mystery.revealSpeciesID), mystery) }
        let names = activeNewsNames
        return ([names.isEmpty ? nil : l.activeNewHint(names, certain: activeWays.count == 1), news.costume ? l.activeCostumeHint : nil,
                 news.newCostume ? l.activeNewCostumeHint : nil] as [String?])
            .compactMap { $0 }.joined(separator: " ")
    }

    /// The new species of `activeNews`, named in their form, for the badge's hint. Those never seen stay "???", like
    /// their silhouettes on the track.
    var activeNewsNames: [String] {
        guard let news = activeNews, let a = state.active else { return [] }
        let seen = graduatedSpeciesIDs.union(a.pathIDs.prefix(a.stageIndex + 1))
        let named = news.newSpecies.filter(seen.contains).map(activeSpeciesName)
        let unseen = news.newSpecies.contains { !seen.contains($0) }
        return named + (unseen ? ["???"] : []) + (news.firstShiny ? [l.activeFirstShiny] : [])
    }

    /// 시간순(과거 졸업분부터 현재 키우는 개체까지)으로 중복 포획된 개체들의 ID 집합.
    var duplicateCatchEntryIDs: Set<String> {
        var seenGraduatedSpecies = Set<DexSpeciesKey>()
        var duplicates = Set<String>()
        for e in entriesInCatchOrder {
            let reachedSpeciesSeen = e.chainOrder.allSatisfy { id in
                seenGraduatedSpecies.contains(DexSpeciesKey(speciesID: id, form: e.form))
            }

            if e.isReleased || isActiveDexEntry(e) {
                if hidesFormNews(e) { continue }
                let uncollected = hasUncollectedEvolutions(
                    from: e.finalID,
                    form: e.form,
                    collectedSpecies: seenGraduatedSpecies
                )
                // The one being raised still brings a costume while one is missing (`ActiveNews.costume`, `newCostume`).
                let bringsCostume = isActiveDexEntry(e) && (activeNews?.costume == true || activeNews?.newCostume == true)
                if reachedSpeciesSeen && !uncollected && !bringsCostume {
                    duplicates.insert(e.id)
                }
            } else {
                if reachedSpeciesSeen {
                    duplicates.insert(e.id)
                }
                for id in e.chainOrder {
                    seenGraduatedSpecies.insert(DexSpeciesKey(speciesID: id, form: e.form))
                }
            }
        }
        return duplicates
    }

    /// How many Pokédex records reached each species, whatever their form: the "×N" of its grid cell and the "Most
    /// caught" sort. The Pokémon being raised counts once it graduates or is sent off.
    var dexCatchCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for entry in state.dex {
            for id in Set(entry.chainOrder) { counts[id, default: 0] += 1 }
        }
        return counts
    }

    /// Each record's rank among the records that reached its species in its form, in catch order, the one being
    /// raised last: a duplicate's badge reads "Duplicate ×3" for the third.
    var dexCatchRanks: [String: Int] {
        var reached: [DexSpeciesKey: Int] = [:]
        var ranks: [String: Int] = [:]
        for e in entriesInCatchOrder {
            for id in Set(e.chainOrder) { reached[DexSpeciesKey(speciesID: id, form: e.form), default: 0] += 1 }
            ranks[e.id] = max(1, reached[DexSpeciesKey(speciesID: e.finalID, form: e.form)] ?? 0)
        }
        return ranks
    }

    /// What the one being raised would be among its species: its repeat badge's "×N".
    var activeCatchRank: Int? { activeDexEntry.flatMap { dexCatchRanks[$0.id] } }

    /// The records in the order they were caught, the oldest first and the one being raised last; records without a
    /// date (from before dates were kept) first, in their saved order.
    private var entriesInCatchOrder: [DexEntry] {
        let graduated = state.dex.enumerated().sorted { a, b in
            let d0 = a.element.caughtAt
            let d1 = b.element.caughtAt
            if let d0, let d1 {
                if d0 != d1 { return d0 < d1 }
            } else if d0 != nil, d1 == nil {
                return false
            } else if d0 == nil, d1 != nil {
                return true
            }
            return a.offset < b.offset
        }.map(\.element)

        return activeDexEntry.map { graduated + [$0] } ?? graduated
    }

    /// 포획 로그 표시 순서 — 현재 키우는 포켓몬을 맨 앞에 고정하고, 졸업 항목은 **기록 시각 최신순**.
    ///
    /// 과거에는 희귀도 내림차순이 먼저였다(종 단위 도감의 규칙). 로그는 시간순 기록이라 희귀도로
    /// 먼저 묶으면 방금 졸업한 개체가 며칠 전에 잡은 상위 희귀도 밑에 묻힌다. 희귀도로 좁히는 일은
    /// 이제 필터 캡슐과 도감이 담당한다.
    ///
    /// caughtAt 이 없는 구버전 항목은 .distantPast 로 묶여 맨 뒤에 온다(그들끼리의 순서는 미정).
    var dexEntriesSorted: [DexEntry] {
        let graduated = state.dex.sorted {
            ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast)
        }
        guard let activeDexEntry else { return graduated }
        return [activeDexEntry] + graduated
    }

    /// 희귀도별 포획 로그 개수(요약 헤더용) — 개체 수 기준. 도감(종 단위)은 dexSpecies 를 쓴다.
    func dexCount(_ rarity: Rarity) -> Int { dexEntries.lazy.filter { $0.rarity == rarity }.count }

    enum DexSortOption: String, CaseIterable, Identifiable, Sendable {
        case numberAsc
        case numberDesc
        case nameAsc
        case nameDesc
        case rarityDesc
        /// The most caught first (`dexCatchCounts`).
        case countDesc

        var id: String { rawValue }
    }

    enum CatchLogSortOption: String, CaseIterable, Identifiable, Sendable {
        case recentFirst
        case oldestFirst
        case numberAsc
        case numberDesc
        case nameAsc
        case nameDesc
        case rarityDesc
        /// The highest "Duplicate ×N" first, the number each card shows; then the species caught most, the latest first.
        case countDesc

        var id: String { rawValue }
    }

    /// 도감 한 칸 — 메인 목록은 종별, 폼이 있는 종의 상세 목록은 폼별로 중복 기록을 합친다.
    /// **종 정보만 담는다** — 성격·획득 횟수처럼 개체에 딸린 것은 포획 로그가 개체 단위로 보여준다.
    struct DexSpecies: Sendable {
        let id: Int                     // speciesID = 도감 번호(정렬 키)
        let name: String
        let rarity: Rarity
        let isShiny: Bool               // 이 종을 이로치로 보유한 적이 있는가
        /// 이 종이 현재 키우는 개체의 **현재 형태**인가. 지나온 진화 단계에는 서지 않는다.
        let isRaising: Bool
        var form: PokemonForm? = nil
        var names: [String: String]? = nil
        var hasNormal = false
        var baseID: Int = 0

        /// Species IDs remain Pokédex numbers; selection also includes the form.
        var collectionID: String {
            guard let form else { return String(id) }
            return "\(id)-\(form.rawValue)"
        }
    }

    private struct DexKey: Hashable {
        let speciesID: Int
        let form: PokemonForm?

        init(_ speciesID: Int, form: PokemonForm?, groupForms: Bool) {
            self.speciesID = speciesID
            self.form = groupForms ? PokemonForm.resolved(speciesID: speciesID, form: form) : nil
        }
    }

    struct DexSpeciesKey: Hashable {
        let speciesID: Int
        let form: PokemonForm?

        init(speciesID: Int, form: PokemonForm?) {
            self.speciesID = speciesID
            self.form = PokemonForm.resolved(speciesID: speciesID, form: form)
        }
    }

    /// Finals reachable from a species of a branching line (Wurmple, Eevee, Meowth, Applin...), for an
    /// individual of this form; nil for finals and outside branching lines. Derived from the evolution tree
    /// of every line (`PokemonEvolutionData`), form gates included: a Kanto Meowth only reaches Persian.
    static func branchingFinals(for speciesID: Int, form: PokemonForm? = nil) -> [Int]? {
        let open = form == nil ? (PokemonEvolutionData.children[speciesID] ?? [])
                               : PokemonEvolutionData.children(of: speciesID, form: form)
        guard !open.isEmpty,
              PokemonEvolutionData.finals(from: PokemonEvolutionData.root(of: speciesID)).count > 1 else { return nil }
        return PokemonEvolutionData.finals(from: speciesID, form: form)
    }

    private func hasUncollectedEvolutions(
        from speciesID: Int,
        form: PokemonForm?,
        collectedSpecies: Set<DexSpeciesKey>
    ) -> Bool {
        if let currentLine, (currentLine.baseID == speciesID || currentLine.tree.node(withID: speciesID) != nil) {
            let finals = currentLine.tree.node(withID: speciesID).map { Self.openFinals($0, form: form) }
                ?? currentLine.tree.finalIDs
            if finals.count > 1 || finals != [speciesID] {
                return finals.contains { finalID in
                    !collectedSpecies.contains(DexSpeciesKey(speciesID: finalID, form: form))
                }
            }
        }
        if let finals = Self.branchingFinals(for: speciesID, form: form) {
            return finals.contains { finalID in
                !collectedSpecies.contains(DexSpeciesKey(speciesID: finalID, form: form))
            }
        }
        return false
    }

    /// 종 하나가 모으는 것 — 누적 전용. 병렬 딕셔너리를 여러 개 두면 키 집합이 서로 어긋날 수 있고
    /// (한쪽에만 써서 그 종이 조용히 사라지거나), 읽는 쪽에 도달 불가한 기본값이 생긴다. 하나로 묶어
    /// 두 여지를 함께 없앤다.
    private struct DexAccumulator {
        /// 첫 발견 때 확정 — 같은 종은 항상 같은 base 라인에서 오므로 갱신할 값이 없다.
        let rarity: Rarity
        let baseID: Int
        var names: [String: String]?
        var isShiny = false
        var hasNormal = false
    }

    /// 도감 목록 — 보유 종만, 도감 번호 오름차순.
    ///
    /// 포함 종 = 졸업분 `chainOrder` ∪ 현재 개체의 **도달분** `pathIDs[0...stageIndex]`.
    /// `plannedPathIDs`(사전 선택된 전체 경로)는 미도달 단계를 포함하므로 절대 쓰지 않는다 — 쓰면
    /// 아직 진화하지 않은 종이 보유로 잡힌다.
    var dexSpecies: [DexSpecies] {
        collectedDexSpecies(groupForms: false)
    }

    /// Sprite → Pokédex detail link targets (species number → dex cell `collectionID`). Only species
    /// in the dex have a key, so eggs, unreached evolutions and uncaught species are not clickable.
    /// The main dex does not split forms (the form is picked on the detail page), so a
    /// species number maps to exactly one cell.
    var dexLinkTargets: [Int: String] {
        dexSpecies.reduce(into: [:]) { links, species in links[species.id] = species.collectionID }
    }

    /// The evolution family of a Pokédex species, for its page: what it evolves from, itself, then what it evolves
    /// into. Stages follow one another until one evolves several ways: those show side by side and the line stops
    /// there (each one's page goes on). Empty for a species that neither evolves nor evolves from anything.
    ///
    /// The family is seen in `form`, the page's: an Alolan Vulpix's leads to an Alolan Ninetales, a Galarian
    /// Meowth's to Perrserker. A species without forms that only one form evolves into (Perrserker, Clodsire)
    /// takes that form, so its Meowth is a Galarian one. The returned form is the one the line is drawn in.
    /// A species not caught in that form is `uncaught`: a silhouette that opens nothing.
    func dexFamily(speciesID: Int, form: PokemonForm?) -> (nodes: [EvoLineItem], form: PokemonForm?) {
        var lineForm = form
        if lineForm == nil, let gate = PokemonEvolutionData.formGates[speciesID], gate.forms.count == 1,
           let only = gate.forms.first {
            lineForm = PokemonForm(only)
        }
        func stage(_ id: Int) -> EvoLineItem {
            EvoLineItem(.species(id), state.ownsSpecies(id, form: lineForm) ? .done : .uncaught)
        }
        var ancestors: [Int] = []
        var id = speciesID
        while let parent = PokemonEvolutionData.parents[id] {
            ancestors.insert(parent, at: 0)
            id = parent
        }
        var nodes = ancestors.map(stage) + [EvoLineItem(.species(speciesID), .current)]
        var node = speciesID
        while true {
            let next = PokemonEvolutionData.children(of: node, form: lineForm)
            if next.count == 1 {
                nodes.append(stage(next[0]))
                node = next[0]
                continue
            }
            if next.count > 1 {
                nodes.append(EvoLineItem(.branch(next.map {
                    BranchEvolutionItem(speciesID: $0, isCollected: state.ownsSpecies($0, form: lineForm))
                }), .done))
            }
            break
        }
        return (nodes.count > 1 ? nodes : [], lineForm)
    }

    /// The species of a Pokédex page's family drawn shiny when the page shows its shiny look: each one caught shiny in
    /// the line's form, never the whole family because the page's species was (the owner, 2026-11-17: a shiny Eevee's
    /// page showed every Eeveelution shiny, none of them caught shiny).
    func dexFamilyShinies(_ family: (nodes: [EvoLineItem], form: PokemonForm?)) -> Set<Int> {
        let ids = family.nodes.flatMap { node -> [Int] in
            switch node.content {
            case .species(let id): [id]
            case .branch(let items): items.map(\.speciesID)
            case .mystery: []
            }
        }
        return Set(ids.filter { state.ownsShinySpecies($0, form: family.form) })
    }

    /// What a Pokédex species shows first, in its grid cell and when its page opens. Among the forms of a species
    /// that has them: a shiny form before a normal one (the representative's first), then the representative, then
    /// the first collected. A species without forms is itself. Either way, a species caught shiny shows shiny.
    func dexCover(for species: DexSpecies) -> DexSpecies {
        let forms = formSpecies(speciesID: species.id)
        guard let first = forms.first else { return species }
        let representative = forms.first { isRepresentative($0) }
        if let representative, representative.isShiny { return representative }
        return forms.first { $0.isShiny } ?? representative ?? first
    }

    /// Collected form summaries for the detail picker; missing forms remain visible but disabled.
    func formSpecies(speciesID: Int) -> [DexSpecies] {
        guard PokemonForm.hasForms(speciesID: speciesID) else { return [] }
        let owned = collectedDexSpecies(groupForms: true).filter { $0.id == speciesID }
        guard PokemonForm.unlockSource(speciesID: speciesID) != nil,
              let species = collectedDexSpecies(groupForms: false).first(where: { $0.id == speciesID }) else { return owned }
        // Arceus shows every form it has, hatched or unlocked by a Plate, with the same individuals and so the same
        // shininess (`CompanionState.ownsShinySpecies` agrees).
        return state.collectedForms(speciesID: speciesID)
            .sorted { PokemonForm.sortOrder($0, speciesID: speciesID) < PokemonForm.sortOrder($1, speciesID: speciesID) }
            .map { form in
                var entry = species
                entry.form = form
                return entry
            }
    }

    private func collectedDexSpecies(groupForms: Bool) -> [DexSpecies] {
        // Read what the result depends on even from the cache, so a view drawing it still observes them.
        let dex = state.dex
        let line = currentLine
        if let cached = dexSpeciesCache[groupForms] { return cached }
        let species = foldDexSpecies(dex, line: line, groupForms: groupForms)
        dexSpeciesCache[groupForms] = species
        return species
    }

    private func foldDexSpecies(_ dex: [DexEntry], line currentLine: EvoLine?, groupForms: Bool) -> [DexSpecies] {
        dexSpeciesFolds += 1
        // 종별 누적을 한 번에 훑는다.
        var acc: [DexKey: DexAccumulator] = [:]
        for entry in dex {
            for id in entry.chainOrder {
                let key = DexKey(id, form: entry.form, groupForms: groupForms)
                var a = acc[key] ?? DexAccumulator(rarity: entry.rarity, baseID: entry.baseID)
                if let n = entry.names?[id] { a.names = n }   // 이름 없는 구버전 항목이 덮어쓰지 않게
                if entry.isShiny { a.isShiny = true } else { a.hasNormal = true }
                acc[key] = a
            }
        }
        if let active = state.active {
            // 도달분만 — stageIndex 가 pathIDs 범위 안임은 두 입구가 보장한다:
            // MonState.init(from:) 의 clamp, 그리고 SaveTransfer 의 가져오기 정규화.
            for id in active.pathIDs.prefix(active.stageIndex + 1) {
                let key = DexKey(id, form: active.form, groupForms: groupForms)
                var a = acc[key] ?? DexAccumulator(rarity: active.rarity, baseID: active.baseID)
                if let n = currentLine?.names[id] { a.names = n }
                if currentIsShiny { a.isShiny = true } else { a.hasNormal = true }   // 위장 중 숨김 규칙 재사용
                acc[key] = a
            }
        }
        return acc.sorted {
            ($0.key.speciesID, PokemonForm.sortOrder($0.key.form, speciesID: $0.key.speciesID))
                < ($1.key.speciesID, PokemonForm.sortOrder($1.key.form, speciesID: $1.key.speciesID))
        }.map { key, a in
            let name = a.names.flatMap { state.language.resolveName($0) } ?? "#\(key.speciesID)"
            return DexSpecies(
                id: key.speciesID,
                name: groupForms ? formDisplayName(name, speciesID: key.speciesID, form: key.form) : name,
                rarity: a.rarity,
                isShiny: a.isShiny,
                isRaising: key.speciesID == state.active?.currentID && (!groupForms || key.form == currentForm),
                form: key.form,
                names: a.names,
                hasNormal: a.hasNormal,
                baseID: a.baseID)
        }
    }

    /// Resolves the primary localized name of an individual final species for sorting and display.
    func dexEntryName(_ entry: DexEntry) -> String {
        let targetID = entry.finalID
        if let stored = entry.names?[targetID], let localized = state.language.resolveName(stored) {
            return localized
        }
        for id in entry.chainOrder.reversed() {
            if let stored = entry.names?[id], let localized = state.language.resolveName(stored) {
                return localized
            }
        }
        return "#\(targetID)"
    }

    /// The one search rule shared by the Pokédex grid and the Catch Log, so the two screens cannot
    /// drift apart. A query matches a Pokédex number (`25` or `#25`) or part of any stored name
    /// in any language, ignoring case and diacritics ("flabebe" finds Flabébé).
    struct DexSearchMatcher: Sendable {
        let query: String
        let number: Int?

        /// `nil` for a blank query, which filters nothing out.
        init?(_ rawQuery: String) {
            let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            query = trimmed
            number = Int(trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed)
        }

        func matches(_ species: DexSpecies) -> Bool {
            matches(ids: [species.id], names: [species.name] + (species.names.map { Array($0.values) } ?? []))
        }

        func matches(speciesID: Int, names: [String: String]? = nil) -> Bool {
            matches(ids: [speciesID], names: names.map { Array($0.values) } ?? [])
        }

        /// An individual matches through any species of its chain, like its evolution line in the log row.
        func matches(_ entry: DexEntry) -> Bool {
            matches(ids: [entry.baseID, entry.finalID] + entry.chainOrder,
                    names: entry.names?.values.flatMap(\.values) ?? [])
        }

        private func matches(ids: [Int], names: [String]) -> Bool {
            if let number, ids.contains(number) { return true }
            // Partial numbers keep working: "25" also finds #125, "#25" finds #25 and #250.
            if ids.contains(where: { "#\($0)".contains(query) }) { return true }
            return names.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Groups related species IDs into evolution families based on entries' chainOrder,
    /// baseIDs, active companion, and branching finals.
    func evolutionFamilySpeciesIDs(for matcher: DexSearchMatcher) -> Set<Int> {
        var directSpeciesIDs = Set<Int>()
        for species in dexSpecies {
            if matcher.matches(species) {
                directSpeciesIDs.insert(species.id)
            }
        }
        for entry in dexEntries {
            if matcher.matches(entry) {
                directSpeciesIDs.insert(entry.baseID)
                directSpeciesIDs.insert(entry.finalID)
                directSpeciesIDs.formUnion(entry.chainOrder)
                if let names = entry.names {
                    for (speciesID, langMap) in names {
                        if matcher.matches(speciesID: speciesID, names: langMap) {
                            directSpeciesIDs.insert(speciesID)
                        }
                    }
                }
            }
        }
        if directSpeciesIDs.isEmpty {
            return []
        }

        var adj: [Int: Set<Int>] = [:]
        func connect(_ a: Int, _ b: Int) {
            adj[a, default: []].insert(b)
            adj[b, default: []].insert(a)
        }

        for entry in dexEntries {
            connect(entry.baseID, entry.finalID)
            for id in entry.chainOrder {
                connect(entry.baseID, id)
            }
            if let names = entry.names {
                for id in names.keys {
                    connect(entry.baseID, id)
                }
            }
        }
        for species in dexSpecies where species.baseID > 0 {
            connect(species.baseID, species.id)
        }
        if let active = state.active {
            for id in active.pathIDs {
                connect(active.baseID, id)
            }
            if let line = currentLine {
                for id in line.names.keys {
                    connect(active.baseID, id)
                }
            }
        }
        for (speciesID, _) in adj {
            if let finals = Self.branchingFinals(for: speciesID) {
                for finalID in finals {
                    connect(speciesID, finalID)
                }
            }
        }

        var familyIDs = Set<Int>()
        var queue = Array(directSpeciesIDs)
        var visited = directSpeciesIDs

        while !queue.isEmpty {
            let current = queue.removeFirst()
            familyIDs.insert(current)
            if let neighbors = adj[current] {
                for next in neighbors where !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }

        return familyIDs
    }

    // MARK: Favorites

    /// A species in the graduated Pokédex can be liked, a Charmander its Charizard went through too (the owner,
    /// 2026-11-18: by species).
    func canFavorite(speciesID: Int) -> Bool { graduatedSpeciesIDs.contains(speciesID) }

    func isFavorite(speciesID: Int) -> Bool { state.favoriteSpecies.contains(speciesID) }

    /// An individual shows under the ♥ filter when the species it graduated as is liked.
    func isFavorite(_ entry: DexEntry) -> Bool { !entry.isReleased && state.favoriteSpecies.contains(entry.finalID) }

    /// Likes a species, or unlikes it.
    func toggleFavorite(speciesID: Int) {
        guard canFavorite(speciesID: speciesID) || isFavorite(speciesID: speciesID) else { return }
        if state.favoriteSpecies.contains(speciesID) { state.favoriteSpecies.remove(speciesID) } else { state.favoriteSpecies.insert(speciesID) }
        save()
    }

    /// The species liked, and only those: the Pokédex's ♥ filter (the owner, 2026-11-18: no evolution along).
    var favoriteSpeciesIDs: Set<Int> { state.favoriteSpecies }

    /// Filters and sorts DexSpecies for the Pokédex grid.
    func filteredDexSpecies(
        query: String = "",
        rarity: Rarity? = nil,
        shinyOnly: Bool = false,
        favoritesOnly: Bool = false,
        evolutionFamily: Bool = false,
        sort: DexSortOption = .numberAsc
    ) -> [DexSpecies] {
        var result = dexSpecies
        if let rarity {
            result = result.filter { $0.rarity == rarity }
        }
        if shinyOnly {
            result = result.filter { $0.isShiny }
        }
        if favoritesOnly {
            let liked = favoriteSpeciesIDs
            result = result.filter { liked.contains($0.id) }
        }
        if let matcher = DexSearchMatcher(query) {
            if evolutionFamily {
                let matchingFamilySpeciesIDs = evolutionFamilySpeciesIDs(for: matcher)
                result = result.filter { matchingFamilySpeciesIDs.contains($0.id) }
            } else {
                result = result.filter { matcher.matches($0) }
            }
        }
        return sortDexSpecies(result, by: sort)
    }

    /// Sorts DexSpecies by the given option.
    func sortDexSpecies(_ species: [DexSpecies], by sort: DexSortOption) -> [DexSpecies] {
        switch sort {
        case .numberAsc:
            return species.sorted { $0.id < $1.id }
        case .numberDesc:
            return species.sorted { $0.id > $1.id }
        case .nameAsc:
            return species.sorted {
                let cmp = $0.name.localizedCompare($1.name)
                return cmp == .orderedAscending ? true : (cmp == .orderedSame ? $0.id < $1.id : false)
            }
        case .nameDesc:
            return species.sorted {
                let cmp = $0.name.localizedCompare($1.name)
                return cmp == .orderedDescending ? true : (cmp == .orderedSame ? $0.id < $1.id : false)
            }
        case .rarityDesc:
            return species.sorted {
                if $0.rarity.sortRank != $1.rarity.sortRank {
                    return $0.rarity.sortRank > $1.rarity.sortRank
                }
                return $0.id < $1.id
            }
        case .countDesc:
            let counts = dexCatchCounts
            return species.sorted {
                let c0 = counts[$0.id] ?? 0
                let c1 = counts[$1.id] ?? 0
                return c0 != c1 ? c0 > c1 : $0.id < $1.id
            }
        }
    }

    /// Filters and sorts DexEntry records for the Catch Log.
    func filteredDexEntries(
        query: String = "",
        rarity: Rarity? = nil,
        shinyOnly: Bool = false,
        favoritesOnly: Bool = false,
        evolutionFamily: Bool = false,
        sort: CatchLogSortOption = .recentFirst
    ) -> [DexEntry] {
        var result = dexEntries
        if let rarity {
            result = result.filter { $0.rarity == rarity }
        }
        if shinyOnly {
            result = result.filter { $0.isShiny }
        }
        if favoritesOnly {
            result = result.filter { isFavorite($0) }
        }
        if let matcher = DexSearchMatcher(query) {
            if evolutionFamily {
                let matchingFamilySpeciesIDs = evolutionFamilySpeciesIDs(for: matcher)
                result = result.filter { entry in
                    matchingFamilySpeciesIDs.contains(entry.baseID)
                        || matchingFamilySpeciesIDs.contains(entry.finalID)
                        || entry.chainOrder.contains(where: { matchingFamilySpeciesIDs.contains($0) })
                }
            } else {
                result = result.filter { matcher.matches($0) }
            }
        }
        return sortDexEntries(result, by: sort)
    }

    /// Sorts DexEntry records by the given option.
    func sortDexEntries(_ entries: [DexEntry], by sort: CatchLogSortOption) -> [DexEntry] {
        switch sort {
        case .recentFirst:
            let active = entries.first(where: { isActiveDexEntry($0) })
            let graduated = entries.filter { !isActiveDexEntry($0) }.sorted {
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
            return (active.map { [$0] } ?? []) + graduated
        case .oldestFirst:
            let active = entries.first(where: { isActiveDexEntry($0) })
            let graduated = entries.filter { !isActiveDexEntry($0) }.sorted {
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return $0.id < $1.id
            }
            return graduated + (active.map { [$0] } ?? [])
        case .countDesc:
            // By the number the card shows, its rank ("Duplicate ×7"): sorted by its species' count, which the records
            // that evolved past it raise, a Pidgey's ×7 came above a Seedot's ×9 (a player, 2026-11-05).
            let ranks = dexCatchRanks
            let counts = dexCatchCounts
            return entries.sorted {
                let r0 = ranks[$0.id] ?? 1
                let r1 = ranks[$1.id] ?? 1
                if r0 != r1 { return r0 > r1 }
                let c0 = counts[$0.finalID] ?? 0
                let c1 = counts[$1.finalID] ?? 0
                if c0 != c1 { return c0 > c1 }
                if $0.finalID != $1.finalID { return $0.finalID < $1.finalID }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        case .numberAsc:
            return entries.sorted {
                if $0.finalID != $1.finalID {
                    return $0.finalID < $1.finalID
                }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        case .numberDesc:
            return entries.sorted {
                if $0.finalID != $1.finalID {
                    return $0.finalID > $1.finalID
                }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        case .nameAsc:
            return entries.sorted {
                let name1 = dexEntryName($0)
                let name2 = dexEntryName($1)
                let cmp = name1.localizedCompare(name2)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        case .nameDesc:
            return entries.sorted {
                let name1 = dexEntryName($0)
                let name2 = dexEntryName($1)
                let cmp = name1.localizedCompare(name2)
                if cmp != .orderedSame {
                    return cmp == .orderedDescending
                }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        case .rarityDesc:
            return entries.sorted {
                if $0.rarity.sortRank != $1.rarity.sortRank {
                    return $0.rarity.sortRank > $1.rarity.sortRank
                }
                let d0 = $0.caughtAt ?? .distantPast
                let d1 = $1.caughtAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        }
    }

    /// Refresh legacy names once, including saves that retained only app-supported languages.
    ///
    /// 격자는 저장된 이름만 읽으므로 백필이 없으면 칸이 종 번호(`#41`)로 남는다. 포획 로그는 행이
    /// 뜰 때 행 단위로 같은 일을 해 왔지만, 로그를 한 번도 안 열면 격자는 계속 번호다.
    /// 라인 조회는 `PokeAPIClient` 가 base 단위로 캐시하므로 같은 라인이 여러 항목이어도 네트워크는 1회.
    /// 오프라인이면 `dexResolveChainNames` 가 저장 없이 폴백만 돌려주므로 다음 진입에서 다시 시도한다.
    func backfillMissingDexNames() async {
        var refreshed = false
        for entry in state.dex where entry.needsNamesRefresh {
            // 성공분만 내부에서 state.dex 에 반영. One save for the whole fill: a names upgrade wrote the whole save
            // once per line of the Pokédex.
            refreshed = await resolveChainNames(entry, saving: false).refreshed || refreshed
        }
        if refreshed { save() }
    }

    /// 도감 항목 진화 체인 각 종의 이름(speciesID → 현재 언어 이름). 저장돼 있으면 즉시(네트워크 0),
    /// 없으면 nil(뷰가 async 조회로 폴백).
    func dexStoredChainNames(_ entry: DexEntry) -> [Int: String]? {
        guard let names = entry.names, !names.isEmpty else { return nil }
        return names.compactMapValues { state.language.resolveName($0) }
    }

    /// Refresh missing/legacy multilingual names; current versions require no lookup.
    /// Offline, keep saved names and use species numbers only where no name is available.
    /// 반환은 chainOrder 전 종을 채운 [speciesID: 현재 언어 이름].
    private func dexNameLine(baseID: Int) async throws -> EvoLine {
        if let request = dexNameRequests[baseID] { return try await request.value }
        let provider = self.provider
        let request = Task { try await provider.line(baseSpeciesID: baseID) }
        dexNameRequests[baseID] = request
        defer { dexNameRequests[baseID] = nil }
        return try await request.value
    }

    func dexResolveChainNames(_ entry: DexEntry) async -> [Int: String] {
        await resolveChainNames(entry, saving: true).names
    }

    /// `refreshed`: the stored entries changed (and were saved when `saving`).
    private func resolveChainNames(_ entry: DexEntry, saving: Bool) async -> (names: [Int: String], refreshed: Bool) {
        // Another row of this evolution line may already have refreshed the stored entry.
        let entry = state.dex.first { $0.id == entry.id } ?? entry
        if !entry.needsNamesRefresh, let stored = dexStoredChainNames(entry) { return (stored, false) }
        let oldNames = dexStoredChainNames(entry) ?? [:]
        guard let line = try? await dexNameLine(baseID: entry.baseID) else {
            return (Dictionary(uniqueKeysWithValues: entry.chainOrder.map { ($0, oldNames[$0] ?? "#\($0)") }), false)
        }
        // Preserve usable older names if a response is partial. Only a complete chain gets
        // the new version, so partial/offline responses remain eligible for retry.
        func refreshed(_ original: DexEntry) -> DexEntry {
            var result = original
            var merged = original.names ?? [:]
            for id in original.chainOrder {
                if let incoming = line.names[id], !incoming.isEmpty {
                    merged[id] = (merged[id] ?? [:]).merging(incoming) { _, new in new }
                }
            }
            result.names = merged.isEmpty ? nil : merged
            if original.chainOrder.allSatisfy({ line.names[$0]?.isEmpty == false }) {
                result.namesVersion = DexEntry.currentNamesVersion
            }
            return result
        }
        // One successful lookup also refreshes duplicate catches of the same evolution line.
        var dex = state.dex
        for index in dex.indices where dex[index].baseID == entry.baseID && dex[index].needsNamesRefresh {
            dex[index] = refreshed(dex[index])
        }
        state.dex = dex   // one write for the line's entries, not one per entry
        if saving { save() }
        let chainNames = refreshed(entry).names ?? [:]
        return (Dictionary(uniqueKeysWithValues: entry.chainOrder.map { id in
            (id, chainNames[id].flatMap { state.language.resolveName($0) } ?? "#\(id)")
        }), true)
    }

    // MARK: 갱신 (AppDelegate 가 UsageStore 값으로 호출)

    /// One log line per provider and day's high, not one per refresh while a provider reads below it.
    @ObservationIgnored private var usageDropLog = LogRepeatSuppressor()

    func update(todayTokensByProvider: [String: Int], todayDate: String, monthTotal: Int,
                burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool) {
        let todayTokens = todayTokensByProvider.values.reduce(0, +)
        // `hasUsageData`는 표시용 snapshot 존재 여부이고, 이 map은 오늘 날짜가 확인된
        // provider 데이터만 담는다. stale snapshot이나 today == nil carrier만 있는 refresh는
        // ledger의 기준점을 움직일 수 있는 관측으로 취급하지 않는다.
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        if !state.installBaselineSet {
            // 설치 기준선 — 실제 데이터가 도착한 시점의 today 를 baseline 으로(이전 사용량 미카운트).
            // 데이터 도착 전(기동 직후 빈 새로고침)에는 잡지 않는다.
            guard hasCurrentProviderData else {
                // 세이브 불러오기가 baseline 판정을 이 경로에 넘겼을 수 있다(SaveTransfer.rebasedForThisDevice).
                // 그 경우 개체는 이미 들어와 있으므로 알로 표시하면 안 되고, 진화 라인 로드도 계속 재시도해야
                // 한다 — 새 Mac 은 AI CLI 를 처음 쓸 때까지 hasUsageData 가 false 라 여기서 막히면 그날 내내
                // 알로 보인다(재시작해도 동일).
                displayState = state.active == nil ? .egg : .idle
                kickLineLoadIfNeeded()
                return
            }
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
            save()
        } else {
            // `today == nil` carrier만 남거나 파싱이 실패한 refresh는 현재 map이 비어 있을 수
            // 있다. 그런 관측으로 날짜·ledger를 움직이면 다음 정상 snapshot을 당일 전체 신규
            // 사용량으로 오인할 수 있으므로, 유효한 사용량이 있는 refresh만 ledger를 갱신한다.
            if hasCurrentProviderData {
                let dateChanged = todayDate != state.lastDate
                if state.claimedTodayTokensByProvider == nil {
                    // 구버전 세이브에는 aggregate high-water mark만 있어 프로바이더별로 분해할 수 없다.
                    // 첫 유효 관측을 새 장부의 기준점으로만 저장해 과거 사용량을 소급 지급하지 않는다.
                    state.claimedTodayTokensByProvider = todayTokensByProvider
                    state.lastDate = todayDate
                    AppLog.write("companion provider ledger seeded date=\(todayDate) providers=\(todayTokensByProvider.keys.sorted().joined(separator: ","))")
                } else if Self.isEarlierDay(todayDate, than: state.lastDate) {
                    // The day went back (a time zone to the west after midnight, the clock set back): that day was
                    // credited already, and crediting its whole total as a new day counted it twice. Nothing is
                    // credited until the date is past again; the ledger waits as it is.
                    AppLog.write("companion usage: date went back \(state.lastDate) → \(todayDate), nothing credited")
                } else if dateChanged {
                    // 일자별 snapshot은 서로 비교할 수 없다. 새 날짜에는 이전 날짜의 ledger를
                    // 기준으로 삼지 않고, 현재 날짜의 누적값 전체를 새 날짜 사용량으로 적립한다.
                    // 단, 위의 nil migration 경로는 구버전 aggregate를 분해할 수 없으므로 seed만 한다.
                    //
                    // 이전 날짜에 이미 알려진 provider가 첫 새로고침에서 빠질 수 있다(오늘 데이터
                    // 없음, stale 응답, 일시 실패). 그 provider를 아예 ledger에서 제거하면 같은
                    // 날짜에 복구될 때 현재 누적값을 "이미 적립한 값"으로 seed해 사용량이 누락된다.
                    // 이전 날짜의 숫자는 비교에 사용할 수 없으므로, 알려진 provider의 새 날짜 기준을
                    // 0으로 열어 둔다. 이후 복구된 현재 날짜 값은 그 날짜의 실제 사용량으로 적립되고,
                    // 같은 날짜의 부분 응답에서는 이 기준을 그대로 보존한다.
                    state.lastDate = todayDate
                    var newLedger = Dictionary(uniqueKeysWithValues:
                        state.claimedTodayTokensByProvider!.keys.map { ($0, 0) })
                    for (providerID, current) in todayTokensByProvider {
                        newLedger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = newLedger
                    let delta = todayTokensByProvider.values.reduce(0, +)
                    earnTokenCandies(todayTokensByProvider)
                    earnCostumeEggs(delta, day: todayDate)
                    recordRaising(todayTokensByProvider)
                    if delta > 0 {
                        state.usedSinceInstall += delta
                        creditGrowth(delta)
                    }
                } else {
                    var ledger = state.claimedTodayTokensByProvider ?? [:]
                    var delta = 0
                    var deltas: [String: Int] = [:]
                    for (providerID, current) in todayTokensByProvider {
                        guard let previous = ledger[providerID] else {
                            // 새로 관측된 프로바이더의 과거 로그를 소급하지 않는다. 이후 refresh부터
                            // 해당 프로바이더의 증가분을 추적할 수 있도록 현재 값을 seed한다.
                            ledger[providerID] = current
                            continue
                        }
                        if current < previous {
                            // The ledger keeps the day's high: only what goes past it is credited. Rebased on the
                            // lower total, a dip and its recovery were credited twice (Cursor falls back from its
                            // API to a lower local estimate, then back). Only this provider's line is concerned.
                            if usageDropLog.shouldWrite(key: "usage-drop-\(providerID)",
                                                        message: "\(todayDate) \(previous)",
                                                        now: clock(), repeatAfter: 3600) {
                                AppLog.write("companion usage: provider=\(providerID) date=\(todayDate) below the day's high (\(current) < \(previous)), credited past the high only")
                            }
                            continue
                        }
                        delta += current - previous
                        deltas[providerID] = current - previous
                        ledger[providerID] = current
                    }
                    // Only a change is written: `state` is observed whole, and an equal write still redrew every
                    // screen open at each refresh.
                    if state.claimedTodayTokensByProvider != ledger { state.claimedTodayTokensByProvider = ledger }
                    earnTokenCandies(deltas)
                    earnCostumeEggs(delta, day: todayDate)
                    recordRaising(deltas)
                    if delta > 0 {
                        state.usedSinceInstall += delta
                        creditGrowth(delta)   // 알 인큐베이션 누적, or the Pokémon's growth, or a dungeon's walk
                    }
                }
            }
        }
        // 이벤트(진화/졸업/부화) 창 만료 — .levelUp 창이 끝날 때 문구 플래그를 함께 정리한다.
        // justEvolvedTo 는 여기(창 만료)에서만 지운다: 과거엔 매 update() 초입에 무조건 nil 로 밀어,
        // 진화 후 4초 창 도중 update 틱이 끼면 "…(으)로 진화했어요"→"성장했어요"로 되돌아갔다(회귀 #4).
        if let until = eventUntil, clock() > until {
            justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        }
        if state.active == nil, state.installBaselineSet, !isHatching {
            if state.eggUsage >= eggHatchThreshold {
                // ready egg 는 부화를 우선한다. 같은 틱에 프리패치와 별도 Task 로 경쟁시키면
                // 프리패치 락을 본 부화가 반환하고 실패 상태도 놓칠 수 있다.
                Task { await hatchIfNeeded() }
            } else {
                // 임계 전에는 종 pre-roll + 라인/스프라이트 예열(부화 순간 딜레이 제거).
                Task { await ensureEggPrefetch() }
            }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        // 위장 메타몽이 첫 진화 임계 도달 → 리빌(재시작 등 applyUsage 킥을 못 탄 경우 백업 트리거)
        if let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, currentLine != nil,
           !isHatching, !isRevealingDitto,
           a.usedAtStage >= stageThreshold(for: a) {
            Task { await revealDitto() }
        }
        let nextDisplayState = computeState(burnTier: burnTier, limitWarning: limitWarning,
                                            hasUsageData: hasUsageData, today: todayTokens)
        if displayState != nextDisplayState { displayState = nextDisplayState }
        announceBirthdayGiftIfNeeded()
        announceEventEggsIfNeeded()
        saveUsage()
        autoSnapshotIfNeeded()
    }

    /// 토큰 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    /// 라인 미로딩(재시작 직후·오프라인)이어도 사용량은 항상 적립한다 — 여기서 드롭하면
    /// 프로바이더별 ledger 는 이미 전진해 델타가 영구 유실된다. 진화 판정만 라인 로드 후로 미룬다.
    func applyUsage(_ delta: Int, isTokenUsage: Bool = true) {
        guard state.active != nil else { return }
        var growthDelta = delta
        let tokenBonus = Self.bonusSum(tokenGrowthFactors)
        if isTokenUsage, tokenBonus > 0, let mon = state.active {
            // The threshold is already divided by the other bonuses. The token items add theirs to that sum:
            // a token counts (1 + every bonus) / (1 + threshold bonuses), and a Rare Candy keeps the latter only.
            let thresholdSpeed = 1 + Self.bonusSum(thresholdGrowthFactors(for: mon))
            growthDelta = Int(Double(delta) * (thresholdSpeed + tokenBonus) / thresholdSpeed)
        }
        state.active!.usedAtStage += growthDelta
        reconcileActiveProfileGrowth()
        // Tokens' growth waits with the usage writes; a Rare Candy's is written at once.
        guard let line = currentLine else { return isTokenUsage ? saveUsage() : save() }
        // An evolution or a graduation is written at once; tokens' growth alone waits with the usage writes.
        var staged = false
        var guardCount = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            let thr = stageThreshold(for: a)
            guard a.usedAtStage >= thr else { break }
            guard let node = line.tree.node(withID: a.currentID) else { break }
            // 위장체는 부화 때는 다형태지만, 에셋 정규화/마이그레이션 뒤 leaf가 될 수 있다.
            // 따라서 terminal 졸업보다 먼저 리빌해야 위장 종이 도감으로 잘못 졸업하지 않는다.
            if a.dittoDisguise != nil, !a.dittoRevealed {
                if !isRevealingDitto { Task { await revealDitto() } }
                break
            }
            // A species none of whose evolutions this form can take is final for it (a Kanto Farfetch'd).
            if Self.openChildren(node, form: a.form).isEmpty {
                graduate(); staged = true; break
            } else {
                let nextIndex = a.stageIndex + 1
                let next: EvoNode
                if a.plannedPathIDs.indices.contains(nextIndex),
                   let planned = node.children.first(where: { $0.speciesID == a.plannedPathIDs[nextIndex] }) {
                    next = planned
                } else if let picked = pickPlannedChild(node, baseID: a.baseID, form: a.form) {
                    next = picked
                    let fallbackRoute = [node.speciesID] + makeEvolutionPlan(from: next, baseID: a.baseID, form: a.form)
                    let repaired = Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex,
                                                     fallbackRoute: fallbackRoute)
                    state.active!.plannedPathIDs = repaired
                    state.active!.totalForms = repaired.count
                    AppLog.write("evolve: repaired invalid planned path for base \(a.baseID)")
                } else {
                    graduate(); staged = true; break
                }
                staged = true
                let wasMystery = activeNews?.mystery != nil
                // Evolving into a legendary (Solgaleo) wins its Memories; into Silvally, the forms they unlock.
                let unlockedForms = itemFormSnapshot()
                state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
                state.active!.stageIndex += 1
                announceFormUnlocks(since: unlockedForms)
                if next.speciesID == PikachuCostume.speciesID { grantPikachuCostume() }
                state.active!.usedAtStage = a.usedAtStage - thr   // 초과분 이월
                if let details = pokemonDetails(speciesID: next.speciesID, form: a.form) {
                    state.active!.profile?.enrich(with: details)
                } else if detailProvider != nil {
                    Task { await self.loadPokemonDetails(speciesID: next.speciesID, form: a.form) }
                }
                let newName = formDisplayName(line.localizedName(next.speciesID, state.language),
                                              speciesID: next.speciesID, form: a.form)
                let body = evolutionBody(newName, wasMystery: wasMystery)
                justEvolvedTo = newName
                justRevealedForm = formReveal(wasMystery: wasMystery)
                fireCelebration(.evolve)
                // 짧은 levelUp 창 — 진화 순간 "…(으)로 진화했어요" 문구 노출(hatch/graduate 와 동일 패턴).
                // 이게 없으면 computeState 가 .levelUp 을 안 내 statusEvolved 가 도달 불가(dead code)였다.
                eventUntil = clock().addingTimeInterval(4)
                notifyCompanionEvent(l.notifEvolveTitle, body)
            }
        }
        reconcileActiveProfileGrowth()
        // Every live read used to write the whole save here, its line loaded: 1.5 MB every few seconds while tokens
        // flowed (#182).
        if isTokenUsage, !staged { saveUsage() } else { save() }
    }

    /// What the menu bar tells of the next stage, or of the hatch: nothing while a form is a mystery (`hidesGrowthAmounts`).
    var menuTokensToNext: Int? { hasActive ? (hidesGrowthAmounts ? nil : tokensToNext) : eggTokensToHatch }

    /// Home's line just after an evolution, the reveal of a form included.
    var evolvedStatus: String? {
        justEvolvedTo.map { [l.statusEvolved($0), justRevealedForm].compactMap { $0 }.joined(separator: " ") }
    }

    /// What the stage that shows a form still a mystery says of that form.
    private func formReveal(wasMystery: Bool) -> String? {
        guard wasMystery, formSuspense == nil, let news = activeNews else { return nil }
        return news.isDuplicate ? l.formRevealNothingNew : l.formRevealBringsNew
    }

    /// The evolution's message, the reveal of a form included.
    func evolutionBody(_ name: String, wasMystery: Bool) -> String {
        [l.notifEvolveBody(name), formReveal(wasMystery: wasMystery)].compactMap { $0 }.joined(separator: " ")
    }

    /// Whether this evolution graduated already, what the evolution plan avoids and Home's track shows as had: neither
    /// a Pokémon sent off nor the one being raised, as the goals count (a Vaporeon sent off leaves Vaporeon to find).
    /// A species with forms is had in this individual's form only (`form`, its line form): a Kanto Slowbro made a
    /// Galarian Slowpoke's Slowbro had, so the plan made a Galarian Slowbro again while Galarian Slowking was missing,
    /// and Home showed it caught. `collectedFinals` keeps no form, so it only answers for a species without forms.
    func isEvolutionCollected(speciesID: Int, baseID: Int, form: PokemonForm? = nil) -> Bool {
        let speciesForm = PokemonForm.resolved(speciesID: speciesID, form: form)
        if speciesForm == nil, state.collectedFinals.contains("\(baseID):\(speciesID)") { return true }
        return state.dex.contains {
            !$0.isReleased && ($0.finalID == speciesID || $0.chainOrder.contains(speciesID))
                && (speciesForm == nil || PokemonForm.resolved(speciesID: speciesID, form: $0.form) == speciesForm)
        }
    }

    /// 분기 노드의 모든 최종체가 이미 수집되었는지 여부. (단일 진화 종인 경우 해당 종 자체의 수집 여부)
    func isBranchNodeCollected(_ node: EvoNode, baseID: Int, form: PokemonForm?) -> Bool {
        Self.openFinals(node, form: form).allSatisfy { isEvolutionCollected(speciesID: $0, baseID: baseID, form: form) }
    }

    /// The evolutions of a node open to an individual of this form (`PokemonEvolutionData.formGates`).
    static func openChildren(_ node: EvoNode, form: PokemonForm?) -> [EvoNode] {
        node.children.filter { PokemonEvolutionData.allows($0.speciesID, from: node.speciesID, form: form) }
    }

    /// Finals an individual of this form can reach from a node of its loaded tree.
    static func openFinals(_ node: EvoNode, form: PokemonForm?) -> [Int] {
        let open = openChildren(node, form: form)
        return open.isEmpty ? [node.speciesID] : open.flatMap { openFinals($0, form: form) }
    }

    /// 분기 진화 anti-duplicate: 미수집 분기가 있으면 이미 획득한 진화는 배제하고 미수집 분기 중에서만 추첨.
    /// 모든 분기를 전부 획득한 경우에만 전체 풀에서 무작위 선택.
    private func pickPlannedChild(_ node: EvoNode, baseID: Int, form: PokemonForm?) -> EvoNode? {
        let open = Self.openChildren(node, form: form)
        guard !open.isEmpty else { return nil }
        let uncollected = open.filter { !isBranchNodeCollected($0, baseID: baseID, form: form) }
        let pool = uncollected.isEmpty ? open : uncollected
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    /// Plans the evolutions an individual will take, among those open to its form: a Kanto Farfetch'd stays
    /// a Farfetch'd, a Galarian one becomes Sirfetch'd.
    private func makeEvolutionPlan(from root: EvoNode, baseID: Int, form: PokemonForm?) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while let next = pickPlannedChild(node, baseID: baseID, form: form) {
            plan.append(next.speciesID)
            node = next
        }
        return plan
    }

    /// Whether every step of a plan is open to this form.
    static func planFollowsForm(_ plan: [Int], form: PokemonForm?) -> Bool {
        zip(plan, plan.dropFirst()).allSatisfy { PokemonEvolutionData.allows($1, from: $0, form: form) }
    }

    static func repairedPlan(realizedPath: [Int], stageIndex: Int, fallbackRoute: [Int]) -> [Int] {
        guard !realizedPath.isEmpty else { return fallbackRoute }
        let currentIndex = min(stageIndex, realizedPath.count - 1)
        let prefix = Array(realizedPath.prefix(currentIndex + 1))
        guard fallbackRoute.first == prefix.last else { return prefix }
        return prefix + fallbackRoute.dropFirst()
    }

    /// 루트부터 실제로 이어지는 가장 긴 ID 경로와 마지막 유효 노드. 첫 ID가 루트와 다르면 루트로 복구한다.
    private func longestValidPath(_ ids: [Int], from root: EvoNode) -> (path: [Int], lastNode: EvoNode) {
        var path = [root.speciesID]
        var node = root
        guard ids.first == root.speciesID else { return (path, node) }
        for id in ids.dropFirst() {
            guard let child = node.children.first(where: { $0.speciesID == id }) else { break }
            path.append(id)
            node = child
        }
        return (path, node)
    }

    /// 저장된 실제 경로와 계획을 현재 에셋 트리에 맞춘다. 완전한 계획만 재사용해 재시작 시 RNG를 소비하지 않는다.
    private func normalizedEvolutionState(_ saved: MonState, from root: EvoNode) -> MonState {
        var normalized = saved
        let realized = longestValidPath(saved.pathIDs, from: root)
        let candidate = longestValidPath(saved.plannedPathIDs, from: root)
        let canReusePlan = candidate.path == saved.plannedPathIDs
            && candidate.path.starts(with: realized.path)
            && Self.openChildren(candidate.lastNode, form: saved.form).isEmpty
            && Self.planFollowsForm(candidate.path, form: saved.form)
        let plan: [Int]
        if canReusePlan {
            plan = candidate.path
        } else {
            let suffix = makeEvolutionPlan(from: realized.lastNode, baseID: saved.baseID, form: saved.form)
            plan = realized.path + suffix.dropFirst()
        }
        normalized.pathIDs = realized.path
        normalized.plannedPathIDs = plan
        normalized.stageIndex = realized.path.count - 1
        normalized.totalForms = plan.count
        return normalized
    }

    private func graduate() {
        guard var a = state.active else { return }
        a.profile?.advanceGrowth(to: PokemonBalance.graduationTotal(a.rarity), rarity: a.rarity)
        if let details = pokemonDetails(speciesID: a.currentID, form: a.form) { a.profile?.enrich(with: details) }
        let finalID = a.currentID
        // The Rotom Catalog pays for a form the line never graduated, when it graduates: paid at the hatch, a form
        // sent off before graduating paid again each time it hatched (#91). Any graduated record of the line in that
        // form counts: `graduatedLineForms` wants every species of the line in it, and a Kanto Slowking paid after a
        // Kanto Slowbro. A revealed Ditto has no form.
        if itemCount(.rotomCatalog) > 0, let form = PokemonForm.resolved(baseID: a.baseID, form: a.form),
           !state.dex.contains(where: { !$0.isReleased && $0.baseID == a.baseID
               && PokemonForm.resolved(baseID: $0.baseID, form: $0.form) == form }) {
            let received = addRareCandies(CollectorBonus.rotomCatalogNewFormCandies)
            AppLog.write("graduate: rotom catalog +\(received) candy for a new form")
        }
        state.collectedFinals.insert("\(a.baseID):\(finalID)")
        state.dex.append(DexEntry(id: a.profile?.instanceID ?? UUID().uuidString,
                                  baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                                  isShiny: a.isShiny, nature: a.nature,
                                  profile: a.profile,
                                  names: currentLine.map { line in   // 체인 각 종의 다국어 이름 저장(표시 즉시)
                                      Dictionary(uniqueKeysWithValues:
                                          a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                                  }, form: a.form, hasNewForm: a.hasNewForm).withRecords(of: a))
        // Not for a Common: one candy is a whole Common line's XP (`RareCandy.xp`), so each one graduated paid the next
        // and Commons graduated for free, one egg apart.
        if ownsReinsOfUnity, a.rarity != .common {
            let received = addRareCandies(CollectorBonus.reinsOfUnityCandies)
            AppLog.write("graduate: reins of unity +\(received) rare candy")
        }
        if itemCount(.explorerKit) > 0 { digTreasureIfDue() }
        let name = formDisplayName(currentLine?.localizedName(finalID, state.language) ?? "",
                                   speciesID: finalID, form: a.form)
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        state.active = nil
        state.reconcileRepresentativeSelection()   // 졸업 체인이 dex 로 옮겨져 선택은 정상적으로 유지된다
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0   // 새 알은 처음부터 인큐베이션
        isHatchRetryDelayed = false
        // eggTier 는 손대지 않는다 — 여기 도달했다는 건 활성 포켓몬이 있었다는 뜻이라 보증은 이미 nil 이다
        // (부화가 소비, 디스크/불러오기는 sanitized 가 정규화). 소비 지점은 hatchCore 한 곳으로 유지한다.
        // "알을 받는 순간" 즉시 프리패칭 시작 — 다음 부화의 종·라인·스프라이트 예열.
        Task { await self.ensureEggPrefetch() }
    }

    // MARK: 인벤토리 / 이상한 사탕

    var rareCandyCount: Int { itemCount(.rareCandy) }
    func itemCount(_ kind: ItemKind) -> Int { state.inventory[kind.rawValue] ?? 0 }
    /// 이로치 부적 보유 여부 — 보유형이라 개수>0 = 소유(부화 shiny 분모를 낮춘다).
    var ownsShinyCharm: Bool { itemCount(.shinyCharm) > 0 }
    var ownsLegendCharm: Bool { itemCount(.legendCharm) > 0 }
    var ownsSilverWing: Bool { itemCount(.silverWing) > 0 }
    var ownsOldSeaMap: Bool { itemCount(.oldSeaMap) > 0 }
    var ownsClearBell: Bool { itemCount(.clearBell) > 0 }
    var ownsRainbowWing: Bool { itemCount(.rainbowWing) > 0 }
    var ownsMagmaStone: Bool { itemCount(.magmaStone) > 0 }
    var ownsSoulDew: Bool { itemCount(.soulDew) > 0 }
    var ownsJadeOrb: Bool { itemCount(.jadeOrb) > 0 }
    var ownsGracidea: Bool { itemCount(.gracidea) > 0 }
    var ownsGriseousOrb: Bool { itemCount(.griseousOrb) > 0 }
    var ownsLibertyPass: Bool { itemCount(.libertyPass) > 0 }
    var ownsRevealGlass: Bool { itemCount(.revealGlass) > 0 }
    var ownsDnaSplicers: Bool { itemCount(.dnaSplicers) > 0 }
    var ownsZygardeCube: Bool { itemCount(.zygardeCube) > 0 }
    var ownsPrisonBottle: Bool { itemCount(.prisonBottle) > 0 }
    var ownsSparklingStone: Bool { itemCount(.sparklingStone) > 0 }
    var ownsSunFlute: Bool { itemCount(.sunFlute) > 0 }
    var ownsBeastBall: Bool { itemCount(.beastBall) > 0 }
    var ownsRustedSword: Bool { itemCount(.rustedSword) > 0 }
    var ownsReinsOfUnity: Bool { itemCount(.reinsOfUnity) > 0 }
    var ownsBoosterEnergy: Bool { itemCount(.boosterEnergy) > 0 }
    var ownsTealMask: Bool { itemCount(.tealMask) > 0 }
    var ownsTeraOrb: Bool { itemCount(.teraOrb) > 0 }
    var ownsRelicStatue: Bool { itemCount(.relicStatue) > 0 }
    var ownsOvalCharm: Bool { itemCount(.ovalCharm) > 0 }
    var ownsGlimmeringCharm: Bool { itemCount(.glimmeringCharm) > 0 }

    /// Zygarde Cube: +1% token growth EXP per 25 graduated species, up to +40%. Graduated, as achievements count:
    /// a Pokémon raised then sent off stays in the Pokédex but never graduated.
    var zygardeCubeMultiplier: Double {
        let percent = min(CollectorBonus.zygardeMaxPercent,
                          graduatedSpeciesIDs.count / CollectorBonus.zygardeSpeciesPerPercent)
        return 1 + Double(percent) / 100
    }

    /// Regional tiers claimed across the badges this species is weak to (Normal badges count for Normal types).
    func ownedBadgeTierCount(weakAgainst speciesID: Int, form: PokemonForm?) -> Int {
        PokemonType.allCases.reduce(0) { count, type in
            PokemonTypeData.isWeak(to: type, speciesID: speciesID, form: form) ? count + claimedBadgeTierCount(type) : count
        }
    }

    /// Growth speed from badges: +2.5% per claimed regional tier of each badge the species is weak to,
    /// cumulative. Growth only: badges never touch the hatch odds.
    func typeBadgeSpeedMultiplier(forSpeciesID speciesID: Int, form: PokemonForm?) -> Double {
        1.0 + CollectorBonus.badgeRegionBonus * Double(ownedBadgeTierCount(weakAgainst: speciesID, form: form))
    }

    /// Regional tiers of this type's badge already claimed.
    func claimedBadgeTierCount(_ type: PokemonType) -> Int {
        PokemonTypeData.badgeGenerations(for: type).filter { isRegionTierClaimed(type.badgeItem, generation: $0) }.count
    }

    /// 소유 아이템(개수>0): 가방 목록.
    /// Consumables first (candies, mints, stones), then passive items, each in `ItemKind` order.
    var ownedItems: [(kind: ItemKind, count: Int)] {
        let owned: [(kind: ItemKind, count: Int)] = ItemKind.allCases.compactMap { k in
            let c = itemCount(k)
            return c > 0 && !k.isRetired ? (k, c) : nil
        }
        return owned.filter { !$0.kind.isPassive } + owned.filter { $0.kind.isPassive }
    }

    /// 이상한 사탕 사용 가능 — 활성 포켓몬 + 라인 로딩 완료 + 재고>0.
    /// 라인 미로딩(재시작 직후·오프라인)이면 비활성 — 사탕이 진화 없이 적립만 되는 것 방지.
    var canUseRareCandy: Bool { maxRareCandyUseCount > 0 }

    /// Use the same rounded, difficulty-adjusted thresholds as actual growth.
    /// Preview the apparent evolution path so hidden identities cannot change the picker.
    private var rareCandyStageCosts: [Int] {
        guard var mon = state.active, currentLine != nil else { return [] }
        if mon.dittoDisguise != nil && !mon.dittoRevealed && mon.usedAtStage >= stageThreshold(for: mon) {
            // The accepted batch is already saved. Wait for the reveal before accepting another.
            return []
        }
        return (mon.stageIndex..<mon.totalForms).map { stage in
            mon.stageIndex = stage
            return stageThreshold(for: mon)
        }
    }

    /// EXP one Rare Candy gives now: the Soul Dew adds 50%. Planning and use both read this value.
    var rareCandyXP: Int { ownsSoulDew ? RareCandy.xp * 3 / 2 : RareCandy.xp }

    /// The odds a shiny hatch's notification tells: none with the Glimmering Charm, which makes every hatch shiny.
    func shinyHatchNotificationOdds(_ denominator: UInt64) -> UInt64? { ownsGlimmeringCharm ? nil : denominator }

    /// The growth the Pokémon being raised still needs to graduate, as Rare Candies count it.
    var growthToGraduation: Int { max(0, rareCandyStageCosts.reduce(0, +) - (state.active?.usedAtStage ?? 0)) }

    var maxRareCandyUseCount: Int {
        // Its growth pauses while a team explores: candies too, until it is back (the owner, 2026-11-05).
        guard expedition == nil else { return 0 }
        let remaining = growthToGraduation
        let xp = rareCandyXP
        let needed = remaining / xp + (remaining % xp == 0 ? 0 : 1)
        return min(rareCandyCount, needed)
    }

    struct RareCandyUsePlan {
        let count: Int
        let xpPerCandy: Int
        var xp: Int { count * xpPerCandy }
        let evolves: Bool
        let graduates: Bool
        let carryoverXP: Int
        let discardedXP: Int
    }

    func planRareCandyUse(count requested: Int) -> RareCandyUsePlan? {
        let count = min(max(0, requested), maxRareCandyUseCount)
        guard count > 0, let mon = state.active else { return nil }
        let costs = rareCandyStageCosts
        let xpPerCandy = rareCandyXP
        var remaining = mon.usedAtStage + count * xpPerCandy
        var evolves = false
        for (index, cost) in costs.enumerated() {
            guard remaining >= cost else { break }
            remaining -= cost
            if index == costs.count - 1 {
                return RareCandyUsePlan(count: count, xpPerCandy: xpPerCandy, evolves: evolves, graduates: true,
                                       carryoverXP: 0, discardedXP: remaining)
            }
            evolves = true
        }
        return RareCandyUsePlan(count: count, xpPerCandy: xpPerCandy, evolves: evolves, graduates: false,
                               carryoverXP: evolves ? remaining : 0, discardedXP: 0)
    }

    /// 사탕 사용 결과 — UI 피드백 분기용.
    enum CandyUseResult: Equatable { case evolved, graduated, progressed, unavailable }

    /// Spend only the candies needed by the current growth plan, preserving unused inventory.
    /// 사탕 XP 는 usedAtStage(진화 진행)에만 반영 — usedSinceInstall/오늘 토큰(실사용 통계)엔 안 잡힌다.
    @discardableResult
    func useRareCandy(count: Int = 1) -> CandyUseResult {
        guard let preview = planRareCandyUse(count: count) else { return .unavailable }
        var consumed = preview.count
        if let mon = state.active, mon.dittoDisguise != nil && !mon.dittoRevealed {
            // Keep the picker indistinguishable from the apparent Pokémon, but preserve whole
            // candies beyond the surprise reveal. Only the last consumed candy's XP carries over.
            let remaining = max(0, stageThreshold(for: mon) - mon.usedAtStage)
            let needed = remaining / preview.xpPerCandy + (remaining % preview.xpPerCandy == 0 ? 0 : 1)
            consumed = min(consumed, needed)
        }
        let xp = consumed * preview.xpPerCandy
        // Every candy used gives its XP; the Shock Drive recharges one in four, which stays in the Bag.
        let recharged = itemCount(.shockDrive) > 0
            ? (0..<consumed).filter { _ in CollectorBonus.shockDriveRecharges(roll: rng.next()) }.count : 0
        if recharged > 0 { AppLog.write("rare candy: shock drive recharged \(recharged) of \(consumed)") }
        state.inventory[ItemKind.rareCandy.rawValue] = rareCandyCount - (consumed - recharged)
        state.active?.raising?.candiesUsed += consumed
        candyFeedbackRecharged = recharged
        let beforeStage = state.active?.stageIndex ?? 0
        // 진화 안 될 때(부분 진행)도 즉시 "+XP" 피드백 — CompanionHeader 가 연출과 별개로 표시.
        candyFeedbackAmount = xp
        candyFeedbackSeq += 1
        // Saves inventory and growth together. Candy XP is not token usage: no growth item multiplies it twice.
        applyUsage(xp, isTokenUsage: false)
        if state.active == nil { return .graduated }
        if state.active!.stageIndex > beforeStage { return .evolved }
        return .progressed
    }

    // MARK: Mints (a graduated Pokémon's nature, at random)

    /// The graduated Pokémon a Mint can change: every one kept, never the Pokémon raised (the owner, 2026-11-09: "sur
    /// tous les pokémon comme les capsules, pas sur celui qui se diplôme").
    var mintCandidates: [DexEntry] { state.dex.filter { !$0.isReleased } }

    /// One Mint on a graduated Pokémon: its nature becomes another one, at random (the owner, 2026-11-09: "au
    /// hasard"). Nil, and nothing spent, without a Mint or for a Pokémon no Mint reaches. The nature it had (nil for
    /// a save older than natures) and the new one.
    @discardableResult
    func useMint(on entryID: String) -> (from: PokemonNature?, to: PokemonNature)? {
        guard itemCount(.mint) > 0, let i = state.dex.firstIndex(where: { $0.id == entryID && !$0.isReleased }) else {
            return nil
        }
        let current = state.dex[i].nature
        let pool = PokemonNature.allCases.filter { $0 != current }
        let new = pool[Int(rng.next() % UInt64(pool.count))]
        state.dex[i].nature = new
        changeBag(.mint, by: -1)
        AppLog.write("mint: \(entryID) \(current?.rawValue ?? "-") -> \(new.rawValue)")
        save()
        return (current, new)
    }

    // MARK: 상점 (재화 = 사용한 토큰)

    /// 상점에서 쓸 수 있는 토큰(재화) = 실사용 누적 − 상점 지출 누적. 성장 미터(usedSinceInstall)는
    /// 여기선 읽기만 — 구매는 spentTokens 만 올려 잔액을 깎는다(진화 진행·오늘/주/월 통계 무영향).
    /// What the travelling merchant paid adds to it (`merchantTokens`).
    var availableTokens: Int { max(0, state.usedSinceInstall + state.merchantTokens - state.spentTokens) }

    // MARK: The travelling merchant (2026-11-09)

    /// The day (`yyyy-MM-dd`) the merchant's visit belongs to: the daily dungeon's.
    var merchantDay: String { challengePeriod(.daily) }

    /// What the day's travelling merchant buys back (one comes every day).
    var merchantWare: ItemKind? { TravellingMerchant.ware(on: merchantDay) }

    /// Whether the day's merchant waits to be looked at: the Shop's arrow to him wears a dot.
    var merchantUnseen: Bool { merchantSeenDay != merchantDay }

    /// The player looked at the day's merchant.
    func markMerchantSeen() {
        if merchantSeenDay != merchantDay { merchantSeenDay = merchantDay }
    }

    /// What he pays for one, at the players' difficulty; the player's discounts do not change it.
    func merchantPrice(of kind: ItemKind) -> Int? {
        TravellingMerchant.buyBackBase(kind).map { PokemonBalance.scaled($0, by: shopDifficulty) }
    }

    /// Sells `count` of today's ware to the merchant: they leave the Bag, their price goes to the wallet. False when he
    /// is not here, or the Bag holds fewer.
    @discardableResult
    func sellToMerchant(_ count: Int) -> Bool {
        guard count > 0, let kind = merchantWare, let price = merchantPrice(of: kind), itemCount(kind) >= count else {
            return false
        }
        _ = changeBag(kind, by: -count)
        state.merchantTokens += price * count
        AppLog.write("merchant: sold \(count) \(kind.rawValue) for \(price * count)")
        persist()
        return true
    }

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    /// Collector items have no price: they are only claimed in the Achievements tab.
    /// What the Shop sells, cheapest first: a passive item bought once (the Shiny Charm) leaves it for the Bag, and a
    /// retired item (`isRetired`) is not sold.
    var purchasableItems: [ItemKind] {
        ItemKind.allCases
            .filter { $0.shopPrice != nil && !$0.isRetired && !($0.isPassive && itemCount($0) > 0) }
            .sorted { ($0.shopPrice ?? 0) < ($1.shopPrice ?? 0) }
    }

    /// The Shop's order: its sections one after the other (`shopSections`). Bought, an egg goes in the Bag.
    var shopEntries: [ShopEntry] { shopSections.flatMap(\.entries) }

    /// The Shop's sections (the owner, 2026-11-05: one price order mixed eggs, balls, candies and charms): the eggs, what
    /// the Pokémon raised uses, what the graduated ones use (the Mint, #183), the dungeons' balls, then what is kept for
    /// good, each cheapest first (`purchasableItems`'s order, the eggs' tiers in theirs; a discount lowers a whole section
    /// alike). Empty ones go.
    enum ShopSection: CaseIterable, Sendable {
        case eggs, raising, graduated, dungeons, keptForGood

        /// The Shop's tab it is shown in (#183): the Pokémon raised, the graduated ones and what is kept for good share
        /// the raising tab.
        var tab: ShopTab {
            switch self {
            case .eggs: .eggs
            case .raising, .graduated, .keptForGood: .raising
            case .dungeons: .dungeons
            }
        }
    }

    /// The Shop's tabs under Prof. Oak's card (#183): one section at a time instead of all of them stacked.
    enum ShopTab: CaseIterable, Sendable {
        case eggs, raising, dungeons

        /// Its sections in the Shop's order.
        var sections: [ShopSection] { ShopSection.allCases.filter { $0.tab == self } }
        /// A tab of several sections names each one; the others' name is the tab's.
        var namesItsSections: Bool { sections.count > 1 }
    }

    /// Where an item of the Bag's Items tab stands, by the Shop's sections (the owner, 2026-11-09: the balls and eggs
    /// were mixed): every egg first (the Legendary Egg and Type: Null's included, which the Bag used to file with the
    /// artifacts) and the evolution stones with them, which trade the Pokémon raised for an egg too (the owner); the
    /// dungeons' items, what is kept for good, the rest for the Pokémon raised. The Mint, found in the dungeons' chests
    /// but used on a graduated Pokémon, has its own section beside the raising (#183).
    nonisolated static func bagSection(of kind: ItemKind) -> ShopSection {
        if kind.isEggItem || kind.rawValue.hasSuffix("Egg") || kind.stoneType != nil { return .eggs }
        if kind == .mint { return .graduated }
        if kind.isDungeonItem { return .dungeons }
        return kind.isPassive ? .keptForGood : .raising
    }

    /// The Bag's sections, top down: the Rare Candies first, above the eggs (the owner, 2026-11-09 evening: "les
    /// bonbons tout en haut"), then the Shop's order. The Shop keeps its eggs first.
    nonisolated static let bagSectionOrder: [ShopSection] = [.raising, .eggs, .graduated, .dungeons, .keptForGood]

    /// An item's place in the Bag and a recap: its section, then among the eggs the Shop's three by rarity with the
    /// Legendary Egg under the Rare one (the owner, 2026-11-09), the other eggs, the stones last; elsewhere the items'
    /// own order.
    nonisolated static func bagRank(of kind: ItemKind) -> (section: Int, place: Int) {
        let section = bagSectionOrder.firstIndex(of: bagSection(of: kind)) ?? 0
        let order = ItemKind.allCases.firstIndex(of: kind) ?? 0
        if let lead = [ItemKind.pokemonEgg, .uncommonEgg, .rareEgg, .legendaryEgg].firstIndex(of: kind) { return (section, lead) }
        return (section, (kind.stoneType != nil ? 10_000 : 100) + order)
    }

    /// Whether `a` comes before `b` in the Bag: the ranks compared field by field, never as tuples inside a sort's
    /// closure, which Xcode 27.2's compiler failed to type (a player's update, 2026-11-09).
    nonisolated static func bagOrdered(_ a: ItemKind, _ b: ItemKind) -> Bool {
        let ra = bagRank(of: a), rb = bagRank(of: b)
        if ra.section != rb.section { return ra.section < rb.section }
        return ra.place < rb.place
    }

    /// An item for sale stands in its Bag section, so the Shop and the Bag file the Mint alike.
    var shopSections: [(section: ShopSection, entries: [ShopEntry])] {
        func section(of entry: ShopEntry) -> ShopSection {
            guard case .item(let kind) = entry else { return .eggs }
            return Self.bagSection(of: kind)
        }
        let entries = purchasableItems.map { ShopEntry.item($0) } + FreshEgg.shopTiers.map { ShopEntry.egg($0) }
        return ShopSection.allCases.compactMap { kind in
            let inSection = entries.filter { section(of: $0) == kind }
            return inSection.isEmpty ? nil : (kind, inSection)
        }
    }

    /// The Shop's tabs with their sections (#183), empty ones left out.
    var shopTabs: [(tab: ShopTab, sections: [(section: ShopSection, entries: [ShopEntry])])] {
        // A plain loop, as `BagView.itemSections`: Xcode 27.2's compiler failed on closures returning such tuples.
        let sections = shopSections
        var tabs: [(tab: ShopTab, sections: [(section: ShopSection, entries: [ShopEntry])])] = []
        for tab in ShopTab.allCases {
            let inTab = sections.filter { $0.section.tab == tab }
            if !inTab.isEmpty { tabs.append((tab: tab, sections: inTab)) }
        }
        return tabs
    }

    /// 구매 가능 — 잔액이 그 아이템 가격 이상(상점 미판매면 false). 활성/알 무관(재고는 미리 쌓아둘 수 있음).
    func canBuy(_ kind: ItemKind) -> Bool {
        guard let price = price(of: kind), !kind.isRetired else { return false }
        if kind.isPassive && itemCount(kind) > 0 { return false }   // 보유형은 1회만(재구매 불가)
        return availableTokens >= price
    }

    /// 한 번에 살 수 있는 최대 개수 — 잔액 ÷ 가격. 보유형은 1회 구매라 최대 1, 이미 보유했거나
    /// 미판매·잔액 부족이면 0.
    func maxBuyCount(_ kind: ItemKind) -> Int {
        guard canBuy(kind), let price = price(of: kind), price > 0 else { return 0 }
        return kind.isPassive ? 1 : availableTokens / price
    }

    /// 아이템 count 개 구매 — 지갑에서 price × count 차감, 인벤토리 +count. usedSinceInstall(성장·통계)·
    /// 진화 진행엔 무영향(지출 원장만 증가). 잔액 부족/미판매/범위 밖 개수면 부분 구매 없이 no-op(false).
    @discardableResult
    func buy(_ kind: ItemKind, count: Int = 1) -> Bool {
        guard count >= 1, count <= maxBuyCount(kind), let price = price(of: kind) else { return false }
        state.spentTokens += price * count
        if kind == .rareCandy {
            addRareCandies(count)
        } else {
            state.inventory[kind.rawValue, default: 0] += count
        }
        save()
        return true
    }

    /// The Explorer Kit counts the graduations: every `ExplorerKit.graduationsPerTreasure` dig up a treasure, put in the
    /// Bag and shown in the news strip until seen.
    private func digTreasureIfDue() {
        // Bounded: a hand-edited count would pay a treasure at every graduation until it ran down.
        let counted = min(max(0, state.graduationsTowardTreasure), ExplorerKit.graduationsPerTreasure - 1)
        state.graduationsTowardTreasure = counted + 1
        guard state.graduationsTowardTreasure >= ExplorerKit.graduationsPerTreasure else { return }
        state.graduationsTowardTreasure -= ExplorerKit.graduationsPerTreasure
        let treasure = ExplorerKit.treasure(roll: Int(rng.next() % UInt64(ExplorerKit.rollRange)))
        state.inventory[treasure.kind.rawValue, default: 0] += treasure.count
        state.unseenTreasures[treasure.kind.rawValue, default: 0] += treasure.count
        AppLog.write("graduate: explorer kit dug up \(treasure.count) \(treasure.kind.rawValue)")
        notifyCompanionEvent(treasure.kind == .legendaryEgg ? l.treasureJackpotTitle : l.treasureTitle,
                             l.treasureBody([(treasure.kind, treasure.count)]))
    }

    /// The treasures not seen yet, the rarest first.
    var unseenTreasures: [(kind: ItemKind, count: Int)] {
        let order: [ItemKind] = [.legendaryEgg, .rareEgg, .uncommonEgg, .rareCandy]
        return state.unseenTreasures.compactMap { key, count in ItemKind(rawValue: key).map { ($0, count) } }
            .filter { $0.count > 0 }
            .sorted { (order.firstIndex(of: $0.kind) ?? order.count) < (order.firstIndex(of: $1.kind) ?? order.count) }
    }

    /// The treasures were seen: the Bag opened, or the strip's page closed.
    func markTreasuresSeen() {
        guard !state.unseenTreasures.isEmpty else { return }
        state.unseenTreasures = [:]
        save()
    }

    /// Adds Rare Candies from any source. Returns how many landed in the bag.
    @discardableResult
    private func addRareCandies(_ count: Int) -> Int {
        state.inventory[ItemKind.rareCandy.rawValue, default: 0] += count
        return count
    }

    /// A save that pre-rolled Arceus before it became the Hall of Origin's alone rolls again (R13), unless the egg is
    /// that boss's.
    private func dropDungeonOnlyPreRoll() {
        guard let pending = state.pendingHatchID, hatchDraw.dungeonOnly.contains(pending), state.eggFromDungeon == nil
        else { return }
        state.pendingHatchID = nil
        state.pendingForm = nil
        state.pendingShiny = false
        AppLog.write("hatch: pre-rolled Arceus dropped, only the Hall of Origin gives it")
    }

    // MARK: The dungeons' access (`CompanionStore+Dungeons`: `state` is written in this file only)

    /// The tokens' growth: a dungeon's walk while a team explores (Q1: growth pauses, the Shop and the candies go
    /// on), else the egg's incubation or the Pokémon's growth.
    private func creditGrowth(_ delta: Int) {
        var delta = delta
        if state.dungeons.budget == nil { state.dungeons.budget = DungeonBudget(start: state.usedSinceInstall - delta) }
        if let left = feedExpedition(delta) {
            state.dungeons.budget?.dungeonTokens += delta - left
            guard left > 0 else { return }
            delta = left
        }
        creditGrowthPastTheDungeon(delta)
    }

    /// The egg's incubation or the Pokémon's growth, for the tokens a dungeon did not take (its boss fallen, its
    /// team lost).
    func creditGrowthPastTheDungeon(_ delta: Int) {
        guard delta > 0 else { return }
        if state.active == nil {
            state.eggUsage += delta
        } else {
            applyUsage(delta)
        }
    }

    func changeDungeons(_ change: (inout DungeonProgress) -> Void) { change(&state.dungeons) }
    /// An achievement's artifact taken by a villains' team stays claimed (issue #180): a save from before the claims were
    /// kept read its claim from the Bag, and would have let it be claimed twice.
    func markAchievementClaimed(_ kind: ItemKind) { state.claimedAchievements.insert(kind.rawValue) }

    /// Tokens paid from the wallet, as a purchase pays them.
    func spendTokens(_ amount: Int) { state.spentTokens += max(0, amount) }

    /// Adds (or with a negative count takes) items in the Bag, never below none. Returns how many moved.
    @discardableResult
    func changeBag(_ kind: ItemKind, by count: Int) -> Int {
        let held = itemCount(kind)
        let moved = max(-held, count)
        state.inventory[kind.rawValue] = held + moved
        return moved
    }

    func grantRareCandies(_ count: Int) -> Int { addRareCandies(count) }

    /// A graduated Pokémon's profile, changed in place (a Capsule raises its IVs). Returns whether it has one.
    @discardableResult
    func changeProfile(of entryID: String, _ change: (inout PokemonProfile) -> Void) -> Bool {
        guard let i = state.dex.firstIndex(where: { $0.id == entryID }), var profile = state.dex[i].profile else { return false }
        change(&profile)
        state.dex[i].profile = profile
        return true
    }
    /// The store's clock (`clock`, injected by the tests).
    var currentDate: Date { clock() }
    func drawSeed() -> UInt64 { rng.next() }
    func persist() { save() }
    /// A usage update's write, at most once per `usageSaveGap` (`saveUsage`).
    func persistUsage() { saveUsage() }

    // MARK: Collector items (unlocked by the Pokédex)

    /// Species registered in the Pokédex: the set the Pokédex grid shows (`dexSpecies`). Graduated and
    /// released chains, plus the stages the current Pokémon has reached. Never `plannedPathIDs`.
    var registeredSpeciesIDs: Set<Int> { state.registeredSpeciesIDs }

    /// Species of the Pokémon raised to the end: graduated entries, never released ones nor the Pokémon being raised.
    /// What achievements count, so that a Pokémon cannot earn one while raised and then be sent off.
    var graduatedSpeciesIDs: Set<Int> { state.graduatedSpeciesIDs }

    /// How much of the Pokédex is collected: species, and appearances (every form of every species, one for a
    /// species without forms), out of everything that can hatch.
    struct CollectionProgress: Equatable, Sendable {
        let species: Int
        let speciesTotal: Int
        let forms: Int
        let formsTotal: Int
        /// Evolution lines, each one family from its first species (Pichu, Pikachu and Raichu are one), with a species
        /// in the collection.
        let lines: Int
        let linesTotal: Int
    }

    /// Every evolution line of the 1,025 species: one per species that evolves from none.
    static let evolutionLineCount = PokemonAssets.animatedSpeciesIDs.filter { PokemonEvolutionData.root(of: $0) == $0 }.count

    /// Every appearance that can be collected: 1,025 species and their other forms, and the battle forms the daily and
    /// weekly dungeons give (the owner, 2026-11-02: they lengthen the end of the game).
    static let collectableFormCount = PokemonAssets.animatedSpeciesIDs.reduce(0) {
        $0 + max(1, PokemonForm.forms(speciesID: $1).count)
    } + BattleForms.all.count

    var collectionProgress: CollectionProgress { collectionProgress(graduatedOnly: false) }

    /// The collection the Oval and Glimmering Charms' achievements count: graduated Pokémon only.
    var graduatedCollectionProgress: CollectionProgress { collectionProgress(graduatedOnly: true) }

    /// `battleForms`: whether the battle forms count, as they do since `HatchRules.Change.battleFormsCount`.
    private func collectionProgress(graduatedOnly: Bool, of s: CompanionState? = nil, battleForms: Bool = true) -> CollectionProgress {
        let s = s ?? state
        let ids = graduatedOnly ? s.graduatedSpeciesIDs : s.registeredSpeciesIDs
        let species = ids.filter(PokemonAssets.animatedSpeciesIDs.contains)
        let graduated = graduatedOnly ? GraduatedForms(s.dex) : nil
        let forms = species.reduce(0) { total, id in
            let collected = graduated.map { s.graduatedForms(speciesID: id, $0) }
                ?? s.collectedForms(speciesID: id, graduatedOnly: false)
            return total + (PokemonForm.hasForms(speciesID: id) ? max(1, collected.count) : 1)
        }
        // A battle form is won by a graduated Pokémon's team, so it counts for both.
        return CollectionProgress(species: species.count, speciesTotal: PokemonAssets.animatedSpeciesIDs.count,
                                  forms: forms + (battleForms ? s.dungeons.battleForms.count : 0),
                                  formsTotal: Self.collectableFormCount - (battleForms ? 0 : BattleForms.all.count),
                                  lines: Set(species.map(PokemonEvolutionData.root)).count,
                                  linesTotal: Self.evolutionLineCount)
    }

    /// How far one species goal is from unlocking its item.
    struct GoalProgress: Equatable, Sendable {
        let goal: SpeciesGoal
        /// Goal species already counted (graduated), in the goal's order.
        let registered: [Int]
        var count: Int { min(registered.count, goal.needed) }
        var isMet: Bool { registered.count >= goal.needed }
    }

    /// Species goals of a collector item with what is already graduated. Empty for items without
    /// species goals (always on sale, or the Azure Flute's duplicate legendary).
    func unlockProgress(of kind: ItemKind, registered: Set<Int>? = nil) -> [GoalProgress] {
        guard case .species(let goals) = kind.unlock else { return [] }
        let registered = registered ?? graduatedSpeciesIDs
        return goals.map { goal in
            GoalProgress(goal: goal, registered: goal.species.filter(registered.contains))
        }
    }

    /// Silvally's Memories won so far by graduated Pokémon, out of `PokemonForm.memoryTypes`.
    var silvallyMemoryCount: Int { state.graduatedSilvallyMemoryTypes.count }

    var graduatedLegendaryCopies: Int { state.graduatedLegendaryCopies }

    /// One regional tier of an achievement: a gym badge's type from one generation, or every species of a
    /// generation for the Legendary Egg.
    struct RegionTier: Equatable, Sendable {
        let generation: Int
        let progress: GoalProgress
        let isClaimed: Bool
        /// A dig whose fossil line was graduated some other way: done, with nothing to claim (`FossilDig`).
        var isWaived = false
        var isDone: Bool { isClaimed || isWaived }
        var isReady: Bool { progress.isMet && !isDone }
    }

    /// The regional tiers of an achievement, in generation order. Empty for an item claimed once.
    func regionTiers(_ kind: ItemKind, registered: Set<Int>? = nil) -> [RegionTier] {
        guard let goals = kind.regionGoals else { return [] }
        if kind == .excavation { return excavationTiers(goals) }
        if let tier = kind.dungeonTier { return medalTiers(tier, goals) }
        if kind.isCostumeMedal {
            // Its goal's ids stand for the costumes (`CostumeMedals.id`), or the months: those collected count.
            let owned = ownedCostumeKeys().all
            let registered: Set<Int> = kind == .costumeMedal
                ? Set(CostumeCatalog.entries.filter { owned.contains($0.key) }.map(CostumeMedals.id))
                : Set((1...12).filter { month in CostumeCatalog.lot(month: month).allSatisfy { owned.contains($0.key) } }
                    .map(CostumeMedals.lotID))
            return goals.map { generation, goal in
                RegionTier(generation: generation, progress: GoalProgress(goal: goal, registered: goal.species.filter(registered.contains)),
                           isClaimed: isRegionTierClaimed(kind, generation: generation))
            }
        }
        if kind == .battleFormsMedal {
            // Its goal's species are the battle forms' varieties: those won count.
            let won = Set(state.dungeons.battleForms.compactMap { BattleForms.form(key: $0)?.pokemonID })
            return goals.map { generation, goal in
                RegionTier(generation: generation, progress: GoalProgress(goal: goal, registered: goal.species.filter(won.contains)),
                           isClaimed: isRegionTierClaimed(kind, generation: generation))
            }
        }
        let registered = registered ?? graduatedSpeciesIDs
        return goals.map { generation, goal in
            RegionTier(generation: generation,
                             progress: GoalProgress(goal: goal, registered: goal.species.filter(registered.contains)),
                       isClaimed: isRegionTierClaimed(kind, generation: generation))
        }
    }

    /// A Dungeons medal's steps: a dungeon counts once it was won, the whole tier once each was. Its goal's species
    /// are the bosses; a dungeon won counts its first one, as the goal reads it.
    private func medalTiers(_ tier: DungeonTier, _ goals: [(generation: Int, goal: SpeciesGoal)]) -> [RegionTier] {
        let won = DungeonMedals.dungeons(tier).filter { state.dungeons.wins($0) > 0 }
            .compactMap { DungeonCatalog.dungeon($0).bosses.first }
        return goals.map { generation, goal in
            RegionTier(generation: generation, progress: GoalProgress(goal: goal, registered: goal.species.filter(won.contains)),
                       isClaimed: isRegionTierClaimed(DungeonMedals.medal(tier), generation: generation))
        }
    }

    /// The digs: Rock-type species graduated in a Rock form count toward each; the last ones are done with nothing to
    /// claim for every fossil line had before the digs, so the eggs match the lines that were missing.
    private func excavationTiers(_ goals: [(generation: Int, goal: SpeciesGoal)]) -> [RegionTier] {
        let rock = rockSpeciesGraduated
        var tiers = goals.map { generation, goal in
            RegionTier(generation: generation, progress: GoalProgress(goal: goal, registered: goal.species.filter(rock.contains)),
                       isClaimed: isRegionTierClaimed(.excavation, generation: generation))
        }
        var waived = min(state.fossilLinesBeforeDigs?.count ?? 0, tiers.filter { !$0.isClaimed }.count)
        for index in tiers.indices.reversed() where waived > 0 && !tiers[index].isClaimed {
            tiers[index].isWaived = true
            waived -= 1
        }
        return tiers
    }

    /// The digs as the Achievements card tells them: 15 eggs, one per fossil line, in the digs' order. Claimed ones
    /// were opened or still wait in the Bag; then those ready to claim, the next one with the Rock-type Pokémon it
    /// still wants, those still to earn, and last those not claimable, for lines graduated before the digs.
    struct ExcavationProgress: Equatable, Sendable {
        let total: Int
        /// Claimed and used: hatched, or hatching now.
        let opened: Int
        /// Claimed and still in the Bag.
        let inBag: Int
        let ready: Int
        /// Done with nothing to claim.
        let notClaimable: Int
        /// Rock-type species graduated toward the next dig, out of `FossilDig.rockPerDig`. nil once every dig is met.
        let towardNext: Int?
        let linesGraduated: Int
        /// Still to earn, the next one included.
        var toEarn: Int { total - opened - inBag - ready - notClaimable }
    }

    var excavationProgress: ExcavationProgress {
        let tiers = regionTiers(.excavation)
        let claimed = tiers.filter(\.isClaimed).count
        let inBag = min(claimed, itemCount(.fossilEgg))
        // The digs ask for 4, 8, 12… Rock species in all: the next one counts from where the one before it stopped.
        let towardNext = tiers.first { !$0.progress.isMet && !$0.isDone }.map { dig in
            min(FossilDig.rockPerDig, max(0, dig.progress.count - (dig.progress.goal.needed - FossilDig.rockPerDig)))
        }
        return ExcavationProgress(total: tiers.count, opened: claimed - inBag, inBag: inBag,
                                  ready: tiers.filter(\.isReady).count, notClaimable: tiers.filter(\.isWaived).count,
                                  towardNext: towardNext,
                                  linesGraduated: FossilDig.lines.filter(graduatedSpeciesIDs.contains).count)
    }

    /// Species graduated in a Rock-type form: their usual one, or one of their forms (Hisuian Arcanine). A species with
    /// forms counts by the forms it graduated in only: a Galarian Corsola (Ghost) counted as Rock, Corsola's usual type.
    var rockSpeciesGraduated: Set<Int> {
        // The Pokédex's forms read once: `collectedForms(graduatedOnly:)` read it again for each species, up to 240 ms
        // each time the popover drew its tabs (#182).
        let graduated = GraduatedForms(state.dex)
        return Set(graduatedSpeciesIDs.filter { id in
            guard PokemonForm.hasForms(speciesID: id) else {
                return PokemonTypeData.types(forSpeciesID: id, form: nil).contains(.rock)
            }
            return state.graduatedForms(speciesID: id, graduated).contains {
                PokemonTypeData.types(forSpeciesID: id, form: $0).contains(.rock)
            }
        })
    }

    func isRegionTierClaimed(_ kind: ItemKind, generation: Int) -> Bool {
        state.claimedAchievements.contains(CompanionState.regionTierKey(kind, generation: generation))
    }

    /// Whether this item's achievement goal is met, counting graduated Pokémon only, in the save or in `s`. Items
    /// without a Pokédex condition are always unlocked. For a regional achievement: one of its regional tiers is complete.
    func isUnlocked(_ kind: ItemKind, registered: Set<Int>? = nil, in given: CompanionState? = nil,
                    graduatedOnly: Bool = true, battleForms: Bool = true) -> Bool {
        let s = given ?? state
        switch kind.unlock {
        case nil: return true
        case .duplicateLegendary: return s.graduatedLegendaryCopies >= 2
        case .silvallyMemories: return s.graduatedSilvallyMemoryTypes.count >= PokemonForm.memoryTypes.count
        case .allSpecies:
            let progress = collectionProgress(graduatedOnly: graduatedOnly, of: s)
            return progress.species >= progress.speciesTotal
        case .allForms:
            let progress = collectionProgress(graduatedOnly: graduatedOnly, of: s, battleForms: battleForms)
            return progress.forms >= progress.formsTotal
        case .allPikachuCostumes: return s.pikachuCostumes.count >= PikachuCostume.allCases.count
        // The state's own forms index when none is given: read once until it changes.
        case .forms(let goal): return formProgress(goal, of: given).isMet
        case .species:
            let counted = registered ?? (graduatedOnly ? s.graduatedSpeciesIDs : s.registeredSpeciesIDs)
            return unlockProgress(of: kind, registered: counted).contains(where: \.isMet)
        }
    }

    /// The first moment since `arrival` that met the item's condition of the time; nil if none did. Within an era of
    /// that condition a Pokédex only fills and a goal only loosens, so one met stays met.
    func unlockedAt(_ kind: ItemKind, since arrival: Date) -> Date? {
        var previous: DexEntry?
        let hatches = dexEntries.map { entry -> (entry: DexEntry, hatchedAt: Date?) in
            defer { previous = entry }
            return (entry, HatchLuck.hatchedAt(of: entry, after: previous))
        }
        let moments = Set(hatches.flatMap { [$0.entry.caughtAt, $0.hatchedAt] }.compactMap { $0 }
            + [arrival, HatchRules.Change.onlyFluteWeighs.publishedAt]).filter { $0 >= arrival }.sorted()
        let graduatedOnly = HatchRules.Change.rarityWeights.publishedAt
        for era in [moments.filter { $0 < graduatedOnly }, moments.filter { $0 >= graduatedOnly }] {
            guard let last = era.last, wasUnlocked(kind, at: last, among: hatches) else { continue }
            var (low, high) = (0, era.count - 1)
            while low < high {
                let mid = (low + high) / 2
                if wasUnlocked(kind, at: era[mid], among: hatches) { high = mid } else { low = mid + 1 }
            }
            return era[low]
        }
        return nil
    }

    /// Whether the item's condition of the time was met at `date`, the Pokédex read back to it. A Pokémon then being
    /// raised reads like one sent off, registered and not graduated, on its base species: its stages have no date.
    private func wasUnlocked(_ kind: ItemKind, at date: Date, among hatches: [(entry: DexEntry, hatchedAt: Date?)]) -> Bool {
        var s = state
        s.active = nil
        s.dex = hatches.compactMap { entry, hatchedAt in
            if let caughtAt = entry.caughtAt, caughtAt <= date { return entry }
            guard let hatchedAt, hatchedAt <= date else { return nil }
            var raised = entry
            raised.chainOrder = [entry.baseID]
            raised.releasedAt = date
            return raised
        }
        let rules = HatchRules(rolledAt: date)
        if kind == .revealGlass, !rules.has(.onlyFluteWeighs) {
            return HatchRules.formerRevealGlassSpecies.allSatisfy(s.registeredSpeciesIDs.contains)
        }
        return isUnlocked(kind, in: s, graduatedOnly: rules.has(.rarityWeights), battleForms: rules.has(.battleFormsCount))
    }

    /// The forms of a forms achievement graduated, in the goal's order.
    struct FormProgress: Equatable, Sendable {
        let goal: FormGoal
        let graduated: [PokemonForm]
        var count: Int { graduated.count }
        var isMet: Bool { count >= goal.forms.count }
    }

    /// `GraduatedForms` of the state, read once until it changes.
    private var graduatedFormsIndex: GraduatedForms {
        if let cached = graduatedFormsCache { return cached }
        let index = GraduatedForms(state.dex)
        graduatedFormsCache = index
        return index
    }

    func formProgress(_ goal: FormGoal, of s: CompanionState? = nil) -> FormProgress {
        let graduated = s.map { $0.collectedForms(speciesID: goal.speciesID, graduatedOnly: true) }
            ?? state.graduatedForms(speciesID: goal.speciesID, graduatedFormsIndex)
        return FormProgress(goal: goal, graduated: goal.forms.filter(graduated.contains))
    }

    // MARK: 업적 (진화의 돌, 체육관 배지, 전설의 유물)

    /// All items claimed through achievements (Evolution Stones, Gym Badges, Legendary Artifacts).
    static let achievementItems: [ItemKind] = ItemKind.allCases.filter(\.isAchievement)

    /// Whether this achievement was already claimed. Stones are used up, so the Bag cannot tell: the
    /// ledger can. A passive item owned before the ledger existed counts as claimed. A regional achievement is
    /// claimed once every regional tier is.
    func isClaimed(_ kind: ItemKind) -> Bool {
        if kind.isRegional { return regionTiers(kind).allSatisfy(\.isDone) }
        return state.claimedAchievements.contains(kind.rawValue) || (kind.isPassive && itemCount(kind) > 0)
    }

    /// Achievements counted one per stone or artifact, and one per regional tier of each regional achievement.
    struct AchievementTally: Equatable, Sendable {
        var ready = 0
        var claimed = 0
        var total = 0
    }

    func achievementTally(in group: CollectorGroup? = nil) -> AchievementTally {
        let tallies = achievementTallies()
        return group.map { tallies.byGroup[$0] ?? AchievementTally() } ?? tallies.all
    }

    /// Every section's tally and the whole one in one pass, which the Achievements tab reads once per draw: its
    /// header, tabs, banner and progress line counted them some 17 times.
    func achievementTallies() -> (all: AchievementTally, byGroup: [CollectorGroup: AchievementTally]) {
        if let cached = achievementTalliesCache { return cached }
        let registered = graduatedSpeciesIDs
        var all = AchievementTally()
        var byGroup: [CollectorGroup: AchievementTally] = [:]
        for kind in Self.achievementItems {
            var one = AchievementTally()
            count(kind, into: &one, registered: registered)
            all.ready += one.ready; all.claimed += one.claimed; all.total += one.total
            if let group = kind.collectorGroup {
                var tally = byGroup[group] ?? AchievementTally()
                tally.ready += one.ready; tally.claimed += one.claimed; tally.total += one.total
                byGroup[group] = tally
            }
        }
        achievementTalliesCache = (all, byGroup)
        return (all, byGroup)
    }

    private func count(_ kind: ItemKind, into tally: inout AchievementTally, registered: Set<Int>) {
        if kind.isRegional {
            let tiers = regionTiers(kind, registered: registered)
            tally.ready += tiers.filter(\.isReady).count
            tally.claimed += tiers.filter(\.isDone).count
            tally.total += tiers.count
        } else {
            let claimed = isClaimed(kind)
            tally.ready += !claimed && isUnlocked(kind, registered: registered) ? 1 : 0
            tally.claimed += claimed ? 1 : 0
            tally.total += 1
        }
    }

    /// Number of achievements ready to be claimed (each regional tier counts).
    var unclaimedAchievementsCount: Int { achievementTally().ready }

    /// Number of claimed achievements.
    var claimedAchievementsCount: Int { achievementTally().claimed }

    /// Total number of achievements.
    var totalAchievementsCount: Int { achievementTally().total }

    /// Claim an achievement reward once unlocked, adding it to the bag for free: one passive item, or
    /// `EvolutionStone.achievementReward` stones.
    @discardableResult
    func claimAchievement(_ kind: ItemKind) -> Bool {
        if kind.isRegional { return claimRegionTiers(kind) > 0 }
        guard kind.isAchievement, isUnlocked(kind), !isClaimed(kind) else { return false }
        let count = grantAchievement(kind)
        save()
        let body = kind == .legendPlate ? l.notifLegendPlateBody
            : kind.givesOtherItems ? l.notifRewardsBody(kind.achievementRewards)
            : l.notifAchievementClaimedBody(l.itemName(kind), count: count)
        notifyCompanionEvent(l.notifAchievementClaimedTitle, body)
        return true
    }

    /// Claims every achievement ready to claim at once (the banner's "Claim all"): one save and one
    /// notification for the lot. Returns how many achievements were claimed.
    @discardableResult
    func claimAllAchievements() -> Int {
        let registered = graduatedSpeciesIDs
        let items = Self.achievementItems.filter { !$0.isRegional && isUnlocked($0, registered: registered) && !isClaimed($0) }
        let tiers = Self.achievementItems.flatMap { kind in
            regionTiers(kind, registered: registered).filter(\.isReady).map { (kind, $0.generation) }
        }
        guard !items.isEmpty || !tiers.isEmpty else { return 0 }
        let forms = itemFormSnapshot()
        items.forEach { _ = grantAchievement($0) }
        tiers.forEach { grantRegionTier($0.0, generation: $0.1) }
        announceFormUnlocks(since: forms)
        save()
        notifyCompanionEvent(l.notifAchievementClaimedTitle, l.notifAchievementsClaimedBody(items.count + tiers.count))
        return items.count + tiers.count
    }

    /// Claims every ready regional tier of one achievement. Returns how many tiers were claimed.
    @discardableResult
    func claimRegionTiers(_ kind: ItemKind) -> Int {
        let ready = regionTiers(kind).filter(\.isReady)
        guard !ready.isEmpty else { return 0 }
        let forms = itemFormSnapshot()
        ready.forEach { grantRegionTier(kind, generation: $0.generation) }
        announceFormUnlocks(since: forms)
        save()
        let regions = ready.map { tier in
            if kind == .excavation { return "#\(tier.generation)" }
            if let dungeonTier = kind.dungeonTier { return l.medalStepName(dungeonTier, step: tier.generation) }
            if kind == .battleFormsMedal { return l.battleFormsMedalStep(tier.generation) }
            if kind == .costumeMedal { return l.costumeMedalStep(tier.generation) }
            if kind == .costumeLotsMedal { return l.costumeLotsMedalStep(tier.generation) }
            return l.regionName(generation: tier.generation)
        }
        .joined(separator: ", ")
        notifyCompanionEvent(l.notifAchievementClaimedTitle,
                             l.notifAchievementClaimedBody("\(l.itemName(kind)) (\(regions))"))
        return ready.count
    }

    /// Forms a claim, a catch or an evolution just unlocked (Arceus's Plates, Silvally's Memories), for the short
    /// message that shows their sprites. One entry per species; a message not seen yet takes the next unlocks in.
    struct FormUnlockNews: Equatable, Sendable {
        let speciesID: Int
        let forms: [PokemonForm]
    }

    private(set) var formUnlockNews: [FormUnlockNews] = []

    func dismissFormUnlockNews() { formUnlockNews = [] }

    private typealias ItemFormSnapshot = [Int: (unlocked: Set<PokemonForm>, owned: Bool)]

    private func itemFormSnapshot() -> ItemFormSnapshot {
        Dictionary(uniqueKeysWithValues: PokemonForm.unlockSources.keys.map { id in
            (id, (unlocked: state.itemUnlockedForms(speciesID: id), owned: state.ownsSpeciesInAnyForm(id)))
        })
    }

    /// Announces the forms unlocked since the snapshot, only for a species in the Pokédex: a Plate or Memory won
    /// before stays silent, and the first Arceus or Silvally announces every one already won.
    private func announceFormUnlocks(since before: ItemFormSnapshot) {
        for (id, previous) in before.sorted(by: { $0.key < $1.key }) {
            guard state.ownsSpeciesInAnyForm(id) else { continue }
            let unlocked = state.itemUnlockedForms(speciesID: id)
            let new = previous.owned ? unlocked.subtracting(previous.unlocked) : unlocked
            guard !new.isEmpty else { continue }
            let pending = formUnlockNews.first { $0.speciesID == id }.map { Set($0.forms) } ?? []
            let forms = new.union(pending).sorted {
                PokemonForm.sortOrder($0, speciesID: id) < PokemonForm.sortOrder($1, speciesID: id)
            }
            formUnlockNews.removeAll { $0.speciesID == id }
            formUnlockNews.append(FormUnlockNews(speciesID: id, forms: forms))
            AppLog.write("forms unlocked: \(id) \(forms.map(\.rawValue))")
        }
    }

    /// Records one regional tier: a badge stays one in the Bag, where its effect line lives; each tier of the
    /// Legendary Egg adds an egg.
    private func grantRegionTier(_ kind: ItemKind, generation: Int) {
        let key = CompanionState.regionTierKey(kind, generation: generation)
        state.claimedAchievements.insert(key)
        if kind.isPassive {
            state.inventory[kind.rawValue] = 1
        } else {
            // A Legendary Egg per region; a Fossil Egg per dig; a Dungeons medal's step its own.
            let rewards = kind == .battleFormsMedal ? BattleFormsMedal.rewards(step: generation)
                : kind == .costumeMedal ? CostumeMedals.rewards(step: generation)
                : kind == .costumeLotsMedal ? CostumeMedals.lotRewards(step: generation)
                : kind.dungeonTier.map { DungeonMedals.rewards($0, step: generation) } ?? kind.achievementRewards
            for reward in rewards { state.inventory[reward.kind.rawValue, default: 0] += reward.count }
        }
        AppLog.write("achievement claimed: \(key)")
    }

    /// Records the claim and puts the reward in the Bag. Returns how many items it added.
    private func grantAchievement(_ kind: ItemKind) -> Int {
        state.claimedAchievements.insert(kind.rawValue)
        for reward in kind.achievementRewards {
            state.inventory[reward.kind.rawValue, default: 0] += reward.count
        }
        let count = kind.achievementRewards.reduce(0) { $0 + $1.count }
        AppLog.write("achievement claimed: \(kind.rawValue) count=\(count)")
        return count
    }

    /// Items for a specific achievement section, sorted: claimable first, then in progress, then claimed; the first two
    /// each from the closest to done (`achievementShare`) to the farthest.
    func achievementItems(in group: CollectorGroup) -> [ItemKind] {
        let registered = graduatedSpeciesIDs
        func rank(_ kind: ItemKind) -> Int {
            if kind.isRegional {
                let tiers = regionTiers(kind, registered: registered)
                if tiers.contains(where: \.isReady) { return 0 }
                // A dig done with nothing to claim is done: counting only claims kept a finished Excavation in progress.
                return tiers.allSatisfy(\.isDone) ? 2 : 1
            }
            if isClaimed(kind) { return 2 }
            return isUnlocked(kind, registered: registered) ? 0 : 1
        }
        let items = ItemKind.allCases.filter { $0.collectorGroup == group }
        let ranks = Dictionary(uniqueKeysWithValues: items.map { ($0, rank($0)) })
        // Highest share first; the order of the catalogue on a tie.
        let behind = Dictionary(uniqueKeysWithValues: items.filter { ranks[$0]! < 2 }.map {
            ($0, -achievementShare($0, registered: registered))
        })
        // The Excavation is not a stone: it closes the Stones tab, as the Legendary Egg, Type: Null's Egg and the two
        // whole-Pokédex charms close the Artifacts, in that order; each closes its own state, never below what is
        // claimed. Closing the tab whatever their state put them under the artifacts already claimed.
        func last(_ kind: ItemKind) -> Int { Self.closingAchievements.firstIndex(of: kind).map { $0 + 1 } ?? 0 }
        func key(_ item: (offset: Int, element: ItemKind)) -> (Int, Int, Double, Int) {
            (ranks[item.element]!, last(item.element), behind[item.element] ?? 0, item.offset)
        }
        return items.enumerated().sorted { key($0) < key($1) }.map(\.element)
    }

    /// The achievements that close their state's place in their tab (ready, in progress, claimed), in order.
    static let closingAchievements: [ItemKind] = [.excavation, .legendaryEgg, .typeNullEgg, .ovalCharm, .glimmeringCharm]

    /// How much of an achievement is done, from 0 to 1, as its card counts it: its goal closest to met (any one is
    /// enough), and for a regional one (a badge) all its regions, each done one whole and the others by their share.
    func achievementShare(_ kind: ItemKind, registered: Set<Int>? = nil) -> Double {
        func share(_ count: Int, _ needed: Int) -> Double { Double(min(count, needed)) / Double(max(1, needed)) }
        if kind.isRegional {
            let tiers = regionTiers(kind, registered: registered)
            guard !tiers.isEmpty else { return 0 }
            return tiers.reduce(0) { $0 + ($1.isDone ? 1 : share($1.progress.count, $1.progress.goal.needed)) }
                / Double(tiers.count)
        }
        switch kind.unlock {
        case .species?:
            return unlockProgress(of: kind, registered: registered).map { share($0.count, $0.goal.needed) }.max() ?? 0
        case .duplicateLegendary?:
            return share(graduatedLegendaryCopies, 2)
        case .silvallyMemories?:
            return share(state.graduatedSilvallyMemoryTypes.count, PokemonForm.memoryTypes.count)
        case .allSpecies?:
            let progress = graduatedCollectionProgress
            return share(progress.species, progress.speciesTotal)
        case .allForms?:
            let progress = graduatedCollectionProgress
            return share(progress.forms, progress.formsTotal)
        case .allPikachuCostumes?:
            return share(state.pikachuCostumes.count, PikachuCostume.allCases.count)
        case .forms(let goal)?:
            return share(formProgress(goal).count, goal.forms.count)
        case nil:
            return 0
        }
    }

    /// Alias for backward compatibility with existing tests and collector group listings.
    func collectorItems(in group: CollectorGroup) -> [ItemKind] {
        achievementItems(in: group)
    }

    // 사탕 전용 래퍼 — 기존 호출부/테스트 호환.
    var canBuyRareCandy: Bool { canBuy(.rareCandy) }
    @discardableResult
    func buyRareCandy() -> Bool { buy(.rareCandy) }

    // MARK: 알 (리롤 — 현재 포켓몬 폐기, 도감·확률 무영향)

    /// 현재 알이 보증하는 등급 하한(UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil. A Legendary Egg's is legendary.
    var eggGuarantee: Rarity? {
        guard state.active == nil else { return nil }
        return state.eggFromLegendaryEgg ? .legendary : state.eggTier
    }
    /// 현재 알이 보증하는 타입(진화의 돌 사용 UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil.
    var eggTypeGuarantee: PokemonType? { state.active == nil ? state.eggTypeGuarantee : nil }

    /// A Shop egg can be bought whenever the wallet holds its price, egg or not: it waits in the Bag, and only using
    /// it sends the current Pokémon off (`useBagEgg`).
    func canBuyEgg(_ tier: Rarity?) -> Bool {
        // The tiers on sale only: an egg of a guarantee no roll can meet (legendary, which no capture rate gives) would
        // never hatch, and its price would be gone. The list is enforced here, where one caller's mistake costs tokens.
        guard FreshEgg.shopTiers.contains(tier) else { return false }
        return availableTokens >= price(of: .egg(tier))
    }

    /// Buys a Shop egg: its price leaves the wallet and the egg goes in the Bag (`ItemKind(shopEgg:)`). Bought, it
    /// used to send the current Pokémon off at once; the player now picks the moment (`useBagEgg`).
    @discardableResult
    func buyEgg(_ tier: Rarity?, count: Int = 1) -> Bool {
        guard count >= 1, count <= maxEggBuyCount(tier), let kind = ItemKind(shopEgg: tier) else { return false }
        state.spentTokens += price(of: .egg(tier)) * count
        state.inventory[kind.rawValue, default: 0] += count
        save()
        AppLog.write("egg purchased: \(kind.rawValue) ×\(count) to the bag")
        return true
    }

    /// How many eggs of a tier the wallet buys at once: they wait in the Bag.
    func maxEggBuyCount(_ tier: Rarity?) -> Int {
        guard canBuyEgg(tier) else { return 0 }
        let price = price(of: .egg(tier))
        return price > 0 ? availableTokens / price : 0
    }

    /// Evolution stone use gate: a stone in the Bag and, like an egg purchase, a companion to send off.
    func canUseStone(_ kind: ItemKind, onReturn: Bool = false) -> Bool {
        kind.stoneType != nil && canSendOffActive(onReturn: onReturn) && itemCount(kind) > 0
    }

    /// Uses one evolution stone from the Bag. Like an egg purchase, the current Pokémon is sent off right
    /// away for an egg, here guaranteed to hatch the stone's type.
    @discardableResult
    func useStone(_ kind: ItemKind) -> Bool {
        guard canUseStone(kind), let type = kind.stoneType else { return false }
        state.inventory[kind.rawValue] = itemCount(kind) - 1   // saved with the new egg
        replaceActiveWithEgg(price: 0, tier: nil, type: type)
        AppLog.write("stone used: \(kind.rawValue), discarded active, type=\(type.rawValue)")
        return true
    }

    func canUseTypeNullEgg(onReturn: Bool = false) -> Bool { canSendOffActive(onReturn: onReturn) && itemCount(.typeNullEgg) > 0 }

    /// Uses the Type: Null Egg, the reward for all of Silvally's Memories: like a stone, the current Pokémon is
    /// sent off for an egg, which hatches a Type: Null.
    @discardableResult
    func useTypeNullEgg() -> Bool {
        guard canUseTypeNullEgg() else { return false }
        state.inventory[ItemKind.typeNullEgg.rawValue] = itemCount(.typeNullEgg) - 1
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromTypeNullEgg = true
        state.pendingHatchID = PokemonForm.typeNullSpeciesID
        state.pendingForm = PokemonForm.resolved(baseID: PokemonForm.typeNullSpeciesID, form: nil)
        save()
        AppLog.write("type null egg used, discarded active")
        return true
    }

    // MARK: Pikachu's costumes

    /// A Pikachu arrived: it brings a costume the player doesn't have yet, chosen from the individual's own seed so
    /// the rolls that follow stay the same, and wears it while it grows.
    private func grantPikachuCostume() {
        let seed = state.active?.profile?.seed ?? UInt64(clock().timeIntervalSince1970)
        guard let costume = PikachuCostume.next(owned: state.pikachuCostumes, seed: seed) else { return }
        state.pikachuCostumes.insert(costume)
        state.active?.pikachuCostume = costume
        AppLog.write("pikachu costume won: \(costume.rawValue)")
        notifyCompanionEvent(l.notifPikachuCostumeTitle, l.notifPikachuCostumeBody(l.pikachuCostumeName(costume)))
    }

    /// Pikachu wears `costume` (one won), or its own look with nil.
    @discardableResult
    func equipPikachuCostume(_ costume: PikachuCostume?) -> Bool {
        if let costume, !state.pikachuCostumes.contains(costume) { return false }
        state.equippedPikachuCostume = costume
        save()
        return true
    }

    func canUseBagEgg(_ kind: ItemKind, onReturn: Bool = false) -> Bool {
        kind.isShopEgg && canSendOffActive(onReturn: onReturn) && itemCount(kind) > 0
    }

    /// Uses one of the Shop's eggs from the Bag, bought or given by an achievement. The current Pokémon is sent off
    /// for an egg that hatches anew, a Pokémon of the egg's rarity or better.
    ///
    /// The Pokémon sent off stays in the Pokédex (`releasedDexEntry`), its growth is lost, and `collectedFinals` is
    /// left alone: it was not raised to the end. No species is rolled here, so offline nothing is lost: the egg's
    /// guarantee is written in the state (`eggTier`) and the hatch reads it.
    @discardableResult
    func useBagEgg(_ kind: ItemKind) -> Bool {
        guard canUseBagEgg(kind) else { return false }
        let tier = kind.bagEggTier
        state.inventory[kind.rawValue] = itemCount(kind) - 1   // saved with the new egg
        replaceActiveWithEgg(price: 0, tier: tier, type: nil)
        AppLog.write("bag egg used: \(kind.rawValue), discarded active, tier=\(tier?.rawValue ?? "none")")
        return true
    }

    func canUseLegendaryEgg(onReturn: Bool = false) -> Bool { canSendOffActive(onReturn: onReturn) && itemCount(.legendaryEgg) > 0 }

    /// Uses a Legendary Egg, the reward for a region whose every species is in the Pokédex: like a stone, the
    /// current Pokémon is sent off for an egg, which hatches a legendary or mythical Pokémon (`chooseBase`).
    @discardableResult
    func useLegendaryEgg() -> Bool {
        guard canUseLegendaryEgg() else { return false }
        state.inventory[ItemKind.legendaryEgg.rawValue] = itemCount(.legendaryEgg) - 1
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromLegendaryEgg = true
        save()
        AppLog.write("legendary egg used, discarded active")
        return true
    }

    func canUseBirthdayEgg(onReturn: Bool = false) -> Bool { canSendOffActive(onReturn: onReturn) && itemCount(.birthdayEgg) > 0 }

    /// Uses the Birthday Egg: like a stone, the current Pokémon is sent off for an egg, which hatches a mythical
    /// Pokémon not graduated yet (`BirthdayGift.pool`).
    @discardableResult
    func useBirthdayEgg() -> Bool {
        guard canUseBirthdayEgg() else { return false }
        state.inventory[ItemKind.birthdayEgg.rawValue] = itemCount(.birthdayEgg) - 1
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromBirthdayEgg = true
        save()
        AppLog.write("birthday egg used, discarded active")
        return true
    }

    /// The Pokémon raised hatched from a Fossil Egg: sent off, it gives its egg back (#77).
    var isRaisingFossilEggPokemon: Bool { state.active?.fromFossilEgg == true }

    /// Not on a Fossil Egg's own Pokémon: sent off, it gives its egg back, so the egg would cost nothing and fossil
    /// hatches would reroll for free (#90). A stone or a Shop egg sends it off.
    func canUseFossilEgg(onReturn: Bool = false) -> Bool {
        canSendOffActive(onReturn: onReturn) && !isRaisingFossilEggPokemon && itemCount(.fossilEgg) > 0
    }

    /// Uses a Fossil Egg: like a stone, the current Pokémon is sent off for an egg, which hatches a fossil line not
    /// graduated yet (`FossilDig`).
    @discardableResult
    func useFossilEgg() -> Bool {
        guard canUseFossilEgg() else { return false }
        state.inventory[ItemKind.fossilEgg.rawValue] = itemCount(.fossilEgg) - 1
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromFossilEgg = true
        save()
        AppLog.write("fossil egg used, discarded active")
        return true
    }

    /// Whether a dungeon's egg of the Bag can be used: as a Fossil Egg, it sends the Pokémon raised off.
    func canUseDungeonEgg(_ id: String) -> Bool {
        canSendOffActive && !isRaisingFossilEggPokemon && state.dungeons.eggs.contains { $0.id == id }
    }

    /// Uses a dungeon's egg (Q20 B): the Pokémon raised is sent off for it, and it hatches its line, shiny when it was
    /// (R9 B: IVs and nature drawn at the hatch).
    @discardableResult
    func useDungeonEgg(_ id: String) -> Bool {
        guard canUseDungeonEgg(id), let egg = state.dungeons.eggs.first(where: { $0.id == id }) else { return false }
        state.dungeons.eggs.removeAll { $0.id == id }
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromDungeon = egg
        save()
        AppLog.write("dungeon egg used: line \(egg.baseID) shiny=\(egg.isShiny)")
        return true
    }

    // MARK: Costume Eggs

    /// One Costume Egg every 300M tokens used during the month's event (the owner, 2026-11-13), only while its lot has
    /// more costumes left to collect than eggs waiting (the owner, 2026-11-18: "si dans l'inventaire on a 3 œufs et
    /// qu'il nous reste 3 costumes à déverrouiller, on gagne pas de 4e œuf"). What an egg holds is drawn when opened.
    func earnCostumeEggs(_ tokens: Int, day: String) {
        guard tokens > 0, let month = CostumeCatalog.month(ofDay: day) else { return }
        let total = state.costumeEggTokens + tokens
        let count = total / CostumeCatalog.tokensPerEgg
        state.costumeEggTokens = total % CostumeCatalog.tokensPerEgg
        guard count > 0 else { return }
        var earned = 0
        for _ in 0..<count where costumeEggsLeftToEarn(month: month) > 0 {
            state.costumeEggs.append(CostumeEgg(month: month))
            earned += 1
        }
        guard earned > 0 else { return }
        AppLog.write("costumes: +\(earned) egg(s) of month \(month)")
        notifyCompanionEvent(l.costumeEggEarnedTitle, l.costumeEggEarnedBody(event: l.costumeEventName(month), count: earned))
    }

    /// The costumes collected or promised: the Pokédex's, the Pokémon raised's, the egg incubating's.
    private var costumesTakenOrIncubating: Set<String> {
        var taken = costumesTaken()
        if let start = state.eggFromCostume?.entry { taken.formUnion(CostumeCatalog.family(of: start).map(\.key)) }
        return taken
    }

    /// The eggs `month`'s lot can still give: its costumes not collected nor promised, less the eggs of that month
    /// waiting in the Bag.
    func costumeEggsLeftToEarn(month: Int) -> Int {
        let taken = costumesTakenOrIncubating
        let left = CostumeCatalog.lot(month: month).filter { !taken.contains($0.key) }.count
        return left - state.costumeEggs.filter { $0.month == month }.count
    }

    /// A costume's stages the player can raise: those of species already graduated, each grown from the one before
    /// (the owner, 2026-11-18: a costumed Eevee grew into Eeveelutions never caught).
    static func ownedFamily(of entry: CostumeEntry, owned: Set<Int>) -> [CostumeEntry] {
        [entry] + CostumeCatalog.children(of: entry).filter { owned.contains($0.speciesID) }
            .flatMap { ownedFamily(of: $0, owned: owned) }
    }

    /// What a Costume Egg of `month` can hatch now: each costume line from the first of its species the player has,
    /// when its stages they can raise still hold a costume not collected. None: the egg waits, locked.
    func costumeEggCandidates(month: Int) -> [CostumeEntry] {
        let owned = graduatedSpeciesIDs
        let taken = costumesTakenOrIncubating
        func roots(_ entry: CostumeEntry) -> [CostumeEntry] {
            owned.contains(entry.speciesID) ? [entry] : CostumeCatalog.children(of: entry).flatMap(roots)
        }
        return CostumeCatalog.starts(month: month).flatMap(roots).filter { root in
            Self.ownedFamily(of: root, owned: owned).contains { !taken.contains($0.key) }
        }
    }

    /// What an opened Costume Egg holds: one of its candidates, at random. Nil when none.
    func drawCostumeEgg(month: Int) -> CostumeEgg? {
        let pool = costumeEggCandidates(month: month)
        guard !pool.isEmpty else { return nil }
        let pick = pool[Int(rng.next() % UInt64(pool.count))]
        return CostumeEgg(id: UUID().uuidString, code: pick.code, speciesID: pick.speciesID, form: pick.form, month: month)
    }

    /// Whether a Costume Egg of the Bag is locked: none of the player's Pokémon has a costume left in its lot.
    func isCostumeEggLocked(_ id: String) -> Bool {
        guard let egg = state.costumeEggs.first(where: { $0.id == id }) else { return false }
        return costumeEggCandidates(month: egg.month).isEmpty
    }

    /// Whether a Costume Egg of the Bag can be used: as any egg, it sends the Pokémon raised off; not while locked.
    func canUseCostumeEgg(_ id: String) -> Bool {
        canSendOffActive && !isRaisingFossilEggPokemon && state.costumeEggs.contains { $0.id == id } && !isCostumeEggLocked(id)
    }

    /// Uses a Costume Egg: what it holds is drawn now, the Pokémon raised is sent off for it, and it hatches its
    /// costumed Pokémon (`hatchCore`).
    @discardableResult
    func useCostumeEgg(_ id: String) -> Bool {
        guard canUseCostumeEgg(id), let egg = state.costumeEggs.first(where: { $0.id == id }),
              var content = drawCostumeEgg(month: egg.month) else { return false }
        content.id = egg.id
        state.costumeEggs.removeAll { $0.id == id }
        replaceActiveWithEgg(price: 0, tier: nil, type: nil)
        state.eggFromCostume = content
        save()
        AppLog.write("costume egg used: \(content.code) #\(content.speciesID)")
        return true
    }

    // MARK: Event eggs

    /// The player's very first catch, its time and line: the companion's anniversary egg follows it.
    var firstCatch: (date: Date, baseID: Int)? {
        state.dex.compactMap { e in e.caughtAt.map { (date: $0, baseID: e.baseID) } }.min { $0.date < $1.date }
    }

    /// The line the Friendship Egg brings back: the first catch's, unless it was a Ditto, which no egg hatches (its
    /// record carries Ditto's number once revealed, left out of every egg's pool): then the next catch's. A Ditto
    /// first kept the egg waiting for a candidate forever, and with no Pokémon raised nothing else could be used.
    var companionLineID: Int? { state.companionLineID }

    /// The event eggs waiting now, earliest event first (`EventEgg.claimable`).
    var eventEggs: [(egg: EventEgg, year: Int)] {
        EventEgg.claimable(now: clock(), claimed: state.claimedEventEggs, firstCatch: firstCatch?.date, calendar: LocalUsageReader.gregorianCalendar())
    }

    /// One line of the events' calendar (7.6): an event egg in one year, or the birthday.
    struct CalendarItem: Equatable, Sendable {
        enum Source: Equatable, Sendable { case event(EventEgg), birthday }
        enum Status: Equatable, Sendable {
            case toTake
            /// `hatched`: the base it hatched, once used (recorded from 2026-10-29).
            case taken(hatched: Int?)
            case upcoming
        }
        let source: Source
        let year: Int
        let start: Date
        /// The start of the day after the last one.
        let end: Date
        let status: Status
    }

    /// The calendar: the eggs on now (to take or taken), the next ones within a year, earliest first, and those taken
    /// this year that are over.
    func eventCalendar() -> (now: [CalendarItem], upcoming: [CalendarItem], taken: [CalendarItem]) {
        let calendar = LocalUsageReader.gregorianCalendar()
        let today = clock()
        let year = calendar.component(.year, from: today)
        let horizon = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        var now: [CalendarItem] = [], upcoming: [CalendarItem] = [], taken: [CalendarItem] = []
        for egg in EventEgg.allCases {
            // Within a year from now, a yearly event comes once at most.
            for y in [year - 1, year, year + 1, year + 2] {
                guard let days = egg.days(in: y, firstCatch: firstCatch?.date, calendar: calendar) else { continue }
                let key = egg.key(year: y)
                let claimEnd = calendar.date(byAdding: .day, value: egg.claimDays, to: days.end) ?? days.end
                let status: CalendarItem.Status = state.claimedEventEggs.contains(key)
                    ? .taken(hatched: state.eventEggHatches[key]) : .toTake
                let item = CalendarItem(source: .event(egg), year: y, start: days.start, end: days.end, status: status)
                if today >= days.start && today < claimEnd {
                    now.append(item)
                } else if days.start > today, days.start < horizon {
                    upcoming.append(CalendarItem(source: .event(egg), year: y, start: days.start, end: days.end,
                                                 status: .upcoming))
                } else if case .taken = status, calendar.component(.year, from: days.start) == year
                            || calendar.component(.year, from: days.end) == year, today >= claimEnd {
                    taken.append(item)
                }
            }
        }
        if let birthday = state.birthday {
            let thisYear = birthday.date(in: year, calendar: calendar)
            let next = thisYear >= calendar.startOfDay(for: today) ? thisYear : birthday.date(in: year + 1, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            upcoming.append(CalendarItem(source: .birthday, year: calendar.component(.year, from: next), start: next,
                                         end: end, status: .upcoming))
        }
        return (now.sorted { $0.start < $1.start }, upcoming.sorted { $0.start < $1.start },
                taken.sorted { $0.start > $1.start })
    }

    /// Whether this waiting egg's event is on, rather than in the two weeks after it.
    func isEventOn(_ egg: EventEgg, year: Int) -> Bool {
        egg.isOn(year: year, now: clock(), firstCatch: firstCatch?.date, calendar: LocalUsageReader.gregorianCalendar())
    }

    /// Puts a waiting event egg in the Bag, once for its year.
    @discardableResult
    func claimEventEgg(_ egg: EventEgg) -> Bool {
        guard let pending = eventEggs.first(where: { $0.egg == egg }) else { return false }
        state.inventory[egg.item.rawValue, default: 0] += 1
        state.claimedEventEggs.insert(egg.key(year: pending.year))
        save()
        AppLog.write("event egg claimed: \(egg.key(year: pending.year))")
        return true
    }

    func canUseEventEgg(_ egg: EventEgg, onReturn: Bool = false) -> Bool {
        canSendOffActive(onReturn: onReturn) && itemCount(egg.item) > 0
    }

    /// Uses an event egg: like a stone, the current Pokémon is sent off for an egg, which hatches the event's Pokémon.
    @discardableResult
    func useEventEgg(_ egg: EventEgg) -> Bool {
        guard canUseEventEgg(egg) else { return false }
        state.inventory[egg.item.rawValue] = itemCount(egg.item) - 1
        replaceActiveWithEgg(price: 0, tier: egg.tier, type: egg.type)
        state.eggEvent = egg
        // The latest claim of this event not hatched yet: what comes out is its.
        state.eggEventKey = state.claimedEventEggs
            .filter { $0.hasPrefix(egg.rawValue + "@") && state.eventEggHatches[$0] == nil }.max()
        save()
        AppLog.write("event egg used: \(egg.rawValue), discarded active")
        return true
    }

    /// The notification, once per waiting event egg.
    private func announceEventEggsIfNeeded() {
        for pending in eventEggs {
            let key = pending.egg.key(year: pending.year)
            guard !state.eventEggsNotified.contains(key) else { continue }
            state.eventEggsNotified.insert(key)
            let title = isEventOn(pending.egg, year: pending.year) ? l.eventEggWish(pending.egg) : l.eventEggStillWaiting(pending.egg)
            notifyCompanionEvent(title, l.eventEggBody(pending.egg))
        }
    }

    private var eggFormTypes: [PokemonType] { incubatingEgg.formTypes }


    // MARK: Birthday gift

    /// The birthday gift claimable now, and whether it is the birthday's week or a catch-up (`BirthdayGift`).
    var birthdayGift: (year: Int, occasion: BirthdayGift.Occasion)? {
        BirthdayGift.claimable(birthday: state.birthday, lastGiftYear: state.lastBirthdayGiftYear,
                               changedAfterGiftYear: state.birthdayChangedAfterGiftYear, now: clock(), calendar: LocalUsageReader.gregorianCalendar())
    }

    /// Sets the player's birthday, or clears it with nil. Changing it never brings a second gift within a year: after
    /// a gift, the next one must be for a birthday year later than the calendar year it was claimed in.
    func setBirthday(_ birthday: Birthday?) {
        guard state.birthday != birthday else { return }
        if let lastGift = state.lastBirthdayGiftYear {
            // The date of the last gift. A save from before it was kept: the date set until now if it has not moved
            // since the gift, else unknown (#92), and then no date typed lifts the block. Settings clear the date,
            // then set a month, then a day: only a date that differs from the gift's waits for a later year, and
            // clearing it sets nothing.
            let giftDate = state.lastBirthdayGiftDate
                ?? (state.birthdayChangedAfterGiftYear == nil ? state.birthday : nil)
            if let giftDate { state.lastBirthdayGiftDate = giftDate }
            if let birthday, birthday != giftDate {
                // A save that claimed before the claim date was kept: its gift's birthday year, at least.
                let claimedIn = state.lastBirthdayGiftClaimedAt.map { LocalUsageReader.gregorianCalendar().component(.year, from: $0) } ?? lastGift
                state.birthdayChangedAfterGiftYear = max(state.birthdayChangedAfterGiftYear ?? claimedIn, claimedIn)
            } else if let giftDate, birthday == giftDate {
                state.birthdayChangedAfterGiftYear = nil
            }
        }
        state.birthday = birthday
        announceBirthdayGiftIfNeeded()
        save()
    }

    /// Puts the Birthday Egg in the Bag, once for this birthday's year.
    @discardableResult
    func claimBirthdayGift() -> Bool {
        guard let gift = birthdayGift else { return false }
        state.inventory[ItemKind.birthdayEgg.rawValue] = itemCount(.birthdayEgg) + 1
        state.lastBirthdayGiftYear = gift.year
        state.lastBirthdayGiftClaimedAt = clock()
        state.lastBirthdayGiftDate = state.birthday
        save()
        AppLog.write("birthday gift claimed for \(gift.year) (\(gift.occasion))")
        return true
    }

    /// The notification, once per birthday whose gift waits.
    private func announceBirthdayGiftIfNeeded() {
        guard let gift = birthdayGift, state.birthdayNotifiedYear != gift.year else { return }
        state.birthdayNotifiedYear = gift.year
        notifyCompanionEvent(gift.occasion == .birthday ? l.notifBirthdayTitle : l.birthdayBelatedTitle, l.notifBirthdayBody)
    }

    /// Shared reset of `buyEgg` and `useStone`: pays (nothing for a stone), sends the current Pokémon off
    /// (kept in the Pokédex) and starts a new egg carrying the guarantee.
    private func replaceActiveWithEgg(price: Int, tier: Rarity?, type: PokemonType?) {
        state.spentTokens += price
        // The Old Amber keeps part of what the Pokémon sent off grew at its stage, for the one that hatches. Read
        // before the write: `state` is not read inside its own assignment.
        let kept = itemCount(.oldAmber) > 0
            ? (state.active.map { max(0, $0.usedAtStage) / 100 * CollectorBonus.oldAmberKeptPercent } ?? 0) : 0
        state.amberCarry = kept
        if let a = state.active {
            state.dex.append(releasedDexEntry(from: a))   // 놓아줌 기록 — 도감에서 종이 사라지지 않게
            // A Fossil Egg's Pokémon sent off before it graduates gives its egg back: its line has no other egg.
            if a.fromFossilEgg {
                state.inventory[ItemKind.fossilEgg.rawValue] = itemCount(.fossilEgg) + 1
                AppLog.write("fossil egg: back to the Bag, its Pokémon sent off before graduating")
            }
        }
        state.active = nil            // 놓아줌 (졸업 아님 — collectedFinals 는 미변경)
        // 놓아준 종도 이제 dex 에 있으므로 대표 선택은 유지된다. 손상 상태 파일 등으로 정말 보유가
        // 끊긴 경우만 자동 추적으로 복귀한다.
        state.reconcileRepresentativeSelection()
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0            // 새 알은 처음부터 인큐베이션(재부화에 5M 필요)
        isHatchRetryDelayed = false
        state.eggTier = tier          // 등급 보증(nil = 보증 없음)
        state.eggTypeGuarantee = type // 진화의 돌의 타입 보증(nil = 보증 없음)
        state.eggFromTypeNullEgg = false
        state.eggFromLegendaryEgg = false
        state.eggFromBirthdayEgg = false
        state.eggFromFossilEgg = false
        state.eggFromDungeon = nil
        state.eggFromCostume = nil
        state.eggEvent = nil
        state.eggEventKey = nil
        state.pendingHatchID = nil    // 새 보증으로 처음부터 롤(활성 포켓몬이 있는 동안엔 원래 비어 있다)
        state.pendingForm = nil
        state.pendingShiny = false
        prefetchedLineID = nil
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        Task { await self.ensureEggPrefetch() }   // 다음 부화 예열
        save()
    }

    /// Parse an epoch string into a Date, supporting Unix timestamp (seconds or ms) or ISO8601 strings.
    nonisolated static func parseEpochDate(_ string: String) -> Date? {
        if let ts = Double(string) {
            if ts > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: ts / 1000.0)
            } else if ts > 100_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return ISO8601Parser.date(from: string)
    }

    /// Whether `day` comes before `other`, both `yyyy-MM-dd`; false for anything else (an empty or test date).
    nonisolated static func isEarlierDay(_ day: String, than other: String) -> Bool {
        func isDay(_ s: String) -> Bool {
            s.count == 10 && s.enumerated().allSatisfy { i, c in i == 4 || i == 7 ? c == "-" : c.isASCII && c.isNumber }
        }
        return isDay(day) && isDay(other) && day < other
    }

    /// Below this, a window without an epoch has gone down for real and starts again (`evaluateCandyGrants`).
    static let epochlessRearmUtilization: Double = 50

    /// How a window's epoch moved since the last poll.
    enum EpochChange: Equatable { case same, reset, otherWindow }

    /// Less than 30 minutes (a day for a week) is the same window: network jitter (Codex ±1 s), fractional seconds
    /// (Claude), a rolling window's drift. Non-date strings (synthetic tests) differ as a reset.
    /// A window resets once its epoch is past: one that moves by a window's worth while the previous one still
    /// runs is another window under the same key (`/login` to another account in the same folder, `codex login`,
    /// another organization answering). Paid as a reset, it paid that account's whole usage at once, and switching
    /// back paid the gap again. A few minutes of slack for the Mac's clock.
    static func epochChange(previous: String, current: String, kind: WindowClass, now: Date) -> EpochChange {
        guard previous != current else { return .same }
        guard let dPrev = parseEpochDate(previous), let dCurr = parseEpochDate(current) else { return .reset }
        let delta = dCurr.timeIntervalSince(dPrev)
        let minAdvance: TimeInterval = kind == .weekly ? 86400 : 1800
        guard abs(delta) >= minAdvance else { return .same }
        return delta > 0 && now >= dPrev.addingTimeInterval(-300) ? .reset : .otherWindow
    }

    /// The candies each window owes now (`RareCandy.candiesDue`), less those it already paid in its epoch. Pure, so
    /// it is tested apart from the Bag and the notifications (evaluateLimitAlerts 자매).
    /// - The ledger (`grantTier`) keeps what each window paid. A new epoch (`resets_at`) starts it again, even when the
    ///   app never saw the window go down (#326); the key never holds the epoch.
    /// - Without an epoch, a window back to nothing owed, and under half full, is a new one.
    /// - What a window paid is never taken back: a utilization that goes down a little pays nothing until it is past
    ///   it again.
    /// - Another window under the key (`epochChange`) pays from now on, as a window first seen does (#79).
    static func evaluateCandyGrants(
        windows: [CandyWindow],
        grantTier: inout [String: Int],
        windowEpoch: inout [String: String],
        now: Date = .distantFuture
    ) -> [CandyGrant] {
        var grants: [CandyGrant] = []
        for w in windows {
            let due = RareCandy.candiesDue(utilization: w.utilization, kind: w.kind, planMultiplier: w.planMultiplier)
            if let epoch = w.epoch {
                if let previousEpoch = windowEpoch[w.key] {
                    switch epochChange(previous: previousEpoch, current: epoch, kind: w.kind, now: now) {
                    case .same:
                        // A reset time that slides (Antigravity's moves a little at each poll) is followed, so a poll
                        // is compared to the last one seen: compared to the first, the slides added up once the
                        // window's end was past and passed for a reset. Under a minute it stays, so a jitter
                        // (Claude's fractional seconds, Codex's 1 s) changes nothing to save.
                        if let p = parseEpochDate(previousEpoch), let c = parseEpochDate(epoch),
                           abs(c.timeIntervalSince(p)) >= 60 {
                            windowEpoch[w.key] = epoch
                        }
                    case .reset:
                        grantTier[w.key] = nil
                        windowEpoch[w.key] = epoch
                    case .otherWindow:
                        grantTier[w.key] = due > 0 ? due : nil
                        windowEpoch[w.key] = epoch
                        continue
                    }
                } else {
                    windowEpoch[w.key] = epoch
                }
            }
            var paid = grantTier[w.key] ?? 0
            // Without an epoch, only a real drop starts a window again: a Pro session hovering around its limit
            // (100%, 99.6%, 100%) owes nothing at each dip and paid its candy again at each return.
            if w.epoch == nil, due == 0, w.utilization < Self.epochlessRearmUtilization { paid = 0 }
            if due > paid {
                let whole = RareCandy.windowCandies(kind: w.kind, planMultiplier: w.planMultiplier)
                grants.append(CandyGrant(windowKey: w.key, windowName: w.name, count: due - paid,
                                         completesWindow: due == whole))
                paid = due
            }
            grantTier[w.key] = paid > 0 ? paid : nil
        }
        return grants
    }

    /// Pays the candies the limit windows owe (`evaluateCandyGrants`). AppDelegate 가 매 refresh 완료 시(한도 로드 후)
    /// 호출. limitsReady=false(한도 미로딩)면 대기(다음 refresh 에 재시도).
    /// - First run: what the windows already owe is not paid back; they pay from then on.
    /// - A save from the rule that paid at 100% only: a window it already paid owes nothing more in its epoch, any
    ///   other pays its usage so far.
    /// - A window first seen later (another login, a Codex bucket), or seen at another plan, pays from then on too:
    ///   a Max 20x login added at 80% of its week would pay 80 candies at once, a Pro week at 60% read as Max 5x 12
    ///   (#79).
    func grantCandies(from polled: [CandyWindow], limitsReady: Bool) {
        guard limitsReady else { return }
        let now = clock()
        // A plan read as 1 is a plan unknown for that poll (`LimitStatus.planMultiplier`) when a bigger one is known for
        // the same window: re-seeded at 1 and back, the window lost what it owed between the two polls.
        let windows = polled.map { w -> CandyWindow in
            guard w.planMultiplier == 1, let known = state.candyWindowPlan[w.key], known > 1,
                  let previous = state.candyWindowEpoch[w.key], let epoch = w.epoch,
                  Self.epochChange(previous: previous, current: epoch, kind: w.kind, now: now) == .same
            else { return w }
            return w.withPlanMultiplier(known)
        }
        if !state.candyFeatureSeeded {
            // 한계(수용): 첫 refresh 에 한 프로바이더 한도만 로드되면 그 프로바이더 창만 시드된다. refresh() 는 전
            // 프로바이더 fetch 를 await 후 onRefresh 하므로 정상 경로에선 원자적 시드다.
            for w in windows { seedCandyLedger(w, paid: true) }
            state.candyFeatureSeeded = true
            state.candyGrantsAsYouGo = true
            save()
            return
        }
        if !state.candyGrantsAsYouGo {
            for w in windows { seedCandyLedger(w, paid: (state.candyGrantTier[w.key] ?? 0) >= 1) }
            state.candyGrantsAsYouGo = true
            save()
        }
        let beforeTier = state.candyGrantTier
        let beforeEpoch = state.candyWindowEpoch
        let beforePlan = state.candyWindowPlan
        for w in windows where state.candyWindowPlan[w.key] != w.planMultiplier {
            let firstSeen = state.candyWindowPlan[w.key] == nil
            let paid = state.candyGrantTier[w.key] ?? 0
            // A window whose stored one has ended is new whatever its plan: what the ended one paid is not carried
            // over (an old save opened after a reset kept last week's count), it starts from nothing as any reset.
            if let previous = state.candyWindowEpoch[w.key], let epoch = w.epoch,
               Self.epochChange(previous: previous, current: epoch, kind: w.kind, now: now) == .reset {
                state.candyWindowPlan[w.key] = w.planMultiplier
                AppLog.write("candies: \(w.key) plan ×\(w.planMultiplier) in a new window, pays from nothing")
                continue
            }
            seedCandyLedger(w, paid: true)
            // Seen for the first time, what it paid already stays paid; at another plan, it paid that plan's share.
            if firstSeen, paid > (state.candyGrantTier[w.key] ?? 0) { state.candyGrantTier[w.key] = paid }
            AppLog.write("candies: \(w.key) \(firstSeen ? "first seen" : "plan now ×\(w.planMultiplier)"), pays from \(state.candyGrantTier[w.key] ?? 0)")
        }
        var grantTier = state.candyGrantTier
        var windowEpoch = state.candyWindowEpoch
        let grants = Self.evaluateCandyGrants(
            windows: windows,
            grantTier: &grantTier,
            windowEpoch: &windowEpoch,
            now: now)
        if state.candyGrantTier != grantTier { state.candyGrantTier = grantTier }
        if state.candyWindowEpoch != windowEpoch { state.candyWindowEpoch = windowEpoch }
        let meteorite = itemCount(.meteorite) > 0 ? CollectorBonus.meteoriteWindowCandies : 0
        for g in grants {
            let received = addRareCandies(g.count + (g.completesWindow ? meteorite : 0))
            pendingCandyNotice.count += received
            pendingCandyNotice.windows.append(g.windowName)
        }
        if !grants.isEmpty {
            AppLog.write("candies: " + grants.map { "\($0.windowKey) +\($0.count)" }.joined(separator: ", "))
        }
        announcePendingCandies()
        // 지급이 없어도 원장 변화(epoch 교체)는 영속해야 한다: 안 하면 재시작 시 지난 창의 원장으로 판정한다.
        if !grants.isEmpty
            || state.candyGrantTier != beforeTier
            || state.candyWindowEpoch != beforeEpoch
            || state.candyWindowPlan != beforePlan {
            save()
        }
    }

    /// Adds a refresh's new tokens to the raising record of the Pokémon raised (`RaisingRecord.add`).
    private func recordRaising(_ deltas: [String: Int]) {
        guard state.active?.raising != nil else { return }
        for (provider, tokens) in deltas where tokens > 0 {
            state.active?.raising?.add(tokens, provider: provider, day: todayUsageDetails[provider])
        }
    }

    /// Whether a provider's tokens pay Rare Candies by themselves: one that never had a limit window the candies read
    /// (Cursor, Gemini CLI, OpenCode…). A provider that had one is paid by its windows, never twice.
    func paysCandiesByTokens(_ providerID: String) -> Bool {
        !state.candyWindowPlan.keys.contains { CandyWindow.providerID(forKey: $0) == providerID }
    }

    /// Pays a candy for every `RareCandy.tokensPerCandyWithoutLimits` tokens of the tools without limit windows,
    /// keeping what is left for the next one. `deltas`: each provider's tokens credited by this refresh.
    private func earnTokenCandies(_ deltas: [String: Int]) {
        let tokens = deltas.reduce(0) { sum, entry in
            entry.value > 0 && paysCandiesByTokens(entry.key) ? sum + entry.value : sum
        }
        guard tokens > 0 else { return }
        let total = state.tokenCandyTokens + tokens
        let candies = total / RareCandy.tokensPerCandyWithoutLimits
        state.tokenCandyTokens = total % RareCandy.tokensPerCandyWithoutLimits
        guard candies > 0 else { return }
        state.tokenCandiesEarned += candies
        pendingCandyNotice.count += addRareCandies(candies)
        pendingCandyNotice.windows.append(l.tokenCandiesSource)
        AppLog.write("candies: +\(candies) from tools without limits")
        announcePendingCandies()
    }

    /// Records a window as paid up to what it owes now (`paid`), or as owing all of it.
    private func seedCandyLedger(_ w: CandyWindow, paid: Bool) {
        let due = RareCandy.candiesDue(utilization: w.utilization, kind: w.kind, planMultiplier: w.planMultiplier)
        state.candyGrantTier[w.key] = paid && due > 0 ? due : nil
        if let epoch = w.epoch { state.candyWindowEpoch[w.key] = epoch }
        state.candyWindowPlan[w.key] = w.planMultiplier
    }

    /// Candies paid since the last candy notification. Windows pay as they go, a bigger plan every few percent, so
    /// one notification sums them at most once an hour.
    private var pendingCandyNotice: (count: Int, windows: [String]) = (0, [])
    private var lastCandyNotice: Date?
    static let candyNoticeInterval: TimeInterval = 3600

    private func announcePendingCandies() {
        guard pendingCandyNotice.count > 0 else { return }
        if let last = lastCandyNotice, clock().timeIntervalSince(last) < Self.candyNoticeInterval { return }
        var seen = Set<String>()
        let names = pendingCandyNotice.windows.filter { seen.insert($0).inserted }.joined(separator: " · ")
        notifyCompanionEvent(l.notifCandyTitle(item: l.itemName(.rareCandy), count: pendingCandyNotice.count),
                             l.notifCandyBody(window: names))
        pendingCandyNotice = (0, [])
        lastCandyNotice = clock()
    }

    /// companion 이벤트 시스템 알림(.app + 토글 ON 일 때만). 한도 알림과 독립.
    private var notifSeq = 0
    func notifyCompanionEvent(_ title: String, _ body: String) {
        guard AppEnv.isBundledApp else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        notifSeq += 1
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "companion-event-\(notifSeq)", content: content, trigger: nil))
    }

    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, !isHatching, state.eggUsage >= eggHatchThreshold else { return }
        dropDungeonOnlyPreRoll()
        // 프리패치가 "종 롤 중"(pending 미확정)일 때만 대기 — 이중 rng 소비 방지.
        // pending 확정 후의 예열(라인/스프라이트)과는 동시 진행해도 안전하다.
        guard state.pendingHatchID != nil || !prefetchInFlight else { return }
        // isHatching 을 롤~부화 전체에 defer 로 잠근다. 과거엔 chooseBase 후 isHatching 을 잠깐
        // 내렸다가(hatch 자체 가드 통과용) hatch 를 호출해, 그 await 창에서 다른 update 틱이
        // 두 번째 종을 롤하는 경합이 있었다. hatchCore 는 isHatching 을 재검사하지 않으므로
        // 여기서 소유한 락 하나로 롤·부화가 원자적으로 보호된다.
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        // 프리패칭된 종이 있으면 그대로 사용(라인·스프라이트 예열됨 → 딜레이 ~0), 없으면 지금 롤.
        let base: Int?
        var forceShiny = state.pendingShiny
        if let pending = state.pendingHatchID {
            base = pending
        } else {
            let pick = await chooseBase()
            base = pick?.id
            forceShiny = pick?.shiny ?? false
        }
        guard isCurrentReadyEgg(generation: generation) else {
            AppLog.write("hatch: discarded before result handling — subject replaced during species roll")
            kickLineLoadIfNeeded()
            return
        }
        guard let base else {
            isHatchRetryDelayed = true
            return
        }
        let pendingForm = state.pendingHatchID == base ? state.pendingForm : HatchDraw.eventForm(baseID: base, event: state.eggEvent)
        let rollItems = state.pendingHatchID == base ? state.pendingHatchItems : nil
        await hatchCore(baseID: base, generation: generation, form: pendingForm, forceShiny: forceShiny,
                        rollItems: rollItems)
    }

    /// 부화가 폐기된 뒤 남은 개체(대개 방금 불러온 개체)의 진화 라인을 다시 로드한다.
    /// `loadCurrentLine` 은 `!isHatching` 을 요구하므로 부화 중에 걸린 로드는 조용히 실패한다 —
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "…" 로 남는다.
    /// Task 본문은 현재 동기 실행(= defer 로 isHatching 해제)이 끝난 뒤 돌므로 락이 이미 풀려 있다.
    private func kickLineLoadIfNeeded() {
        guard state.active != nil, currentLine == nil else { return }
        Task { await loadCurrentLine() }
    }

    // MARK: 알 프리패칭

    private var prefetchInFlight = false
    private var prefetchedLineID: Int?   // 라인·스프라이트 예열 완료한 종(세션 메모리)

    private func isCurrentEgg(generation: Int) -> Bool {
        activeGeneration == generation && state.active == nil
    }

    private func isCurrentReadyEgg(generation: Int) -> Bool {
        isCurrentEgg(generation: generation) && state.eggUsage >= eggHatchThreshold
    }

    private func markHatchRetryDelayedIfReady(generation: Int) {
        guard isCurrentReadyEgg(generation: generation) else { return }
        isHatchRetryDelayed = true
    }

    private func finishEggPrefetch(generation: Int, shouldHatch: Bool) {
        prefetchInFlight = false
        guard shouldHatch, isCurrentReadyEgg(generation: generation) else { return }
        Task { await self.hatchIfNeeded() }
    }

    /// 알 상태에서 부화를 미리 준비 — ① 종 pre-roll(pendingHatchID, 영속) ② 진화 라인
    /// fetch(provider 캐시 적재) ③ 스프라이트 예열(정적+애니메이션+shiny 애니메이션).
    /// 전부 성공하면 부화 순간 네트워크 0. 실패 지점부터 다음 update 틱에 이어서 재시도.
    private func ensureEggPrefetch() async {
        guard state.active == nil, !isHatching, !prefetchInFlight else { return }
        let generation = activeGeneration
        var shouldHatch = false
        prefetchInFlight = true
        defer { finishEggPrefetch(generation: generation, shouldHatch: shouldHatch) }

        dropDungeonOnlyPreRoll()
        if state.pendingHatchID == nil {
            let selected = await chooseBase()
            // await 사이에 부화가 끝났거나(active != nil) 상태가 통째로 교체됐으면(세이브 불러오기)
            // 이 롤을 버린다 — 안 그러면 불러온 알의 pre-roll 을 남의 롤로 덮어쓴다.
            guard isCurrentEgg(generation: generation) else { return }
            guard let pick = selected else {
                markHatchRetryDelayedIfReady(generation: generation)
                return
            }
            let id = pick.id
            state.pendingHatchID = id
            state.pendingHatchItems = hatchDraw.items
            state.pendingShiny = pick.shiny
            state.pendingForm = state.eggFromCostume.flatMap { PokemonForm.resolved(baseID: id, form: $0.form) }
                ?? state.eggFromDungeon.flatMap { PokemonForm.resolved(baseID: id, form: $0.form) }
                ?? HatchDraw.eventForm(baseID: id, event: state.eggEvent) ?? rollLineForm(baseID: id, types: eggFormTypes)
            save()
        }
        guard let id = state.pendingHatchID else { return }
        if prefetchedLineID == id {
            isHatchRetryDelayed = false
            shouldHatch = true
            return
        }
        let form = state.pendingForm
        let line: EvoLine
        do {
            line = try await provider.line(baseSpeciesID: id)
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            return
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        // 스프라이트 예열 — 부화 직후 보일 것들: base 정적+애니메이션, shiny 롤(1/64) 대비 shiny 애니메이션.
        // .app 번들에서만(단위 테스트가 실네트워크에 닿지 않도록 — 알림과 동일한 게이트).
        if AppEnv.isBundledApp {
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: true, form: form)
            if PokemonForm.hasForms(speciesID: line.baseID) {
                _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: true, form: form)
            }
            await loadFormNames(baseID: line.baseID, form: form)
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        prefetchedLineID = id
        isHatchRetryDelayed = false
        shouldHatch = true
    }

    /// Draws only for lines with forms, so other species keep their random sequence.
    private func rollLineForm(baseID: Int, types: [PokemonType] = []) -> PokemonForm? {
        let draw = hatchDraw.lineFormDraw(baseID: baseID, types: types)
        guard !draw.forms.isEmpty else { return nil }
        return PokemonForm.roll(rng.next(), among: draw.forms, collected: draw.collected)
    }

    /// Warms the localized names the hatch, evolution and graduation messages of this line show.
    private func loadFormNames(baseID: Int, form: PokemonForm?) async {
        await loadFormNames(PokemonForm.formSpecies(baseID: baseID).compactMap {
            PokemonForm.nameResource(speciesID: $0, form: form)
        })
    }

    /// The raised Pokémon's form names, for its title and its evolution and graduation messages.
    func loadActiveFormNames() async {
        guard let active = state.active else { return }
        await loadFormNames(baseID: active.baseID, form: active.form)
    }

    func loadFormNames(_ resources: [PokemonNameResource]) async {
        for resource in Set(resources) {
            _ = await PokemonNameDisplayStore.shared.load(resource, provider: PokemonNameClient.shared)
        }
    }

    func formDisplayName(_ name: String, speciesID: Int, form: PokemonForm?) -> String {
        PokemonForm.displayName(name, speciesID: speciesID, form: form, language: state.language)
    }

    func hatch(baseID: Int) async {
        guard !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        await hatchCore(baseID: baseID, generation: generation)
    }

    // MARK: 메타몽 위장/리빌

    /// 메타몽 위장 롤 판정(순수) — common·≥2형태만, 미리 뽑은 roll 값으로 1/128. (부수효과 없이 xctest)
    nonisolated static func dittoDisguiseHit(rarity: Rarity, totalForms: Int, roll: UInt64) -> Bool {
        rarity == .common && totalForms >= 2 && roll % PokemonOdds.dittoDisguiseDenominator == 0
    }

    /// 이로치 부화 분모: 부적 보유 48, 없으면 64; the Reveal Glass halves it again. 판정과 알림 문구가 같은
    /// 값을 쓰도록 여기가 단일 소스다.
    nonisolated static func shinyDenominator(charmOwned: Bool, revealGlassOwned: Bool = false) -> UInt64 {
        let denom = charmOwned ? ShinyCharm.shinyDenominator : PokemonOdds.shinyDenominator
        return revealGlassOwned ? max(1, denom / 2) : denom
    }

    /// 지금 부화하면 적용될 이로치 분모.
    var shinyDenominator: UInt64 { hatchDraw.shinyDenominator }

    /// 이로치 부화 판정(순수) — 미리 뽑은 roll 값 % 분모==0. (부수효과 없이 xctest)
    nonisolated static func rollsShiny(roll: UInt64, charmOwned: Bool, revealGlassOwned: Bool = false) -> Bool {
        roll % shinyDenominator(charmOwned: charmOwned, revealGlassOwned: revealGlassOwned) == 0
    }

    /// 실제 부화 로직 — isHatching 락은 호출자(hatch / hatchIfNeeded)가 소유·해제한다.
    /// `rollItems`: the draw items owned when the species was rolled before the hatch (`pendingHatchItems`).
    private func hatchCore(baseID: Int, generation: Int, form pendingForm: PokemonForm? = nil,
                           forceShiny: Bool = false, rollItems: Set<ItemKind>? = nil) async {
        let fetched: EvoLine
        do {
            fetched = try await provider.line(baseSpeciesID: baseID)
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            AppLog.write("hatch: line fetch failed for base \(baseID) — egg kept, retry next tick")
            return
        }
        // 라인 fetch 창(네트워크) 동안 활성 개체가 교체됐으면 이 부화 결과를 폐기한다. 세이브 불러오기가
        // 그 창에 들어오면, 여기서 멈추지 않는 한 갓 부화한 개체가 방금 불러온 개체를 덮어쓴다.
        // (loadCurrentLine·revealDitto 와 같은 세대 가드 — isHatching 락은 같은 앱 내 중복 부화만 막는다.)
        guard activeGeneration == generation else {
            AppLog.write("hatch: discarded — active subject replaced during line fetch")
            kickLineLoadIfNeeded()
            return
        }
        // 산 보증을 지키는 마지막 관문 — 진짜 등급을 아는 건 여기뿐이다(후보 인덱스엔 capture_rate 만
        // 있고 is_legendary 가 없다). 필터가 어긋났으면(인덱스 stale 등) 낮은 등급을 그냥 내주지 말고
        // 알을 유지한 채 pre-roll 만 버려 다음 틱에 다시 뽑는다 — 사용자는 산 보증을 계속 들고 있는다.
        // A season's Deerling is the exception to its egg's Uncommon guarantee (`EventEgg.tier`).
        let seasonDeerling = state.eggEvent?.seasonForm != nil && fetched.baseID == EventEgg.deerlingID
        if let tier = state.eggTier, fetched.rarity.sortRank < tier.sortRank, !seasonDeerling {
            AppLog.write("hatch: rolled \(fetched.rarity) below guaranteed \(tier) — discarded, re-roll next tick")
            state.pendingHatchID = nil
            state.pendingForm = nil
            prefetchedLineID = nil
            markHatchRetryDelayedIfReady(generation: generation)
            save()
            return
        }
        // Same last gate for a stone's type guarantee, on the pre-rolled form when there is one (a stale
        // index or pre-roll could still hand over another type). Keep the egg and re-roll next tick.
        if let typeGuarantee = state.eggTypeGuarantee,
           !PokemonTypeData.canHatch(baseID: fetched.baseID, as: typeGuarantee, form: pendingForm) {
            AppLog.write("hatch: rolled \(fetched.baseID) without guaranteed type \(typeGuarantee), discarded; re-roll next tick")
            state.pendingHatchID = nil
            state.pendingForm = nil
            prefetchedLineID = nil
            markHatchRetryDelayedIfReady(generation: generation)
            save()
            return
        }
        state.pendingHatchID = nil
        state.pendingForm = nil
        state.pendingHatchItems = nil
        // A later egg can roll the same species with another form and must warm its own sprite.
        prefetchedLineID = nil
        // A Costume Egg hatches its first costumed stage, which grows only into the stages wearing its costume.
        let costumeEgg = state.eggFromCostume
        let line = costumeEgg.flatMap { Self.costumeLine(fetched, start: $0.speciesID, code: $0.code, form: $0.form,
                                                         owned: graduatedSpeciesIDs) }
            ?? fetched
        let firstID = costumeEgg == nil ? line.baseID : line.tree.speciesID
        currentLine = line
        isHatchRetryDelayed = false
        // 부화 임계 초과분은 부화체 성장에 이월(낭비 없음).
        let overflow = max(0, state.eggUsage - eggHatchThreshold)
        state.eggUsage = 0
        let egg = incubatingEgg
        let hatchEgg = state.incubatingHatchEgg
        let draw = hatchDraw
        let fromRarityEgg = state.eggTier != nil && state.eggEvent == nil
        state.eggTier = nil   // 보증은 이 부화로 소비된다(다음 알은 다시 무보증)
        let typeGuarantee = state.eggTypeGuarantee
        // Still restrict the form rolled below: a stone's type, a season's types.
        let formTypes = eggFormTypes
        let event = state.eggEvent
        let fromFossilEgg = state.eggFromFossilEgg
        if fromFossilEgg { state.fossilEggsHatched += 1 }
        let fromLegendaryBossEgg = state.eggFromDungeon?.isLegendary == true
        state.eggTypeGuarantee = nil
        state.eggFromTypeNullEgg = false
        state.eggFromLegendaryEgg = false
        state.eggFromBirthdayEgg = false
        state.eggFromFossilEgg = false
        state.eggFromDungeon = nil
        state.eggFromCostume = nil
        if event != nil, let key = state.eggEventKey { state.eventEggHatches[key] = line.baseID }
        state.eggEvent = nil
        state.eggEventKey = nil
        state.pendingShiny = false
        // 개체 롤: shiny(1/64, 부적 1/48, Reveal Glass halves it)·성격(25종)은 부화 순간 확정, 진화해도 유지.
        // 알림 문구는 이 판정과 같은 분모를 보여준다.
        let shinyOdds = draw.shinyDenominator
        // The Glimmering Charm, reward for every form, makes every hatch shiny; the roll is still drawn so the
        // rolls after it stay the same.
        let rolledShiny = draw.rollsShiny(roll: rng.next())
        // A Birthday Egg once every legendary and mythical graduated is shiny too.
        let isShiny = rolledShiny || draw.alwaysShiny || forceShiny
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        // The roll is still drawn where no Ditto may hide, so the rolls after it stay the same.
        if dittoDisguiseRollingEnabled,
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()),
           draw.letsDittoHide(baseID: line.baseID, egg: egg, fromFossilEgg: fromFossilEgg), costumeEgg == nil {
            dittoDisguise = line.baseID
        }
        var evolutionPlan = makeEvolutionPlan(from: line.tree, baseID: line.baseID, form: pendingForm)
        var profile = PokemonProfile.generate(seed: rng.next())
        let form = costumeEgg != nil ? PokemonForm.resolved(baseID: line.baseID, form: costumeEgg?.form)
            : pendingForm ?? rollLineForm(baseID: line.baseID, types: formTypes)
        // After the form roll: an Alolan Vulpix gets an Alolan Vulpix's ability. Enriching draws nothing from `rng`.
        if let details = pokemonDetails(speciesID: firstID, form: form) { profile.enrich(with: details) }
        // The form is rolled last so owning forms never shifts the other rolls; a plan it cannot take (a
        // Galarian Meowth planned into Persian) is redone for it, which only happens on form-gated lines.
        if !Self.planFollowsForm(evolutionPlan, form: form) {
            evolutionPlan = makeEvolutionPlan(from: line.tree, baseID: line.baseID, form: form)
        }
        // A repeat only when this line already graduated in this form: an Alolan Dugtrio is new to the
        // Pokédex even after a Kanto one graduated, so it gets no repeat boost.
        let hasGrowthBoost = state.hasCollectedFinal(forBaseID: line.baseID, form: form)
        // Checked before this individual joins the Pokédex: does it bring a form its line never had?
        let hasNewForm = form.map { !state.graduatedLineForms(baseID: line.baseID).contains($0) } ?? false
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        let unlockedForms = itemFormSnapshot()
        state.active = MonState(baseID: line.baseID, pathIDs: [firstID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, profile: profile, hasGrowthBoost: hasGrowthBoost,
                                dittoDisguise: dittoDisguise, form: form)
        state.active?.hasNewForm = hasNewForm
        state.active?.costume = costumeEgg?.code
        state.active?.fromFossilEgg = fromFossilEgg
        state.active?.fromLegendaryBossEgg = fromLegendaryBossEgg
        state.active?.raising = RaisingRecord(hatchedAt: clock())
        state.active?.fromStoneEgg = typeGuarantee != nil && event == nil
        state.active?.fromRarityEgg = fromRarityEgg
        state.active?.hatch = HatchRecord(egg: hatchEgg, rollItems: rollItems ?? draw.items, hatchItems: draw.items,
                                          rolledBaseID: dittoDisguise == nil ? nil : line.baseID)
        // What the Old Amber kept, short of the first evolution: the amber alone never evolves it as it hatches.
        if state.amberCarry > 0, let mon = state.active {
            let given = min(state.amberCarry, max(0, stageThreshold(for: mon) - 1))
            state.active?.usedAtStage = given
            AppLog.write("hatch: old amber gave \(given) of \(state.amberCarry)")
        }
        state.amberCarry = 0
        state.lastHatchedBaseID = line.baseID
        // A disguised Ditto is not the species it shows: nothing unlocks until it is revealed.
        if dittoDisguise == nil { announceFormUnlocks(since: unlockedForms) }
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) boost=\(hasGrowthBoost) ditto=\(dittoDisguise != nil) form=\(form?.rawValue ?? "none")")
        let name = formDisplayName(line.localizedName(firstID, state.language),
                                   speciesID: firstID, form: form)
        notifyCompanionEvent(showShiny ? l.notifShinyHatchTitle : l.notifHatchTitle,
                             showShiny ? l.notifShinyHatchBody(name, odds: shinyHatchNotificationOdds(shinyOdds))
                                       : l.notifHatchBody(name))
        justEvolvedTo = nil        // 새 부화는 "성장" 문구(진화 아님) — 직전 진화명이 남아 표시되지 않게
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        if overflow > 0 { applyUsage(overflow) }   // 이월분 즉시 반영(필요 시 진화/리빌까지)
        // 연출은 이월 진화 뒤에 발화 — 이월 evolve 가 shiny 부화 버스트를 덮지 않도록
        // 마지막 이벤트를 hatch 로 유지한다. 이월로 즉시 졸업한 극단 케이스면 생략(이미 도감행).
        if state.active != nil { fireCelebration(.hatch(shiny: showShiny)) }
        save()
        if detailProvider != nil { Task { await self.loadPokemonDetails(speciesID: firstID, form: form) } }
    }

    /// The line a costumed Pokémon grows on (the owner, 2026-11-13): from the first stage wearing its costume, only the
    /// evolutions that wear it too (`CostumeCatalog.children`); its line's base, rarity and names stay the line's. Nil
    /// when the line has no such stage.
    /// `owned`: the species graduated, the only ones it may grow into (the owner, 2026-11-18); nil keeps every stage
    /// wearing the costume (a line reloaded for a Pokémon already raised).
    static func costumeLine(_ line: EvoLine, start: Int, code: String, form: PokemonForm?, owned: Set<Int>? = nil) -> EvoLine? {
        guard let node = line.tree.node(withID: start) else { return nil }
        func prune(_ node: EvoNode) -> EvoNode {
            let worn = CostumeCatalog.entry(code: code, speciesID: node.speciesID, form: form)
                .map { Set(CostumeCatalog.children(of: $0).map(\.speciesID).filter { owned?.contains($0) ?? true }) } ?? []
            return EvoNode(speciesID: node.speciesID, children: node.children.filter { worn.contains($0.speciesID) }.map(prune))
        }
        return EvoLine(baseID: line.baseID, tree: prune(node), rarity: line.rarity, names: line.names)
    }

    /// 위장 → 리빌: 진화 못 하는 메타몽이 "첫 진화 임계"에서 진화 대신 정체를 드러내는 순간.
    /// Ditto 라인 로드 후 상태 변환(rare·단일형태·초과분 이월, isShiny/nature 유지) + 연출·알림.
    private func revealDitto() async {
        guard let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, !isRevealingDitto else { return }
        let generation = activeGeneration
        let firstEvoThr = stageThreshold(for: a)
        guard a.usedAtStage >= firstEvoThr else { return }   // 임계 미달 방어
        isRevealingDitto = true
        defer { isRevealingDitto = false }
        guard let dittoLine = try? await provider.line(baseSpeciesID: PokemonOdds.dittoSpeciesID) else {
            AppLog.write("ditto reveal: line fetch failed — retry next tick"); return
        }
        guard activeGeneration == generation,
              var m = state.active, m.dittoDisguise != nil, !m.dittoRevealed else { return }
        let latestFirstEvoThr = stageThreshold(for: m)
        guard m.usedAtStage >= latestFirstEvoThr else { return }
        let disguiseName = currentLine?.localizedName(m.baseID, state.language) ?? "#\(m.baseID)"
        let carryOver = max(0, m.usedAtStage - latestFirstEvoThr)   // 위장체 첫 진화 초과분 → 메타몽 성장 이월
        // 메타몽으로 전환 — rarity/forms 는 로드한 라인에서, isShiny/nature/dittoDisguise 는 유지.
        let previousRarity = m.rarity
        m.baseID = dittoLine.baseID
        let evolutionPlan = makeEvolutionPlan(from: dittoLine.tree, baseID: dittoLine.baseID, form: nil)
        m.pathIDs = [dittoLine.baseID]
        m.plannedPathIDs = evolutionPlan
        m.stageIndex = 0
        m.rarity = dittoLine.rarity
        m.totalForms = evolutionPlan.count
        m.usedAtStage = carryOver
        m.dittoRevealed = true
        m.form = nil
        // Ditto has no form: the disguise's new form, and the Prison Bottle's +50% with it, go.
        m.hasNewForm = false
        // The hatch boost came from the disguise's line; from now on only a repeat Ditto earns it.
        m.hasGrowthBoost = state.hasCollectedFinal(forBaseID: dittoLine.baseID)
        m.profile?.rebaseForSpeciesIdentity(from: previousRarity, to: dittoLine.rarity)
        if let details = pokemonDetails(speciesID: dittoLine.baseID, form: nil) {
            m.profile?.enrich(with: details)
        }
        let shiny = m.isShiny
        state.active = m
        state.reconcileRepresentativeSelection()   // 위장 종만 근거였던 선택은 리빌과 함께 제거
        currentLine = dittoLine
        AppLog.write("ditto reveal: disguise=\(m.dittoDisguise ?? -1) → ditto rarity=\(dittoLine.rarity) shiny=\(shiny)")
        fireCelebration(.dittoReveal(shiny: shiny))
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(5)
        notifyCompanionEvent(shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle,
                             shiny ? l.notifShinyDittoRevealBody(disguiseName) : l.notifDittoRevealBody(disguiseName))
        save()
        applyUsage(0)   // 이월분으로 메타몽 졸업 재평가(rare 3B라 보통 즉시 졸업 아님)
        isRevealingDitto = false   // Details are enrichment, not part of the reveal transaction.
        if detailProvider != nil {
            await loadPokemonDetails(speciesID: PokemonOdds.dittoSpeciesID, form: nil)
        }
    }

    private func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        if let fetched = try? await provider.line(baseSpeciesID: a.baseID) {
            // await 중 사용량·민트 등 활성 상태는 계속 바뀔 수 있다. 요청 당시 스냅샷을 다시 쓰지 말고
            // 같은 개체가 아직 활성인 경우에만 최신 상태를 정규화한다.
            guard activeGeneration == generation,
                  let latest = state.active, latest.baseID == a.baseID, currentLine == nil else { return }
            // A costumed Pokémon grows on its costume's stages only, from the first one it hatched as.
            let line = latest.costume.flatMap { code in
                Self.costumeLine(fetched, start: latest.pathIDs.first ?? latest.currentID, code: code, form: latest.form)
            } ?? fetched
            state.active = normalizedEvolutionState(latest, from: line.tree)
            state.reconcileRepresentativeSelection()   // 손상 경로 정규화로 사라진 단계가 대표로 남지 않게
            currentLine = line
            save()   // 마이그레이션 선택을 사용량 재평가 전에 영속화해 재시작마다 다시 롤리지 않는다.
            applyUsage(0)   // 라인 미로딩 동안 적립된 사용량이 임계를 넘었으면 지금 진화 판정
            // Path normalization can change currentID without entering the regular evolution branch.
            isHatching = false   // Do not hold the line-load lock across detail HTTP requests.
            // After a relaunch only the popover loads form names; evolution and graduation
            // notifications need them before it is opened.
            if AppEnv.isBundledApp { await loadActiveFormNames() }
            if let active = state.active, detailProvider != nil {
                await loadPokemonDetails(speciesID: active.currentID, form: active.form)
            }
        }
    }

    /// 부화 종 선정 — 하드코딩 풀 없이 PokéAPI 의 base 전체(1~9세대)에서 가중 선택.
    ///   ① base 인덱스(id + capture_rate)를 GraphQL 1쿼리로 취득(30일 디스크 캐시 → 보통 0콜)
    ///   ② 가중치 = 등급별 한 값(`PokemonOdds.hatchWeight`: 일반 212 · 고급 90 · 희귀 40 · 전설 3). capture_rate 는
    ///      등급만 정한다(`BaseSpecies.rarity`) — 같은 등급의 라인은 모두 같은 확률.
    ///      단, 이미 수집한 base 는 가중치 ½(미수집 부스트 — 재부화/shiny 사냥은 열어둠)
    ///   ③ 누적 가중치에서 정확히 1롤 — 루프/재롤 없음, 시간 상한 확정적
    /// 인덱스 취득 실패(오프라인 + 캐시 없음) 시 nil → 알 유지, 다음 갱신 틱 재시도.
    private func chooseBase() async -> (id: Int, shiny: Bool)? {
        let tier = state.eggTier
        let typeGuarantee = state.eggTypeGuarantee
        // A dungeon's egg knows its line already.
        if let egg = state.eggFromDungeon { return (egg.baseID, egg.isShiny) }
        // A Costume Egg knows its Pokémon: its line, then its first costumed stage at the hatch (`costumeLine`).
        if let egg = state.eggFromCostume { return (SpeciesInfo.baseID(of: egg.speciesID), false) }
        if let full = try? await provider.baseSpeciesIndex(), !full.isEmpty {
            if state.eggFromBirthdayEgg { return chooseBirthdayBase(full) }
            if state.eggFromFossilEgg { return chooseFossilBase(full) }
            let draw = hatchDraw
            let event = state.eggEvent
            if let event, draw.seasonDeerling(full, event: event) != nil, rng.next() % EventEgg.deerlingOdds == 0 {
                AppLog.write("hatch roll: \(event.rawValue) egg base=\(EventEgg.deerlingID)")
                return (EventEgg.deerlingID, event.alwaysShiny)
            }
            let pool = draw.hatchPool(full, egg: incubatingEgg, logging: true)
            guard !pool.isEmpty else {
                AppLog.write("hatch: no candidate for guaranteed tier=\(tier?.rawValue ?? "none") type=\(typeGuarantee?.rawValue ?? "none") legendary=\(state.eggFromLegendaryEgg), egg kept; retry next tick")
                return nil
            }
            let index = pool.map(\.base)
            let weights = pool.map(\.weight)
            let total = weights.reduce(0, +)
            var r = Int(rng.next() % UInt64(total))
            for (i, w) in weights.enumerated() {
                r -= w
                if r < 0 {
                    // Enough to check a streak later: the species' weight against the egg's whole pool.
                    AppLog.write("hatch roll: base=\(index[i].id) weight=\(w) of \(total) candidates=\(index.count) tier=\(tier?.rawValue ?? "none") type=\(typeGuarantee?.rawValue ?? "none") legendaryEgg=\(state.eggFromLegendaryEgg) event=\(event?.rawValue ?? "none")")
                    return (index[i].id, event?.alwaysShiny ?? false)
                }
            }
            return index.last.map { ($0.id, event?.alwaysShiny ?? false) }   // 도달 불가(방어)
        }
        // GraphQL base 인덱스 엔드포인트 장애 → REST 폴백. 부화가 한 엔드포인트에 묶이지 않게.
        AppLog.write("hatch: base index unavailable, REST fallback")
        if state.eggFromBirthdayEgg { return await chooseBirthdayBaseViaREST() }
        // An event's egg keeps its shiny promise there too.
        return await chooseBaseViaREST().map { ($0, state.eggEvent?.alwaysShiny ?? false) }
    }

    /// The Birthday Egg's roll without the index, its rule kept (`chooseBirthdayBase`): a mythical line not graduated,
    /// else a legendary one, from the lists of both; once all graduated, any of them, shiny. A random legendary of the
    /// REST fallback could be one graduated while a mythical was missing, and was never shiny.
    private func chooseBirthdayBaseViaREST() async -> (id: Int, shiny: Bool)? {
        // R13: Arceus comes from the Hall of Origin only until caught, this fallback too (it drew 493, review of 2026-11-02).
        let dungeonOnly = hatchDraw.dungeonOnly
        let graduated = graduatedSpeciesIDs.union(dungeonOnly)
        let mythicals = Set(SpeciesGoal.mythicals).subtracting(graduated)
        if !mythicals.isEmpty { return await chooseListedBaseViaREST(mythicals, charm: false).map { ($0, false) } }
        let legendaries = Set(SpeciesGoal.legendaries).subtracting(graduated)
        if !legendaries.isEmpty { return await chooseListedBaseViaREST(legendaries, charm: false).map { ($0, false) } }
        return await chooseListedBaseViaREST(Set(SpeciesGoal.mythicals + SpeciesGoal.legendaries).subtracting(dungeonOnly),
                                             charm: false)
            .map { ($0, true) }
    }

    // MARK: Hatch pool and odds

    /// An egg's guarantees: the egg incubating, for the roll, or an egg a card shows before it is used.
    struct EggSpec: Equatable, Sendable {
        var tier: Rarity?
        var type: PokemonType?
        var legendaryEgg = false
        var event: EventEgg?

        init(tier: Rarity? = nil, type: PokemonType? = nil, legendaryEgg: Bool = false, event: EventEgg? = nil) {
            self.tier = tier
            self.type = type
            self.legendaryEgg = legendaryEgg
            self.event = event
        }

        /// The egg a Bag item gives when used, for the items whose odds the Bag shows: the Shop's eggs, the stones
        /// and the Legendary Egg. The event, Birthday, Fossil and Type: Null eggs have rolls of their own.
        init?(item: ItemKind) {
            if item.isShopEgg { self.init(tier: item.bagEggTier) }
            else if let type = item.stoneType { self.init(type: type) }
            else if item == .legendaryEgg { self.init(legendaryEgg: true) }
            else { return nil }
        }

        /// The types the egg's Pokémon must have, which its form roll keeps to: a stone's, else a season's.
        var formTypes: [PokemonType] { type.map { [$0] } ?? event?.seasonTypes ?? [] }
    }

    /// The roll's rules against this Pokédex and the draw items owned now.
    var hatchDraw: HatchDraw {
        HatchDraw(collection: state, items: Set(ItemKind.drawItems.filter { itemCount($0) > 0 }))
    }

    var incubatingEgg: EggSpec {
        EggSpec(tier: state.eggTier, type: state.eggTypeGuarantee, legendaryEgg: state.eggFromLegendaryEgg,
                event: state.eggEvent)
    }

    /// The base index the egg cards' odds read, loaded once (`loadHatchIndex`). The roll reads the index itself.
    private(set) var hatchIndex: [BaseSpecies]? { didSet { oakOddsCache = [:] } }

    /// How many species each rarity holds: every species of each line of the hatch index, at its line's rarity. Nil
    /// until the index is loaded (`loadHatchIndex`). What the Pokédex's rarity counts read "120/430" from.
    var speciesTotalsByRarity: [Rarity: Int]? { hatchIndex.map(Self.speciesTotals) }

    /// The species of each line, by the line's first species.
    private static let lineSizes: [Int: Int] = PokemonAssets.animatedSpeciesIDs.reduce(into: [:]) {
        $0[PokemonEvolutionData.root(of: $1), default: 0] += 1
    }

    static func speciesTotals(_ index: [BaseSpecies]) -> [Rarity: Int] {
        index.reduce(into: [:]) { totals, base in totals[base.rarity, default: 0] += lineSizes[base.id] ?? 1 }
    }

    /// Each species' rarity, its line's in the hatch index: a species never caught has one too, for the Pokédex's rarity
    /// filter (#183). Nil before the index loads.
    var speciesRarities: [Int: Rarity]? {
        guard let index = hatchIndex else { return nil }
        let byLine = Dictionary(index.map { ($0.id, $0.rarity) }, uniquingKeysWith: { first, _ in first })
        return PokemonAssets.animatedSpeciesIDs.reduce(into: [:]) { out, id in
            out[id] = byLine[PokemonEvolutionData.root(of: id)]
        }
    }

    func loadHatchIndex() async {
        guard hatchIndex == nil, let full = try? await provider.baseSpeciesIndex(), !full.isEmpty else { return }
        hatchIndex = full
    }

    private(set) var hatchLuck: HatchLuck?
    @ObservationIgnored private var replayedLuckInputs: LuckInputs?

    struct LuckInputs: Equatable {
        let entries: [DexEntry]
        let drawItems: [ItemKind]
        let eggsUsed: [HatchEgg: Int]
    }

    var luckInputs: LuckInputs {
        LuckInputs(entries: dexEntries, drawItems: (ItemKind.drawItems + ItemKind.formerDrawItems).filter { itemCount($0) > 0 },
                   eggsUsed: EggStock.used(in: state))
    }

    /// Replays every hatch off the main thread once the species index is loaded, again only when its inputs changed.
    func loadHatchLuck() async {
        let inputs = luckInputs
        await loadHatchIndex()
        guard let index = hatchIndex, inputs != replayedLuckInputs else { return }
        let today = state, includesActive = state.active != nil, now = clock()
        let itemsSince = Dictionary(uniqueKeysWithValues: inputs.drawItems.compactMap { item in
            drawItemSince(item).map { (item, $0) }
        })
        let luck = await Task.detached(priority: .userInitiated) {
            HatchLuck(entries: inputs.entries, includesActive: includesActive, today: today, index: index,
                      itemsSince: itemsSince, now: now)
        }.value
        guard luckInputs == inputs else { return }
        hatchLuck = luck
        replayedLuckInputs = inputs
    }

    /// Notes the egg the player says a hatch from before the record came from, after a release; nil forgets it. The
    /// Pokémon Egg after a graduation, and what the app noted itself, are not theirs to say.
    func chooseHatchEgg(_ egg: HatchEgg?, forEntry id: String) {
        let record = egg.map { HatchRecord(egg: $0, source: .player) }
        if let i = state.dex.firstIndex(where: { $0.id == id }) {
            guard i > 0, state.dex[i - 1].isReleased, state.dex[i].hatch?.isOpenToPlayer != false else { return }
            state.dex[i].hatch = record
        } else if id == activeDexEntry?.id, state.dex.last?.isReleased == true,
                  state.active?.hatch?.isOpenToPlayer != false {
            state.active?.hatch = record
        } else {
            return
        }
        save()
    }

    /// Gives each hatch whose egg is still unknown the one it most likely came from (`HatchLuck.guessedEggs`), which the
    /// player may still change.
    func deduceUnknownEggs() {
        guard let guesses = hatchLuck?.guessedEggs(), !guesses.isEmpty else { return }
        for i in state.dex.indices {
            if let egg = guesses[state.dex[i].id] { state.dex[i].hatch = HatchRecord(egg: egg, source: .deduced) }
        }
        if let id = activeDexEntry?.id, let egg = guesses[id] { state.active?.hatch = HatchRecord(egg: egg, source: .deduced) }
        save()
    }

    /// Reads the log for the eggs of the hatches from before the record, off the main thread: the file is up to 2 MB, and
    /// the older half is in `.old.log`.
    func readEggJournal(from log: URL = AppLog.logFileURL) async {
        let older = log.deletingPathExtension().appendingPathExtension("old.log")
        let journal = await Task.detached(priority: .utility) {
            EggJournal(text: [older, log].compactMap { try? String(decoding: Data(contentsOf: $0), as: UTF8.self) }
                .joined(separator: "\n"))
        }.value
        absorb(journal)
    }

    /// Writes in the save what the log says, for it to outlive the log's rotation: an egg goes to the hatch after the
    /// release it was used for, over the player's word and the app's guess, not over a record.
    func absorb(_ journal: EggJournal) {
        var releases: [Int: Int] = [:]
        for (i, entry) in state.dex.enumerated() {
            if let at = entry.releasedAt { releases[Int(at.timeIntervalSince1970)] = i }
        }
        func noted(_ egg: HatchEgg, over record: HatchRecord?) -> HatchRecord? {
            record?.isOpenToPlayer == false ? record : HatchRecord(egg: egg, source: .journal)
        }
        for use in journal.uses {
            let second = Int(use.at.timeIntervalSince1970)
            guard let released = releases[second] ?? releases[second - 1] else { continue }
            if released + 1 < state.dex.count {
                let record = noted(use.egg, over: state.dex[released + 1].hatch)
                state.dex[released + 1].hatch = record
            } else if state.active != nil {
                let record = noted(use.egg, over: state.active?.hatch)
                state.active?.hatch = record
            }
        }
        // The Pokémon that hatched is the next to leave. Sent off before its reveal, it keeps the disguise as its line.
        for disguise in journal.disguises {
            let second = Int(disguise.at.timeIntervalSince1970)
            guard let i = state.dex.firstIndex(where: { $0.caughtAt.map { Int($0.timeIntervalSince1970) > second } ?? false }),
                  state.dex[i].baseID == PokemonOdds.dittoSpeciesID else { continue }
            let afterRelease = i > 0 && state.dex[i - 1].isReleased
            var record = state.dex[i].hatch ?? (afterRelease ? nil : HatchRecord(egg: .tier(nil), source: .journal))
            guard record?.source == .journal else { continue }
            record?.rolledBaseID = disguise.baseID
            state.dex[i].hatch = record
        }
        save()
    }

    /// PokeTokenBar v2.5.4, the release that let Shop prices go down to 10%: every player had the Shiny Charm from then.
    static let shinyCharmForEveryone = Date(timeIntervalSince1970: 1_789_223_036)   // 2026-09-12 14:23:56 UTC

    /// Since when the player has a draw item they own, for the hatches from before the record: from the first moment
    /// that met its condition of the time, or from the update that brought it if none did. The Shiny Charm, sold in the
    /// Shop, from `shinyCharmForEveryone`.
    func drawItemSince(_ item: ItemKind) -> Date? {
        guard itemCount(item) > 0 else { return nil }
        guard let arrival = HatchRules.Change.arrival(of: item)?.publishedAt else { return Self.shinyCharmForEveryone }
        return unlockedAt(item, since: arrival) ?? arrival
    }

    /// One rarity's share of an egg's pool, by weight.
    struct RarityShare: Equatable, Sendable {
        let rarity: Rarity
        let share: Double
    }

    /// What an egg can hatch, as its roll would now: each rarity's share, commonest first, and the share of
    /// species not graduated yet. Nil before the index is loaded or for an egg nothing can hatch from.
    struct HatchOdds: Equatable, Sendable {
        let rarities: [RarityShare]
        let newSpecies: Double
    }

    func hatchOdds(for egg: EggSpec) -> HatchOdds? {
        guard let index = hatchIndex else { return nil }
        let pool = hatchDraw.hatchPool(index, egg: egg)
        let total = pool.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        let graduated = graduatedSpeciesIDs
        var byRarity: [Rarity: Int] = [:]
        var newWeight = 0
        for (base, weight) in pool {
            byRarity[base.rarity, default: 0] += weight
            if !graduated.contains(base.id) { newWeight += weight }
        }
        let order: [Rarity] = [.common, .uncommon, .rare, .legendary]
        return HatchOdds(rarities: order.compactMap { r in
                             byRarity[r].map { RarityShare(rarity: r, share: Double($0) / Double(total)) }
                         },
                         newSpecies: Double(newWeight) / Double(total))
    }

    /// Whole percents that add up to 100 (largest remainder): rounded one by one, 78.5, 11.1, 9.3 and 1.1 make 99.
    nonisolated static func wholePercents(_ shares: [Double]) -> [Int] {
        let scaled = shares.map { $0 * 100 }
        var result = scaled.map { Int($0.rounded(.down)) }
        let missing = 100 - result.reduce(0, +)
        let order = scaled.indices.sorted { (scaled[$0] - Double(result[$0])) > (scaled[$1] - Double(result[$1])) }
        for i in order.prefix(max(0, missing)) { result[i] += 1 }
        return result
    }

    /// The candidates without the line hatched last, so no egg brings the same line twice in a row; all of them
    /// when it is the only one.
    nonisolated static func withoutLastHatched(_ index: [BaseSpecies], last: Int?) -> [BaseSpecies] {
        guard let last else { return index }
        let others = index.filter { $0.id != last }
        return others.isEmpty ? index : others
    }

    /// A Fossil Egg's roll: one of `fossilDraw`'s lines.
    private func chooseFossilBase(_ index: [BaseSpecies]) -> (id: Int, shiny: Bool)? {
        let lines = hatchDraw.fossilDraw(index)
        guard !lines.isEmpty else {
            AppLog.write("hatch: no fossil line for the fossil egg, egg kept; retry next tick")
            return nil
        }
        let pick = lines[Int(rng.next() % UInt64(lines.count))]
        AppLog.write("hatch roll: fossil egg base=\(pick.id) of \(lines.count)")
        return (pick.id, false)
    }

    /// A Birthday Egg's roll among `birthdayDraw`'s lines.
    private func chooseBirthdayBase(_ index: [BaseSpecies]) -> (id: Int, shiny: Bool)? {
        let (lines, byWeight) = hatchDraw.birthdayDraw(index)
        guard !lines.isEmpty else {
            AppLog.write("hatch: no legendary or mythical line for the birthday egg, egg kept; retry next tick")
            return nil
        }
        var pick = lines[lines.count - 1].base
        if byWeight {
            var r = Int(rng.next() % UInt64(max(1, lines.reduce(0) { $0 + $1.weight })))
            for line in lines {
                r -= line.weight
                if r < 0 { pick = line.base; break }
            }
        } else {
            pick = lines[Int(rng.next() % UInt64(lines.count))].base
        }
        AppLog.write("hatch roll: birthday egg base=\(pick.id) of \(lines.count) candidates shiny=\(byWeight)")
        return (pick.id, byWeight)
    }

    /// REST 폴백 — animated 에셋 지원 범위에서 무작위 id 를 뽑아 base 인지 확인(rejection sampling).
    /// GraphQL 인덱스가 죽어도 부화가 되게 한다. 가중치(capture_rate)는 생략 — 희귀도는 부화 후
    /// line() 이 실제 capture_rate 로 계산하므로 결과 개체의 등급은 정확하다. 인덱스 복구 시 가중 선택 재개.
    private func chooseBaseViaREST() async -> Int? {
        // A Fossil Egg asks for its candidates themselves: 32 random numbers seldom meet one of 15 lines, one in 1,025
        // even less. So does an event egg of a few lines, the Friendship Egg's one above all.
        if let egg = state.eggFromDungeon { return egg.baseID }
        if let egg = state.eggFromCostume { return SpeciesInfo.baseID(of: egg.speciesID) }
        if state.eggFromFossilEgg { return await chooseListedBaseViaREST(hatchDraw.fossilCandidates, charm: false) }
        if let lines = state.eggEvent?.lines(companionLine: companionLineID) {
            return await chooseListedBaseViaREST(lines, charm: ownsOvalCharm)
        }
        let tier = state.eggTier
        let typeGuarantee = state.eggTypeGuarantee
        // The Oval Charm, as in `chooseBase`: a line with a form still missing while the tries find one, else the
        // first candidate that keeps the egg's other guarantees.
        var withoutTheCharm: Int?
        let dungeonOnly = hatchDraw.dungeonOnly
        for attempt in 1...32 {
            let ids = PokemonAssets.animatedSpeciesIDs
            let id = Int(rng.next() % UInt64(ids.count)) + ids.lowerBound
            do {
                if let bs = try await provider.baseSpecies(id: id), !dungeonOnly.contains(bs.id) {
                    // 등급 보증은 가중 경로와 **같은 기준**으로 여기서도 걸러야 한다 — 이 폴백만 빠지면
                    // GraphQL 인덱스 장애 때 보증이 조용히 깨진다. 못 찾으면 알 유지(구매 소멸 금지).
                    if let tier, !tier.admits(bs) { continue }
                    if state.eggFromLegendaryEgg || state.eggFromBirthdayEgg, !bs.isLegendary { continue }
                    if state.eggFromFossilEgg, !hatchDraw.fossilCandidates.contains(bs.id) { continue }
                    if !state.eggFromFossilEgg, FossilDig.isFossilLine(bs.id), !graduatedSpeciesIDs.contains(bs.id) {
                        continue
                    }
                    if let typeGuarantee, !PokemonTypeData.canHatch(baseID: bs.id, as: typeGuarantee) { continue }
                    if let event = state.eggEvent, !event.admits(bs, companionLine: companionLineID) { continue }
                    // Not the line hatched last again; the index path keeps it when it is the only one, this one
                    // retries.
                    if bs.id == state.lastHatchedBaseID { continue }
                    if ownsOvalCharm, !state.lineMissesForms(baseID: bs.id, types: eggFormTypes) {
                        withoutTheCharm = withoutTheCharm ?? id
                        continue
                    }
                    AppLog.write("hatch: REST fallback picked base \(id) (cap \(bs.captureRate), \(attempt) tries)")
                    return id
                }
                // nil = base 아님(진화 중간체) → 다음 시도
            } catch {
                AppLog.write("hatch: REST fallback network error — retry next tick: \(error)")
                return nil   // REST 도 불가 → 알 유지, 다음 update 틱 재시도
            }
        }
        if let withoutTheCharm {
            AppLog.write("hatch: REST fallback found no line missing a form, picked base \(withoutTheCharm)")
            return withoutTheCharm
        }
        AppLog.write("hatch: REST fallback exhausted 32 tries")
        return nil
    }

    /// The REST fallback of an egg that names its lines: each of them asked for, in a random order, then the index
    /// path's rules (`chooseBase`): with the Oval Charm, a line with a form still missing while one is left; not the
    /// line hatched last while another is.
    private func chooseListedBaseViaREST(_ candidates: Set<Int>, charm: Bool) async -> Int? {
        var lines = Array(candidates).sorted()
        for index in lines.indices.reversed() {
            lines.swapAt(index, Int(rng.next() % UInt64(index + 1)))
        }
        var found: [Int] = []
        for line in lines {
            do {
                if try await provider.baseSpecies(id: line) != nil { found.append(line) }
            } catch {
                AppLog.write("hatch: REST fallback network error, retry next tick: \(error)")
                return nil
            }
        }
        if charm {
            let missing = found.filter { state.lineMissesForms(baseID: $0, types: eggFormTypes) }
            if !missing.isEmpty { found = missing }
        }
        let others = found.filter { $0 != state.lastHatchedBaseID }
        guard let pick = (others.isEmpty ? found : others).first else {
            AppLog.write("hatch: REST fallback found none of the egg's \(candidates.count) lines")
            return nil
        }
        AppLog.write("hatch: REST fallback picked listed line \(pick) of \(found.count) found")
        return pick
    }

    private func computeState(burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool, today: Int) -> CompanionStateKind {
        if state.active == nil { return .egg }
        if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { return .levelUp }
        if limitWarning { return .tired }
        if !hasUsageData || today == 0 { return .sleep }
        switch burnTier {
        case .idle: return .idle
        case .normal: return .working
        case .fast, .blazing: return .focus
        }
    }

    // MARK: 세이브 이전 (기기 교체)

    /// 덮어쓰기 확인에 쓸 "이 기기의 현재 진행" 요약.
    var transferSummary: SaveSummary { SaveSummary(state: state) }

    /// 저장 패널에 채울 기본 파일명. 봉투의 `exportedAt` 과 **같은 시계**에서 뽑는다 — 뷰가 따로
    /// `Date()` 를 부르면 파일명 날짜와 내용의 날짜가 갈릴 수 있다(자정 경계).
    var suggestedExportFileName: String { SaveTransfer.suggestedFileName(date: clock()) }

    /// 내보내기 페이로드. 파일 쓰기는 호출자(UI)가 사용자가 고른 위치에 수행한다.
    func exportedSaveData(appVersion: String, deviceName: String) throws -> Data {
        try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: clock())
    }

    /// 검증된 세이브를 이 기기에 적용 — 기존 상태 백업 → 기기 기준 재정렬 → 저장 → 라인 재로딩.
    /// 백업을 못 남기면 **적용하지 않고** throw 한다 — 확인창이 "직전 상태가 남는다"고 약속하므로,
    /// 그 약속을 못 지키는 채로 덮어쓰면 사용자는 되돌릴 수단 없이 진행을 잃는다.
    /// `snapshotFirst`: an import keeps the state it replaces as a snapshot too, which Settings lists and restores: the
    /// copy beside the save (`backupStateBeforeImport`) is a bare state the import refuses. A restore made its own.
    func applySave(_ envelope: SaveEnvelope, todayTokensByProvider: [String: Int], todayDate: String,
                   hasUsageData: Bool, snapshotFirst: Bool = true) throws {
        guard saveLock == nil else { throw SaveTransferError.saveLocked }
        try backupStateBeforeImport()
        if snapshotFirst {
            do { try createManualSnapshot() } catch { AppLog.write("save import: no snapshot of the state replaced: \(error)") }
        }
        state = SaveTransfer.rebasedForThisDevice(envelope.state,
                                                  current: state,
                                                  todayTokensByProvider: todayTokensByProvider,
                                                  todayDate: todayDate,
                                                  hasUsageData: hasUsageData)
        // 이전 개체 기준으로 진행 중이던 비동기·연출을 전부 무효화한다. activeGeneration 을 올리지
        // 않으면 먼저 떠 있던 라인 로드가 완료되며 새로 불러온 개체를 덮어쓴다.
        activeGeneration += 1
        currentLine = nil
        prefetchedLineID = nil
        justEvolvedTo = nil
        justGraduated = nil
        eventUntil = nil
        celebration = nil
        isHatchRetryDelayed = false
        // 이전 개체 기준의 1회성 피드백(사탕 +XP)도 비운다 — 안 비우면 불러온 직후 남의
        // 개체에 대한 "+XP" 가 새 개체 위에 떠오른다.
        candyFeedbackAmount = 0
        displayState = state.active != nil ? .idle : .egg
        migrateToAdditiveGrowthIfNeeded()
        migratePokemonProfilesIfNeeded()
        migrateLightBallToRewardsIfNeeded()
        recordFossilLinesBeforeDigsIfNeeded()
        reconcileOverclaimedDigsIfNeeded()
        save()
        if state.active != nil { Task { await loadCurrentLine() } }
        if detailProvider != nil { Task { await preparePokemonProfiles() } }
        AppLog.write("save imported from \(envelope.sourceDevice): dex=\(state.dex.count) lifetime=\(state.usedSinceInstall)")
    }

    /// 덮어쓰기 직전 현재 상태를 옆에 남긴다 — 잘못 불러왔을 때 되돌릴 수단.
    /// 슬롯을 하나만 쓰면 두 번째 불러오기가 **원본**을 덮어써, "잘못 불러왔으니 되돌린다"는 바로 그
    /// 상황에서 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯을 쓰고 오래된 것부터 정리한다.
    @discardableResult
    private func backupStateBeforeImport() throws -> URL {
        guard let data = try? JSONEncoder().encode(state) else { throw SaveTransferError.backupFailed }
        let dir = fileURL.deletingLastPathComponent()
        let backup = dir.appendingPathComponent(SaveTransfer.backupFileName(date: clock()))
        do {
            try data.write(to: backup, options: .atomic)
        } catch {
            AppLog.write("save import aborted — backup write failed: \(error)")
            throw SaveTransferError.backupFailed
        }
        pruneImportBackups(in: dir)
        return backup
    }

    /// 최근 N 개만 남기고 오래된 백업을 지운다. 파일명이 `yyyy-MM-dd-HHmmss` 라 사전순 = 시간순이다.
    private func pruneImportBackups(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let backups = names.filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        guard backups.count > SaveTransfer.backupsToKeep else { return }
        for stale in backups.dropLast(SaveTransfer.backupsToKeep) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
        }
    }

    // MARK: 스냅샷 (로컬 자동 백업 & 복원)

    func refreshSnapshots() {
        availableSnapshots = SaveSnapshotManager.listSnapshots(for: fileURL)
    }

    @discardableResult
    /// Refused while the save is locked (`saveLock`): the state then is a fresh or a lossy one, and each snapshot of it
    /// pushed one of the real ones out of the ten kept.
    func createManualSnapshot(now: Date? = nil) throws -> SaveSnapshot {
        guard saveLock == nil else { throw SaveTransferError.saveLocked }
        let timestamp = now ?? clock()
        let snapshot = try SaveSnapshotManager.createSnapshot(
            state: state,
            for: fileURL,
            date: timestamp,
            appVersion: SaveSnapshotManager.defaultAppVersion,
            deviceName: SaveSnapshotManager.defaultDeviceName
        )
        lastAutoSnapshotDate = timestamp
        refreshSnapshots()
        return snapshot
    }

    private var automaticSnapshotInterval: TimeInterval {
        SaveSnapshotManager.minAutoSnapshotInterval
    }

    func autoSnapshotIfNeeded(now: Date? = nil) {
        let timestamp = now ?? clock()
        // A snapshot dated after now (the Mac's clock set ahead to try an event) is not the newest: counted, it held
        // the automatic snapshots back until that date.
        let newest = availableSnapshots.first { $0.date <= timestamp }

        guard newest == nil ||
              timestamp.timeIntervalSince(newest!.date) >= automaticSnapshotInterval
        else {
            return
        }

        guard state.usedSinceInstall > 0 || !state.dex.isEmpty || state.active != nil else { return }

        _ = try? createManualSnapshot(now: timestamp)
    }

    func restoreSnapshot(
        _ snapshot: SaveSnapshot,
        todayTokensByProvider: [String: Int] = [:],
        todayDate: String = "",
        hasUsageData: Bool = false
    ) throws {
        // Read and validate the selected snapshot before taking the safety snapshot: at the retention
        // limit, that extra file prunes the oldest one, which may be the snapshot being restored.
        // A snapshot that no longer decodes also fails here, before anything is written or pruned.
        guard saveLock == nil else { throw SaveTransferError.saveLocked }
        let envelope = try SaveSnapshotManager.loadEnvelope(from: snapshot.fileURL)
        _ = try? createManualSnapshot()
        try applySave(envelope,
                      todayTokensByProvider: todayTokensByProvider,
                      todayDate: todayDate,
                      hasUsageData: hasUsageData,
                      snapshotFirst: false)
        refreshSnapshots()
        AppLog.write("snapshot restored: \(snapshot.id)")
    }

    // MARK: Pokémon combat profiles / details

    /// Exact current/final individuals for a Pokédex species. Earlier evolution stages remain
    /// species reference pages; the same evolved individual is not duplicated as a second creature.
    func pokemonIndividuals(speciesID: Int, form: PokemonForm? = nil) -> [DexEntry] {
        let form = PokemonForm.resolved(speciesID: speciesID, form: form)
        // A Plate changes Arceus's look, not the individual: every Arceus shows in each form it has.
        let anyForm = PokemonForm.unlockSource(speciesID: speciesID) != nil
        return dexEntriesSorted.filter {
            $0.finalID == speciesID && $0.profile != nil
                && (anyForm || PokemonForm.resolved(speciesID: speciesID, form: $0.form) == form)
        }
    }

    /// The PokéAPI data of one species in one form: the form's own when it is a variety (an Alolan Vulpix's stats
    /// and Snow Cloak), never its default form's. `pokemonDetailsByID` is keyed by `PokemonForm.detailsID`.
    func pokemonDetails(speciesID: Int, form: PokemonForm?) -> PokemonDetails? {
        pokemonDetailsByID[PokemonForm.detailsID(speciesID: speciesID, form: form)]
    }

    func failedToLoadPokemonDetails(speciesID: Int, form: PokemonForm?) -> Bool {
        failedPokemonDetailIDs.contains(PokemonForm.detailsID(speciesID: speciesID, form: form))
    }

    /// Loads immutable PokéAPI metadata of this form and fills the profiles of the individuals in it. The form is
    /// required: with the species alone, an Alolan Vulpix would get a Kanto one's stats, ability and moves.
    func loadPokemonDetails(speciesID: Int, form: PokemonForm?) async {
        let id = PokemonForm.detailsID(speciesID: speciesID, form: form)
        if let details = pokemonDetailsByID[id] {
            enrichProfiles(for: speciesID, detailsID: id, with: details)
            return
        }
        guard let detailProvider, !loadingPokemonDetailIDs.contains(id) else { return }
        loadingPokemonDetailIDs.insert(id)
        failedPokemonDetailIDs.remove(id)
        defer { loadingPokemonDetailIDs.remove(id) }
        do {
            let details = try await detailProvider.pokemonDetails(pokemonID: id, speciesID: speciesID)
            pokemonDetailsByID[id] = details
            enrichProfiles(for: speciesID, detailsID: id, with: details)
        } catch {
            failedPokemonDetailIDs.insert(id)
            AppLog.write("pokemon details fetch failed id=\(id) species=\(speciesID): \(error)")
        }
    }

    /// Startup/background warmup for the only profile needed before a detail page is opened.
    func preparePokemonProfiles() async {
        guard let active = state.active else { return }
        await loadPokemonDetails(speciesID: active.currentID, form: active.form)
    }

    /// Fills the profiles of the individuals of this species whose form reads these details. `enrich` keeps the
    /// rolled ability slot and recomputes its name and the moves, so an individual saved with its default form's
    /// ability gets its own form's on the next load.
    private func enrichProfiles(for speciesID: Int, detailsID: Int, with details: PokemonDetails) {
        var changed = false
        if var active = state.active, active.currentID == speciesID,
           PokemonForm.detailsID(speciesID: speciesID, form: active.form) == detailsID, var profile = active.profile {
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                active.profile = profile
                state.active = active
                changed = true
            }
        }
        for index in state.dex.indices where state.dex[index].finalID == speciesID
            && PokemonForm.detailsID(speciesID: speciesID, form: state.dex[index].form) == detailsID {
            guard var profile = state.dex[index].profile else { continue }
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                state.dex[index].profile = profile
                changed = true
            }
        }
        if changed { save() }
    }

    /// Additive migration for pre-profile saves. It never needs network and therefore cannot block launch.
    /// Deferred fields (gender/ability/moves) are filled after the cached/detail fetch succeeds.
    private func migratePokemonProfilesIfNeeded() {
        var changed = false
        if var active = state.active, active.profile == nil {
            let key = "active:\(active.baseID):\(active.pathIDs.map(String.init).joined(separator: ",")):\(state.lastDate)"
            active.profile = PokemonProfile.generate(seed: PokemonProfileMigration.seed(key))
            state.active = active
            changed = true
        }
        for index in state.dex.indices {
            let entry = state.dex[index]
            if entry.profile == nil {
                let graduated = !entry.isReleased
                // Released entries only persisted their reached `chainOrder`, not the originally
                // planned form count. Treating that count as `totalForms` is the best recoverable
                // estimate, but it is an upper bound when release happened before the planned final.
                let growth = graduated
                    ? PokemonBalance.graduationTotal(entry.rarity)
                    : Self.reconstructedGrowthTokens(
                        rarity: entry.rarity, totalForms: max(1, entry.chainOrder.count),
                        completedStages: max(0, entry.chainOrder.count - 1), currentStageUsage: 0)
                var profile = PokemonProfile.generate(
                    seed: PokemonProfileMigration.seed("dex:\(entry.id):\(entry.finalID)"),
                    growthTokens: growth,
                    instanceID: entry.id)
                profile.applyGrowth(0, rarity: entry.rarity)
                state.dex[index].profile = profile
                changed = true
            }
        }
        let before = state.active?.profile
        reconcileActiveProfileGrowth()
        if !changed {
            if before != state.active?.profile { save() }
            return
        }

        // One recoverable snapshot before the first format expansion. Never overwrite it.
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("companion-state.pre-profiles-v1.json")
        if FileManager.default.fileExists(atPath: fileURL.path),
           !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        save()
        AppLog.write("pokemon profile migration complete — previous state kept as \(backup.lastPathComponent)")
    }

    /// Completed phases retain their earned credit. Only the current raw phase is repriced
    /// by difficulty/repeat boost; its profile high-water mark prevents level loss.
    private func reconcileActiveProfileGrowth() {
        guard var active = state.active, var profile = active.profile else { return }
        let completed = Self.reconstructedGrowthTokens(
            rarity: active.rarity, totalForms: active.totalForms,
            completedStages: active.stageIndex, currentStageUsage: 0)
        let standardPhase = PokemonBalance.phaseThreshold(
            rarity: active.rarity, totalForms: active.totalForms, stageIndex: active.stageIndex)
        let fraction = min(1, max(0, Double(active.usedAtStage) / Double(max(1, stageThreshold(for: active)))))
        let candidate = min(PokemonBalance.graduationTotal(active.rarity),
                            completed + Int((Double(standardPhase) * fraction).rounded(.down)))
        profile.advanceGrowth(to: candidate, rarity: active.rarity)
        if let details = pokemonDetails(speciesID: active.currentID, form: active.form) { profile.enrich(with: details) }
        active.profile = profile
        state.active = active
    }

    static func reconstructedGrowthTokens(rarity: Rarity, totalForms: Int,
                                          completedStages: Int, currentStageUsage: Int) -> Int {
        let forms = max(1, totalForms)
        let completed = min(max(0, completedStages), forms)
        let completedGrowth = (0..<completed).reduce(0) { total, stage in
            total + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: forms, stageIndex: stage)
        }
        return min(SaveTransfer.maxTokenValue,
                   completedGrowth + min(SaveTransfer.maxTokenValue, max(0, currentStageUsage)))
    }

    // MARK: 영속
    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 파일 없음 = 신규 설치. A file there but unreadable is no new install: it was written over.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                saveLock = .unreadable
                AppLog.write("companion state unreadable, nothing is written until it reads: \(error)")
            }
            return
        }
        let decoded = LenientDecoding.recordingLosses { try? JSONDecoder().decode(CompanionState.self, from: data) }
        guard let s = decoded.value else {
            // 디코드 실패(전면 손상/미래 스키마) → 원본을 .corrupt 로 백업 후 유효한 스냅샷으로 복구 시도.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
                AppLog.write("companion state decode failed — original backed up to \(backup.lastPathComponent)")
            } catch {
                AppLog.write("failed to move corrupt state file to \(backup.lastPathComponent): \(error)")
            }

            if let recovered = SaveSnapshotManager.loadLatestValidSnapshot(for: fileURL) {
                state = SaveTransfer.sanitized(recovered)
                state.convertCalendarYears(recordedIn: Calendar.current, now: clock())
                AppLog.write("automatically recovered companion state from snapshot")
                save()
            } else {
                state = CompanionState()
                AppLog.write("no snapshot available, starting fresh")
            }
            return
        }
        // 불러오기 경계와 같은 정규화를 디스크에서 읽을 때도 건다. 불러오기만 막으면 **이미 저장된**
        // 극단값은 그대로 남아, 앱이 매 기동마다 같은 값을 읽어 산술 트랩으로 죽는 상태를 못 벗어난다
        // (디코드는 *성공*하므로 위의 .corrupt 복구도 발동하지 않는다). 여기서 걸면 자가 복구된다.
        state = SaveTransfer.sanitized(s)
        state.convertCalendarYears(recordedIn: Calendar.current, now: clock())
        if let saved = s.writer, let writer, saved.isNewer(than: writer) {
            saveLock = .newerBuild(commit: String(saved.commit.prefix(7)))
            AppLog.write("companion state written by a later build \(saved.commit.prefix(7)) (\(saved.date)), this one "
                + "(\(writer.commit.prefix(7)), \(writer.date)) writes nothing")
        } else if !decoded.losses.isEmpty {
            keepLossyCopy(of: data, losses: decoded.losses)
        }
    }

    /// The file as it was, beside it, before a write drops what the decoding left out: written by a version that knew
    /// more, it held fields this one cannot read. The last three are kept.
    private func keepLossyCopy(of data: Data, losses: [String]) {
        let dir = fileURL.deletingLastPathComponent()
        let stamp = SaveSnapshotManager.snapshotFileName(date: clock())
            .replacingOccurrences(of: SaveSnapshotManager.snapshotPrefix, with: "")
        let copy = dir.appendingPathComponent(Self.lossyCopyPrefix + stamp)
        do {
            try data.write(to: copy, options: .atomic)
            AppLog.write("companion state read with \(losses.count) field(s) left out (\(losses.prefix(5).joined(separator: ", "))), "
                + "original kept as \(copy.lastPathComponent)")
        } catch {
            AppLog.write("companion state: could not keep the lossy original: \(error)")
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for stale in names.filter({ $0.hasPrefix(Self.lossyCopyPrefix) }).sorted().dropLast(3) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
        }
    }
    static let lossyCopyPrefix = "companion-state.lossy-"
    /// What the file holds, as last written. Every refresh ends with a save: a refresh that changed nothing rewrote
    /// the whole file all the same (660 KB for 571 Pokédex entries, twice a minute while tokens flow).
    private var savedState: CompanionState?

    /// A usage update's save: at once when the last write is `usageSaveGap` old, else once that much after it.
    private func saveUsage() {
        guard usageSaveGap > 0, let last = lastSaveWrite else { return save() }
        let since = Date().timeIntervalSince(last)
        guard since < usageSaveGap else { return save() }
        guard usageSaveTask == nil else { return }
        let wait = usageSaveGap - since
        usageSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.usageSaveTask = nil
            self.save()
        }
    }

    /// Writes what a usage update left waiting (the app quitting).
    func flushPendingSave() {
        guard usageSaveTask != nil else { return }
        save()
    }

    private func save() {
        refreshRepresentativeSubject()
        guard saveLock == nil else { return }
        if let writer, state.writer != writer { state.writer = writer }
        // This write carries what a usage update had waiting.
        usageSaveTask?.cancel()
        usageSaveTask = nil
        guard state != savedState else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
            savedState = state
            savesWritten += 1
            lastSaveWrite = Date()
        } catch {
            AppLog.write("save failed: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
extension CompanionStore {
    /// 테스트용 알 사용량 주입.
    func setEggUsageForTesting(_ usage: Int) {
        state.eggUsage = usage
    }
}
#endif
