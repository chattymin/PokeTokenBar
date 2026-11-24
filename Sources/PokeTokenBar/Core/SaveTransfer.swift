import Foundation

/// 기기 교체용 세이브 이전 — 상태를 봉투에 담아 내보내고, 다른 기기에서 들여온다.
///
/// `CompanionState` 를 그대로 파일로 쓰지 않고 봉투로 감싸는 이유: 상태 디코딩이 의도적으로
/// 관대해서(`lenient*` — 한 필드가 깨져도 도감 전체를 날리지 않으려고) **아무 JSON 이나 넣어도
/// 전 필드가 기본값으로 흡수되며 "성공"한다.** 봉투 없이는 남의 JSON 을 골라도 불러오기가
/// 성공한 뒤 도감이 빈 상태가 되어, 사용자에겐 "앱이 내 진행을 지웠다"로 보인다.
/// 봉투의 `format`/`schema` 는 관대 디코딩 대상이 아니라(기본값 없음) 이 오인을 먼저 차단한다.
struct SaveEnvelope: Codable, Sendable {
    static let formatID = "poketokenbar.save"
    /// v2 adds persistent generated Pokémon profiles (IVs, gender, ability, level and moves).
    static let schemaVersion = 2

    var format: String
    var schema: Int
    var appVersion: String
    var exportedAt: Date
    var sourceDevice: String
    var state: CompanionState
}

/// 봉투의 앞부분만 읽는 최소 구조 — 본문(`state`)이 상위 스키마라 못 읽히더라도 "새 버전 세이브"임을
/// 알아보고 정확한 안내를 하기 위해서다. 이게 없으면 상위 스키마 파일이 "세이브 파일이 아니에요"로
/// 뜬다(사용자는 앱을 업데이트하면 된다는 걸 모른다).
private struct SaveHeader: Decodable {
    let format: String
    let schema: Int
}

/// 덮어쓰기 확인에 쓰는 요약 — "무엇이 대체되는지"를 수치로 보여주기 위한 값.
/// (경고문에 대상을 구체적으로 적는 것이 일반적인 "정말 진행할까요?" 보다 사용자에게 유용하다.)
struct SaveSummary: Equatable, Sendable {
    var dexCount: Int
    var lifetimeTokens: Int

    init(state: CompanionState) {
        dexCount = state.dex.count
        lifetimeTokens = state.usedSinceInstall
    }
}

enum SaveTransferError: Error, Equatable {
    /// 봉투가 아니거나 다른 앱의 JSON.
    case notASaveFile
    /// 이 빌드보다 새 스키마 — 상위 버전에서 만든 세이브.
    case newerSchema(found: Int, supported: Int)
    /// 세이브로 보기엔 과하게 큰 파일 — 파싱이 메인스레드를 오래 잡는다.
    case fileTooLarge(bytes: Int, limit: Int)
    /// 덮어쓰기 전 백업을 못 남겼다 — 확인창이 약속한 복구 수단이 없으므로 불러오기를 중단한다.
    case backupFailed
    /// The save is locked (`CompanionStore.SaveLock`): nothing is written, snapshots included, until it reads.
    case saveLocked
}

/// 불러오기 확인창의 버튼 배치 규칙. AppKit 밖으로 빼둔 이유는 이 규칙이 **데이터 손실과 직결**되는데
/// `NSAlert` 구성은 XCTest 에서 도달할 수 없기 때문이다 — 두 줄이 뒤바뀌면 Return 한 키로 이 Mac 의
/// 진행이 대체되는데 잡을 자동 테스트가 없었다.
enum ImportConfirmPolicy {
    static let replaceButtonIndex = 0
    static let cancelButtonIndex = 1

    /// 기본 버튼(Return)은 **취소**여야 한다. 파괴적 동작을 기본으로 두지 않는다.
    static func keyEquivalent(forButtonAt index: Int) -> String {
        index == cancelButtonIndex ? "\r" : ""
    }
}

