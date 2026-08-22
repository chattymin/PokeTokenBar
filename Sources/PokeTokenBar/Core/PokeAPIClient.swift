import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도 및 세대 ID.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호
    let generationID: Int   // 1(관동)~5(하나)

    enum CodingKeys: String, CodingKey {
        case id
        case captureRate
        case generationID
    }

    init(id: Int, captureRate: Int, generationID: Int? = nil) {
        self.id = id
        self.captureRate = captureRate
        self.generationID = generationID ?? Self.inferGenerationID(for: id)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        captureRate = try c.decode(Int.self, forKey: .captureRate)
        generationID = try c.decodeIfPresent(Int.self, forKey: .generationID) ?? Self.inferGenerationID(for: id)
    }

    static func inferGenerationID(for id: Int) -> Int {
        switch id {
        case 1...151: return 1
        case 152...251: return 2
        case 252...386: return 3
        case 387...493: return 4
        case 494...649: return 5
        default: return 1
        }
    }
}

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~5세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?
    /// 지원되는 포켓몬 지역 목록.
    func fetchRegions() async throws -> [RegionInfo]
    /// 특정 지역의 위치 목록.
    func fetchLocations(regionID: Int) async throws -> [LocationInfo]
    /// 특정 위치에서 출현하는 포켓몬 species ID 목록.
    func fetchLocationEncounterSpeciesIDs(locationID: String) async throws -> Set<Int>
}

extension PokeProviding {
    func fetchRegions() async throws -> [RegionInfo] { [] }
    func fetchLocations(regionID: Int) async throws -> [LocationInfo] { [] }
    func fetchLocationEncounterSpeciesIDs(locationID: String) async throws -> Set<Int> { [] }
}

