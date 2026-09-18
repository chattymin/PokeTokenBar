import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The card is always light, so an exported image looks the same in light and dark mode.
enum TrainerCardStyle {
    static let size = CGSize(width: PopoverMetrics.contentWidth, height: 196)
    static let exportScale: CGFloat = 4
    static let ink = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let muted = Color(red: 0.42, green: 0.44, blue: 0.49)
    static let paper = Color(white: 0.985)

    /// Common type colors, keyed by PokéAPI type name.
    private static let typeColors: [String: UInt32] = [
        "normal": 0xA8A77A, "fire": 0xEE8130, "water": 0x6390F0, "electric": 0xF7D02C,
        "grass": 0x7AC74C, "ice": 0x96D9D6, "fighting": 0xC22E28, "poison": 0xA33EA1,
        "ground": 0xE2BF65, "flying": 0xA98FF3, "psychic": 0xF95587, "bug": 0xA6B91A,
        "rock": 0xB6A136, "ghost": 0x735797, "dragon": 0x6F35FC, "dark": 0x705746,
        "steel": 0xB7B7CE, "fairy": 0xD685AD,
    ]

    static func accent(forType type: String?) -> NSColor {
        guard let type, let rgb = typeColors[type] else { return .systemOrange }
        return NSColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Light type colors such as Electric or Ice cannot be read as text on the white card.
    static func title(on accent: NSColor) -> Color {
        Color(nsColor: accent.blended(withFraction: 0.35, of: .black) ?? accent)
    }
}

struct TrainerCardMember: Identifiable {
    let entry: DexEntry
    let name: String
    var id: String { entry.id }
}

/// Everything the card prints, read once from the store so the live card and the export match.
@MainActor
struct TrainerCardContent {
    let language: AppLanguage
    let trainerID: Int?
    let trainerName: String
    let showsTokens: Bool
    let stats: CompanionStore.TrainerCardStats
    let companionSpeciesID: Int?
    let companionShiny: Bool
    let companionName: String
    let companionDetail: String
    let types: [String]
    let team: [TrainerCardMember]
    let teamPicked: Bool

    init(store: CompanionStore, showsTokens: Bool) {
        language = store.language
        trainerID = store.trainerID
        trainerName = store.trainerName
        self.showsTokens = showsTokens
        stats = store.trainerCardStats
        // The pinned Pokémon, or the raised one when nothing is pinned — the card shows the same
        // face as the menu bar, so a fresh egg does not take it over.
        let subject = store.cardSubject
        companionSpeciesID = subject.speciesID
        companionShiny = subject.isShiny
        companionName = subject.name
        companionDetail = subject.detail
        types = subject.speciesID.flatMap { store.pokemonDetailsByID[$0]?.types } ?? []
        team = store.trainerTeam.map { entry in
            TrainerCardMember(entry: entry,
                              name: store.dexStoredChainNames(entry)?[entry.finalID] ?? "#\(entry.finalID)")
        }
        teamPicked = store.isTeamPicked
    }

    var l: L { L(language) }

