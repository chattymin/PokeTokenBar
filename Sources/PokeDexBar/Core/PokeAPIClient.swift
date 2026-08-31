import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도.
/// `isLegendary`/`isMythical` 은 기본값을 주지 않는다 — 이 필드가 없던 구 디스크 캐시
/// (`base-index.json`)는 디코드가 그대로 실패해야 한다. 기본값을 주면 옛 캐시가 "전설 아님"으로
/// 조용히 읽혀, 전설 뽑기가 실제로는 절대 전설을 못 주는 결함이 재발한다 — 실패해야 재구축된다.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호
    let isLegendary: Bool
    let isMythical: Bool
    /// 성장 곡선. 기본값(`mediumFast`)은 이 필드를 생략하는 기존 테스트 호출부가 계속 컴파일되게
    /// 하기 위한 메모리와이즈 이니셜라이저 편의일 뿐이다 — Codable 합성 디코드는 기본값을 무시하고
    /// 키를 그대로 요구하므로, 이 필드가 없던 구 디스크 캐시(`base-index.json`)는 여전히 디코드가
    /// 실패해 자동 재구축된다(위 isLegendary/isMythical 과 같은 이유).
    var growthRate: GrowthRate = .mediumFast
    /// 성비(PokéAPI `gender_rate`) — 8분의 몇이 암컷인가. `-1` 은 무성별.
    /// 기본값이 있는 이유는 `growthRate` 와 같다(메모리 생성 편의) — 합성 Codable 은 여전히 키를
    /// 요구하므로, 이 필드가 없는 옛 `base-index.json` 은 디코드에 실패해 자동으로 다시 만들어진다.
    var genderRate: Int = GenderBalance.defaultRate
}

/// 메타몽 종 id — 위장·변신 등 별도 처리가 필요한 특수종이라 일반 부화 후보 풀에서 제외한다.
private let dittoSpeciesID = 132

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~5세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?

    /// 도감 상세의 프로필(키·몸무게·분류·도감설명). 디스크에 캐시된다 — 종 하나에 평생 한 번.
    func speciesProfile(id: Int) async throws -> SpeciesProfile
}

extension PokeProviding {
    /// 기본은 "없다" — 테스트 스텁 여럿이 이 프로토콜을 입는데, 도감 상세를 안 다루는 스텁까지
    /// 프로필을 지어내게 하는 것보다 던지는 쪽이 정직하다. 실제 클라이언트는 구현을 갖는다.
    func speciesProfile(id: Int) async throws -> SpeciesProfile {
        throw URLError(.unsupportedURL)
    }
}

