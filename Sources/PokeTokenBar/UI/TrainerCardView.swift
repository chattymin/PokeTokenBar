import AppKit
import SwiftUI

// MARK: - Pokémon Type Colors

enum PokemonTypeColor {
    static func color(for typeName: String) -> Color {
        switch typeName.lowercased() {
        case "fire": return Color(red: 0.98, green: 0.50, blue: 0.20)
        case "water": return Color(red: 0.28, green: 0.55, blue: 0.90)
        case "grass": return Color(red: 0.40, green: 0.75, blue: 0.35)
        case "electric": return Color(red: 0.98, green: 0.82, blue: 0.20)
        case "ice": return Color(red: 0.42, green: 0.82, blue: 0.88)
        case "fighting": return Color(red: 0.80, green: 0.30, blue: 0.22)
        case "poison": return Color(red: 0.65, green: 0.38, blue: 0.72)
        case "ground": return Color(red: 0.82, green: 0.68, blue: 0.38)
        case "flying": return Color(red: 0.55, green: 0.68, blue: 0.95)
        case "psychic": return Color(red: 0.95, green: 0.40, blue: 0.62)
        case "bug": return Color(red: 0.58, green: 0.72, blue: 0.25)
        case "rock": return Color(red: 0.72, green: 0.62, blue: 0.32)
        case "ghost": return Color(red: 0.45, green: 0.38, blue: 0.68)
        case "dragon": return Color(red: 0.42, green: 0.38, blue: 0.90)
        case "dark": return Color(red: 0.42, green: 0.38, blue: 0.35)
        case "steel": return Color(red: 0.65, green: 0.72, blue: 0.75)
        case "fairy": return Color(red: 0.95, green: 0.65, blue: 0.82)
        default: return Color(red: 0.62, green: 0.65, blue: 0.68)
        }
    }
}

// MARK: - Trainer Card Data Model

@MainActor
struct TrainerCardData {
    let trainerName: String
    let trainerID: String
    let startDate: String
    let todayTokens: Int
    let allTimeTokens: Int
    let pokedexCount: Int
    let hallOfFameCount: Int
    let rankBall: String
    let rankTitle: String
    let isEgg: Bool
    let speciesID: Int?
    let speciesName: String
    let isShiny: Bool
    let stageText: String
    let levelText: String
    let natureText: String?
    let types: [String]
    let eggProgressText: String?
    let spriteImage: NSImage?
    let accentColor: Color
    let exportDate: String
    let language: AppLanguage
    let l: L

    static func generateTrainerID() -> String {
        let name = NSUserName()
        let hash = abs(name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) })
        let idNum = (hash % 90000) + 10000
        return String(format: "%05d", idNum)
    }

    static var defaultTrainerName: String {
        let full = NSFullUserName()
        if !full.isEmpty { return full }
        let short = NSUserName()
        if !short.isEmpty { return short }
        return "Trainer"
    }
}

// MARK: - Canvas View (Rendered by ImageRenderer & Preview)

@MainActor
struct TrainerCardCanvasView: View {
    let data: TrainerCardData

    static let cardWidth: CGFloat = 520
    static let cardHeight: CGFloat = 320

    var body: some View {
        ZStack {
            cardBackground
            VStack(spacing: 10) {
                cardHeader
                Divider().overlay(Color.white.opacity(0.12))
                cardBody
                Divider().overlay(Color.white.opacity(0.12))
                cardFooter
            }
            .padding(14)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [data.accentColor.opacity(0.9), data.accentColor.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    // MARK: Background
    private var cardBackground: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
            LinearGradient(
                colors: [data.accentColor.opacity(0.22), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Subtle retro mesh grid overlay
            GeometryReader { proxy in
                Path { path in
                    let step: CGFloat = 20
                    var x: CGFloat = 0
                    while x < proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Color.white.opacity(0.025), lineWidth: 1)
            }
        }
    }

    // MARK: Header
    private var cardHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                // Mini Pokéball emblem
                ZStack {
                    Circle().fill(Color.white).frame(width: 14, height: 14)
                    Circle().trim(from: 0.5, to: 1.0)
                        .fill(Color.red).frame(width: 14, height: 14)
                    Rectangle().fill(Color.black).frame(width: 14, height: 2)
                    Circle().fill(Color.black).frame(width: 6, height: 6)
                    Circle().fill(Color.white).frame(width: 3, height: 3)
                }
                Text("POKÉ TOKEN TRAINER CARD")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(1)
            }

            Spacer()

            Text("IDNo. \(data.trainerID)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(data.accentColor)
        }
    }

    // MARK: Body
    private var cardBody: some View {
        HStack(spacing: 12) {
            companionHeroBox
            statsBox
        }
    }

    // Left Column: Companion Hero
    private var companionHeroBox: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(data.accentColor.opacity(0.35), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    if let img = data.spriteImage {
                        let fit = SpriteFit.size(for: img.size, box: 80)
                        Image(nsImage: img)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .frame(width: 80, height: 80)
                    } else {
                        Text(data.isEgg ? "🥚" : "❓")
                            .font(.system(size: 48))
                            .frame(width: 80, height: 80)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if data.isShiny {
                    Text("✨ SHINY")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.85), in: Capsule())
                        .foregroundStyle(.black)
                        .padding(5)
                }
            }
            .frame(width: 165, height: 105)