    func firstCatchText() -> String? {
        stats.firstCatch.map { date in
            let formatter = DateFormatter()
            formatter.locale = language.displayLocale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    var idText: String {
        l.trainerIDLabel(trainerID.map { String(format: "%05d", $0) } ?? "-----")
    }
}

@MainActor
private struct TrainerCardFrame<Content: View>: View {
    let accent: NSColor
    var holo = false
    @ViewBuilder let content: Content

    var body: some View {
        let base = Color(nsColor: accent)
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [base, base.opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if holo {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: ([.pink, .yellow, .mint, .cyan, .purple, .pink] as [Color])
                                            .map { $0.opacity(0.6) },
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            RoundedRectangle(cornerRadius: 11).fill(TrainerCardStyle.paper).padding(6)
            if holo {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(stops: [.init(color: .clear, location: 0.3),
                                                 .init(color: .cyan.opacity(0.12), location: 0.45),
                                                 .init(color: .pink.opacity(0.12), location: 0.55),
                                                 .init(color: .clear, location: 0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(6)
            }
            content.padding(18)
        }
        .frame(width: TrainerCardStyle.size.width, height: TrainerCardStyle.size.height)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
private struct TrainerCardHeader<Badge: View>: View {
    let title: String
    let idText: String
    let color: Color
    @ViewBuilder var badge: Badge

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            badge
            Spacer(minLength: 4)
            Text(idText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(TrainerCardStyle.muted)
                .fixedSize()
        }
    }
}

@MainActor
struct TrainerCardFront: View {
    let content: TrainerCardContent

    var body: some View {
        let accent = TrainerCardStyle.accent(forType: content.types.first)
        TrainerCardFrame(accent: accent, holo: content.companionShiny) {
            VStack(spacing: 6) {
                TrainerCardHeader(title: content.l.trainerCardTitle, idText: content.idText,
                                  color: TrainerCardStyle.title(on: accent)) { EmptyView() }
                HStack(alignment: .top, spacing: 10) {
                    let rows = Self.rows(content)
                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            row(rows[index].label, rows[index].value, last: index == rows.count - 1)
                        }
                    }
                    companion(accent: accent).frame(width: 104)
                }
                Spacer(minLength: 0)
                rarityBar
            }
        }
    }

    static func rows(_ content: TrainerCardContent) -> [(label: String, value: String)] {
        let l = content.l
        var rows: [(label: String, value: String)] = []
        if !content.trainerName.isEmpty { rows.append((l.trainerNameLabel, content.trainerName)) }
        if content.showsTokens {
            rows.append((l.trainerTokensLabel, TokenFormatter.compact(content.stats.lifetimeTokens)))
        }
        rows.append((l.dexTitle, "\(content.stats.speciesCount) / \(content.stats.speciesTotal)"))
        rows.append((l.dexShinyLabel, "\(content.stats.shinyCount)"))
        rows.append((l.trainerGraduatedLabel, "\(content.stats.graduatedCount)"))
        rows.append((l.trainerDuplicatesLabel, "\(content.stats.duplicateCount)"))
        if let firstCatch = content.firstCatchText() { rows.append((l.trainerFirstCatchLabel, firstCatch)) }
        return rows
    }

    private func row(_ label: String, _ value: String, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(TrainerCardStyle.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(value).font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(TrainerCardStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 2)
            if !last { Rectangle().fill(TrainerCardStyle.muted.opacity(0.18)).frame(height: 1) }
        }
    }

    private func companion(accent: NSColor) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(Color(nsColor: accent).opacity(0.14))
                Circle().strokeBorder(Color(nsColor: accent).opacity(0.5), lineWidth: 1.5)
                SpriteView(speciesID: content.companionSpeciesID, size: 54, animated: true,
                           shiny: content.companionShiny)
            }
            .frame(width: 70, height: 70)
            HStack(spacing: 2) {
                Text(content.companionName)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(TrainerCardStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if content.companionShiny { Text("✨").font(.system(size: 8)) }
            }
            if !content.companionDetail.isEmpty {
                Text(content.companionDetail)
                    .font(.system(size: 8)).foregroundStyle(TrainerCardStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 3) {
                ForEach(content.types.prefix(2), id: \.self) { type in
                    PokemonNameLabel(.type, type, language: content.language)
                        .textCase(.uppercase)
                        .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(nsColor: TrainerCardStyle.accent(forType: type))))
                }
            }
        }
    }

    private var rarityBar: some View {
        // Grouping the log never yields a zero, so a present key always means a visible slice.
        let counts = rarityDisplayOrder.compactMap { rarity in
            content.stats.rarityCounts[rarity].map { (rarity, $0) }
        }
        let total = max(1, counts.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(counts, id: \.0) { rarity, count in
                        Capsule().fill(rarityColor(rarity))
                            .frame(width: max(4, (geo.size.width - CGFloat(counts.count * 2))
                                                  * CGFloat(count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 5)
            HStack(spacing: 4) {
                Text(counts.map { "\($0.1) \(content.l.rarityLabel($0.0))" }.joined(separator: " · "))
                    .font(.system(size: 8)).foregroundStyle(TrainerCardStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("PokeTokenBar")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(TrainerCardStyle.muted.opacity(0.8))
                    .fixedSize()
            }
        }
    }
}

/// Team edits the card back offers. nil on an exported card, which has no controls.
struct TrainerTeamActions {
    /// Opens the picker: a slot index replaces that member, nil fills the next free slot.
    let pick: (Int?) -> Void
    let remove: (DexEntry) -> Void
    let move: (DexEntry, Int) -> Void
}

@MainActor
struct TrainerCardBack: View {
    let content: TrainerCardContent
    var actions: TrainerTeamActions?

    var body: some View {
        let accent = TrainerCardStyle.accent(forType: content.types.first)
        let title = TrainerCardStyle.title(on: accent)
        // Both sides carry the holo frame, so a shiny card stays a shiny card when it is flipped.
        TrainerCardFrame(accent: accent, holo: content.companionShiny) {
            VStack(spacing: 6) {
                TrainerCardHeader(title: content.l.trainerTeamTitle, idText: content.idText, color: title) {
                    Text(content.teamPicked ? content.l.trainerTeamPicked : content.l.trainerTeamAuto)
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(content.teamPicked ? title : TrainerCardStyle.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .overlay(Capsule().strokeBorder(content.teamPicked ? title : TrainerCardStyle.muted,
                                                        lineWidth: 0.8))
                        .fixedSize()
                }
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { column in
                                let slot = row * 3 + column
                                slotView(slot, title: title)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Int, title: Color) -> some View {
        let member = content.team.indices.contains(slot) ? content.team[slot] : nil
        let shape = RoundedRectangle(cornerRadius: 9)
        ZStack {
            shape.fill(.white)
            if let member {
                shape.strokeBorder(rarityColor(member.entry.rarity), lineWidth: 1.5)
                VStack(spacing: 0) {
                    SpriteView(speciesID: member.entry.finalID, size: 36, animated: true,
                               shiny: member.entry.isShiny)
                    Text(member.name)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(TrainerCardStyle.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(content.l.rarityLabel(member.entry.rarity))
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(rarityColor(member.entry.rarity))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                VStack {
                    HStack {
                        if slot == 0 {
                            Text(content.l.trainerTeamLead.uppercased())
                                .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(title))
                                .fixedSize()
                        }
                        Spacer(minLength: 0)
                        if member.entry.isShiny { Text("✨").font(.system(size: 8)) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
            } else {
                shape.strokeBorder(TrainerCardStyle.muted.opacity(0.35),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                VStack(spacing: 2) {
                    PokeBallIcon(size: 18).grayscale(1).opacity(0.35)
                    if actions != nil {
                        Text(content.l.trainerTeamAdd)
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(TrainerCardStyle.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(shape)
        .onTapGesture { actions?.pick(member == nil ? nil : slot) }
        // A tap gesture alone is invisible to VoiceOver: name the slot and give it the activation.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(member.map { "\($0.name) · \(content.l.rarityLabel($0.entry.rarity))" }
                            ?? content.l.trainerTeamAdd)
        .accessibilityAddTraits(actions == nil ? [] : .isButton)
        .accessibilityAction { actions?.pick(member == nil ? nil : slot) }
        .contextMenu {
            if let actions, let member {
                Button(content.l.trainerTeamReplace) { actions.pick(slot) }
                Button(content.l.trainerTeamMoveLeft) { actions.move(member.entry, -1) }
                    .disabled(slot == 0)
                Button(content.l.trainerTeamMoveRight) { actions.move(member.entry, 1) }
                    .disabled(slot >= content.team.count - 1)
                Divider()
                Button(content.l.trainerTeamRemove) { actions.remove(member.entry) }
            }
        }
        .help(member.map { "\($0.name) · \(content.l.rarityLabel($0.entry.rarity))" } ?? content.l.trainerTeamAdd)
    }
}

@MainActor
private struct PokeBallIcon: View {
    static let spriteName = "poke-ball"
    let size: CGFloat
    @State private var image = SpriteLoader.cachedItemImage(name: spriteName)

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none)
            } else {
                Circle().strokeBorder(TrainerCardStyle.muted, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .task {
            guard image == nil else { return }
            image = await SpriteLoader.itemImage(name: Self.spriteName)
        }
    }
}

/// Collection tab screen: the card, its team picker and the export buttons.
@MainActor
struct TrainerCardScreen: View {
    let store: CompanionStore
    let onBack: () -> Void
    @AppStorage(TrainerCardExport.showsTokensKey) private var showsTokens = true
    @State private var nameDraft: String
    /// Non-nil while picking. The inner value is the slot to replace, nil to fill the next one.
    @State private var picking: Int??
    @State private var copied = false

    init(store: CompanionStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
        _nameDraft = State(initialValue: store.trainerName)
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    if picking != nil { picking = nil } else { onBack() }
                } label: {
                    Label(l.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(picking == nil ? l.trainerCardTitle : l.trainerTeamPickTitle)
                    .font(.callout.weight(.semibold))
            }
            if let slot = picking {
                TrainerTeamPicker(store: store) { entry in
                    store.addToTeam(entry, slot: slot)
                    picking = nil
                }
            } else {
                card
                controls
                Spacer(minLength: 0)
            }
        }
        .task {
            store.ensureTrainerID()
            if let id = store.cardSubject.speciesID { await store.loadPokemonDetails(speciesID: id) }
            await store.backfillMissingDexNames()
        }
    }

    private var card: some View {
        let content = TrainerCardContent(store: store, showsTokens: showsTokens)
        return VStack(spacing: 8) {
            TrainerCardFront(content: content)
            TrainerCardBack(content: content, actions: TrainerTeamActions(
                pick: { slot in picking = .some(slot) },
                remove: { store.removeFromTeam($0) },
                move: { store.moveInTeam($0, by: $1) }))
        }
    }

    private var controls: some View {
        let l = store.l
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField(l.trainerNamePlaceholder, text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onChange(of: nameDraft) {
                        if nameDraft.count > TrainerCard.nameLimit {
                            nameDraft = String(nameDraft.prefix(TrainerCard.nameLimit))
                        }
                        store.setTrainerName(nameDraft)
                    }
                Toggle(l.trainerCardShowTokens, isOn: $showsTokens)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                Button(copied ? l.trainerCardCopied : l.trainerCardCopy) {
                    Task {
                        guard await TrainerCardExport.copy(store: store, showsTokens: showsTokens) else { return }
                        copied = true
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                Button(l.trainerCardSave) {
                    Task { await TrainerCardExport.save(store: store, showsTokens: showsTokens) }
                }
                Spacer(minLength: 4)
                // A toggle, not a reset button: the picked line-up is kept and comes back.
                Toggle(l.trainerTeamUseAuto, isOn: Binding(get: { !store.isTeamPicked },
                                                           set: { store.setAutomaticTeam($0) }))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .help(l.trainerTeamAutoHelp)
            }
            .controlSize(.small)
        }
    }
}

@MainActor
private struct TrainerTeamPicker: View {
    let store: CompanionStore
    let onPick: (DexEntry) -> Void

    var body: some View {
        let inTeam = Set(store.trainerTeamKeys)
        let candidates = store.teamCandidates.filter { store.teamKey(for: $0).map { !inTeam.contains($0) } ?? false }
        if candidates.isEmpty {
            Text(store.l.trainerTeamNoCandidates)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(candidates) { entry in
                        Button { onPick(entry) } label: { row(entry) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ entry: DexEntry) -> some View {
        HStack(spacing: 8) {
            SpriteView(speciesID: entry.finalID, size: 36, shiny: entry.isShiny)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.dexStoredChainNames(entry)?[entry.finalID] ?? "#\(entry.finalID)")
                        .font(.callout.weight(.semibold))
                    if entry.isShiny { Text("✨").font(.system(size: 10)) }
                }
                HStack(spacing: 4) {
                    Text(store.l.rarityLabel(entry.rarity).uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(rarityColor(entry.rarity)).foregroundStyle(.white)
                        .clipShape(Capsule())
                    if store.isActiveDexEntry(entry) {
                        Text(store.l.dexRaising.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer(minLength: 4)
            if let nature = entry.nature {
                Text(nature.name(store.language)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Renders the card to PNG. ImageRenderer draws a single pass and never runs a view's loading task,
/// so every sprite and type name the card needs is cached first.
@MainActor
enum TrainerCardExport {
    static let showsTokensKey = "trainerCardShowsTokens"

    static var showsTokens: Bool {
        UserDefaults.standard.object(forKey: showsTokensKey) as? Bool ?? true
    }

    static func sheet(_ content: TrainerCardContent) -> some View {
        VStack(spacing: 12) {
            TrainerCardFront(content: content)
            TrainerCardBack(content: content)
        }
        .padding(12)
        .environment(\.locale, content.language.displayLocale)
    }

    static func pngData(store: CompanionStore, showsTokens: Bool) async -> Data? {
        store.ensureTrainerID()
        if let id = store.cardSubject.speciesID { await store.loadPokemonDetails(speciesID: id) }
        await preload(TrainerCardContent(store: store, showsTokens: showsTokens))
        let renderer = ImageRenderer(content: sheet(TrainerCardContent(store: store, showsTokens: showsTokens)))
        renderer.scale = TrainerCardStyle.exportScale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func preload(_ content: TrainerCardContent) async {
        let sprites = [(content.companionSpeciesID, content.companionShiny)]
            + content.team.map { (Optional($0.entry.finalID), $0.entry.isShiny) }
        for (speciesID, shiny) in sprites {
            guard let speciesID else {
                _ = await SpriteLoader.eggImage()
                continue
            }
            _ = await SpriteLoader.animationFrames(speciesID: speciesID, shiny: shiny)
            _ = await SpriteLoader.image(speciesID: speciesID, shiny: shiny)
        }
        _ = await SpriteLoader.itemImage(name: PokeBallIcon.spriteName)
        for type in content.types {
            _ = await PokemonNameDisplayStore.shared.load(.init(kind: .type, name: type),
                                                          provider: PokemonNameClient.shared)
        }
    }

    @discardableResult
    static func copy(store: CompanionStore, showsTokens: Bool = TrainerCardExport.showsTokens) async -> Bool {
        guard let png = await pngData(store: store, showsTokens: showsTokens) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }

    static func save(store: CompanionStore, showsTokens: Bool) async {
        guard let png = await pngData(store: store, showsTokens: showsTokens) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "trainer-card.png"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            AppLog.write("trainer card save failed: \(error)")
        }
    }
}
