import SwiftUI

// MARK: - Generic Item Sprite & Coin Icon Views

/// PokéAPI 아이템 스프라이트(캐시/런타임 페치)를 렌더링하는 뷰 (이모지 없음).
@MainActor
struct ItemNamedSpriteView: View {
    let name: String
    var size: CGFloat = 20
    var fallbackSymbol: String = "circle.inset.filled"
    @State private var img: NSImage?

    init(name: String, size: CGFloat = 20, fallbackSymbol: String = "circle.inset.filled") {
        self.name = name
        self.size = size
        self.fallbackSymbol = fallbackSymbol
        _img = State(initialValue: SpriteLoader.cachedItemImage(name: name))
    }

    var body: some View {
        Group {
            if let img {
                let fit = SpriteFit.size(for: img.size, box: size)
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.65))
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: name) {
            guard img == nil else { return }
            img = await SpriteLoader.itemImage(name: name)
        }
    }
}

/// 동전 케이스(Coin Case) 스프라이트를 사용하는 카지노 동전 아이콘.
@MainActor
struct CoinSpriteView: View {
    var size: CGFloat = 16

    var body: some View {
        ItemNamedSpriteView(name: "coin-case", size: size, fallbackSymbol: "circle.circle.fill")
    }
}

// MARK: - Main Casino View (Clean, Simple & Overflow-Proof)

