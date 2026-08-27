import Foundation

/// Single source for PokéAPI sprite URLs (companion, dex, items) shared by app and widget.
public enum PokeSpriteURL {
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"

    public static func species(id: Int, shiny: Bool) -> URL? {
        URL(string: "\(base)/pokemon/\(shiny ? "shiny/" : "")\(id).png")
    }

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
        guard let url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        if let file = directory?.appendingPathComponent(key) {
            try? data.write(to: file, options: .atomic)
        }
        return image
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
