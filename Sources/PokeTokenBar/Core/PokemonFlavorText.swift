import Foundation

/// One Pokédex entry: the game version it appeared in and its text.
struct DexFlavorText: Sendable, Equatable, Identifiable {
    /// PokéAPI `version.name` — stable across languages and refetches.
    let versionKey: String
    /// PokéAPI `version.id`, which follows release order.
    let versionID: Int
    /// Localized version name, or the formatted slug when none is available.
    let versionLabel: String
    /// One paragraph, without the line breaks that fit the games' text boxes.
    let text: String
    var id: String { versionKey }
}

/// The entries for one species and the language that actually filled them.
struct DexEntries: Sendable, Equatable {
    /// Oldest version first, newest last.
    let entries: [DexFlavorText]
    /// English when the requested language has no entries at all (PokéAPI has no `pt`).
    let language: AppLanguage
    /// Served by the REST fallback, whose version labels are slugs. Shown, but never treated as final.
    var isDegraded = false
}

/// Flavor text is the first per-language PokéAPI request: everything else caches every language at
/// once. A response therefore belongs to a species *and* a language and must never land under another.
struct FlavorTextRequest: Hashable, Sendable {
    let speciesID: Int
    let language: AppLanguage
}

/// Separate from `PokeProviding` so existing evolution-only test doubles stay small.
protocol PokemonFlavorTextProviding: Sendable {
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries
}

/// A source-independent entry (GraphQL row or REST entry) before collapsing.
struct FlavorRow: Sendable {
    let versionKey: String
    let versionID: Int
    let languageCode: String
    let text: String
    /// Language code → localized version name. Empty on the REST fallback.
    let labels: [String: String]
}