            // Companion identity
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if let id = data.speciesID {
                        Text(String(format: "#%03d", id))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(data.speciesName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                if data.isEgg {
                    if let prog = data.eggProgressText {
                        Text(prog)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(data.levelText)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(data.accentColor)
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(data.stageText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let nature = data.natureText {
                        Text(nature)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }

                if !data.types.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(data.types, id: \.self) { type in
                            Text(type.uppercased())
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PokemonTypeColor.color(for: type), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(width: 165)
        }
        .frame(width: 165, height: 210)
    }

    // Right Column: Stats & Milestones
    private var statsBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Sub-header: Trainer info
            HStack {
                HStack(spacing: 3) {
                    Text("NAME:")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(data.trainerName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text("START:")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(data.startDate)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Stat Cards Grid
            VStack(spacing: 6) {
                statRow(
                    icon: "🔥",
                    label: data.l.trainerCardTodayBurn,
                    value: TokenFormatter.compact(data.todayTokens),
                    valueColor: .orange
                )

                statRow(
                    icon: "⭐",
                    label: data.l.trainerCardAllTimeBurn,
                    value: TokenFormatter.compact(data.allTimeTokens),
                    valueColor: .yellow
                )

                HStack(spacing: 6) {
                    miniStatCell(
                        icon: "📖",
                        label: data.l.trainerCardPokedex,
                        value: "\(data.pokedexCount) / 151"
                    )
                    miniStatCell(
                        icon: "🏆",
                        label: data.l.trainerCardHallOfFame,
                        value: "\(data.hallOfFameCount) \(data.l.trainerCardGraduatedSuffix)"
                    )
                }

                // Rank
                HStack(spacing: 6) {
                    Text(data.rankBall)
                        .font(.system(size: 13))
                    Text("RANK")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(data.rankTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(data.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 210, alignment: .top)
    }

    private func statRow(icon: String, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(icon).font(.system(size: 12))
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func miniStatCell(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Footer
    private var cardFooter: some View {
        HStack {
            Text("⚡ PokeTokenBar · macOS AI Token Companion")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.8))
            Spacer()
            Text(data.exportDate)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.6))
        }
    }
}

// MARK: - Trainer Card View (Inside Popover Navigation)

@MainActor
struct TrainerCardView: View {
    @Environment(UsageStore.self) private var usage
    @Environment(CompanionStore.self) private var companion
    @AppStorage("trainerCardCustomName") private var customName: String = ""

    @State private var isCopied = false
    let onClose: () -> Void

    private var effectiveTrainerName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TrainerCardData.defaultTrainerName : trimmed
    }

    private var cardData: TrainerCardData {
        let store = companion
        let l = store.l
        let today = usage.todayTotalTokens
        let allTime = store.state.usedSinceInstall
        let rank = l.trainerRankTitle(tokens: allTime)

        let isEgg = !store.hasActive
        let speciesID = isEgg ? nil : store.currentSpeciesID
        let speciesName = store.displayName
        let isShiny = store.currentIsShiny

        let details = speciesID.flatMap { store.pokemonDetailsByID[$0] }
        let types = details?.types ?? []

        let levelText: String
        if let level = store.state.active?.profile?.level {
            levelText = "Lv. \(level)"
        } else {
            levelText = "Lv. 5"
        }

        let natureText: String?
        if let nature = store.currentNature {
            natureText = nature.name(store.language)
        } else {
            natureText = nil
        }

        let eggProgText: String?
        if isEgg {
            eggProgText = store.l.eggToHatch(TokenFormatter.compact(store.eggTokensToHatch))
        } else {
            eggProgText = nil
        }

        let spriteImg: NSImage?
        if isEgg {
            spriteImg = SpriteLoader.cachedEggImage()
        } else if let sid = speciesID {
            spriteImg = SpriteLoader.cachedImage(
                speciesID: sid,
                animated: false,
                shiny: isShiny,
                unownForm: store.currentUnownForm
            )
        } else {
            spriteImg = nil
        }

        let accentColor: Color
        if isEgg {
            accentColor = rarityColor(store.eggGuarantee)
        } else if let firstType = types.first {
            accentColor = PokemonTypeColor.color(for: firstType)
        } else {
            accentColor = .orange
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM"
        let startDate = formatter.string(from: Date())

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy.MM.dd"
        let exportDate = dayFormatter.string(from: Date())

        return TrainerCardData(
            trainerName: effectiveTrainerName,
            trainerID: TrainerCardData.generateTrainerID(),
            startDate: startDate,
            todayTokens: today,
            allTimeTokens: allTime,
            pokedexCount: store.state.dex.count,
            hallOfFameCount: store.state.collectedFinals.count,
            rankBall: rank.ball,
            rankTitle: rank.title,
            isEgg: isEgg,
            speciesID: speciesID,
            speciesName: speciesName,
            isShiny: isShiny,
            stageText: store.stageText,
            levelText: levelText,
            natureText: natureText,
            types: types,
            eggProgressText: eggProgText,
            spriteImage: spriteImg,
            accentColor: accentColor,
            exportDate: exportDate,
            language: store.language,
            l: l
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header bar
            HStack {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(companion.l.back)
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(companion.l.trainerCardTitle)
                    .font(.headline.weight(.semibold))

                Spacer()

                // Invisible spacer matching back button width for centering
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, PopoverMetrics.padding)
            .padding(.top, 12)

            // Scaled Card Preview
            let cardScale = (PopoverMetrics.contentWidth) / TrainerCardCanvasView.cardWidth
            TrainerCardCanvasView(data: cardData)
                .frame(width: TrainerCardCanvasView.cardWidth, height: TrainerCardCanvasView.cardHeight)
                .scaleEffect(cardScale)
                .frame(
                    width: PopoverMetrics.contentWidth,
                    height: TrainerCardCanvasView.cardHeight * cardScale
                )
                .clipShape(RoundedRectangle(cornerRadius: 16 * cardScale))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                .padding(.horizontal, PopoverMetrics.padding)

            // Name Customization Field
            HStack(spacing: 8) {
                Text(companion.l.trainerCardCustomNamePlaceholder)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField(TrainerCardData.defaultTrainerName, text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding(.horizontal, PopoverMetrics.padding)

            // Action Buttons
            HStack(spacing: 10) {
                Button {
                    copyCardToClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? companion.l.trainerCardCopied : companion.l.trainerCardCopy)
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isCopied ? .green : .accentColor)

                Button {
                    saveCardImage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text(companion.l.trainerCardSave)
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, PopoverMetrics.padding)
            .padding(.bottom, 12)
        }
        .frame(width: PopoverMetrics.width)
    }

    // MARK: - Actions

    @MainActor
    private func renderCardImage() -> NSImage? {
        let canvas = TrainerCardCanvasView(data: cardData)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0 // @2x Retina resolution
        renderer.proposedSize = ProposedViewSize(
            width: TrainerCardCanvasView.cardWidth,
            height: TrainerCardCanvasView.cardHeight
        )
        return renderer.nsImage
    }

    @MainActor
    private func copyCardToClipboard() {
        guard let nsImage = renderCardImage() else { return }
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(tiffData, forType: .tiff)

        withAnimation(.spring(duration: 0.25)) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { isCopied = false }
            }
        }
    }

    @MainActor
    private func saveCardImage() {
        guard let nsImage = renderCardImage() else { return }
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }

        let panel = NSSavePanel()
        panel.title = companion.l.trainerCardSave
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        panel.nameFieldStringValue = "PokeTokenCard_\(dateStr).png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pngData.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            AppLog.write("Trainer card image save failed: \(error)")
        }
    }
}
