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

    var text: String {
        items.map { item in
            (language.resolveName(names[item.resource] ?? [:])
             ?? PokemonNameLocalization.identifier(item.resource.name)) + item.suffix
        }.joined(separator: " · ")
    }
    var body: some View { Text(text) }
}

/// Only mounted rows fetch names, following the LazyVStack's lazy row creation.
/// Language changes resolve the already-loaded multilingual response without restarting I/O.
@MainActor
struct PokemonNameLabel: View {
    let items: [PokemonNameItem]
    let language: AppLanguage
    var provider: any PokemonNameProviding = PokemonNameClient.shared
    @State private var names: [PokemonNameResource: [String: String]] = [:]

    init(_ kind: PokemonNameResource.Kind, _ name: String, language: AppLanguage, suffix: String = "") {
        items = [PokemonNameItem(resource: .init(kind: kind, name: name), suffix: suffix)]
        self.language = language
    }

    init(items: [PokemonNameItem], language: AppLanguage) {
        self.items = items
        self.language = language
    }

    var body: some View {
        PokemonNameText(items: items, language: language, names: names)
            .task(id: items.map(\.resource)) {
                await withTaskGroup(of: (PokemonNameResource, [String: String]?).self) { group in
                    for resource in Set(items.map(\.resource)) {
                        group.addTask { (resource, try? await provider.names(for: resource)) }
                    }
                    for await (resource, translations) in group {
                        guard !Task.isCancelled else { return }
                        if let translations { names[resource] = translations }
                    }
                }
            }
    }
}
