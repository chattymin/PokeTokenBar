import Foundation

/// Shared by species names and battle metadata. Keep every language returned by the API;
/// adding an app language must not require changing a second allowlist or redownloading names.
enum PokemonNameLocalization {
    static func languageCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
    }

    static func collect(_ entries: [NameDTO]) -> [String: String] {
        var names: [String: String] = [:]
        for entry in entries {
            let code = languageCode(entry.language.name)
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty && !name.isEmpty { names[code] = name }
        }
        return names
    }

    static func resolve(_ names: [String: String], preferredCodes: [String]) -> String? {
        // Old saves may contain mixed-case PokéAPI language codes (for example ja-Hrkt).
        var normalized: [String: String] = [:]
        for key in names.keys.sorted() {
            let value = names[key]!.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { normalized[languageCode(key)] = value }
        }
        for code in preferredCodes + ["en"] {
            if let name = normalized[languageCode(code)] { return name }
        }
        return nil
    }

    /// Last resort while offline or before the first translation response arrives.
    static func identifier(_ raw: String) -> String {
        raw.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

struct PokemonNameResource: Hashable, Sendable {
    enum Kind: String, Sendable { case type, ability, move }
    let kind: Kind
    let name: String

    var cacheKey: String { kind.rawValue + "-" + name }
    var isValid: Bool {
        !name.isEmpty && name.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
}

protocol PokemonNameProviding: Sendable {
    func names(for resource: PokemonNameResource) async throws -> [String: String]
}

/// On-demand metadata names, independent of battle-data/profile loading.
/// Shared resources (e.g. the same move on two species) share their request and 30-day cache.
actor PokemonNameClient: PokemonNameProviding {
    static let shared = PokemonNameClient()
    private struct Snapshot: Codable, Sendable {
        let fetchedAt: Date
        let names: [String: String]
    }
    private struct NamesDTO: Decodable { let names: [NameDTO] }
    private let directory: URL?
    private let fetch: @Sendable (URL) async throws -> Data
    private let now: @Sendable () -> Date
    private var cache: [PokemonNameResource: Snapshot] = [:]
    private var inFlight: [PokemonNameResource: Task<Snapshot, Error>] = [:]

    init(directory: URL? = AppStatePaths.directory().appendingPathComponent("pokemon-names-v1", isDirectory: true),
         now: @escaping @Sendable () -> Date = Date.init,
         fetch: @escaping @Sendable (URL) async throws -> Data = PokemonNameClient.download) {
        self.directory = directory
        self.now = now
        self.fetch = fetch
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func names(for resource: PokemonNameResource) async throws -> [String: String] {
        guard resource.isValid else { throw URLError(.badURL) }
        if let pending = inFlight[resource] { return try await pending.value.names }
        let file = directory?.appendingPathComponent(resource.cacheKey + ".json")
        let previous = cache[resource] ?? file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        if let previous, now().timeIntervalSince(previous.fetchedAt) < 30 * 86400 {
            cache[resource] = previous
            return previous.names
        }
        let url = URL(string: "https://pokeapi.co/api/v2/\(resource.kind.rawValue)/\(resource.name)/")!
        let fetch = self.fetch
        let clock = self.now
        let task = Task<Snapshot, Error> {
            do {
                let response = try await fetch(url)
                let names = PokemonNameLocalization.collect(try JSONDecoder().decode(NamesDTO.self, from: response).names)
                return Snapshot(fetchedAt: clock(), names: names)
            } catch {
                if let previous { return previous }
                throw error
            }
        }
        inFlight[resource] = task
        defer { inFlight[resource] = nil }
        let snapshot = try await task.value
        cache[resource] = snapshot
        if let file, let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return snapshot.names
    }
}
