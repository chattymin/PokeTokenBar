import Foundation

/// Single source for PokéAPI sprite URLs (companion, dex, items) shared by app and widget.
public enum PokeSpriteURL {
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"

    public static func species(id: Int, shiny: Bool) -> URL? {
        URL(string: "\(base)/pokemon/\(shiny ? "shiny/" : "")\(id).png")
    }

    /// Gen-V animated GIF — only species 1…649 have one (same rule as the Mac's PokemonAssets).
    public static func hasAnimatedSprite(id: Int) -> Bool { (1...649).contains(id) }

    public static func animatedSpecies(id: Int, shiny: Bool) -> URL? {
        guard hasAnimatedSprite(id: id) else { return nil }
        return URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/\(shiny ? "shiny/" : "")\(id).gif")
    }

    public static func animatedSpeciesKey(id: Int, shiny: Bool) -> String { "\(id)_\(shiny)_anim.gif" }

    public static func item(name: String) -> URL? {
        URL(string: "\(base)/items/\(name).png")
    }

    /// Stable on-disk file name for a species sprite — the same key the widget has always used.
    public static func speciesKey(id: Int, shiny: Bool) -> String { "\(id)_\(shiny).png" }
    public static func itemKey(name: String) -> String { "item_\(name).png" }
}

#if canImport(UIKit)
import UIKit

/// Sprite cache shared by the iOS app and the widget extension: memory (NSCache) in front of the
/// app-group `WidgetSprites` directory. The widget cannot load over the network reliably, so the app
/// warms the disk layer whenever a payload arrives; both read through `cachedImage`.
public final class SpriteCache: @unchecked Sendable {
    public static let shared = SpriteCache()

    public static let appGroup = "group.io.github.chattymin.poketokenbar"

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appendingPathComponent("WidgetSprites", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Synchronous lookup: memory, then disk. Never touches the network.
    public func cachedImage(key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let file = directory?.appendingPathComponent(key),
              let data = try? Data(contentsOf: file),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Cached image or a network fetch that populates both layers. nil on any failure.
    public func image(for url: URL?, key: String) async -> UIImage? {
        if let hit = cachedImage(key: key) { return hit }
        guard let data = await data(for: url, key: key), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Raw bytes (e.g. an animated GIF) from disk, else fetched and written to disk. nil on failure.
    public func data(for url: URL?, key: String) async -> Data? {
        if let file = directory?.appendingPathComponent(key), let data = try? Data(contentsOf: file) {
            return data
        }
        guard let url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        if let file = directory?.appendingPathComponent(key) {
            try? data.write(to: file, options: .atomic)
        }
        return data
    }

    /// Warm the disk layer for what the widget will need (current + representative sprite).
    public func prefetchSpecies(_ pairs: [(id: Int, shiny: Bool)]) async {
        for pair in pairs {
            _ = await image(for: PokeSpriteURL.species(id: pair.id, shiny: pair.shiny),
                            key: PokeSpriteURL.speciesKey(id: pair.id, shiny: pair.shiny))
        }
    }
}
#endif
