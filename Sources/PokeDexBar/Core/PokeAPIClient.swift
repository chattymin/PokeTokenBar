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
            .appendingPathComponent("PokeDexBar")
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
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate is_legendary is_mythical } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map {
            BaseSpecies(id: $0.id, captureRate: $0.capture_rate,
                       isLegendary: $0.is_legendary, isMythical: $0.is_mythical)
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
                           isLegendary: dto.is_legendary, isMythical: dto.is_mythical)
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
