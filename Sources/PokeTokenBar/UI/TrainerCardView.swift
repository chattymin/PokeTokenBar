import AppKit
import SwiftUI

// MARK: - Pokémon Type Colors & Energy Symbols

enum PokemonTypeColor {
    static func color(for typeName: String) -> Color {
        switch typeName.lowercased() {
        case "fire": return Color(red: 0.94, green: 0.42, blue: 0.18)
        case "water": return Color(red: 0.25, green: 0.52, blue: 0.88)
        case "grass": return Color(red: 0.35, green: 0.70, blue: 0.30)
        case "electric": return Color(red: 0.95, green: 0.78, blue: 0.15)
        case "ice": return Color(red: 0.40, green: 0.80, blue: 0.86)
        case "fighting": return Color(red: 0.78, green: 0.28, blue: 0.20)
        case "poison": return Color(red: 0.62, green: 0.35, blue: 0.70)
        case "ground": return Color(red: 0.80, green: 0.65, blue: 0.35)
        case "flying": return Color(red: 0.52, green: 0.65, blue: 0.92)
        case "psychic": return Color(red: 0.92, green: 0.38, blue: 0.60)
        case "bug": return Color(red: 0.55, green: 0.70, blue: 0.22)
        case "rock": return Color(red: 0.70, green: 0.60, blue: 0.30)
        case "ghost": return Color(red: 0.42, green: 0.35, blue: 0.65)
        case "dragon": return Color(red: 0.40, green: 0.35, blue: 0.88)
        case "dark": return Color(red: 0.38, green: 0.35, blue: 0.32)
        case "steel": return Color(red: 0.62, green: 0.70, blue: 0.72)
        case "fairy": return Color(red: 0.92, green: 0.62, blue: 0.80)
        default: return Color(red: 0.60, green: 0.62, blue: 0.65)
        }
    }

    static func cardGradients(for typeName: String) -> [Color] {
        switch typeName.lowercased() {
        case "fire":
            return [Color(red: 0.92, green: 0.38, blue: 0.20), Color(red: 0.70, green: 0.18, blue: 0.12)]
        case "water":
            return [Color(red: 0.28, green: 0.58, blue: 0.90), Color(red: 0.14, green: 0.32, blue: 0.70)]
        case "grass":
            return [Color(red: 0.40, green: 0.75, blue: 0.35), Color(red: 0.18, green: 0.48, blue: 0.22)]
        case "electric":
            return [Color(red: 0.98, green: 0.85, blue: 0.25), Color(red: 0.82, green: 0.62, blue: 0.12)]
        case "dragon":
            return [Color(red: 0.45, green: 0.38, blue: 0.85), Color(red: 0.22, green: 0.16, blue: 0.52)]
        case "psychic":
            return [Color(red: 0.90, green: 0.35, blue: 0.58), Color(red: 0.65, green: 0.18, blue: 0.42)]
        default:
            return [Color(red: 0.30, green: 0.33, blue: 0.40), Color(red: 0.15, green: 0.17, blue: 0.22)]
        }
    }
}

enum PokemonTypeEnergy {
    static func symbol(for typeName: String) -> String {
        switch typeName.lowercased() {
        case "fire": return "🔥"
        case "water": return "💧"
        case "grass": return "🌿"
        case "electric": return "⚡"
        case "ice": return "❄️"
        case "fighting": return "🥊"
        case "poison": return "☠️"
        case "ground": return "🏜️"
        case "flying": return "🦅"
        case "psychic": return "👁️"
        case "bug": return "🐛"
        case "rock": return "🪨"
        case "ghost": return "👻"
        case "dragon": return "🐉"
        case "dark": return "🌑"
        case "steel": return "⚙️"
        case "fairy": return "✨"
        default: return "⚪"
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

// MARK: - Pokémon TCG Card Canvas View (Rendered by ImageRenderer & Preview)

@MainActor
struct TrainerCardCanvasView: View {
    let data: TrainerCardData

    // Classic Pokémon Trading Card Aspect Ratio (approx 63mm : 88mm)
    static let cardWidth: CGFloat = 330
    static let cardHeight: CGFloat = 465

    private var primaryType: String {
        data.types.first ?? (data.isEgg ? "normal" : "normal")
    }

    var body: some View {
        ZStack {
            // 1. Classic Yellow TCG Outer Border
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.98, green: 0.83, blue: 0.22))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)

            // 2. Inner Card Face
            VStack(spacing: 6) {
                topHeaderRow
                illustrationWindow
                speciesInfoStrip
                movesSection
                bottomStatsGrid
                cardFooterStrip
            }
            .padding(10)
            .background(
                LinearGradient(
                    colors: PokemonTypeColor.cardGradients(for: primaryType),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(red: 0.4, green: 0.35, blue: 0.15).opacity(0.4), lineWidth: 1.5)
            )
            .padding(8) // Yellow border width
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    // MARK: - 1. Top Header Row (Stage, Name, HP, Energy)
    private var topHeaderRow: some View {
        HStack(alignment: .center, spacing: 6) {
            // Stage Badge
            Text(data.isEgg ? "기본 알" : data.stageText)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 0.95, green: 0.90, blue: 0.75), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 1)

            // Pokémon Name
            Text(data.speciesName)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                .lineLimit(1)

            Spacer()

            // HP / Today's Tokens
            HStack(spacing: 3) {
                Text("HP")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(TokenFormatter.compact(data.todayTokens))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Energy Symbol Circle
            ZStack {
                Circle()
                    .fill(PokemonTypeColor.color(for: primaryType))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                Text(PokemonTypeEnergy.symbol(for: primaryType))
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 2. Illustration Window
    private var illustrationWindow: some View {
        ZStack(alignment: .topTrailing) {
            // Metallic / Holographic background
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                RadialGradient(
                    colors: [data.accentColor.opacity(0.45), Color.clear],
                    center: .center,
                    startRadius: 5,
                    endRadius: 90
                )
                // Shimmer grid
                GeometryReader { proxy in
                    Path { path in
                        let step: CGFloat = 16
                        var x: CGFloat = 0
                        while x < proxy.size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                            x += step
                        }
                    }
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                }
            }

            // Sprite Art
            VStack {
                Spacer()
                if let img = data.spriteImage {
                    let targetBox: CGFloat = data.isEgg ? 64 : 96
                    let fit = SpriteFit.size(for: img.size, box: targetBox)
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                } else {
                    Text(data.isEgg ? "🥚" : "❓")
                        .font(.system(size: 54))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Shiny Stamp
            if data.isShiny {
                HStack(spacing: 2) {
                    Text("✨")
                    Text("SHINY")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .foregroundStyle(.black)
                .padding(6)
            }
        }
        .frame(height: 145)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.85, blue: 0.40),
                            Color(red: 0.70, green: 0.55, blue: 0.20),
                            Color(red: 0.90, green: 0.80, blue: 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
    }

    // MARK: - 3. Species / Pokédex Ribbon Strip
    private var speciesInfoStrip: some View {
        let metaItems: [String] = [
            data.speciesID.map { String(format: "NO. %03d", $0) },
            data.natureText,
            data.types.isEmpty ? nil : data.types.map { $0.uppercased() }.joined(separator: "/"),
            data.levelText.isEmpty ? nil : data.levelText
        ].compactMap { $0 }

        return HStack(spacing: 5) {
            Text(metaItems.joined(separator: " · "))
                .fontWeight(.bold)
        }
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.10))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2.5)
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.90, blue: 0.75), Color(red: 0.85, green: 0.80, blue: 0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.15), radius: 1)
    }