enum SaveTransfer {
    /// 세이브 파일 크기 상한. 정상 세이브는 수 KB 이고 도감이 가득 차도 수백 KB 를 넘지 않는다.
    /// 상한이 없으면 거대한 JSON 이 메인스레드 파싱을 수 초간 잡는다(실측: 39MB → 약 1.8초 정지).
    static let maxFileBytes = 8 * 1024 * 1024

    /// 세이브에 들어올 수 있는 수치의 상한 — 실사용(수십억)의 10만 배라 정상 진행을 자르지 않으면서,
    /// 이 값끼리 더하고 빼도 Int64 범위 안에 머문다.
    static let maxTokenValue = 1_000_000_000_000_000
    /// The most of one item a save holds: far above any real count, far below an add's overflow.
    static let maxItemCount = 1_000_000_000

    /// 내보내기 파일명 — 날짜가 들어가야 여러 번 내보내도 덮어쓰지 않는다.
    static func suggestedFileName(date: Date) -> String {
        "PokeTokenBar-Save-\(dayStamp(date)).json"
    }

    /// 백업 파일명 — 불러올 때마다 새 슬롯. 하나만 유지하면 두 번째 불러오기가 **원본**을 덮어써,
    /// "잘못 불러왔으니 되돌린다"는 바로 그 상황에서 되돌릴 대상이 사라진다.
    static func backupFileName(date: Date) -> String {
        "companion-state.pre-import-\(secondStamp(date)).json"
    }
    static let backupFilePrefix = "companion-state.pre-import-"
    /// 유지할 백업 개수 — 오래된 것부터 지운다.
    static let backupsToKeep = 5

    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
    private static func dayStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd") }
    private static func secondStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd-HHmmss") }

