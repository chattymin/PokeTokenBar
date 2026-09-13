import SwiftUI

struct PokemonNameItem: Hashable, Sendable {
    let resource: PokemonNameResource
    var suffix = ""
}

/// A plain Text preserves wrapping of joined ability names and all parent typography.
@MainActor
struct PokemonNameText: View {
    let items: [PokemonNameItem]
    let language: AppLanguage
    let names: [PokemonNameResource: [String: String]]
    var failed: Set<PokemonNameResource> = []

    var text: String {
        items.map { item in
            guard let translations = names[item.resource] else {
                return (failed.contains(item.resource)
                        ? PokemonNameLocalization.identifier(item.resource.name) : "…") + item.suffix
            }
            return (language.resolveName(translations)
                    ?? PokemonNameLocalization.identifier(item.resource.name)) + item.suffix
        }.joined(separator: " · ")
    }
    var body: some View { Text(text) }
}

/// Synchronous presentation snapshot: reopening a detail starts with the last translated names.
/// The API client still owns disk caching, request deduplication, and freshness checks.
@MainActor @Observable
final class PokemonNameDisplayStore {
    static let shared = PokemonNameDisplayStore()
    private(set) var names: [PokemonNameResource: [String: String]] = [:]

    func load(_ resource: PokemonNameResource, provider: any PokemonNameProviding) async -> Bool {
        do {
            let translations = try await provider.names(for: resource)
            guard !Task.isCancelled else { return false }
            names[resource] = translations
            return true
        } catch {
            return false
        }
    }
}

/// Only mounted rows fetch names, following the LazyVStack's lazy row creation.
/// Language changes resolve the already-loaded multilingual response without restarting I/O.
@MainActor
struct PokemonNameLabel: View {
    let items: [PokemonNameItem]
    let language: AppLanguage
    var provider: any PokemonNameProviding = PokemonNameClient.shared
    var displayStore = PokemonNameDisplayStore.shared
    @State private var failed: Set<PokemonNameResource> = []

    init(_ kind: PokemonNameResource.Kind, _ name: String, language: AppLanguage, suffix: String = "") {
        items = [PokemonNameItem(resource: .init(kind: kind, name: name), suffix: suffix)]
        self.language = language
    }

    init(items: [PokemonNameItem], language: AppLanguage) {
        self.items = items
        self.language = language
    }

    var body: some View {
        PokemonNameText(items: items, language: language, names: displayStore.names, failed: failed)
            .task(id: items.map(\.resource)) {
                failed.subtract(items.map(\.resource))
                await withTaskGroup(of: (PokemonNameResource, Bool).self) { group in
                    for resource in Set(items.map(\.resource)) {
                        group.addTask { (resource, await displayStore.load(resource, provider: provider)) }
                    }
                    for await (resource, loaded) in group {
                        guard !Task.isCancelled else { return }
                        if !loaded { failed.insert(resource) }
                    }
                }
            }
    }
}
