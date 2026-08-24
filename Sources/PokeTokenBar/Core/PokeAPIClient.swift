import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호
}

/// 버전별 도감 설명 한 줄 — 게임 버전 라벨 + 설명문.
/// 제공 버전 수는 언어마다 다름(ko/ja 는 6세대부터라 피카츄 12개, en 33개). 없는 건 빼고 영어로 대체 안 함.
struct DexFlavorText: Sendable, Equatable, Identifiable {
    let versionKey: String     // PokéAPI version.name — 안정 식별자(ForEach id)
    let versionLabel: String   // 표시용 현지화 이름. 못 얻으면 슬러그 정돈본
    let text: String           // 게임 화면 줄바꿈을 걷어낸 한 문단
    var id: String { versionKey }
}

/// 도감 설명 묶음 — **실제로 쓰인 언어**를 함께 돌려준다.
/// 요청 언어에 설명이 한 줄도 없으면 영어로 채우는데, 뷰가 그 사실을 알아야 안내를 띄운다.
struct DexEntries: Sendable, Equatable {
    let entries: [DexFlavorText]
    let language: AppLanguage
    /// 요청한 언어가 아닌 언어로 채워졌는가 — "영어로 표시 중" 안내 판정.
    func isFallback(from requested: AppLanguage) -> Bool { language != requested }
}

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~5세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?
    /// 종의 버전별 도감 설명(요청 언어, 발매순). 그 언어 설명이 없는 버전은 제외,
    /// 한 줄도 없으면 영어로 대체(무엇으로 채웠는지는 `DexEntries.language`).
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries
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
    // `ja-hrkt` 는 소문자 — PokéAPI 가 내보내는 실제 값이라 대문자면 아무것도 매칭되지 않는다.
    private let langCodes = ["ko", "en", "ja", "ja-hrkt", "es", "fr", "pt"]
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
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("base-index.json")
    }()
    private struct BaseIndexSnapshot: Codable { let fetchedAt: Date; let entries: [BaseSpecies] }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable { let id: Int; let capture_rate: Int }
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
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(PokemonOdds.dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map { BaseSpecies(id: $0.id, captureRate: $0.capture_rate) }
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

    // MARK: 도감 설명 (버전별 flavor text)

    private struct FlavorCacheKey: Hashable {
        let speciesID: Int
        let language: AppLanguage
    }
    private var flavorCache: [FlavorCacheKey: DexEntries] = [:]

    private struct GraphQLFlavorResponse: Decodable {
        struct Lang: Decodable { let name: String }
        struct VersionName: Decodable { let name: String; let language: Lang }
        struct Version: Decodable { let name: String; let versionnames: [VersionName] }
        struct Row: Decodable { let flavor_text: String; let language: Lang; let version: Version }
        struct DataBox: Decodable { let pokemonspeciesflavortext: [Row] }
        let data: DataBox
    }

    /// 요청 언어 결과를 그대로 쓸지, 영어로 대체할지 — 순수 판정(테스트용).
    ///
    /// **비어 있을 때만** 대체한다. 버전 단위 누락은 대체 대상이 아니다 — 한국어에 없는 초대작 설명을
    /// 영어로 끼워 넣으면 한 화면에 두 언어가 섞인다(그건 그냥 목록에서 뺀다). 언어 *전체*가 빈 경우는
    /// 층위가 다르다: PokéAPI 에 `pt` 처럼 그 언어 자체가 없으면 상세가 통째로 빈 화면이 되는데,
    /// 그런 언어는 종 이름도 이미 영어로 폴백돼 있어 영어로 채우는 쪽이 화면이 일관된다.
    /// 영어 자체가 비면 더 갈 곳이 없으므로 대체하지 않는다(무한 폴백 방지).
    static func needsEnglishFallback(entries: [DexFlavorText], language: AppLanguage) -> Bool {
        entries.isEmpty && language != .en
    }

    /// 종의 버전별 도감 설명. GraphQL 1쿼리 우선, 죽어 있으면 REST 폴백 — base 인덱스와 같은 이중화.
    /// 요청 언어에 한 줄도 없으면 영어로 한 번 더 조회한다(`needsEnglishFallback`).
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        let key = FlavorCacheKey(speciesID: speciesID, language: language)
        if let cached = flavorCache[key] { return cached }
        var (entries, degraded) = try await loadFlavorTexts(speciesID: speciesID, language: language)
        var used = language
        if Self.needsEnglishFallback(entries: entries, language: language) {
            let english = try await loadFlavorTexts(speciesID: speciesID, language: .en)
            (entries, used) = (english.entries, .en)
            degraded = degraded || english.degraded
        }
        let result = DexEntries(entries: entries, language: used)
        // 열화본(REST 폴백 — 버전 라벨이 슬러그)은 캐시하지 않는다. 캐시하면 GraphQL 이 살아나도
        // 세션 내내 영어 제목이 남는다. 재생성 비용은 0(`speciesCache` 재사용)이라 다음 열람이 복구한다.
        if !degraded { flavorCache[key] = result }
        return result
    }

    /// 한 언어치 조회 — GraphQL 우선, 실패 시 REST. `degraded` = 버전 라벨이 현지화 없이 슬러그로 내려감.
    private func loadFlavorTexts(speciesID: Int,
                                 language: AppLanguage) async throws -> (entries: [DexFlavorText], degraded: Bool) {
        do {
            return (try await fetchFlavorTextsViaGraphQL(speciesID: speciesID, language: language), false)
        } catch {
            AppLog.write("dex flavor text (GraphQL) failed for #\(speciesID) — REST fallback: \(error)")
            return (try await flavorTextsViaREST(speciesID: speciesID, language: language), true)
        }
    }

    private func fetchFlavorTextsViaGraphQL(speciesID: Int, language: AppLanguage) async throws -> [DexFlavorText] {
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 언어를 서버에서 걸러 받아 REST 전문(~50KB)의 5% 남짓. version_id 오름차순 = 발매순.
        // 버전 이름도 같은 쿼리에서 조인 — 왕복 추가 없음.
        let codes = language.apiCodes.map { "\"\($0)\"" }.joined(separator: ",")
        let query = """
        { pokemonspeciesflavortext(where: {pokemon_species_id: {_eq: \(speciesID)}, \
        language: {name: {_in: [\(codes)]}}}, order_by: {version_id: asc}) \
        { flavor_text language { name } \
        version { name versionnames(where: {language: {name: {_in: [\(codes)]}}}) { name language { name } } } } }
        """
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLFlavorResponse.self, from: data)
        let rows = decoded.data.pokemonspeciesflavortext.map {
            FlavorRow(versionKey: $0.version.name, languageCode: $0.language.name, text: $0.flavor_text,
                      labels: Dictionary($0.version.versionnames.map { ($0.language.name, $0.name) },
                                         uniquingKeysWith: { first, _ in first }))
        }
        return Self.collapse(rows, language: language)
    }

    private func flavorTextsViaREST(speciesID: Int, language: AppLanguage) async throws -> [DexFlavorText] {
        let dto = try await species(speciesID)
        let rows = (dto.flavor_text_entries ?? []).map {
            FlavorRow(versionKey: $0.version.name, languageCode: $0.language.name, text: $0.flavor_text, labels: [:])
        }
        return Self.collapse(rows, language: language)
    }

    /// 언어 후보가 여러 줄로 오는 원본(일본어는 `ja`·`ja-hrkt` 두 벌)을 버전당 한 줄로 접기.
    /// 버전 순서는 입력(발매순) 유지, 같은 버전 안에서는 `apiCodes` 앞 후보가 우선.
    static func collapse(_ rows: [FlavorRow], language: AppLanguage) -> [DexFlavorText] {
        // 순서는 배열, 중복 판정은 인덱스 맵. 키로 다시 조회하지 않는 건 nil 이 될 수 없는 Optional 이
        // 테스트로 덮을 수 없는 분기를 만들기 때문.
        var picked: [(key: String, rank: Int, row: FlavorRow)] = []
        var slotByKey: [String: Int] = [:]
        for row in rows {
            // 요청하지 않은 언어가 섞여 오는 경로(REST 전문)를 여기서 제외.
            guard let rank = language.apiCodes.firstIndex(of: row.languageCode) else { continue }
            if let slot = slotByKey[row.versionKey] {
                if rank < picked[slot].rank { picked[slot] = (row.versionKey, rank, row) }
            } else {
                slotByKey[row.versionKey] = picked.count
                picked.append((row.versionKey, rank, row))
            }
        }
        return picked.map { entry in
            let label = language.apiCodes.lazy.compactMap { entry.row.labels[$0] }.first
                ?? Self.versionLabelFallback(entry.key)
            return DexFlavorText(versionKey: entry.key, versionLabel: label,
                                 text: Self.sanitizeFlavorText(entry.row.text))
        }
    }

    /// 원문 제어문자 제거 — 줄바꿈·페이지구분(`\u{0C}`)은 화면 폭에 맞춘 것이라 공백으로 흡수,
    /// soft hyphen 은 삭제. 일본어의 전각 공백(U+3000)은 의도된 표기라 유지.
    static func sanitizeFlavorText(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\u{00AD}", with: "")
        for control in ["\n", "\r", "\u{000C}"] {
            s = s.replacingOccurrences(of: control, with: " ")
        }
        return s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// 현지화 버전 이름을 못 얻었을 때의 라벨 — 슬러그 정돈만("omega-ruby" → "Omega Ruby").
    /// 번역이 아니라 어느 언어에서든 영어 제목으로 보임.
    static func versionLabelFallback(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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
    /// 도감 설명(전 언어·전 버전). optional 인 이유 — 이 키가 빠진 응답 하나가 같은 DTO 를 쓰는
    /// 부화 경로까지 디코드 실패로 끌고 가면 안 되기 때문.
    let flavor_text_entries: [FlavorTextDTO]?
}
struct FlavorTextDTO: Decodable, Sendable {
    let flavor_text: String
    let language: NamedRef
    let version: NamedRef
}
/// 소스(GraphQL/REST)에 무관한 도감 설명 한 줄의 원본 — 접기(`collapse`) 입력.
struct FlavorRow: Sendable {
    let versionKey: String
    let languageCode: String
    let text: String
    let labels: [String: String]   // 언어코드 → 현지화된 버전 이름(REST 폴백은 빈 값)
}
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }
struct ChainLink: Decodable, Sendable {
    let species: NamedRef
    let evolves_to: [ChainLink]
}