/// PokéAPI 클라이언트 — 종/진화체인을 런타임 fetch + 파싱. 포켓몬 데이터는 레포에 번들하지 않는다.
/// species 응답은 actor 캐시(다국어 이름 재사용).
actor PokeAPIClient: PokeProviding {
    static let shared = PokeAPIClient()
    private let base = URL(string: "https://pokeapi.co/api/v2")!
    private let langCodes = ["ko", "en", "ja-Hrkt", "ja"]
    private var speciesCache: [Int: SpeciesDTO] = [:]
    private var lineCache: [Int: EvoLine] = [:]   // 프리패칭 → 부화 순간 네트워크 0

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if let cached = lineCache[baseSpeciesID] { return cached }
        let baseSpecies = try await species(baseSpeciesID)
        // PokéAPI 응답의 URL — 비정상/빈 값이면 force-unwrap 대신 throw(앱은 알 상태 유지).
        guard let chainURL = Self.validatedChainURL(baseSpecies.evolution_chain.url) else {
            throw URLError(.badURL)
        }
        let chainDTO: ChainDTO = try await get(chainURL)
        let tree = node(from: chainDTO.chain)
        let rarity = Rarity.from(captureRate: baseSpecies.capture_rate,
                                 isLegendary: baseSpecies.is_legendary,
                                 isMythical: baseSpecies.is_mythical)
        // 라인의 모든 종 이름(지원 언어만) + 성장 곡선
        var names: [Int: [String: String]] = [:]
        var growthRates: [Int: GrowthRate] = [:]
        var genderRates: [Int: Int] = [:]
        for id in allIDs(tree) {
            let sp = try await species(id)
            var byLang: [String: String] = [:]
            for n in sp.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
            names[id] = byLang
            growthRates[id] = GrowthRate.fromAPI(sp.growth_rate.name)
            genderRates[id] = sp.gender_rate
        }
        let line = EvoLine(baseID: baseSpeciesID, tree: tree, rarity: rarity, names: names,
                           growthRates: growthRates, genderRates: genderRates)
        lineCache[baseSpeciesID] = line
        return line
    }

    // MARK: base 인덱스 (부화 후보)

    private var baseIndexCache: [BaseSpecies]?
    private var restBuildInFlight = false
    private var restBuildTried = false   // 세션당 1회 (GraphQL 다운 시 REST 인덱스 구축 트리거)
    private static let baseIndexFile: URL = {
        let dir = AppEnv.userDirectory(.applicationSupportDirectory)
            .appendingPathComponent(AppEnv.storageName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("base-index.json")
    }()
    struct BaseIndexSnapshot: Codable {
        let fetchedAt: Date
        let entries: [BaseSpecies]
        /// 이 인덱스를 만들 때의 종 범위 상한. 범위가 넓어져도(649 → 1025) 캐시는 30일을 살아남기
        /// 때문에, 이걸 안 보면 옛 범위로 만든 인덱스가 계속 쓰이며 새 세대가 부화 풀에 영영
        /// 안 들어온다. 구 형식(필드 없음)은 0으로 읽혀 항상 재구축된다.
        var maxSpeciesID = 0

        /// 지금 다루는 범위로 만든 인덱스인가.
        func matchesCurrentRange() -> Bool {
            maxSpeciesID == PokemonAssets.speciesIDs.upperBound
        }

        init(fetchedAt: Date, entries: [BaseSpecies], maxSpeciesID: Int) {
            self.fetchedAt = fetchedAt
            self.entries = entries
            self.maxSpeciesID = maxSpeciesID
        }

        // 범위 필드가 없던 구 형식도 읽어야 오프라인 폴백이 살아 있다 — 없으면 0으로 읽혀
        // `matchesCurrentRange()` 가 거짓이 되고, 온라인이면 곧바로 재구축된다.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
            entries = try c.decode([BaseSpecies].self, forKey: .entries)
            maxSpeciesID = (try? c.decode(Int.self, forKey: .maxSpeciesID)) ?? 0
        }
    }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable {
            let id: Int
            let capture_rate: Int
            let is_legendary: Bool
            let is_mythical: Bool
            /// PokéAPI GraphQL 은 REST 의 `growth_rate` 와 달리 밑줄 없는 관계명 `growthrate` 를 쓴다.
            let growthrate: NamedRef
            /// 관계가 아니라 컬럼이라 REST 와 같은 밑줄 표기다(`growthrate` 와 대비된다).
            let gender_rate: Int
        }
        let data: DataBox
    }

    /// 1~5세대 base(진화라인 시작점) 전체 — PokéAPI GraphQL 1쿼리.
    /// 우선순위: 메모리 캐시 → 디스크 캐시(30일 TTL) → GraphQL fetch(성공 시 디스크 갱신)
    /// → TTL 지난 디스크라도 있으면 사용(오프라인 폴백). 전부 실패 시 throw(알 유지, 다음 틱 재시도).
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if let c = baseIndexCache { return c }
        let disk = (try? Data(contentsOf: Self.baseIndexFile))
            .flatMap { try? JSONDecoder().decode(BaseIndexSnapshot.self, from: $0) }
        if let disk, disk.matchesCurrentRange(),
           Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            baseIndexCache = disk.entries
            return disk.entries
        }
        do {
            let entries = try await fetchBaseIndex()
            baseIndexCache = entries
            let snapshot = BaseIndexSnapshot(fetchedAt: Date(), entries: entries,
                                             maxSpeciesID: PokemonAssets.speciesIDs.upperBound)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.baseIndexFile, options: .atomic)
            }
            AppLog.write("base index: rebuilt for range ≤\(PokemonAssets.speciesIDs.upperBound) — \(entries.count) bases")
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {   // 오프라인 — 오래된 인덱스라도 사용
                baseIndexCache = disk.entries
                return disk.entries
            }
            // GraphQL 다운 + 캐시 없음 → REST 로 인덱스를 백그라운드 구축(세션 1회).
            // 이번 뽑기는 실패로 돌아가고(상점이 재시도를 안내한다 — 재화는 안 빠진다),
            // 구축이 끝나면 디스크 캐시로 남아 이후 선택이 가중·수집반영·오프라인가능으로 복귀한다.
            if !restBuildTried {
                restBuildTried = true
                Task { await self.buildBaseIndexViaREST() }
            }
            AppLog.write("base index (GraphQL) failed, no cache — REST build triggered; this draw fails and the user retries: \(error)")
            throw error
        }
    }

    /// GraphQL base 인덱스 엔드포인트 장애 시 REST(pokemon-species/{id})로 base 인덱스를 직접 구축·영속.
    /// 한 번 성공하면 base-index.json(30일)으로 남아 이후 선택은 네트워크 없이 가중·수집반영으로 동작 →
    /// 부화가 특정 엔드포인트 생존에 영구히 묶이지 않게 하는 자가치유 캐시. PokéAPI 배려로 소규모 동시성.
    func buildBaseIndexViaREST() async {
        guard baseIndexCache == nil, !restBuildInFlight else { return }
        restBuildInFlight = true
        defer { restBuildInFlight = false }
        AppLog.write("base index: building via REST (GraphQL unavailable)…")
        var bases: [BaseSpecies] = []
        let batchSize = 6
        var start = 1
        let maxID = PokemonAssets.speciesIDs.upperBound
        while start <= maxID {
            let end = min(start + batchSize - 1, maxID)
            let found = await withTaskGroup(of: BaseSpecies?.self) { group -> [BaseSpecies] in
                for id in start...end { group.addTask { try? await self.baseSpecies(id: id) } }
                var acc: [BaseSpecies] = []
                for await r in group { if let r { acc.append(r) } }
                return acc
            }
            bases.append(contentsOf: found)
            start += batchSize
        }
        // 대부분 실패(네트워크 불안정)면 빈약한 인덱스를 영속하지 않고 다음 세션 재시도.
        guard bases.count >= 150 else {
            AppLog.write("base index: REST build incomplete (\(bases.count)) — not cached, will retry next session")
            return
        }
        bases.sort { $0.id < $1.id }
        baseIndexCache = bases
        let snapshot = BaseIndexSnapshot(fetchedAt: Date(), entries: bases,
                                         maxSpeciesID: PokemonAssets.speciesIDs.upperBound)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.baseIndexFile, options: .atomic)
        }
        AppLog.write("base index: REST build done — \(bases.count) bases persisted (offline-capable now)")
    }

    private func fetchBaseIndex() async throws -> [BaseSpecies] {
        // 공식 GraphQL — evolves_from IS NULL(=base) + id ≤ 1025(다루는 종 범위 상한)
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 메타몽(#132)은 별도 처리가 필요한 특수종이라 일반 부화 풀에서 제외(_neq).
        let maxID = PokemonAssets.speciesIDs.upperBound
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate is_legendary is_mythical gender_rate growthrate { name } } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map {
            BaseSpecies(id: $0.id, captureRate: $0.capture_rate,
                       isLegendary: $0.is_legendary, isMythical: $0.is_mythical,
                       growthRate: GrowthRate.fromAPI($0.growthrate.name),
                       genderRate: $0.gender_rate)
        }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
    }

    private func species(_ id: Int) async throws -> SpeciesDTO {
        if let c = speciesCache[id] { return c }
        let dto: SpeciesDTO = try await get(base.appendingPathComponent("pokemon-species/\(id)"))
        speciesCache[id] = dto
        return dto
    }

    /// REST 폴백 — 단일 종 상세(pokemon-species/{id})로 base 여부·capture_rate 판정.
    /// GraphQL base 인덱스가 죽어도 REST(pokeapi.co/api/v2)는 별개 엔드포인트라 동작한다.
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        guard id != dittoSpeciesID else { return nil }   // 메타몽은 일반 부화 후보에서 제외
        let dto = try await species(id)
        guard dto.evolves_from_species == nil else { return nil }   // 진화 중간체는 부화 후보 아님
        return BaseSpecies(id: id, captureRate: dto.capture_rate,
                           isLegendary: dto.is_legendary, isMythical: dto.is_mythical,
                           growthRate: GrowthRate.fromAPI(dto.growth_rate.name),
                           genderRate: dto.gender_rate)
    }

    private var profileCache: [Int: SpeciesProfile] = [:]

    /// 프로필 디스크 캐시 자리. 스프라이트 캐시와 같은 지붕(Application Support) 아래다.
    private static func profileURL(id: Int) -> URL {
        let dir = AppEnv.supportDirectory().appendingPathComponent("species-profiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id).json")
    }

    func speciesProfile(id: Int) async throws -> SpeciesProfile {
        if let cached = profileCache[id] { return cached }
        // 디스크 — 도감설명·키·몸무게는 안 변하는 값이라 무효화가 필요 없다.
        if let data = try? Data(contentsOf: Self.profileURL(id: id)),
           let stored = try? JSONDecoder().decode(SpeciesProfile.self, from: data) {
            profileCache[id] = stored
            return stored
        }
        let dto = try await species(id)
        let size: PokemonSizeDTO = try await get(base.appendingPathComponent("pokemon/\(id)"))
        // ko/en/ja 만 담는다 — 다른 언어까지 실으면 프로필 캐시가 열 배로 는다.
        let flavors = (dto.flavor_text_entries ?? []).compactMap { entry -> FlavorRecord? in
            guard ["ko", "en", "ja"].contains(entry.language.name),
                  let version = entry.version?.name else { return nil }
            return FlavorRecord(version: version, language: entry.language.name,
                                text: SpeciesProfile.cleaned(entry.flavor_text))
        }
        func genus(_ lang: String) -> String {
            (dto.genera ?? []).first(where: { $0.language.name == lang })?.genus
                ?? (dto.genera ?? []).first(where: { $0.language.name == "en" })?.genus ?? ""
        }
        func name(_ lang: String) -> String {
            dto.names.first(where: { $0.language.name == lang })?.name
                ?? dto.names.first(where: { $0.language.name == "en" })?.name ?? "#\(id)"
        }
        let profile = SpeciesProfile(
            speciesID: id,
            nameKo: name("ko"), nameEn: name("en"), nameJa: name("ja"),
            typeSlugs: size.types.sorted { $0.slot < $1.slot }.map(\.type.name),
            heightDm: size.height, weightHg: size.weight,
            genusKo: genus("ko"), genusEn: genus("en"), genusJa: genus("ja"),
            flavors: flavors)
        profileCache[id] = profile
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: Self.profileURL(id: id))
        }
        return profile
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func node(from link: ChainLink, parentLevel: Int = 1) -> EvoNode {
        let speciesID = Self.id(from: link.species.url ?? "")
        let raw = Self.requirement(from: link.evolution_details, speciesID: speciesID, parentLevel: parentLevel)
        let myLevel = if case .level(let n) = raw { n } else { parentLevel }
        return EvoNode(speciesID: speciesID,
                       children: link.evolves_to.map { node(from: $0, parentLevel: myLevel) },
                       requirementRaw: raw,
                       regionalRequirementRaw: Self.regionalRequirement(from: link.evolution_details),
                       requiredGender: Self.gender(from: link.evolution_details))
    }

    /// 조건 목록 → 이 앱이 쓰는 요구 조건. 여러 건이면 **재현 가능한 것 중 첫 번째**를 쓴다
    /// (버전별로 갈리는 경우가 있고, 그중 하나만 만족하면 되는 것이 본가 규칙이다). 우선순위는
    /// 도구 → 통신교환 → 든 도구 → 친밀도 → 명시된 레벨 → **카탈로그(레벨이 안 적힌 31종)** →
    /// 레벨 규칙(그 외 미명시) 순으로 고정이다. 통신교환은 도구가 따로 없으므로 연결의 끈으로
    /// 대신한다 — 이 앱에는 교환 상대가 없다. `speciesID` 는 카탈로그 조회 키, `parentLevel` 은
    /// 이 갈래 바로 앞 단계가 도달한 레벨(뿌리는 1) — 레벨이 안 적힌 갈래의 하한 계산(`EvoBalance`)에 쓴다.
    static func requirement(from details: [EvolutionDetail]?, speciesID: Int, parentLevel: Int) -> EvoRequirementRaw {
        guard let details, !details.isEmpty else { return .none }
        for (index, d) in details.enumerated() {
            // **레벨이 *다른* 조건줄에 있으면 이 도구는 지방 모습의 것이다**(모래사원·야도란·
            // 붐볼·불카모스 4종 — 전수 확인). 여기서 도구를 집으면 원종의 레벨 조건이 통째로
            // 사라져, 관동 모래두지가 얼음의돌만 있으면 **레벨 1에** 진화한다(사용자 제보).
            //
            // **같은 줄 안의 레벨은 다르다** — 그건 이 조건의 일부라 도구가 이긴다(기존 규칙
            // `testAnItemStillWinsOverALevel`). 실제 응답에 그런 줄은 0건이지만, 두 경우를
            // 뭉뚱그리면 그 규칙이 조용히 뒤집힌다.
            if Self.levelLivesInAnotherDetail(details, itemIndex: index) { continue }
            if let item = d.item?.name, EvolutionItem.named(item) != nil {
                return .item(item)
            }
            if d.trigger?.name == "trade" {
                // 물건을 들고 교환하는 15종은 그 물건이 조건이다 — 연결의 끈으로 뭉뚱그리면
                // 에레키부스터·금속코트 같은 것이 게임에서 사라진다.
                if let held = d.held_item?.name, EvolutionItem.named(held) != nil {
                    return .item(held)
                }
                return .item(EvolutionItem.linkingCord.rawValue)
            }
            // **든 도구도 도구다.** 럭키(둥근돌)·글라이온(예리한이빨)·포푸니라/포푸니크(예리한손톱)
            // 넷이 여기 걸린다 — 지금까지는 통신교환일 때만 held_item 을 봤다. 원작의 "밤에" 같은
            // 시간대 조건은 이 앱에 밤낮이 없어 버린다(포푸니라/포푸니크가 같은 물건을 공유하게 된다).
            if let held = d.held_item?.name, EvolutionItem.named(held) != nil { return .item(held) }
        }
        for d in details where (d.min_happiness ?? 0) > 0 { return .friendship }
        if let stated = details.compactMap(\.min_level).min() { return .level(stated) }
        // PokéAPI 가 레벨을 아예 안 주는 31종(기술·전투·조작 조건)은 이 앱이 옮긴 표를 먼저 본다 —
        // `min_level` 이 없을 때만 의미가 있으므로 명시된 레벨보다 뒤, 일반 폴백보다는 앞이다.
        if let override = UnstatedEvolutionCatalog.override(speciesID: speciesID) { return override }
        // 카탈로그에도 없는(장소 등) 갈래는 앞 단계 레벨 위로 일정 간격 띄운 값으로 채운다 —
        // `.none` 으로 두면 조건 없이 즉시 진화해 버린다.
        return .level(max(parentLevel + EvoBalance.marginOverParent, EvoBalance.unstatedLevel))
    }
    /// 지방 모습에만 걸리는 도구 조건. 원종이 레벨로 진화하는데 도구 조건이 함께 온 갈래에서만
    /// 값이 나온다(4종). 그 외에는 nil 이라 지방 모습도 원종과 같은 조건을 쓴다.
    static func regionalRequirement(from details: [EvolutionDetail]?) -> EvoRequirementRaw? {
        guard let details else { return nil }
        for (index, d) in details.enumerated()
        where Self.levelLivesInAnotherDetail(details, itemIndex: index) {
            if let item = d.item?.name, EvolutionItem.named(item) != nil { return .item(item) }
        }
        return nil
    }

    /// `itemIndex` 줄의 도구가 **지방 모습의 것인가** — 레벨 조건이 다른 줄에 따로 있으면 그렇다.
    /// 같은 줄에 있으면 한 조건의 두 부분이므로 아니다.
    static func levelLivesInAnotherDetail(_ details: [EvolutionDetail], itemIndex: Int) -> Bool {
        details.enumerated().contains { other, d in
            other != itemIndex && (d.min_level ?? 0) > 0
        }
    }

    /// 성별 제한 — **요구 조건과 따로 싣는다.** 조건 enum 에 넣으면 "새벽의돌 **그리고** 수컷"
    /// (엘레이드)처럼 둘을 동시에 요구하는 갈래를 표현할 수 없다. 여섯 갈래뿐이지만 그 여섯이
    /// 전부 도구·레벨 조건과 겹친다.
    static func gender(from details: [EvolutionDetail]?) -> Gender? {
        guard let details else { return nil }
        for d in details {
            switch d.gender {
            case 1: return .female
            case 2: return .male
            default: continue
            }
        }
        return nil
    }

    private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }

    static func id(from speciesURL: String) -> Int {
        // ".../pokemon-species/{id}/"
        let parts = speciesURL.split(separator: "/").filter { !$0.isEmpty }
        return Int(parts.last ?? "0") ?? 0
    }

    /// PokéAPI evolution_chain URL 검증(SSRF 가드) — 서버 제어 문자열이므로 https + pokeapi.co 로 고정해
    /// 응답 변조 시 임의 호스트 fetch 를 막는다. 부적합하면 nil(호출부가 throw → 앱은 알 상태 유지).
    static func validatedChainURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "pokeapi.co" else { return nil }
        return url
    }
}