    /// `pretty`: indented for a person to read (an export); the app's own snapshots are written compact.
    static func encode(state: CompanionState, appVersion: String, deviceName: String, now: Date,
                       pretty: Bool = true) throws -> Data {
        let envelope = SaveEnvelope(format: SaveEnvelope.formatID,
                                    schema: SaveEnvelope.schemaVersion,
                                    appVersion: appVersion,
                                    exportedAt: now,
                                    sourceDevice: deviceName,
                                    state: state)
        let encoder = JSONEncoder()
        // 사람이 열어봤을 때 읽히도록(무엇이 옮겨가는지 확인 가능) — 4KB 라 크기는 무의미.
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    /// Whether the file is an envelope (it has a `format`), whatever its schema, size or state: such a file is never
    /// read as a bare state, which the lenient decoding turned into an empty game.
    static func isEnvelope(_ data: Data) -> Bool {
        struct Probe: Decodable { let format: String }
        return (try? JSONDecoder().decode(Probe.self, from: data)) != nil
    }

    /// `maxBytes`: the limit of a file picked by the player; the app's own snapshots have none (they grow by about
    /// 21 KB a day, and refused past 8 MB they were restored as an empty game).
    static func decode(_ data: Data, maxBytes: Int = maxFileBytes) throws -> SaveEnvelope {
        guard data.count <= maxBytes else {
            throw SaveTransferError.fileTooLarge(bytes: data.count, limit: maxBytes)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 헤더를 먼저 읽는다 — 본문이 상위 스키마라 못 읽혀도 "새 버전 세이브"로 정확히 안내하기 위해.
        guard let header = try? decoder.decode(SaveHeader.self, from: data),
              header.format == SaveEnvelope.formatID else {
            throw SaveTransferError.notASaveFile
        }
        guard header.schema <= SaveEnvelope.schemaVersion else {
            throw SaveTransferError.newerSchema(found: header.schema, supported: SaveEnvelope.schemaVersion)
        }
        guard var envelope = try? decoder.decode(SaveEnvelope.self, from: data) else {
            throw SaveTransferError.notASaveFile   // 같은 스키마인데 못 읽힘 = 손상
        }
        envelope.state = sanitized(envelope.state)
        return envelope
    }

    /// 신뢰경계 값 정규화 — 세이브는 **앱 밖에서** 온다(손편집·전송 중 손상·다른 빌드).
    ///
    /// `CompanionState` 의 디코딩은 의도적으로 관대해서(한 필드가 깨져도 도감을 안 날리려고) 말이 안 되는
    /// 값도 통과시킨다. 그 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 **프로세스를 죽이고,
    /// 재기동해도 같은 파일을 읽어 다시 죽는다** — 사용자가 파일을 손으로 지우기 전까지 앱을 못 쓴다
    /// (`load()` 의 `.corrupt` 자동복구는 디코드가 *성공*하므로 발동하지 않는다).
    ///
    /// 다운스트림 산술 지점마다 막으면 새 지점이 생길 때마다 재발하므로, 값이 **들어오는 경계 한 곳**에서
    /// 정규화한다. 대상은 실제로 산술에 쓰이는 필드뿐이다 — 도감·인벤토리 항목은 잘라내지 않는다(데이터 손실).
    static func sanitized(_ state: CompanionState) -> CompanionState {
        func clampToken(_ v: Int) -> Int { min(max(0, v), maxTokenValue) }
        var s = state
        s.usedSinceInstall = clampToken(s.usedSinceInstall)
        s.spentTokens = clampToken(s.spentTokens)
        s.merchantTokens = clampToken(s.merchantTokens)
        s.eggUsage = clampToken(s.eggUsage)
        s.amberCarry = clampToken(s.amberCarry)
        s.costumeEggTokens = clampToken(s.costumeEggTokens)
        // Counts are added to (a treasure, a claim, a purchase): one near Int.max trapped at its next add, at every
        // launch. Capped far above any real count: no item is dropped.
        s.inventory = s.inventory.mapValues { min(max(0, $0), maxItemCount) }
        s.unseenTreasures = s.unseenTreasures.mapValues { min(max(0, $0), maxItemCount) }
        s.candyCrumbs = min(max(0, s.candyCrumbs), maxItemCount)
        s.claimedTodayTokensByProvider = s.claimedTodayTokensByProvider?.reduce(into: [:]) { result, entry in
            result[entry.key] = clampToken(entry.value)
        }
        // 알 보증은 "지금 품고 있는 알"에만 붙는 값이라 활성 포켓몬과 공존할 수 없다. 손편집·구버전
        // 조합으로 둘 다 들어오면 그 보증이 다음 알로 새어 영구 프리미엄이 되므로 여기서 떨군다.
        // 그 보증으로 미리 뽑아둔 종(pendingHatchID)도 함께 버린다 — 보증만 지우면 졸업 후 받는 **무료**
        // 알이 그 pre-roll 로 부화해, 아무도 사지 않은 프리미엄 결과가 나온다.
        if s.active != nil {
            s.eggTier = nil; s.eggTypeGuarantee = nil; s.pendingHatchID = nil; s.eggFromTypeNullEgg = false
            s.eggFromLegendaryEgg = false; s.eggFromBirthdayEgg = false; s.pendingShiny = false; s.eggEvent = nil; s.eggFromFossilEgg = false
            s.eggFromDungeon = nil
            s.eggFromCostume = nil
        }
        if let egg = s.eggFromDungeon, !isHatchable(egg) { s.eggFromDungeon = nil }
        // A Costume Egg this version has no costume for would hatch a plain Pokémon: its costume is dropped with it.
        if let egg = s.eggFromCostume, egg.entry == nil { s.eggFromCostume = nil }
        // The Bag's eggs hold only their month; what they hold is drawn when opened.
        s.costumeEggs.removeAll { !(1...12).contains($0.month) }
        s.migrateLegacyBadgeClaims()
        s.pendingForm = PokemonForm.resolved(baseID: s.pendingHatchID ?? 0, form: s.pendingForm)
        // 만족시킬 수 없는 보증은 알을 영구히 못 깨게 만든다 — 전설은 capture_rate 로 표현할 수 없어
        // (captureRateCeiling == nil) 두 롤 경로 모두 후보를 0개로 만들고, 부화가 없으니 보증도 소비되지
        // 않으며, 새 알 구매는 `hasActive` 게이트에 막혀 빠져나갈 수단이 없다. 디코드는 *성공*하므로
        // load() 의 .corrupt 복구도 안 걸려 파일을 손으로 지우기 전엔 앱을 못 쓴다.
        // 관대 디코딩은 모르는 rawValue 만 걸러낼 뿐 **아는데 만족 불가능한 값**은 그대로 통과시킨다.
        if s.eggTier?.captureRateCeiling == nil { s.eggTier = nil }
        // 진화 체인에 같은 종이 두 번 들어오면(손편집) 도감 이름 조회·놓아주기·졸업의
        // `Dictionary(uniqueKeysWithValues:)` 가 트랩한다. 첫 등장만 남긴다.
        func deduped(_ ids: [Int]) -> [Int] {
            var seen = Set<Int>()
            return ids.filter { seen.insert($0).inserted }
        }
        if var active = s.active {
            active.usedAtStage = clampToken(active.usedAtStage)
            // totalForms 는 `kk * (kk + 1)` 형태로 쓰여(PokemonBalance.phaseThreshold) 큰 값이 그 자체로 트랩이다.
            active.totalForms = min(max(1, active.totalForms), 12)
            active.stageIndex = min(max(0, active.stageIndex), max(0, active.pathIDs.count - 1))
            let currentID = active.currentID
            active.pathIDs = deduped(active.pathIDs)
            active.plannedPathIDs = deduped(active.plannedPathIDs)
            active.stageIndex = active.pathIDs.firstIndex(of: currentID) ?? active.stageIndex
            active.stageIndex = min(active.stageIndex, max(0, active.pathIDs.count - 1))
            active.profile?.sanitize()
            s.active = active
        }
        for index in s.dex.indices {
            s.dex[index].chainOrder = deduped(s.dex[index].chainOrder)
            s.dex[index].profile?.sanitize()
        }
        s.dungeons = sanitized(s.dungeons, clampToken: clampToken)
        s.reconcileRepresentativeSelection()
        return s
    }

    /// A dungeon egg the app can hatch: its line's first species and the boss it came from among the 1,025 it knows.
    private static func isHatchable(_ egg: DungeonEgg) -> Bool {
        (1...1025).contains(egg.baseID) && SpeciesInfo.all[egg.baseID] != nil && (1...1025).contains(egg.sourceSpeciesID)
    }

    /// The dungeons' counts are added to (tokens, wins, a first victory's doubled loot) and some become seeds
    /// (`UInt64(floor)`, `UInt64(departures + 1)`): out of range, each trapped at its next use.
    private static func sanitized(_ progress: DungeonProgress, clampToken: (Int) -> Int) -> DungeonProgress {
        func count(_ v: Int) -> Int { min(max(0, v), maxItemCount) }
        func loot(_ l: ExpeditionLoot) -> ExpeditionLoot {
            var l = l
            l.candies = count(l.candies)
            l.items = l.items.mapValues(count)
            return l
        }
        var p = progress
        p.wins = p.wins.mapValues(count)
        p.departures = count(p.departures)
        p.budget = p.budget.map { DungeonBudget(start: clampToken($0.start), dungeonTokens: clampToken($0.dungeonTokens)) }
        // An egg of a species the app cannot hatch would send the Pokémon raised off for an egg that never opens.
        p.eggs = p.eggs.filter(isHatchable)
        // The challenges' days and weeks are short keys; their draws name known battle forms; a member's form is one.
        p.dailyTried = p.dailyTried.flatMap { $0.count <= 10 ? $0 : nil }
        // The week's try is a day's since 2026-11-10 (a week's key before).
        p.weeklyTried = p.weeklyTried.flatMap { $0.count <= 10 ? $0 : nil }
        p.challengeDraws = p.challengeDraws.filter { $0.key.count <= 24 && BattleForms.form(key: $0.value) != nil }
        p.challengeWins = p.challengeWins.filter { $0.key.count <= 24 && BattleForms.form(key: $0.value) != nil }
        // What a villains' team took: items the app knows, counts in range; none means no hideout (issue #180).
        p.stashes = p.stashes.compactMap { stash in
            var stash = stash
            stash.items = stash.items.filter { ItemKind(rawValue: $0.key) != nil && $0.value > 0 }.mapValues(count)
            return stash.items.isEmpty ? nil : stash
        }
        p.ambushes = p.ambushes.filter { $0.kind != nil }.map { ambush in
            var ambush = ambush
            ambush.count = min(max(1, ambush.count), 3)
            return ambush
        }
        let battleForms = Set(BattleForms.all.map(\.form.rawValue))
        p.battleFormChoice = p.battleFormChoice.filter { battleForms.contains($0.value) }
        // An expedition already over waits for nothing that would close it, and a boss the app does not know would give an
        // egg that never opens: neither travels (it locked the dungeons, or the Pokémon raised).
        if let e = p.expedition, case .finished = e.phase { p.expedition = nil }
        if let e = p.expedition, SpeciesBattleTable.data(speciesID: e.boss.speciesID, form: e.boss.form) == nil
            || SpeciesInfo.all[e.boss.speciesID] == nil {
            p.expedition = nil
        }
        if var e = p.expedition {
            // One to three throws and a price within the wallet's reach: past them, a throw counted backwards, and none
            // left spent the balls for nothing.
            switch e.phase {
            case .capture(let left): e.phase = .capture(throwsLeft: min(max(1, left), 3))
            case .awaitingHeal(let price): e.phase = .awaitingHeal(price: clampToken(price))
            case .exploring, .finished: break
            }
            e.loot.eggs = e.loot.eggs.filter(isHatchable)
            e.cost = min(max(1, e.cost), maxTokenValue)
            e.floor = min(max(1, e.floor), e.floors)
            e.floorTokens = clampToken(e.floorTokens)
            e.reserve = clampToken(e.reserve)
            e.tokensIn = clampToken(e.tokensIn)
            e.candiesLeft = count(e.candiesLeft)
            e.battles = count(e.battles)
            e.loot = loot(e.loot)
            e.berries = e.berries.mapValues(count)
            e.revives = e.revives.mapValues(count)
            // A battle multiplies stats and levels: a hand-edited one far past any real Pokémon's overflowed.
            for i in e.team.indices { e.team[i].spec = clamped(e.team[i].spec) }
            e.log = clamped(e.log)
            p.expedition = e
        }
        if var r = p.lastResult {
            r.tokens = clampToken(r.tokens)
            r.battles = count(r.battles)
            r.loot = loot(r.loot)
            r.loot.eggs = r.loot.eggs.filter(isHatchable)
            r.log = clamped(r.log)
            p.lastResult = r
        }
        return p
    }

    /// A Pokémon a battle can take: a level of 1 to 100, stats of 1 to 20,000, HP within its maximum.
    private static func clamped(_ spec: BattlerSpec) -> BattlerSpec {
        var spec = spec
        spec.level = min(max(1, spec.level), 100)
        for path in [\BattleStats.hp, \.attack, \.defense, \.specialAttack, \.specialDefense, \.speed] {
            spec.stats[keyPath: path] = min(max(1, spec.stats[keyPath: path]), 20_000)
        }
        spec.hp = min(max(0, spec.hp), spec.stats.hp)
        return spec
    }

    /// The journal's battles, replayed by "Replay", within what the engine takes: two sides of one to six Pokémon, each
    /// clamped as the team is; a battle that is not goes.
    private static func clamped(_ log: [ExpeditionLogEntry]) -> [ExpeditionLogEntry] {
        log.compactMap { entry in
            guard case .battle(var battle) = entry.kind else { return entry }
            guard battle.setup.sides.count == 2,
                  battle.setup.sides.allSatisfy({ (1...6).contains($0.battlers.count) }) else { return nil }
            for side in battle.setup.sides.indices {
                battle.setup.sides[side].battlers = battle.setup.sides[side].battlers.map(clamped)
                battle.setup.sides[side].active = min(max(1, battle.setup.sides[side].active), battle.setup.sides[side].battlers.count)
            }
            var kept = entry
            kept.kind = .battle(battle)
            return kept
        }
    }

    /// 다른 기기에서 온 상태를 **이 기기 기준으로 재정렬**한다.
    ///
    /// `CompanionState` 의 필드는 이전 관점에서 세 부류다.
    ///  - **진행**: 어느 기기에서든 참(`usedSinceInstall`·`dex`·`inventory`·`active`·`eggUsage`·`eggTier`·
    ///    `pendingHatchID`·`pendingForm`·`representativeSpeciesID`·`representativeForm`…)
    ///    → 그대로. 알 보증(`eggTier`)은 산 물건이지 이 기기의 장부가 아니라 기기를 옮겨도 따라간다.
    ///  - **로컬 장부**: *그 기기가* 어디까지 적립했나(`claimedTodayTokensByProvider`·`lastDate`·`installBaselineSet`)
    ///    → 새 기기 기준으로 다시 잡는다. 그대로 들여오면 옛 기기의 오늘 총량이 문턱이 되어
    ///    `CompanionStore.update` 의 프로바이더별 증분 게이트가 이전 당일 내내 거짓이 되고,
    ///    새 기기 사용분이 조용히 안 잡힌다(자정에 저절로 낫기 때문에 버그로 안 보인다).
    ///  - **기기 환경설정**: 진행이 아니라 이 기기에서 보는 방식(`language`) → **현재 기기 값을 지킨다**.
    ///    일본어 Mac 의 세이브가 영어 Mac 의 UI 언어를 바꾸면 안 된다.
    ///
    /// 계정 전역 원장(`candyGrantTier`·`candyWindowEpoch`)은 교체가 아니라 **key 별 병합**이다. 한도 창 key 는 계정
    /// 단위라 두 기기가 같은 창을 본다 — 더 오래된 세이브로 통째 교체하면 이미 지급한 창의 기록이
    /// 사라져 같은 창에서 사탕이 재지급된다(보존만으로는 이 역방향을 못 막는다).
    static func rebasedForThisDevice(_ imported: CompanionState,
                                     current: CompanionState,
                                     todayTokensByProvider: [String: Int],
                                     todayDate: String,
                                     hasUsageData: Bool) -> CompanionState {
        var state = imported
        state.language = current.language
        // The build that writes is this Mac's, not the exporting one's (`CompanionState.writer`).
        state.writer = current.writer
        let (importedLedger, currentLedger) = withoutEndedWindows(imported, current)
        state.candyGrantTier = mergedGrantTier(importedLedger.candyGrantTier, currentLedger.candyGrantTier)
        state.candyWindowEpoch = mergedWindowEpochs(
            importedLedger.candyWindowEpoch, importedLedger.candyGrantTier,
            currentLedger.candyWindowEpoch, currentLedger.candyGrantTier)
        state.candyWindowPlan = mergedWindowPlans(importedLedger.candyWindowPlan, importedLedger.candyGrantTier,
                                                  currentLedger.candyWindowPlan, currentLedger.candyGrantTier)
        state.candyFeatureSeeded = imported.candyFeatureSeeded || current.candyFeatureSeeded
        state.candyGrantsAsYouGo = imported.candyGrantsAsYouGo || current.candyGrantsAsYouGo
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        if hasCurrentProviderData {
            // 신규 설치와 같은 규칙: 불러온 시점 이전의 이 기기 사용량은 소급 적립하지 않는다.
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
        } else {
            // 아직 이 기기의 오늘 사용량을 모른다(파싱 전·프로바이더 없음·stale snapshot만 존재).
            // `hasUsageData`는 snapshot 존재 여부일 뿐 오늘 날짜 데이터의 존재를 보장하지 않는다.
            // 여기서 빈 map을 이미 seed된 장부로 저장하면 첫 정상 snapshot이 "새 provider"로
            // 취급되어 그 시점까지의 하루치가 조용히 누락된다 → baseline 판정을 신규 설치 경로에 넘긴다.
            state.installBaselineSet = false
            state.claimedTodayTokensByProvider = nil
            state.lastDate = ""
        }
        return state
    }

    /// Both ledgers without the windows one side saw in an earlier epoch than the other: that window ended, and its
    /// count says nothing of the current one. Merged by max, a snapshot of last week paid 80 kept this week's count at
    /// 80 under this week's epoch, and nothing was paid until the week passed 80%. The later window keeps its count,
    /// epoch and plan together. Windows of the same epoch, or without one, merge as before.
    static func withoutEndedWindows(_ a: CompanionState, _ b: CompanionState) -> (CompanionState, CompanionState) {
        var a = a, b = b
        for key in Set(a.candyWindowEpoch.keys).intersection(b.candyWindowEpoch.keys) {
            guard let dateA = a.candyWindowEpoch[key].flatMap(CompanionStore.parseEpochDate),
                  let dateB = b.candyWindowEpoch[key].flatMap(CompanionStore.parseEpochDate),
                  abs(dateA.timeIntervalSince(dateB)) >= 1800 else { continue }
            if dateA < dateB {
                a.candyGrantTier[key] = nil; a.candyWindowEpoch[key] = nil; a.candyWindowPlan[key] = nil
            } else {
                b.candyGrantTier[key] = nil; b.candyWindowEpoch[key] = nil; b.candyWindowPlan[key] = nil
            }
        }
        return (a, b)
    }

    /// Each window's plan from the side whose ledger `mergedGrantTier` keeps, this device's on a tie: the count paid
    /// and the plan it was paid at stay together.
    static func mergedWindowPlans(
        _ plansA: [String: Int], _ tiersA: [String: Int],
        _ plansB: [String: Int], _ tiersB: [String: Int]
    ) -> [String: Int] {
        var out: [String: Int] = [:]
        for key in Set(plansA.keys).union(plansB.keys) {
            let fromA = (tiersA[key] ?? 0) > (tiersB[key] ?? 0) || plansB[key] == nil
            out[key] = fromA ? plansA[key] ?? plansB[key] : plansB[key]
        }
        return out
    }

    /// 창 key 별로 더 높은 tier 를 남긴다 — 어느 쪽에서든 이미 지급했으면 지급한 것으로 본다.
    static func mergedGrantTier(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        a.merging(b) { max($0, $1) }
    }

    /// epoch 병합 — 양쪽이 이미 지급(tier≥1)한 창은 더 늦은 epoch 를 남겨 현재 창에서 재지급을 막고,
    /// 한쪽만 지급했으면 그쪽 epoch 를 쓴다(다른 기기가 못 본 창은 이후 live epoch 교체로 재무장 가능).
    static func mergedWindowEpochs(
        _ epochsA: [String: String], _ tiersA: [String: Int],
        _ epochsB: [String: String], _ tiersB: [String: Int]
    ) -> [String: String] {
        let keys = Set(epochsA.keys).union(epochsB.keys).union(tiersA.keys).union(tiersB.keys)
        var out: [String: String] = [:]
        for key in keys {
            let tierA = tiersA[key] ?? 0
            let tierB = tiersB[key] ?? 0
            if tierA > 0, tierB > 0 {
                out[key] = [epochsA[key], epochsB[key]].compactMap { $0 }.max()
            } else if tierA > 0 {
                out[key] = epochsA[key]
            } else if tierB > 0 {
                out[key] = epochsB[key]
            } else {
                out[key] = [epochsA[key], epochsB[key]].compactMap { $0 }.max()
            }
        }
        return out.compactMapValues { $0 }
    }
}