/// Version-specific Pokédex entries. One GraphQL query returns the entries and the localized version
/// names. Any GraphQL failure — transport, HTTP status, an `errors` payload without `data`, or a body
/// that does not decode — falls back to REST, whose slug-labelled result is never cached.
actor PokemonFlavorTextClient: PokemonFlavorTextProviding {
    static let shared = PokemonFlavorTextClient()

    private static let graphQLURL = URL(string: "https://graphql.pokeapi.co/v1beta2")!
    private let fetch: @Sendable (URLRequest) async throws -> (Data, Int)
    private var cache: [FlavorTextRequest: DexEntries] = [:]

    init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = PokemonFlavorTextClient.download) {
        self.fetch = fetch
    }

    static func download(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        let request = FlavorTextRequest(speciesID: speciesID, language: language)
        if let cached = cache[request] { return cached }
        var result = try await load(speciesID: speciesID, language: language)
        if Self.needsEnglishFallback(entries: result.entries, language: language) {
            // An empty REST answer is as conclusive as an empty GraphQL one (REST carries every
            // language), so only the English labels decide whether the result is degraded.
            result = try await load(speciesID: speciesID, language: .en)
        }
        if !result.isDegraded { cache[request] = result }
        return result
    }

    /// Falls back only when the requested language has nothing at all. A version missing in that
    /// language is dropped instead — filling it from English would mix two languages on one card.
    /// English has nowhere further to go.
    static func needsEnglishFallback(entries: [DexFlavorText], language: AppLanguage) -> Bool {
        entries.isEmpty && language != .en
    }

    private func load(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        do {
            var request = URLRequest(url: Self.graphQLURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["query": Self.query(speciesID: speciesID, language: language)])
            let (data, status) = try await fetch(request)
            return DexEntries(entries: try Self.parseGraphQL(data, status: status, language: language),
                              language: language)
        } catch {
            AppLog.write("dex flavor text (GraphQL) failed for #\(speciesID) — REST fallback: \(error)")
            var request = URLRequest(url: URL(string: "https://pokeapi.co/api/v2/pokemon-species/\(speciesID)")!)
            request.timeoutInterval = 15
            let (data, status) = try await fetch(request)
            return DexEntries(entries: try Self.parseREST(data, status: status, language: language),
                              language: language, isDegraded: true)
        }
    }

    /// Filtered to the requested language server-side, with version names joined in the same query.
    static func query(speciesID: Int, language: AppLanguage) -> String {
        let codes = language.apiCodes.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        { pokemonspeciesflavortext(where: {pokemon_species_id: {_eq: \(speciesID)}, \
        language: {name: {_in: [\(codes)]}}}, order_by: {version_id: asc}) \
        { flavor_text language { name } \
        version { id name versionnames(where: {language: {name: {_in: [\(codes)]}}}) { name language { name } } } } }
        """
    }

    private struct GraphQLResponse: Decodable {
        struct Language: Decodable { let name: String }
        struct VersionName: Decodable {
            let name: String
            let language: Language
        }
        struct Version: Decodable {
            let id: Int
            let name: String
            let versionnames: [VersionName]
        }
        struct Row: Decodable {
            let flavor_text: String
            let language: Language
            let version: Version
        }
        struct DataBox: Decodable { let pokemonspeciesflavortext: [Row] }
        let data: DataBox
    }

    static func parseGraphQL(_ data: Data, status: Int, language: AppLanguage) throws -> [DexFlavorText] {
        guard status == 200 else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder().decode(GraphQLResponse.self, from: data).data.pokemonspeciesflavortext.map {
            FlavorRow(versionKey: $0.version.name, versionID: $0.version.id, languageCode: $0.language.name,
                      text: $0.flavor_text,
                      labels: $0.version.versionnames.reduce(into: [:]) { $0[$1.language.name] = $1.name })
        }
        return collapse(rows, language: language)
    }

    private struct SpeciesFlavorDTO: Decodable {
        /// Unlike `NamedRef`, the URL is required: it is the only source of the version's release order.
        struct Ref: Decodable {
            let name: String
            let url: String
        }
        struct Entry: Decodable {
            let flavor_text: String
            let language: Ref
            let version: Ref
        }
        let flavor_text_entries: [Entry]
    }

    /// Decoded on its own rather than through `SpeciesDTO`, so the species cache that every hatch
    /// and name backfill fills does not also hold every language's entries.
    static func parseREST(_ data: Data, status: Int, language: AppLanguage) throws -> [DexFlavorText] {
        guard status == 200 else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder().decode(SpeciesFlavorDTO.self, from: data).flavor_text_entries.map {
            FlavorRow(versionKey: $0.version.name, versionID: PokeAPIClient.id(from: $0.version.url),
                      languageCode: $0.language.name, text: $0.flavor_text, labels: [:])
        }
        return collapse(rows, language: language)
    }

    /// One entry per version, oldest first. Japanese arrives twice (`ja-hrkt`, `ja`); within a version
    /// the earlier `apiCodes` candidate wins whatever order the rows came in.
    static func collapse(_ rows: [FlavorRow], language: AppLanguage) -> [DexFlavorText] {
        let codes = language.apiCodes.map(PokemonNameLocalization.languageCode)
        var best: [String: (rank: Int, row: FlavorRow)] = [:]
        for row in rows {
            // The REST body carries every language; drop the ones that were not requested.
            guard let rank = codes.firstIndex(of: PokemonNameLocalization.languageCode(row.languageCode)) else { continue }
            if let current = best[row.versionKey], current.rank <= rank { continue }
            best[row.versionKey] = (rank, row)
        }
        return best.values.map(\.row).sorted { $0.versionID < $1.versionID }.map { row in
            let labels = row.labels.reduce(into: [String: String]()) {
                $0[PokemonNameLocalization.languageCode($1.key)] = $1.value
            }
            return DexFlavorText(versionKey: row.versionKey, versionID: row.versionID,
                                 versionLabel: codes.lazy.compactMap { labels[$0] }.first
                                     ?? PokemonNameLocalization.identifier(row.versionKey),
                                 text: sanitize(row.text))
        }
    }

    /// Line and page breaks only fit the games' text boxes, so they become spaces; soft hyphens go.
    /// Japanese ideographic spaces (U+3000) are intended spacing and stay.
    static func sanitize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\u{00AD}", with: "")
        for control in ["\n", "\r", "\u{000C}"] {
            text = text.replacingOccurrences(of: control, with: " ")
        }
        return text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
