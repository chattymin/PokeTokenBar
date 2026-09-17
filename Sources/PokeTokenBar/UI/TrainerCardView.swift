import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Trainer Card View (Render Target)

@MainActor
struct TrainerCardView: View {
    let data: TrainerCardData
    let l: L

    static let cardWidth: CGFloat = 332
    static let cardHeight: CGFloat = 206

    var body: some View {
        Group {
            switch data.theme {
            case .classic: classicLayout
            case .masterBall: masterBallLayout
            case .gameBoy1989: gameBoyLayout
            case .celadonNeon: neonLayout
            case .teamRocket: rocketLayout
            case .indigoPlateau: plateauLayout
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: borderWidth)
        )
        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
    }

    // MARK: - Corner Radius / Border

    private var cornerRadius: CGFloat {
        switch data.theme {
        case .gameBoy1989: return 14
        case .celadonNeon: return 6
        case .teamRocket: return 4
        default: return 12
        }
    }

    private var borderWidth: CGFloat {
        switch data.theme {
        case .celadonNeon, .indigoPlateau, .masterBall: return 2.0
        case .gameBoy1989: return 2.5
        default: return 1.5
        }
    }

    private var borderStyle: AnyShapeStyle {
        switch data.theme {
        case .classic:
            return AnyShapeStyle(Color(red: 0.20, green: 0.20, blue: 0.22))
        case .gameBoy1989:
            return AnyShapeStyle(Color(red: 0.55, green: 0.55, blue: 0.50))
        case .celadonNeon:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.06, green: 0.88, blue: 0.75), Color(red: 0.10, green: 0.94, blue: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .teamRocket:
            return AnyShapeStyle(Color(red: 0.75, green: 0.10, blue: 0.18))
        case .indigoPlateau:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.80, blue: 0.25), Color(red: 0.85, green: 0.65, blue: 0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .masterBall:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.50, green: 0.15, blue: 0.68), Color(red: 0.90, green: 0.30, blue: 0.72), Color(red: 0.95, green: 0.78, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 1) Classic Layout (Pokeball Split — Red / Seam / White)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var classicLayout: some View {
        let primary = Color(red: 0.12, green: 0.12, blue: 0.14)
        let label = Color(red: 0.40, green: 0.40, blue: 0.45)
        let tileBg = Color.black.opacity(0.04)
        let tileBorder = Color.black.opacity(0.12)
        let frameBg = Color(red: 0.98, green: 0.98, blue: 0.99)
        let frameBorder = Color(red: 0.75, green: 0.75, blue: 0.78)

        return VStack(spacing: 0) {
            // Red dome with header
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.85, green: 0.15, blue: 0.18), Color(red: 0.72, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 7, height: 7)
                        Text(l.trainerCard.uppercased())
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("IDNo. \(data.trainerID)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 31)

            // Seam
            Rectangle().fill(Color(red: 0.15, green: 0.15, blue: 0.16)).frame(height: 2)

            // White zone — content centered
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.98, blue: 0.99), Color(red: 0.92, green: 0.92, blue: 0.94)],
                    startPoint: .top, endPoint: .bottom
                )