    // MARK: - 4. Moves / Coding Lore Section
    private var movesSection: some View {
        VStack(spacing: 8) {
            // Move 1: Today's Burn
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 2) {
                        Text(PokemonTypeEnergy.symbol(for: primaryType)).font(.system(size: 11))
                        Text(PokemonTypeEnergy.symbol(for: primaryType)).font(.system(size: 11))
                    }
                    Text(data.isEgg ? "따뜻한 온기 (Warmth)" : "오늘의 코딩 (Daily Coding)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(TokenFormatter.compact(data.todayTokens))
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))
                }

                Text(data.isEgg
                     ? "오늘 적립된 \(TokenFormatter.compact(data.todayTokens)) 토큰으로 알을 정성스럽게 부화 인큐베이팅 중이다."
                     : "오늘 하루 동안 AI 모델과 페어 프로그래밍하며 소비한 토큰 수치이다.")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Move 2: Lifetime Rush
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 2) {
                        Text("⭐").font(.system(size: 10))
                        Text("⭐").font(.system(size: 10))
                        Text("⭐").font(.system(size: 10))
                    }
                    Text(data.isEgg ? "부화 인큐베이션 (Hatch)" : "누적 토큰 러시 (Lifetime Rush)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(TokenFormatter.compact(data.allTimeTokens))
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))
                }

                Text(data.isEgg
                     ? (data.eggProgressText ?? "새로운 포켓몬 부화까지 토큰을 모으는 중이다.")
                     : "설치 후 누적 토큰. 도감 \(data.pokedexCount)종 등록 및 명예의 전당 \(data.hallOfFameCount)마리 졸업.")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 5. Bottom Stats Grid (Weakness, Resistance, Retreat)
    private var bottomStatsGrid: some View {
        HStack(spacing: 0) {
            // Weakness
            VStack(spacing: 1) {
                Text("약점 (weakness)")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("⚡ 한도 ×2")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 16).overlay(Color.white.opacity(0.2))

            // Resistance
            VStack(spacing: 1) {
                Text("저항력 (resistance)")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("🛡️ 캐시 -30")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 16).overlay(Color.white.opacity(0.2))

            // Retreat
            VStack(spacing: 1) {
                Text("후퇴 (retreat)")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("🍬 ×1")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 6. Card Footer Strip
    private var cardFooterStrip: some View {
        HStack {
            Text("Illus. \(data.trainerName) · PokeTokenBar")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))

            Spacer()

            Text("© 2026 Dev TCG")
                .font(.system(size: 6, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Text(String(format: "★ %03d/151 PROMO", data.pokedexCount))
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.25))
        }
        .padding(.horizontal, 2)
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
        VStack(spacing: 10) {
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

                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, PopoverMetrics.padding)
            .padding(.top, 10)

            // Pokémon TCG Card Preview (Scaled to fit popover)
            let cardScale = min(1.0, (PopoverMetrics.contentWidth) / TrainerCardCanvasView.cardWidth)
            TrainerCardCanvasView(data: cardData)
                .scaleEffect(cardScale)
                .frame(
                    width: TrainerCardCanvasView.cardWidth * cardScale,
                    height: TrainerCardCanvasView.cardHeight * cardScale
                )
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
            .padding(.bottom, 10)
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