/// 카지노 (Casino)
/// 깔끔한 2단 탭: [ 슬롯머신 | 경품 교환소 ]
@MainActor
struct CasinoView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    enum MainTab: Int, CaseIterable {
        case slots
        case prizes
    }

    @State private var mainTab: MainTab = .slots
    @State private var showCoinStore: Bool = false

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar: Solde de Jetons + Bouton Achat
            headerBar(l)

            // Tiroir d'achat de jetons (repliable)
            if showCoinStore {
                coinStoreSection(l)
            }

            // Navigation principale: [ Machine à sous | Comptoir des Prix ]
            Picker("", selection: $mainTab) {
                Text(l.slotMachine).tag(MainTab.slots)
                Text(l.prizeCorner).tag(MainTab.prizes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Contenu de la section
            if mainTab == .slots {
                SlotMachineView(store: store)
            } else {
                CasinoPrizeCornerView(store: store, nav: nav)
            }
        }
        .frame(maxWidth: PopoverMetrics.contentWidth, alignment: .top)
        .animation(.easeInOut(duration: 0.15), value: showCoinStore)
    }

    private func headerBar(_ l: L) -> some View {
        HStack(spacing: 8) {
            CoinSpriteView(size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(l.coinBalance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(store.casinoCoins)")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                showCoinStore.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: showCoinStore ? "chevron.up" : "plus")
                        .font(.caption2)
                    Text(l.buyCoins)
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func coinStoreSection(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.buyCoins)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(l.spendableTokens): \(TokenFormatter.compact(store.availableTokens))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(CoinPackage.all) { pkg in
                    CoinPackageTile(store: store, package: pkg)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Coin Package Tile (Clean & Compact)

@MainActor
private struct CoinPackageTile: View {
    let store: CompanionStore
    let package: CoinPackage

    private var canAfford: Bool { store.availableTokens >= package.tokenCost }

    var body: some View {
        HStack(spacing: 4) {
            CoinSpriteView(size: 13)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text("\(package.coins)")
                        .font(.caption2.weight(.bold))
                    if package.bonusPercent > 0 {
                        Text("+\(package.bonusPercent)%")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(TokenFormatter.compact(package.tokenCost))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button(store.l.buy) {
                store.buyCasinoCoins(package: package)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(!canAfford)
        }
        .padding(5)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Slot Machine View (Clean, Native & Perfectly Sized)

@MainActor
private struct SlotMachineView: View {
    let store: CompanionStore

    @State private var grid: [[SlotSymbol]] = [
        [.seven, .bar, .pikachu],
        [.cherry, .pokeBall, .jigglypuff],
        [.bar, .voltorb, .seven]
    ]
    @State private var selectedLines: Int = 5
    @State private var multiplier: Int = 1
    @State private var isSpinning: Bool = false
    @State private var lastResult: SlotResult? = nil
    @State private var newlyUnlockedTheme: AppThemeKind? = nil
    @State private var showPayouts: Bool = false

    private var baseCoins: Int {
        switch selectedLines {
        case 1: return 1
        case 3: return 2
        default: return 3
        }
    }

    private var totalCost: Int { baseCoins * multiplier }
    private var canSpin: Bool { store.casinoCoins >= totalCost && !isSpinning }

    var body: some View {
        let l = store.l
        VStack(spacing: 8) {
            // Theme Celebration Toast
            if let wonTheme = newlyUnlockedTheme {
                HStack(spacing: 6) {
                    ItemNamedSpriteView(name: wonTheme.itemSprite, size: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(l.newThemeUnlocked) \(l.themeName(wonTheme))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.yellow)
                        Text(l.themeRarityLabel(wonTheme))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(wonTheme.rarityColor)
                    }
                    Spacer()
                    Button(l.themeApplyAction) {
                        store.setActiveTheme(wonTheme)
                        newlyUnlockedTheme = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Win Toast
            if let res = lastResult, res.totalWin > 0 {
                HStack(spacing: 4) {
                    if res.isJackpot {
                        Text(l.jackpotWin)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("+" + String(res.totalWin))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                        CoinSpriteView(size: 11)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(res.isJackpot ? Color.yellow.opacity(0.2) : Color.green.opacity(0.12))
                .clipShape(Capsule())
            }

            // 3x3 Reels (Clean & centered)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { col in
                            SlotCellTile(
                                symbol: grid[row][col],
                                isHighlighted: isCellInWinningLine(row: row, col: col)
                            )
                        }
                    }
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Betting Controls: Lines & Multipliers
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(l.paylinesCount)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedLines) {
                        Text("1").tag(1)
                        Text("3").tag(3)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 80)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(l.multiplierLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $multiplier) {
                        Text("×1").tag(1)
                        Text("×5").tag(5)
                        Text("×10").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
            .padding(.horizontal, 2)

            // Spin Action Button
            Button {
                spinReels()
            } label: {
                HStack(spacing: 5) {
                    if isSpinning {
                        ProgressView().controlSize(.small)
                        Text(l.spinning)
                            .font(.caption.weight(.semibold))
                    } else {
                        Text(l.spinReels)
                            .font(.caption.weight(.semibold))
                        Text("(\(totalCost)")
                            .font(.caption2)
                        CoinSpriteView(size: 11)
                        Text(")")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canSpin)

            // Payouts Disclosure
            DisclosureGroup(isExpanded: $showPayouts) {
                payoutsSummaryView(l)
            } label: {
                Text(l.payoutTable)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func isCellInWinningLine(row: Int, col: Int) -> Bool {
        guard let lines = lastResult?.winningLines else { return false }
        for line in lines {
            switch line {
            case 0: if row == 1 { return true }
            case 1: if row == 0 { return true }
            case 2: if row == 2 { return true }
            case 3: if row == col { return true }
            case 4: if row == (2 - col) { return true }
            default: break
            }
        }
        return false
    }

    private func spinReels() {
        guard store.spendCasinoCoins(totalCost) else { return }
        isSpinning = true
        lastResult = nil
        newlyUnlockedTheme = nil

        Task {
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 60_000_000)
                grid = [
                    [SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!],
                    [SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!],
                    [SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!, SlotSymbol.allCases.randomElement()!]
                ]
            }

            let result = SlotMachineEngine.spin(
                lines: selectedLines,
                multiplier: multiplier,
                currentUnlocked: store.unlockedThemes
            )
            grid = result.grid
            lastResult = result

            if result.totalWin > 0 {
                store.addCasinoCoins(result.totalWin)
            }

            if let wonTheme = result.unlockedTheme {
                store.unlockCasinoTheme(wonTheme)
                newlyUnlockedTheme = wonTheme
            }

            isSpinning = false
        }
    }

    private func payoutsSummaryView(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                payoutEntry("777", "300×")
                payoutEntry("BAR", "100×")
                HStack(spacing: 2) {
                    SpriteView(speciesID: 39, size: 14)
                    Text("30×").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                    Image(systemName: "sparkles")
                        .font(.system(size: 7))
                        .foregroundStyle(.purple)
                }
                HStack(spacing: 2) {
                    ItemNamedSpriteView(name: "cheri-berry", size: 12)
                    Text("25×").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
                HStack(spacing: 2) {
                    SpriteView(speciesID: 25, size: 14)
                    Text("20×").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
                HStack(spacing: 2) {
                    ItemNamedSpriteView(name: "poke-ball", size: 12)
                    Text("10×").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 3) {
                ItemNamedSpriteView(name: "cheri-berry", size: 10)
                Text(l.twoCherriesWinHint)
                Text("·")
                Text(l.slotThemeRollHint)
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func payoutEntry(_ label: String, _ mult: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold))
            Text(mult).font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
        }
    }
}

// MARK: - Slot Cell Tile

@MainActor
private struct SlotCellTile: View {
    let symbol: SlotSymbol
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            switch symbol.visual {
            case .text(let txt):
                Text(txt)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(txt == "777" ? Color.red : Color.primary)
            case .pokemon(let speciesID):
                SpriteView(speciesID: speciesID, size: 28, animated: false)
            case .item(let itemName):
                ItemNamedSpriteView(name: itemName, size: 24)
            }
        }
        .frame(width: 44, height: 40)
        .background(isHighlighted ? Color.yellow.opacity(0.2) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.yellow : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Prize Corner View (Consistent with ShopItemCard style)

@MainActor
private struct CasinoPrizeCornerView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            // Porygon (Featured)
            if let porygonItem = CasinoPrizeItem.all.first(where: { $0.speciesID == 137 }) {
                PorygonFeatureCard(store: store, item: porygonItem)
            }

            // Star Prism
            if let starPrism = CasinoPrizeItem.all.first(where: { $0.isStarPrism }) {
                StarPrismPrizeCard(store: store, item: starPrism)
            }

            // Rare Pokémon
            VStack(alignment: .leading, spacing: 4) {
                Text(l.rarePokemon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                let rareMons = CasinoPrizeItem.all.filter { $0.speciesID != nil && $0.speciesID != 137 }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(rareMons) { item in
                        CasinoPokemonCard(store: store, item: item)
                    }
                }
            }

            // App Themes
            VStack(alignment: .leading, spacing: 4) {
                Text(l.appThemesSection)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(l.slotThemeRollHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                VStack(spacing: 3) {
                    ForEach(AppThemeKind.allCases, id: \.self) { theme in
                        ThemeRowTile(store: store, theme: theme)
                    }
                }
            }
        }
    }
}

// MARK: - Porygon Feature Card

@MainActor
private struct PorygonFeatureCard: View {
    let store: CompanionStore
    let item: CasinoPrizeItem
    @State private var confirming = false

    private var canAfford: Bool { store.casinoCoins >= item.coinCost }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                SpriteView(speciesID: 137, size: 36, animated: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.casinoPrizeSpeciesName(137))
                            .font(.callout.weight(.semibold))
                        Text(l.casinoExclusiveBadge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(l.exclusivePokemonHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack {
                HStack(spacing: 3) {
                    Text(l.shopPriceLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    CoinSpriteView(size: 13)
                    Text("\(item.coinCost)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()

                if confirming {
                    HStack(spacing: 4) {
                        Button(l.exchangeAction) {
                            store.buyCasinoPokemon(speciesID: 137, coinCost: item.coinCost)
                            confirming = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(l.cancel) { confirming = false }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                } else {
                    Button(l.exchangeAction) { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canAfford)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Star Prism Prize Card

@MainActor
private struct StarPrismPrizeCard: View {
    let store: CompanionStore
    let item: CasinoPrizeItem
    @State private var confirming = false

    private var canAfford: Bool { store.casinoCoins >= item.coinCost }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ItemNamedSpriteView(name: "bright-powder", size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(.starPrism))
                            .font(.callout.weight(.semibold))
                        let owned = store.itemCount(.starPrism)
                        if owned > 0 {
                            Text(l.ownedCount(owned))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(l.itemDescription(.starPrism))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack {
                HStack(spacing: 3) {
                    Text(l.shopPriceLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    CoinSpriteView(size: 13)
                    Text("\(item.coinCost)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()

                if confirming {
                    HStack(spacing: 4) {
                        Button(l.exchangeAction) {
                            store.buyStarPrism()
                            confirming = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(l.cancel) { confirming = false }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                } else {
                    Button(l.exchangeAction) { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canAfford)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Casino Pokemon Card (Abra, Dratini, Scyther, Cleffa)

@MainActor
private struct CasinoPokemonCard: View {
    let store: CompanionStore
    let item: CasinoPrizeItem
    @State private var confirming = false

    private var canAfford: Bool { store.casinoCoins >= item.coinCost }

    var body: some View {
        let l = store.l
        let speciesID = item.speciesID ?? 1
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SpriteView(speciesID: speciesID, size: 28, animated: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.casinoPrizeSpeciesName(speciesID))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 2) {
                        CoinSpriteView(size: 10)
                        Text("\(item.coinCost)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                if confirming {
                    HStack(spacing: 2) {
                        Button(l.exchangeAction) {
                            store.buyCasinoPokemon(speciesID: speciesID, coinCost: item.coinCost)
                            confirming = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button(action: { confirming = false }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                    }
                } else {
                    Button(l.exchangeAction) { confirming = true }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(!canAfford)
                }
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Theme Row Tile (Showcase & Apply)

@MainActor
private struct ThemeRowTile: View {
    let store: CompanionStore
    let theme: AppThemeKind

    private var isUnlocked: Bool { store.unlockedThemes.contains(theme.rawValue) }
    private var isActive: Bool { store.activeTheme == theme }

    var body: some View {
        let l = store.l
        HStack(spacing: 8) {
            ItemNamedSpriteView(name: theme.itemSprite, size: 20)

            HStack(spacing: 5) {
                Text(l.themeName(theme))
                    .font(.caption.weight(.semibold))

                if theme != .classic {
                    Text(l.themeRarityLabel(theme))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.rarityColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(theme.rarityColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: 2) {
                    Circle().fill(theme.accentColor).frame(width: 5, height: 5)
                    Circle().fill(theme.secondaryAccentColor).frame(width: 5, height: 5)
                }
            }

            Spacer(minLength: 4)

            if isUnlocked {
                if isActive {
                    Text(l.themeApplied)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Button(l.themeApplyAction) {
                        store.setActiveTheme(theme)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isActive ? theme.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