/// PokéAPI 클라이언트 — 종/진화체인을 런타임 fetch + 파싱. 포켓몬 데이터는 레포에 번들하지 않는다.
/// species 응답은 actor 캐시(다국어 이름 재사용).
actor PokeAPIClient: PokeProviding {
    static let shared = PokeAPIClient()
    private let base = URL(string: "https://pokeapi.co/api/v2")!
    // Lockstep with the union of AppLanguage.apiCodes. "pt" collects nothing today
    // (PokéAPI has no such language) but is listed so it is picked up the moment
    // one appears — omit it and EvoLine.names never carries it, pinning English.
    // AppLanguage.apiCodes 의 합집합과 lockstep. "pt" 는 아직 PokéAPI 에 없어 수집되지 않지만,
    // 추가되는 즉시 잡히도록 함께 둔다(없으면 EvoLine.names 에 안 담겨 영어 폴백이 고정된다).
    private let langCodes = ["ko", "en", "ja-Hrkt", "ja", "es", "fr", "pt"]
    private var speciesCache: [Int: SpeciesDTO] = [:]
    private var lineCache: [Int: EvoLine] = [:]   // 프리패칭 → 부화 순간 네트워크 0
    private var regionsCache: [RegionInfo]?
    private var locationsCache: [Int: [LocationInfo]] = [:]

    private func regionsCacheURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        return dir.appendingPathComponent("regions-index.json")
    }

    private func locationsCacheURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        return dir.appendingPathComponent("locations-index.json")
    }

    func fetchRegions() async throws -> [RegionInfo] {
        // Step 1: 메모리 캐시
        if let cached = regionsCache, !cached.isEmpty { return cached }

        // Step 2: 디스크 캐시 (regions-index.json)
        if let diskRegions = loadRegionsFromDiskCache(), !diskRegions.isEmpty {
            regionsCache = diskRegions
            return diskRegions
        }

        // Step 3 (Option A): GraphQL 실시간 전수 추출
        if let fetched = try? await fetchRegionsViaGraphQL(), !fetched.isEmpty {
            regionsCache = fetched
            saveRegionsToDiskCache(fetched)
            return fetched
        }

        // Step 4 (Option B): REST API 폴백
        if let restFetched = try? await fetchRegionsViaREST(), !restFetched.isEmpty {
            regionsCache = restFetched
            saveRegionsToDiskCache(restFetched)
            return restFetched
        }

        // Step 5 (Option C): 완전 오프라인 무저작권 제네릭 폴백 (저작권 데이터 원천 배제)
        let fallback = Self.generateGenericRegionsFallback()
        return fallback
    }

    func fetchLocations(regionID: Int) async throws -> [LocationInfo] {
        // Step 1: 메모리 캐시
        if let cached = locationsCache[regionID], !cached.isEmpty { return cached }

        // Step 2: 디스크 캐시 복원 (locations-index.json)
        if locationsCache.isEmpty, let diskLocations = loadLocationsFromDiskCache(), !diskLocations.isEmpty {
            var map: [Int: [LocationInfo]] = [:]
            for loc in diskLocations {
                map[loc.regionID, default: []].append(loc)
            }
            locationsCache = map
            if let result = locationsCache[regionID], !result.isEmpty { return result }
        }

        // Step 3 (Option A): GraphQL 실시간 전수 추출
        if let fetchedMap = try? await fetchAllLocationsViaGraphQL(), !fetchedMap.isEmpty {
            locationsCache = fetchedMap
            saveLocationsToDiskCache(fetchedMap.values.flatMap { $0 })
            if let result = locationsCache[regionID], !result.isEmpty { return result }
        }

        // Step 4 (Option B): REST API 폴백
        if let restLocations = try? await fetchLocationsViaREST(regionID: regionID), !restLocations.isEmpty {
            locationsCache[regionID] = restLocations
            return restLocations
        }

        // Step 5 (Option C): 완전 오프라인 무저작권 제네릭 폴백 (저작권 데이터 원천 배제)
        let fallback = Self.generateGenericLocationsFallback(regionID: regionID)
        return fallback
    }

    // MARK: REST API 폴백 구현 (Option B)

    private func fetchRegionsViaREST() async throws -> [RegionInfo] {
        var regions: [RegionInfo] = []
        for id in 1...5 {
            guard let url = URL(string: "https://pokeapi.co/api/v2/region/\(id)/") else { continue }
            struct RESTRegionDTO: Decodable {
                struct NameRow: Decodable {
                    let name: String
                    struct LangRef: Decodable { let name: String }
                    let language: LangRef
                }
                let id: Int
                let name: String
                let names: [NameRow]
            }
            guard let dto: RESTRegionDTO = try? await get(url) else { continue }
            var namesMap: [String: String] = [:]
            for row in dto.names { namesMap[row.language.name] = row.name }
            regions.append(RegionInfo(id: dto.id, name: dto.name, names: namesMap))
        }
        return regions
    }

    private func fetchLocationsViaREST(regionID: Int) async throws -> [LocationInfo] {
        guard let url = URL(string: "https://pokeapi.co/api/v2/region/\(regionID)/") else { return [] }
        struct RESTRegionLocationsDTO: Decodable {
            struct LocRef: Decodable {
                let name: String
                let url: String
            }
            let id: Int
            let locations: [LocRef]
        }
        guard let dto: RESTRegionLocationsDTO = try? await get(url) else { return [] }

        var locations: [LocationInfo] = []
        for locRef in dto.locations {
            let cat = Self.inferLocationCategory(locRef.name)
            locations.append(LocationInfo(id: locRef.name, regionID: regionID, name: locRef.name, category: cat, names: [:]))
        }
        return locations
    }

    // MARK: 오프라인 무저작권 제네릭 폴백 (Option C)

    static var fallbackLocations: [Int: [LocationInfo]] {
        var map: [Int: [LocationInfo]] = [:]
        for r in 1...5 {
            map[r] = generateGenericLocationsFallback(regionID: r)
        }
        return map
    }

    static var fallbackRegions: [RegionInfo] {
        return generateGenericRegionsFallback()
    }

    static func generateGenericRegionsFallback() -> [RegionInfo] {
        return (1...5).map { id in
            RegionInfo(
                id: id,
                name: "region-\(id)",
                names: [
                    "ko": "\(id)지역",
                    "en": "Region \(id)",
                    "ja": "第\(id)地方",
                    "es": "Región \(id)"
                ]
            )
        }
    }

    static func generateGenericLocationsFallback(regionID: Int) -> [LocationInfo] {
        let sampleCategories: [LocationCategory] = [.town, .route, .forest, .cave, .water, .landmark]
        return (1...6).map { idx in
            let cat = sampleCategories[(idx - 1) % sampleCategories.count]
            let locID = "region-\(regionID)-location-\(idx)"
            return LocationInfo(
                id: locID,
                regionID: regionID,
                name: locID,
                category: cat,
                names: [
                    "ko": "\(regionID)지역 장소 \(idx)",
                    "en": "Location \(regionID)-\(idx)",
                    "ja": "第\(regionID)地方 場所\(idx)",
                    "es": "Lugar \(regionID)-\(idx)"
                ]
            )
        }
    }

    private func loadRegionsFromDiskCache() -> [RegionInfo]? {
        let url = regionsCacheURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([RegionInfo].self, from: data)
    }

    private func saveRegionsToDiskCache(_ regions: [RegionInfo]) {
        let url = regionsCacheURL()
        guard let data = try? JSONEncoder().encode(regions) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadLocationsFromDiskCache() -> [LocationInfo]? {
        let url = locationsCacheURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LocationInfo].self, from: data)
    }

    private func saveLocationsToDiskCache(_ locations: [LocationInfo]) {
        let url = locationsCacheURL()
        guard let data = try? JSONEncoder().encode(locations) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private struct GraphQLLocationsResponse: Decodable {
        struct DataBox: Decodable { let region: [RegionRow] }
        struct RegionRow: Decodable {
            let id: Int
            let name: String
            let locations: [LocRow]
        }
        struct LocRow: Decodable {
            let id: Int
            let name: String
            let locationnames: [NameRow]
            let locationareas: [AreaRow]
        }
        struct AreaRow: Decodable {
            let encounters: [EncRow]
        }
        struct EncRow: Decodable {
            let pokemon_id: Int
        }
        struct NameRow: Decodable {
            let name: String
            let language: LangRef
        }
        struct LangRef: Decodable { let name: String }
        let data: DataBox
    }

    private func fetchAllLocationsViaGraphQL() async throws -> [Int: [LocationInfo]] {
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let query = "{ region(where: {id: {_lte: 5}}, order_by: {id: asc}) { id name locations { id name locationnames { name language { name } } locationareas { encounters { pokemon_id } } } } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLLocationsResponse.self, from: data)

        var resultMap: [Int: [LocationInfo]] = [:]
        for r in decoded.data.region {
            let locs = r.locations.map { loc in
                var namesMap: [String: String] = [:]
                for row in loc.locationnames { namesMap[row.language.name] = row.name }
                let category = Self.inferLocationCategory(loc.name)
                let distinctSpecies = Set(loc.locationareas.flatMap { $0.encounters.map(\.pokemon_id) })
                let speciesSet = distinctSpecies.isEmpty ? nil : distinctSpecies
                return LocationInfo(id: loc.name, regionID: r.id, name: loc.name, category: category, names: namesMap, encounterSpeciesIDs: speciesSet)
            }
            resultMap[r.id] = locs
        }
        return resultMap
    }

    static func inferLocationCategory(_ name: String) -> LocationCategory {
        let n = name.lowercased()
        if n.contains("route") || n.contains("way") || n.contains("path") { return .route }
        if n.contains("forest") || n.contains("woods") || n.contains("jungle") { return .forest }
        if n.contains("cave") || n.contains("mt-") || n.contains("mount") || n.contains("tunnel") || n.contains("mine") || n.contains("rock") || n.contains("peak") { return .cave }
        if n.contains("lake") || n.contains("sea") || n.contains("bay") || n.contains("river") || n.contains("ocean") || n.contains("water") || n.contains("beach") || n.contains("island") { return .water }
        if n.contains("tower") || n.contains("ruins") || n.contains("shrine") || n.contains("castle") || n.contains("zone") || n.contains("park") || n.contains("resort") || n.contains("lab") { return .landmark }
        return .town
    }

    func fetchLocationEncounterSpeciesIDs(locationID: String) async throws -> Set<Int> {
        // PokéAPI /location/{id}/ -> areas -> /location-area/{id}/ -> pokemon_encounters
        guard let url = URL(string: "https://pokeapi.co/api/v2/location/\(locationID)/") else { return [] }
        struct LocDetail: Decodable {
            struct AreaRef: Decodable { let url: String }
            let areas: [AreaRef]
        }
        struct AreaDetail: Decodable {
            struct EncRow: Decodable {
                struct PokRef: Decodable { let url: String }
                let pokemon: PokRef
            }
            let pokemon_encounters: [EncRow]
        }
        guard let loc: LocDetail = try? await get(url) else { return [] }
        var speciesIDs = Set<Int>()
        for area in loc.areas.prefix(3) {
            guard let areaURL = URL(string: area.url),
                  let areaDetail: AreaDetail = try? await get(areaURL) else { continue }
            for enc in areaDetail.pokemon_encounters {
                let id = Self.id(from: enc.pokemon.url)
                if id > 0 { speciesIDs.insert(id) }
            }
        }
        return speciesIDs
    }

    private struct GraphQLRegionsResponse: Decodable {
        struct DataBox: Decodable { let region: [RegionRow] }
        struct RegionRow: Decodable {
            let id: Int
            let name: String
            let regionnames: [NameRow]
        }
        struct NameRow: Decodable {
            let name: String
            let language: LangRef
        }
        struct LangRef: Decodable { let name: String }
        let data: DataBox
    }

    private func fetchRegionsViaGraphQL() async throws -> [RegionInfo] {
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let query = "{ region(where: {id: {_lte: 5}}, order_by: {id: asc}) { id name regionnames { name language { name } } } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLRegionsResponse.self, from: data)
        return decoded.data.region.map { r in
            var namesMap: [String: String] = [:]
            for row in r.regionnames { namesMap[row.language.name] = row.name }
            return RegionInfo(id: r.id, name: r.name, names: namesMap)
        }
    }

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
        // 라인의 모든 종 이름(지원 언어만)
        var names: [Int: [String: String]] = [:]
        for id in allIDs(tree) {
            let sp = try await species(id)
            var byLang: [String: String] = [:]
            for n in sp.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
            names[id] = byLang
        }
        let line = EvoLine(baseID: baseSpeciesID, tree: tree, rarity: rarity, names: names)
        lineCache[baseSpeciesID] = line
        return line
    }

    // MARK: base 인덱스 (부화 후보)

    private var baseIndexCache: [BaseSpecies]?
    private var restBuildInFlight = false
    private var restBuildTried = false   // 세션당 1회 (GraphQL 다운 시 REST 인덱스 구축 트리거)
    private static let baseIndexFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("base-index.json")
    }()
    private struct BaseIndexSnapshot: Codable { let fetchedAt: Date; let entries: [BaseSpecies] }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable { let id: Int; let capture_rate: Int; let generation_id: Int? }
        let data: DataBox
    }

    /// 1~5세대 base(진화라인 시작점) 전체 — PokéAPI GraphQL 1쿼리.
    /// 우선순위: 메모리 캐시 → 디스크 캐시(30일 TTL) → GraphQL fetch(성공 시 디스크 갱신)
    /// → TTL 지난 디스크라도 있으면 사용(오프라인 폴백). 전부 실패 시 throw(알 유지, 다음 틱 재시도).
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if let c = baseIndexCache { return c }
        let disk = (try? Data(contentsOf: Self.baseIndexFile))
            .flatMap { try? JSONDecoder().decode(BaseIndexSnapshot.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            baseIndexCache = disk.entries
            return disk.entries
        }
        do {
            let entries = try await fetchBaseIndex()
            baseIndexCache = entries
            if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: entries)) {
                try? data.write(to: Self.baseIndexFile, options: .atomic)
            }
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {   // 오프라인 — 오래된 인덱스라도 사용
                baseIndexCache = disk.entries
                return disk.entries
            }
            // GraphQL 다운 + 캐시 없음 → REST 로 인덱스를 백그라운드 구축(세션 1회).
            // 이번 부화는 per-hatch REST 폴백(chooseBaseViaREST)이 즉시 처리하고,
            // 구축이 끝나면 디스크 캐시로 남아 이후 선택이 가중·수집반영·오프라인가능으로 복귀한다.
            if !restBuildTried {
                restBuildTried = true
                Task { await self.buildBaseIndexViaREST() }
            }
            AppLog.write("base index (GraphQL) failed, no cache — REST build triggered; per-hatch fallback handles now: \(error)")
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
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
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
        if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: bases)) {
            try? data.write(to: Self.baseIndexFile, options: .atomic)
        }
        AppLog.write("base index: REST build done — \(bases.count) bases persisted (offline-capable now)")
    }

    private func fetchBaseIndex() async throws -> [BaseSpecies] {
        // 공식 GraphQL — evolves_from IS NULL(=base) + id ≤ 649(Gen-V 애니메이션 스프라이트 상한)
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 메타몽(#132)은 위장 리빌 전용 → 일반 부화 풀에서 제외(_neq).
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(PokemonOdds.dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate generation_id } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map { BaseSpecies(id: $0.id, captureRate: $0.capture_rate, generationID: $0.generation_id) }
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
        guard id != PokemonOdds.dittoSpeciesID else { return nil }   // 메타몽은 위장 리빌 전용 — 일반 부화 제외
        let dto = try await species(id)
        guard dto.evolves_from_species == nil else { return nil }   // 진화 중간체는 부화 후보 아님
        return BaseSpecies(id: id, captureRate: dto.capture_rate)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func node(from link: ChainLink) -> EvoNode {
        EvoNode(speciesID: Self.id(from: link.species.url ?? ""),
                children: link.evolves_to.map(node(from:)))
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
}
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }
struct ChainLink: Decodable, Sendable {
    let species: NamedRef
    let evolves_to: [ChainLink]
}