// MARK: - DTO (PokéAPI 응답 부분 디코드)

struct SpeciesDTO: Decodable, Sendable {
    let capture_rate: Int
    let is_legendary: Bool
    let is_mythical: Bool
    let names: [NameDTO]
    let evolution_chain: URLRef
    let evolves_from_species: NamedRef?   // nil = 진화라인 시작점(base)
    let growth_rate: NamedRef
    /// 성비 — 8분의 몇이 암컷인가. `-1` 은 무성별.
    let gender_rate: Int
    /// 도감설명 — (언어 × 게임 버전) 격자라 같은 언어가 여러 번 온다.
    let flavor_text_entries: [FlavorDTO]?
    /// 분류("쥐포켓몬") — 언어별.
    let genera: [GenusDTO]?
}
struct FlavorDTO: Decodable, Sendable {
    let flavor_text: String
    let language: NamedRef
    let version: NamedRef?
}
struct GenusDTO: Decodable, Sendable { let genus: String; let language: NamedRef }
/// `pokemon/{id}` 에서 키·몸무게·타입만 — 나머지 필드(수백 줄)는 안 읽는다.
struct PokemonSizeDTO: Decodable, Sendable {
    let height: Int
    let weight: Int
    let types: [TypeSlotDTO]
}
struct TypeSlotDTO: Decodable, Sendable { let slot: Int; let type: NamedRef }
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }
struct ChainLink: Decodable, Sendable {
    let species: NamedRef
    let evolves_to: [ChainLink]
    /// 이 종이 되기 위한 조건들. 버전마다 여러 개가 올 수 있어 배열이다.
    let evolution_details: [EvolutionDetail]?
}

/// `evolution_details` 한 건. 이 앱이 재현할 수 있는 필드만 읽는다 — 장소·특정 기술처럼
/// 대응물이 없는 조건은 아예 안 읽고 조건 없음으로 떨어뜨린다(막으면 그 종을 영영 못 얻는다).
struct EvolutionDetail: Decodable, Sendable {
    let trigger: NamedRef?
    let item: NamedRef?
    /// 통신교환/레벨업 때 들고 있어야 하는 물건. 통신교환 25종 중 15종, 레벨업 4종이 이걸 요구한다.
    let held_item: NamedRef?
    let min_happiness: Int?
    /// 본가 `min_level`. 명시가 없는 갈래(장소·기술 등)는 nil — `EvoBalance` 규칙으로 채운다.
    let min_level: Int?
    /// 성별 제한(1=암컷, 2=수컷). 제한이 없으면 nil — 전 1025종에서 여섯 갈래만 값이 있다.
    let gender: Int?
}
