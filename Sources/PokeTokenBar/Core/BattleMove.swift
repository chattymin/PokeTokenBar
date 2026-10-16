import Foundation

enum BattleDamageClass: String, Codable, Sendable {
    case physical, special, status
}

struct BattleStatChange: Codable, Sendable, Equatable {
    let stat: String
    let change: Int
}

/// Battle-relevant move data, reduced from PokéAPI `/move/{name}` at the trust boundary.
/// Uses current-generation values, matching the types shown on the Pokémon detail page.
struct BattleMove: Codable, Sendable, Equatable {
    let name: String
    let type: String
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let priority: Int
    let damageClass: BattleDamageClass
    let target: String
    let statChanges: [BattleStatChange]
    let category: String?
    let statChance: Int
    let critRate: Int
    let drain: Int
    let healing: Int
    let minHits: Int?
    let maxHits: Int?
    let ailment: String?
    let ailmentChance: Int
    let flinchChance: Int

    /// Includes moves whose damage comes from a rule instead of a fixed power (see `damageRule`).
    var isDamaging: Bool { damageClass != .status && (power != nil || hasDamageRule) }

    func withType(_ type: String) -> BattleMove {
        BattleMove(name: name, type: type, power: power, accuracy: accuracy, pp: pp, priority: priority,
                   damageClass: damageClass, target: target, statChanges: statChanges, category: category,
                   statChance: statChance, critRate: critRate, drain: drain, healing: healing,
                   minHits: minHits, maxHits: maxHits, ailment: ailment, ailmentChance: ailmentChance,
                   flinchChance: flinchChance)
    }

    init(name: String, type: String, power: Int?, accuracy: Int?, pp: Int, priority: Int,
         damageClass: BattleDamageClass, target: String, statChanges: [BattleStatChange] = [],
         category: String? = nil, statChance: Int = 0, critRate: Int = 0, drain: Int = 0, healing: Int = 0,
         minHits: Int? = nil, maxHits: Int? = nil, ailment: String? = nil, ailmentChance: Int = 0,
         flinchChance: Int = 0) {
        self.name = name
        self.type = type
        self.power = power
        self.accuracy = accuracy
        self.pp = pp
        self.priority = priority
        self.damageClass = damageClass
        self.target = target
        self.statChanges = statChanges
        self.category = category
        self.statChance = statChance
        self.critRate = critRate
        self.drain = drain
        self.healing = healing
        self.minHits = minHits
        self.maxHits = maxHits
        self.ailment = ailment
        self.ailmentChance = ailmentChance
        self.flinchChance = flinchChance
    }

    /// Clamps every server-controlled number to its main-series range.
    init?(dto: BattleMoveDTO) {
        guard let damageClass = BattleDamageClass(rawValue: dto.damage_class?.name ?? "") else { return nil }
        let meta = dto.meta
        self.init(
            name: dto.name,
            type: dto.type.name,
            power: dto.power.map { min(250, max(1, $0)) },
            accuracy: dto.accuracy.map { min(100, max(1, $0)) },
            pp: min(64, max(1, dto.pp ?? 1)),
            priority: min(5, max(-7, dto.priority)),
            damageClass: damageClass,
            target: dto.target.name,
            statChanges: dto.stat_changes.map {
                BattleStatChange(stat: $0.stat.name, change: min(6, max(-6, $0.change)))
            }.sorted { $0.stat < $1.stat },
            category: meta?.category?.name,
            statChance: Self.percent(meta?.stat_chance),
            critRate: min(6, max(0, meta?.crit_rate ?? 0)),
            drain: min(100, max(-100, meta?.drain ?? 0)),
            healing: min(100, max(-100, meta?.healing ?? 0)),
            minHits: meta?.min_hits.map { min(10, max(1, $0)) },
            maxHits: meta?.max_hits.map { min(10, max(1, $0)) },
            ailment: meta?.ailment?.name,
            ailmentChance: Self.percent(meta?.ailment_chance),
            flinchChance: Self.percent(meta?.flinch_chance))
    }

    private static func percent(_ value: Int?) -> Int { min(100, max(0, value ?? 0)) }
}

struct BattleMoveDTO: Decodable, Sendable {
    struct StatChangeDTO: Decodable, Sendable { let change: Int; let stat: NamedRef }
    struct MetaDTO: Decodable, Sendable {
        let ailment: NamedRef?
        let category: NamedRef?
        let min_hits: Int?
        let max_hits: Int?
        let drain: Int?
        let healing: Int?
        let crit_rate: Int?
        let ailment_chance: Int?
        let flinch_chance: Int?
        let stat_chance: Int?
    }
    let name: String
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let priority: Int
    let type: NamedRef
    let damage_class: NamedRef?
    let target: NamedRef
    let stat_changes: [StatChangeDTO]
    let meta: MetaDTO?
}

protocol BattleMoveProviding: Sendable {
    func move(named name: String) async throws -> BattleMove
}

/// Memory → 30-day disk cache → REST, with stale disk fallback offline. Concurrent requests share one fetch.
actor BattleMoveClient: BattleMoveProviding {
    static let shared = BattleMoveClient()
    private struct Snapshot: Codable, Sendable {
        let fetchedAt: Date
        let move: BattleMove
    }
    private let directory: URL?
    private let fetch: @Sendable (URL) async throws -> Data
    private let now: @Sendable () -> Date
    private var cache: [String: Snapshot] = [:]
    private var inFlight: [String: Task<Snapshot, Error>] = [:]

    init(directory: URL? = AppStatePaths.directory().appendingPathComponent("battle-moves-v1", isDirectory: true),
         now: @escaping @Sendable () -> Date = Date.init,
         fetch: @escaping @Sendable (URL) async throws -> Data = PokemonNameClient.download) {
        self.directory = directory
        self.now = now
        self.fetch = fetch
    }

    func move(named name: String) async throws -> BattleMove {
        guard PokemonNameResource(kind: .move, name: name).isValid else { throw URLError(.badURL) }
        if let pending = inFlight[name] { return try await pending.value.move }
        let file = directory?.appendingPathComponent(name + ".json")
        let previous = cache[name] ?? file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        if let previous, now().timeIntervalSince(previous.fetchedAt) < 30 * 86400 {
            cache[name] = previous
            return previous.move
        }
        let url = URL(string: "https://pokeapi.co/api/v2/move/\(name)/")!
        let fetch = self.fetch
        let clock = self.now
        let task = Task<Snapshot, Error> {
            do {
                let dto = try JSONDecoder().decode(BattleMoveDTO.self, from: try await fetch(url))
                guard dto.name == name, let move = BattleMove(dto: dto) else {
                    throw URLError(.cannotParseResponse)
                }
                return Snapshot(fetchedAt: clock(), move: move)
            } catch {
                if let previous { return previous }
                throw error
            }
        }
        inFlight[name] = task
        defer { inFlight[name] = nil }
        let snapshot = try await task.value
        cache[name] = snapshot
        if let file, let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return snapshot.move
    }
}