                // Pokeball watermark
                pokeBallWatermark(stroke: Color.black.opacity(0.06), fill: Color.black.opacity(0.08))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)

                // Content centered in white zone
                VStack(alignment: .leading, spacing: 5) {
                    trainerNameRow(primary: primary, label: label)
                    HStack(alignment: .top, spacing: 10) {
                        pokemonFrame(bg: frameBg, border: frameBorder, nameColor: primary, subColor: label, subBg: tileBg)
                        statsGrid(label: label, value: primary, tileBg: tileBg, tileBorder: tileBorder)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 2) Master Ball Layout (The Ball Itself)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var masterBallLayout: some View {
        let purpleTop = Color(red: 0.38, green: 0.10, blue: 0.55)
        let purpleDark = Color(red: 0.22, green: 0.04, blue: 0.35)
        let pink = Color(red: 0.94, green: 0.24, blue: 0.68)
        let pinkDim = Color(red: 0.76, green: 0.14, blue: 0.52)
        let bottomLight = Color(red: 0.96, green: 0.95, blue: 0.98)
        let bottomDark = Color(red: 0.86, green: 0.84, blue: 0.90)
        let seamColor = Color(red: 0.12, green: 0.08, blue: 0.16)
        let ringOuter = Color(red: 0.88, green: 0.86, blue: 0.92)
        let ringInner = Color(red: 0.62, green: 0.58, blue: 0.68)
        let textOnPurple: Color = .white
        let textOnLight = Color(red: 0.16, green: 0.08, blue: 0.25)
        let textDimOnLight = Color(red: 0.48, green: 0.36, blue: 0.58)

        return ZStack {
            // ── Master Ball background: top purple, seam, bottom white ──
            VStack(spacing: 0) {
                // Purple top hemisphere (height 100)
                ZStack {
                    LinearGradient(colors: [purpleTop, purpleDark],
                                   startPoint: .top, endPoint: .bottom)

                    // Two iconic magenta capsule bumps
                    HStack {
                        Capsule()
                            .fill(LinearGradient(colors: [pink, pinkDim],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 34, height: 12)
                            .rotationEffect(.degrees(-15))
                            .offset(x: 28, y: 12)
                        Spacer()
                        Capsule()
                            .fill(LinearGradient(colors: [pink, pinkDim],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 34, height: 12)
                            .rotationEffect(.degrees(15))
                            .offset(x: -28, y: 12)
                    }

                    // Iconic white "M" symbol above the center button
                    Text("M")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                        .offset(y: 22)
                }
                .frame(height: 100)

                // Dark seam band
                ZStack {
                    Rectangle().fill(seamColor).frame(height: 6)
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                        .offset(y: -2.5)
                }

                // Pearlescent light bottom hemisphere (height 100)
                LinearGradient(colors: [bottomLight, bottomDark],
                               startPoint: .top, endPoint: .bottom)
            }

            // ── Center circle (Master Ball core button) with Pokemon ──
            ZStack {
                // Outer chrome metallic bezel
                Circle()
                    .fill(LinearGradient(
                        colors: [ringOuter, ringInner, ringOuter],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.40), radius: 6, y: 2)

                // Inner black seam
                Circle()
                    .strokeBorder(seamColor, lineWidth: 3)
                    .frame(width: 90, height: 90)

                // Inner portal lens with cosmic violet gradient
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.18, green: 0.10, blue: 0.28),
                                 Color(red: 0.08, green: 0.04, blue: 0.14)],
                        center: .center, startRadius: 5, endRadius: 44
                    ))
                    .frame(width: 84, height: 84)

                // Magenta glow accent ring inside lens
                Circle()
                    .strokeBorder(pink.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 82, height: 82)

                // Pokemon sprite
                SpriteView(speciesID: data.pokemonID, size: 76, animated: false, shiny: data.isShiny)
                    .frame(width: 80, height: 80)

                // Shiny badge
                if data.isShiny {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.25))
                        .padding(3)
                        .background(Color.black.opacity(0.7), in: Circle())
                        .frame(width: 84, height: 84, alignment: .topTrailing)
                        .offset(x: -2, y: 2)
                }
            }

            // ── 4 Corners Info Layout ──

            // Top-Left: Trainer header & Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 0.95, green: 0.82, blue: 0.25)).frame(width: 5, height: 5)
                    Text("MASTER BALL")
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.25))
                }
                HStack(spacing: 3) {
                    Text(l.trainerCardTrainerLabel.uppercased() + ":")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(textOnPurple.opacity(0.70))
                    Text(data.trainerName)
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(textOnPurple)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 12).padding(.top, 10)

            // Top-Right: IDNo. & Casino Coins
            VStack(alignment: .trailing, spacing: 2) {
                Text("IDNo. \(data.trainerID)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(textOnPurple.opacity(0.90))
                HStack(spacing: 3) {
                    Image(systemName: "suit.diamond.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.25))
                    Text(data.casinoCoins.formatted())
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.25))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 12).padding(.top, 10)

            // Bottom-Left: Pokemon info & Token stats
            VStack(alignment: .leading, spacing: 2) {
                Text(data.pokemonName)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(textOnLight)
                    .lineLimit(1)
                if let sub = data.pokemonSubtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(textDimOnLight)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    mbCornerStat(label: l.trainerCardLifetimeTokens, value: TokenFormatter.compact(data.totalTokens), labelColor: textDimOnLight, valColor: textOnLight)
                    mbCornerStat(label: l.trainerCardTodayTokens, value: TokenFormatter.compact(data.todayTokens), labelColor: textDimOnLight, valColor: textOnLight)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 12).padding(.bottom, 10)

            // Bottom-Right: Pokedex stats
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    mbCornerStat(label: l.trainerCardPokedexLabel, value: "\(data.pokedexCount)/\(data.pokedexTotal)", labelColor: textDimOnLight, valColor: textOnLight)
                    mbCornerStat(label: l.trainerCardGraduatedLabel, value: "\(data.graduatedCount)", labelColor: textDimOnLight, valColor: textOnLight)
                    mbCornerStat(label: l.trainerCardShiniesLabel, value: "\(data.shinyCount)", labelColor: textDimOnLight, valColor: textOnLight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12).padding(.bottom, 10)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 3) Game Boy 1989 Layout (Hardware Shell + Green LCD Screen)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var gameBoyLayout: some View {
        let shell = Color(red: 0.78, green: 0.78, blue: 0.72)
        let shellDark = Color(red: 0.70, green: 0.70, blue: 0.64)
        let bezel = Color(red: 0.26, green: 0.27, blue: 0.30)
        let screenBg = Color(red: 0.54, green: 0.67, blue: 0.06)
        let screenLight = Color(red: 0.60, green: 0.73, blue: 0.10)
        let ink = Color(red: 0.06, green: 0.16, blue: 0.02)
        let inkMid = Color(red: 0.18, green: 0.30, blue: 0.06)

        return ZStack {
            // Shell
            LinearGradient(colors: [shell, shellDark], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                // Top shell: power LED + branding text
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.70, green: 0.10, blue: 0.18))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color.red.opacity(0.4), radius: 2)
                    Spacer()
                    Text(l.trainerCard.uppercased())
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.38))
                        .tracking(2)
                    Spacer()
                    Text("IDNo.\(data.trainerID)")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.46))
                }
                .padding(.horizontal, 14)
                .frame(height: 18)

                // Screen area: bezel → screen → content
                ZStack {
                    // Dark bezel
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(bezel)
                        .padding(.horizontal, 8)

                    // Green LCD
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(colors: [screenBg, screenLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                    // Scanlines overlay
                    VStack(spacing: 0) {
                        ForEach(0..<80, id: \.self) { _ in
                            Rectangle().fill(Color.black.opacity(0.025)).frame(height: 0.5)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    // Screen content
                    HStack(alignment: .top, spacing: 8) {
                        // Left: Pokemon
                        VStack(spacing: 2) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(screenBg.opacity(0.7))
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(ink.opacity(0.3), lineWidth: 1)
                                    )
                                SpriteView(speciesID: data.pokemonID, size: 68, animated: false, shiny: data.isShiny)
                                    .frame(width: 72, height: 72)
                                if data.isShiny {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(ink)
                                        .padding(2)
                                }
                            }
                            Text(data.pokemonName)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .frame(width: 72)
                            if let sub = data.pokemonSubtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                                    .foregroundStyle(inkMid)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(width: 72)
                            }
                        }

                        // Right: trainer + compact stats
                        VStack(alignment: .leading, spacing: 2.5) {
                            HStack(spacing: 3) {
                                Text(l.trainerCardTrainerLabel.uppercased() + ":")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(inkMid)
                                Text(data.trainerName)
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                            }
                            Rectangle().fill(ink.opacity(0.20)).frame(height: 1)

                            gbStatLine(l.trainerCardLifetimeTokens, TokenFormatter.compact(data.totalTokens), ink: ink, mid: inkMid)
                            gbStatLine(l.trainerCardTodayTokens, TokenFormatter.compact(data.todayTokens), ink: ink, mid: inkMid)
                            gbStatLine(l.trainerCardPokedexLabel, "\(data.pokedexCount)/\(data.pokedexTotal)", ink: ink, mid: inkMid)
                            gbStatLine(l.trainerCardGraduatedLabel, "\(data.graduatedCount)", ink: ink, mid: inkMid)
                            gbStatLine(l.trainerCardShiniesLabel, "\(data.shinyCount)", ink: ink, mid: inkMid)
                            gbStatLine(l.trainerCardCasinoCoinsLabel, data.casinoCoins.formatted(), ink: ink, mid: inkMid)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }

                // Bottom shell: decorative dots (d-pad / buttons hint)
                HStack(spacing: 0) {
                    // D-pad hint
                    ZStack {
                        RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.28, green: 0.28, blue: 0.30))
                            .frame(width: 18, height: 6)
                        RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.28, green: 0.28, blue: 0.30))
                            .frame(width: 6, height: 18)
                    }
                    .padding(.leading, 20)

                    Spacer()

                    // A/B buttons
                    HStack(spacing: 5) {
                        Circle().fill(Color(red: 0.60, green: 0.12, blue: 0.22)).frame(width: 10, height: 10)
                        Circle().fill(Color(red: 0.60, green: 0.12, blue: 0.22)).frame(width: 10, height: 10)
                    }
                    .rotationEffect(.degrees(-25))
                    .padding(.trailing, 20)
                }
                .frame(height: 24)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 4) Celadon Neon Layout (Cyberpunk Arcade)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var neonLayout: some View {
        let neon = Color(red: 0.06, green: 0.88, blue: 0.72)
        let neonGreen = Color(red: 0.12, green: 0.95, blue: 0.50)
        let bg = Color(red: 0.04, green: 0.06, blue: 0.14)
        let textBright: Color = .white
        let textDim = Color.white.opacity(0.65)

        return ZStack {
            bg

            VStack(spacing: 0) {
                // Top: trainer info + pokemon
                HStack(alignment: .top, spacing: 10) {
                    // Pokemon with neon glow ring
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .strokeBorder(neon.opacity(0.35), lineWidth: 2)
                                .frame(width: 84, height: 84)
                                .shadow(color: neon.opacity(0.25), radius: 6)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(bg)
                                .frame(width: 78, height: 78)

                            SpriteView(speciesID: data.pokemonID, size: 74, animated: false, shiny: data.isShiny)
                                .frame(width: 78, height: 78)

                            if data.isShiny {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.yellow)
                                    .padding(3)
                                    .background(Color.black.opacity(0.6), in: Circle())
                                    .offset(x: -1, y: 1)
                            }
                        }
                        Text(data.pokemonName)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(neon)
                            .lineLimit(1)
                            .frame(width: 84)
                        if let sub = data.pokemonSubtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(neonGreen.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 84)
                        }
                    }

                    // Right: trainer info + header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.trainerCard.uppercased())
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(neon)
                            Spacer()
                            Text("IDNo.\(data.trainerID)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(textDim)
                        }

                        Rectangle().fill(neon.opacity(0.4)).frame(height: 1)

                        HStack(spacing: 3) {
                            Text(l.trainerCardTrainerLabel.uppercased() + ":")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(textDim)
                            Text(data.trainerName)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(textBright)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer(minLength: 4)

                // Neon separator
                Rectangle().fill(
                    LinearGradient(colors: [neon.opacity(0), neon.opacity(0.5), neon.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                ).frame(height: 1)

                // Bottom stat strip: 3x2 grid with neon dividers
                HStack(spacing: 0) {
                    neonStatCell(l.trainerCardLifetimeTokens, TokenFormatter.compact(data.totalTokens), accent: neon, dim: textDim, bright: textBright)
                    neonDivider(neon)
                    neonStatCell(l.trainerCardTodayTokens, TokenFormatter.compact(data.todayTokens), accent: neonGreen, dim: textDim, bright: textBright)
                    neonDivider(neon)
                    neonStatCell(l.trainerCardPokedexLabel, "\(data.pokedexCount)/\(data.pokedexTotal)", accent: neon, dim: textDim, bright: textBright)
                }
                .frame(height: 32)

                HStack(spacing: 0) {
                    neonStatCell(l.trainerCardGraduatedLabel, "\(data.graduatedCount)", accent: neonGreen, dim: textDim, bright: textBright)
                    neonDivider(neon)
                    neonStatCell(l.trainerCardShiniesLabel, "\(data.shinyCount)", accent: neon, dim: textDim, bright: textBright)
                    neonDivider(neon)
                    neonStatCell(l.trainerCardCasinoCoinsLabel, data.casinoCoins.formatted(), accent: neonGreen, dim: textDim, bright: textBright)
                }
                .frame(height: 32)
                .padding(.bottom, 6)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 5) Team Rocket Layout (Classified Dossier)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var rocketLayout: some View {
        let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
        let red = Color(red: 0.90, green: 0.12, blue: 0.22)
        let redDim = Color(red: 0.75, green: 0.10, blue: 0.18)
        let textBright: Color = .white
        let textDim = Color.white.opacity(0.60)

        return ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.14, green: 0.06, blue: 0.08)],
                startPoint: .top, endPoint: .bottom
            )

            // Large "R" watermark
            Text("R")
                .font(.system(size: 140, weight: .black, design: .serif))
                .italic()
                .foregroundStyle(red.opacity(0.07))
                .offset(x: 60, y: 10)

            VStack(spacing: 0) {
                // Header bar
                HStack {
                    Rectangle().fill(red).frame(width: 3, height: 14)
                    Text(l.trainerCard.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(red)
                    Spacer()
                    Text("IDNo.\(data.trainerID)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(textDim)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Rectangle().fill(red.opacity(0.4)).frame(height: 1).padding(.horizontal, 12).padding(.top, 4)

                // Main content: photo + dossier fields
                HStack(alignment: .top, spacing: 10) {
                    // Photo with red border
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bg)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(redDim, lineWidth: 1.5)
                                )
                            SpriteView(speciesID: data.pokemonID, size: 72, animated: false, shiny: data.isShiny)
                                .frame(width: 80, height: 80)
                            if data.isShiny {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.yellow)
                                    .padding(3)
                                    .background(Color.black.opacity(0.6), in: Circle())
                                    .offset(x: -2, y: 2)
                            }
                        }
                        Text(data.pokemonName)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(textBright)
                            .lineLimit(1)
                            .frame(width: 80)
                    }

                    // Dossier fields
                    VStack(alignment: .leading, spacing: 4) {
                        rocketField(label: l.trainerCardTrainerLabel.uppercased(), value: data.trainerName, red: red, dim: textDim, bright: textBright)

                        if let sub = data.pokemonSubtitle, !sub.isEmpty {
                            rocketField(label: "STATUS", value: sub, red: red, dim: textDim, bright: textBright)
                        }

                        Rectangle().fill(red.opacity(0.2)).frame(height: 1).padding(.top, 2)

                        // Compact stat pairs
                        HStack(spacing: 8) {
                            rocketStat(l.trainerCardLifetimeTokens, TokenFormatter.compact(data.totalTokens), dim: textDim, bright: textBright)
                            rocketStat(l.trainerCardTodayTokens, TokenFormatter.compact(data.todayTokens), dim: textDim, bright: textBright)
                        }
                        HStack(spacing: 8) {
                            rocketStat(l.trainerCardPokedexLabel, "\(data.pokedexCount)/\(data.pokedexTotal)", dim: textDim, bright: textBright)
                            rocketStat(l.trainerCardGraduatedLabel, "\(data.graduatedCount)", dim: textDim, bright: textBright)
                        }
                        HStack(spacing: 8) {
                            rocketStat(l.trainerCardShiniesLabel, "\(data.shinyCount)", dim: textDim, bright: textBright)
                            rocketStat(l.trainerCardCasinoCoinsLabel, data.casinoCoins.formatted(), dim: textDim, bright: textBright)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 6) Indigo Plateau Layout (Hall of Fame)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var plateauLayout: some View {
        let goldPrimary = Color(red: 0.96, green: 0.82, blue: 0.32)
        let goldDark = Color(red: 0.72, green: 0.54, blue: 0.16)
        let goldBright = Color(red: 1.0, green: 0.92, blue: 0.55)
        let bgMidnight = Color(red: 0.05, green: 0.06, blue: 0.20)
        let bgDeep = Color(red: 0.09, green: 0.08, blue: 0.28)
        let bgDark = Color(red: 0.03, green: 0.04, blue: 0.14)
        let textDim = Color.white.opacity(0.65)

        return ZStack {
            // Royal velvet midnight background
            LinearGradient(
                colors: [bgMidnight, bgDeep, bgDark],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Fine gold inner frame
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [goldBright, goldPrimary, goldDark, goldPrimary],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .padding(3)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(goldPrimary.opacity(0.25), lineWidth: 0.6)
                .padding(6)

            VStack(spacing: 0) {
                // ── Luxury Ribbon Header ──
                ZStack {
                    LinearGradient(
                        colors: [goldPrimary.opacity(0.22), goldPrimary.opacity(0.08), goldPrimary.opacity(0.22)],
                        startPoint: .leading, endPoint: .trailing
                    )

                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(goldBright)
                        Text(l.trainerCard.uppercased())
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(goldBright)
                            .tracking(2)
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(goldBright)

                        Spacer()

                        Text("IDNo. \(data.trainerID)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(goldPrimary)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 24)

                // Fine gold divider line
                Rectangle()
                    .fill(LinearGradient(
                        colors: [goldDark.opacity(0.2), goldPrimary, goldBright, goldPrimary, goldDark.opacity(0.2)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 1)

                // ── Main Content Area ──
                HStack(alignment: .center, spacing: 10) {
                    // Left: Pokemon Cameo Frame
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            // Gold frame
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(RadialGradient(
                                    colors: [Color(red: 0.15, green: 0.16, blue: 0.40), Color(red: 0.06, green: 0.07, blue: 0.22)],
                                    center: .center, startRadius: 5, endRadius: 46
                                ))
                                .frame(width: 82, height: 82)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [goldBright, goldPrimary, goldDark],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.8
                                        )
                                )

                            SpriteView(speciesID: data.pokemonID, size: 74, animated: false, shiny: data.isShiny)
                                .frame(width: 82, height: 82)

                            if data.isShiny {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(goldBright)
                                    .padding(3)
                                    .background(Color.black.opacity(0.65), in: Circle())
                                    .offset(x: -2, y: 2)
                            }
                        }

                        Text(data.pokemonName)
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(goldBright)
                            .lineLimit(1)
                            .frame(width: 84)

                        if let sub = data.pokemonSubtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(goldPrimary.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 3))
                                .frame(width: 84)
                        }
                    }

                    // Right: Champion Header + Hall of Fame Telemetry Grid
                    VStack(alignment: .leading, spacing: 4) {
                        // Champion & Trainer
                        HStack(spacing: 4) {
                            Text("CHAMPION")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundStyle(goldDark)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(goldPrimary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

                            Text(data.trainerName)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        // 2x3 Luxury Telemetry Plaque
                        VStack(spacing: 3.5) {
                            HStack(spacing: 4) {
                                hofTile(icon: "chart.bar.fill", label: l.trainerCardLifetimeTokens, value: TokenFormatter.compact(data.totalTokens), gold: goldPrimary, bright: goldBright, dim: textDim)
                                hofTile(icon: "bolt.fill", label: l.trainerCardTodayTokens, value: TokenFormatter.compact(data.todayTokens), gold: goldPrimary, bright: goldBright, dim: textDim)
                            }
                            HStack(spacing: 4) {
                                hofTile(icon: "book.closed.fill", label: l.trainerCardPokedexLabel, value: "\(data.pokedexCount)/\(data.pokedexTotal)", gold: goldPrimary, bright: goldBright, dim: textDim)
                                hofTile(icon: "graduationcap.fill", label: l.trainerCardGraduatedLabel, value: "\(data.graduatedCount)", gold: goldPrimary, bright: goldBright, dim: textDim)
                            }
                            HStack(spacing: 4) {
                                hofTile(icon: "sparkles", label: l.trainerCardShiniesLabel, value: "\(data.shinyCount)", gold: goldPrimary, bright: goldBright, dim: textDim)
                                hofTile(icon: "suit.diamond.fill", label: l.trainerCardCasinoCoinsLabel, value: data.casinoCoins.formatted(), gold: goldPrimary, bright: goldBright, dim: textDim)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Spacer(minLength: 0)

                // Footer Line
                HStack(spacing: 4) {
                    Rectangle().fill(goldDark.opacity(0.35)).frame(height: 0.5)
                    Text("HALL OF FAME INDUCTEE")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(goldPrimary.opacity(0.6))
                        .tracking(1)
                    Rectangle().fill(goldDark.opacity(0.35)).frame(height: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // -- Pokeball watermark (Classic / Master Ball)
    private func pokeBallWatermark(stroke: Color, fill: Color) -> some View {
        ZStack {
            Circle()
                .strokeBorder(stroke, lineWidth: 10)
                .frame(width: 100, height: 100)
            Rectangle()
                .fill(stroke)
                .frame(width: 100, height: 10)
            Circle()
                .strokeBorder(fill, lineWidth: 6)
                .frame(width: 36, height: 36)
        }
    }

    // -- Trainer name row (Classic / Master Ball)
    private func trainerNameRow(primary: Color, label: Color) -> some View {
        HStack(spacing: 4) {
            Text(l.trainerCardTrainerLabel.uppercased() + ":")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(label)
            Text(data.trainerName)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    // -- Pokemon frame with name/subtitle (Classic / Master Ball)
    private func pokemonFrame(bg: Color, border: Color, nameColor: Color, subColor: Color, subBg: Color) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bg)
                    .frame(width: 86, height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(border, lineWidth: 1.5)
                    )
                SpriteView(speciesID: data.pokemonID, size: 76, animated: false, shiny: data.isShiny)
                    .frame(width: 86, height: 86)
                if data.isShiny {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(3)
                        .background(Color.black.opacity(0.60), in: Circle())
                        .offset(x: -3, y: 3)
                }
            }
            Text(data.pokemonName)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .frame(width: 86)
            if let subtitle = data.pokemonSubtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(subColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(subBg)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(width: 86)
            }
        }
    }

    // -- 2x3 stat grid with tile style (Classic / Master Ball)
    private func statsGrid(label: Color, value: Color, tileBg: Color, tileBorder: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                statTile(icon: "chart.bar.fill", label: l.trainerCardLifetimeTokens, value: TokenFormatter.compact(data.totalTokens),
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
                statTile(icon: "bolt.fill", label: l.trainerCardTodayTokens, value: TokenFormatter.compact(data.todayTokens),
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
            }
            HStack(spacing: 5) {
                statTile(icon: "book.closed.fill", label: l.trainerCardPokedexLabel, value: "\(data.pokedexCount) / \(data.pokedexTotal)",
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
                statTile(icon: "graduationcap.fill", label: l.trainerCardGraduatedLabel, value: "\(data.graduatedCount)",
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
            }
            HStack(spacing: 5) {
                statTile(icon: "sparkles", label: l.trainerCardShiniesLabel, value: "\(data.shinyCount)",
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
                statTile(icon: "suit.diamond.fill", label: l.trainerCardCasinoCoinsLabel, value: data.casinoCoins.formatted(),
                         labelColor: label, valueColor: value, bg: tileBg, border: tileBorder)
            }
        }
    }

    // -- Single tile stat (Classic / Master Ball)
    private func statTile(icon: String, label: String, value: String,
                          labelColor: Color, valueColor: Color,
                          bg: Color, border: Color) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(labelColor)
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(border, lineWidth: 0.9)
        )
    }

    // -- Game Boy compact stat line
    private func gbStatLine(_ label: String, _ value: String, ink: Color, mid: Color) -> some View {
        HStack(spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(mid)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    // -- Neon stat cell
    private func neonStatCell(_ label: String, _ value: String, accent: Color, dim: Color, bright: Color) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // -- Neon vertical divider
    private func neonDivider(_ color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.25))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // -- Team Rocket dossier field
    private func rocketField(label: String, value: String, red: Color, dim: Color, bright: Color) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(red.opacity(0.8))
            Text(value)
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(bright)
                .lineLimit(1)
        }
    }

    // -- Team Rocket compact stat
    private func rocketStat(_ label: String, _ value: String, dim: Color, bright: Color) -> some View {
        VStack(alignment: .leading, spacing: 0.5) {
            Text(label.uppercased())
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundStyle(bright)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // -- Master Ball corner stat
    private func mbCornerStat(label: String, value: String, labelColor: Color, valColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(valColor)
                .lineLimit(1)
        }
    }

    // -- Hall of Fame luxury plaque tile
    private func hofTile(icon: String, label: String, value: String, gold: Color, bright: Color, dim: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(gold)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label.uppercased())
                    .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value)
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(bright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color(red: 0.12, green: 0.14, blue: 0.36).opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(gold.opacity(0.30), lineWidth: 0.7)
        )
    }
}

// MARK: - Trainer Card Modal View

@MainActor
struct TrainerCardModalView: View {
    let store: CompanionStore
    let usageStore: UsageStore?
    let nav: PopoverNavigation
    let onClose: () -> Void

    @State private var selectedTheme: AppThemeKind
    @State private var useActiveMon: Bool = true
    @State private var selectedDexSpeciesID: Int
    @State private var showAsShiny: Bool = false
    @State private var copyFeedback: Bool = false

    // MARK: - Persistence keys
    private static let udKeyUseActiveMon = "PTB_TrainerCard_useActiveMon"
    private static let udKeySpeciesID = "PTB_TrainerCard_selectedSpeciesID"
    private static let udKeyShowAsShiny = "PTB_TrainerCard_showAsShiny"
    private static let udKeySelectedTheme = "PTB_TrainerCard_selectedTheme"

    init(
        store: CompanionStore,
        usageStore: UsageStore? = nil,
        nav: PopoverNavigation,
        initialSpeciesID: Int? = nil,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.usageStore = usageStore
        self.nav = nav
        self.onClose = onClose

        let ud = UserDefaults.standard

        if let initialSpeciesID {
            // Opened from Pokedex tap — override with explicit species
            _useActiveMon = State(initialValue: false)
            _selectedDexSpeciesID = State(initialValue: initialSpeciesID)
            _showAsShiny = State(initialValue: store.state.ownsShinySpecies(initialSpeciesID))
            _selectedTheme = State(initialValue: store.activeTheme)
        } else if ud.object(forKey: Self.udKeyUseActiveMon) != nil {
            // Restore previous session
            let savedUseActive = ud.bool(forKey: Self.udKeyUseActiveMon)
            let savedSpeciesID = ud.integer(forKey: Self.udKeySpeciesID)
            let savedShiny = ud.bool(forKey: Self.udKeyShowAsShiny)
            let savedThemeRaw = ud.string(forKey: Self.udKeySelectedTheme) ?? ""
            let savedTheme = AppThemeKind(rawValue: savedThemeRaw) ?? store.activeTheme

            _useActiveMon = State(initialValue: savedUseActive)
            _selectedDexSpeciesID = State(initialValue: savedSpeciesID > 0 ? savedSpeciesID : (store.currentSpeciesID ?? 25))
            _showAsShiny = State(initialValue: savedShiny)
            _selectedTheme = State(initialValue: savedTheme)
        } else {
            // First open ever — defaults
            let activeID = store.currentSpeciesID ?? 25
            _useActiveMon = State(initialValue: true)
            _selectedDexSpeciesID = State(initialValue: activeID)
            _showAsShiny = State(initialValue: store.currentIsShiny)
            _selectedTheme = State(initialValue: store.activeTheme)
        }
    }

    private var l: L { store.l }

    private var currentPokemonData: (pokemonID: Int?, pokemonName: String, subtitle: String?, isShiny: Bool) {
        if useActiveMon, let active = store.state.active {
            var subtitleParts: [String] = []
            if active.totalForms > 1 {
                subtitleParts.append(l.stage(active.stageIndex + 1, active.totalForms).uppercased())
            } else {
                subtitleParts.append(l.rarityLabel(active.rarity).uppercased())
            }
            if let nature = active.nature {
                subtitleParts.append(nature.name(store.language).uppercased())
            }
            let sub = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
            return (active.currentID, store.displayName, sub, active.isShiny)
        } else if let species = store.dexSpecies.first(where: { $0.id == selectedDexSpeciesID }) {
            let entry = store.state.dex.first { $0.chainOrder.contains(species.id) }
            var subtitleParts: [String] = []
            if let entry {
                subtitleParts.append(l.rarityLabel(entry.rarity).uppercased())
                if let nature = entry.nature {
                    subtitleParts.append(nature.name(store.language).uppercased())
                }
            } else {
                subtitleParts.append(l.rarityLabel(species.rarity).uppercased())
            }
            let sub = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
            return (species.id, species.name, sub, showAsShiny)
        } else {
            return (store.currentSpeciesID, store.displayName, nil, store.currentIsShiny)
        }
    }

    private var cardData: TrainerCardData {
        let mon = currentPokemonData
        let name = TrainerCardData.defaultTrainerName()
        let id = TrainerCardData.deterministicTrainerID(from: name)
        let todayTokens = usageStore?.todayTotalTokens ?? 0
        let graduated = store.state.dex.filter { !$0.isReleased }.count

        return TrainerCardData(
            trainerName: name,
            trainerID: id,
            theme: selectedTheme,
            pokemonID: mon.pokemonID,
            pokemonName: mon.pokemonName,
            pokemonSubtitle: mon.subtitle,
            isShiny: mon.isShiny,
            totalTokens: store.state.usedSinceInstall,
            todayTokens: todayTokens,
            pokedexCount: store.dexSpecies.count,
            pokedexTotal: 151,
            graduatedCount: graduated,
            shinyCount: store.state.dex.filter(\.isShiny).count + (store.currentIsShiny ? 1 : 0),
            casinoCoins: store.casinoCoins
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    cardPreviewSection
                    exportButtonsRow
                    controlsSection
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: PopoverMetrics.width)
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Label(l.back, systemImage: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.activeTheme.accentColor)

            Spacer()

            Text(l.trainerCardTitle)
                .font(.headline)

            Spacer()

            Text(l.back)
                .font(.caption)
                .opacity(0)
        }
        .padding(.horizontal, PopoverMetrics.padding)
        .padding(.top, 12)
    }

    private var cardPreviewSection: some View {
        TrainerCardView(data: cardData, l: l)
            .padding(.top, 4)
    }

    private var exportButtonsRow: some View {
        HStack(spacing: 10) {
            Button {
                copyCard()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                    Text(copyFeedback ? l.trainerCardCopied : l.trainerCardCopyImage)
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(copyFeedback ? Color.green.opacity(0.18) : store.activeTheme.accentColor.opacity(0.14))
                .foregroundStyle(copyFeedback ? Color.green : store.activeTheme.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                saveCardPNG()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                    Text(l.trainerCardSaveImage)
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PopoverMetrics.padding)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            themePickerBlock
            pokemonSourceBlock
            casinoHintBlock
        }
        .padding(PopoverMetrics.padding)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, PopoverMetrics.padding)
    }

    private var themePickerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.activeThemeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(l.activeThemeLabel, selection: $selectedTheme) {
                ForEach(AppThemeKind.allCases.filter { store.unlockedThemes.contains($0.rawValue) }, id: \.self) { theme in
                    Text(l.themeName(theme)).tag(theme)
                }
            }
            .labelsHidden()
            .accessibilityLabel(l.activeThemeLabel)
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pokemonSourceBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.trainerCardPokemonSource)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(l.trainerCardPokemonSource, selection: $useActiveMon) {
                Text(l.trainerCardActiveMon).tag(true)
                Text(l.trainerCardDexMon).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(l.trainerCardPokemonSource)

            if !useActiveMon {
                HStack(spacing: 8) {
                    Picker(l.trainerCardDexMon, selection: $selectedDexSpeciesID) {
                        ForEach(store.dexSpecies) { species in
                            Text(store.state.ownsShinySpecies(species.id) ? "\u{2605} \(species.name)" : species.name)
                                .tag(species.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(l.trainerCardDexMon)
                    .pickerStyle(.menu)
                    .onChange(of: selectedDexSpeciesID) { _, newID in
                        if store.state.ownsShinySpecies(newID) {
                            showAsShiny = true
                        } else {
                            showAsShiny = false
                        }
                        UserDefaults.standard.set(newID, forKey: Self.udKeySpeciesID)
                    }

                    let canShiny = store.state.ownsShinySpecies(selectedDexSpeciesID)
                    Toggle(isOn: $showAsShiny) {
                        Text(l.trainerCardShiny)
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!canShiny)
                    .onChange(of: showAsShiny) { _, newVal in
                        UserDefaults.standard.set(newVal, forKey: Self.udKeyShowAsShiny)
                    }
                }
            }
        }
        .onChange(of: useActiveMon) { _, newVal in
            UserDefaults.standard.set(newVal, forKey: Self.udKeyUseActiveMon)
        }
        .onChange(of: selectedTheme) { _, newVal in
            UserDefaults.standard.set(newVal.rawValue, forKey: Self.udKeySelectedTheme)
        }
    }

    @ViewBuilder
    private var casinoHintBlock: some View {
        if store.unlockedThemes.count < AppThemeKind.allCases.count {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(store.activeTheme.accentColor)
                Text(l.trainerCardCasinoHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    private func copyCard() {
        let renderer = ImageRenderer(content: TrainerCardView(data: cardData, l: l))
        renderer.scale = 3.0
        guard let image = renderer.nsImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        withAnimation(.easeInOut(duration: 0.2)) {
            copyFeedback = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) {
                copyFeedback = false
            }
        }
    }

    private func saveCardPNG() {
        let renderer = ImageRenderer(content: TrainerCardView(data: cardData, l: l))
        renderer.scale = 3.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let speciesPart = cardData.pokemonID.map(String.init) ?? "egg"
        panel.nameFieldStringValue = "trainer-card-\(speciesPart).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? pngData.write(to: url)
        }
    }
}
