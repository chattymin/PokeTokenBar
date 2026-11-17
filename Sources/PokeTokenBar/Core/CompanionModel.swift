import Foundation

/// 표시 상태 — 사용량/burn 으로 결정(스프라이트 모션 강도·상태 문구).
enum CompanionStateKind: String, Sendable {
    case egg, idle, working, focus, tired, sleep, levelUp
}

/// 앱 언어. 포켓몬 이름은 PokéAPI 다국어 names 에서 가져온다.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja, es, fr, pt, de, ru
    /// PokéAPI language.name 후보(첫 매칭 사용)
    var apiCodes: [String] {
        switch self {
        case .ko: return ["ko"]
        case .en: return ["en"]
        case .ja: return ["ja-hrkt", "ja"]
        case .es: return ["es"]
        case .fr: return ["fr"]
        case .pt: return ["pt-br", "pt"]
        case .de: return ["de"]
        // 공식 러시아어 이름(Пикачу·Иви 등)은 있지만 PokéAPI 에 ru 데이터가 아직 없어 지금은 영어로 폴백된다 —
        // 데이터 부재에 따른 임시 범위이지 러시아의 표기 관행이 아니다. PokéAPI 가 ru 를 제공하면 그대로 쓰인다.
        case .ru: return ["ru"]
        }
    }
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語"; case .es: return "Español"; case .fr: return "Français"; case .pt: return "Português"; case .de: return "Deutsch"; case .ru: return "Русский" }
    }

    var displayLocale: Locale { Locale(identifier: rawValue) }

    /// byLang(langCode→name) 에서 이 언어의 이름을 고른다(apiCodes 첫 매칭 → 영어 폴백).
    func resolveName(_ byLang: [String: String]) -> String? {
        PokemonNameLocalization.resolve(byLang, preferredCodes: apiCodes)
    }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추(글로벌 출시: 한국어 강제 금지).
    /// ko/ja/es/fr/pt/de/ru 만 매칭, 그 외 전부 영어(fallback-of-fallback). 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        systemDefault(for: Locale.preferredLanguages.first)
    }

    /// 시스템 언어 매핑의 순수 판정 — 실제 환경을 바꾸지 않고 locale 분기를 검증할 수 있게 분리한다.
    static func systemDefault(for preferredLanguage: String?) -> AppLanguage {
        switch preferredLanguage?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        case "es": return .es
        case "fr": return .fr
        case "pt": return .pt
        case "de": return .de
        case "ru": return .ru
        default:   return .en
        }
    }
}

/// 희귀도 — PokéAPI capture_rate / is_legendary 로 판정.
enum Rarity: String, Codable, Sendable {
    case common, uncommon, rare, legendary
    /// 등급 크기(높을수록 희귀) — 두 `Rarity` 를 비교하기 위한 순위.
    /// **목록 정렬용이 아니다**: 포획 로그는 기록 시각순, 도감은 도감 번호순이고 희귀도는 필터로만 좁힌다.
    /// 유일한 소비자는 프리미엄 알의 보증 관문(`hatch` 의 `line.rarity.sortRank < tier.sortRank`) —
    /// 뽑힌 등급이 산 보증보다 낮은지 판정한다. 순서가 뒤집히면 고급/희귀 알이 조용히 낮은 등급을
    /// 통과시키므로 `testSortRankOrdersRarityAscendingByValue` 가 순서를 고정한다.
    var sortRank: Int {
        switch self {
        case .common:    return 0
        case .uncommon:  return 1
        case .rare:      return 2
        case .legendary: return 3
        }
    }
    /// 이 등급의 capture_rate 상한 — 이 값 이하면 그 종은 이 등급 **이상**이다.
    /// `from(captureRate:…)` 의 분류 임계이자, 프리미엄 알이 부화 후보를 미리 거르는 기준이다.
    /// 두 곳에 임계를 따로 적으면 한쪽만 바뀌었을 때 등급 보증이 조용히 깨지므로 **여기가 단일 소스**다.
    ///
    /// nil = a tier capture_rate cannot express: legendaries are told by `is_legendary`/`is_mythical` only. Most have
    /// a capture_rate of 45 or less, but Necrozma, Eternatus and Terapagos have 255 (scripted catches in the games),
    /// so a tier egg admits a base by its legendary flag first (`admits`), not by its capture_rate alone.
    var captureRateCeiling: Int? {
        switch self {
        case .rare:      return 45
        case .uncommon:  return 120
        case .common:    return 255
        case .legendary: return nil
        }
    }
    /// capture_rate 가 이 등급 이상을 뜻하는지 — 전설은 capture_rate 로 판정할 수 없어 항상 false.
    func includes(captureRate: Int) -> Bool {
        guard let ceiling = captureRateCeiling else { return false }
        return captureRate <= ceiling
    }
    /// Whether a tier egg can hatch this base: one of its rarity or better, the rarity the card shows
    /// (`BaseSpecies.rarity`: legendaries by their flag, the others by capture rate).
    func admits(_ species: BaseSpecies) -> Bool {
        species.rarity.sortRank >= sortRank
    }
    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Rarity {
        if isLegendary || isMythical { return .legendary }
        if Rarity.rare.includes(captureRate: captureRate) { return .rare }
        if Rarity.uncommon.includes(captureRate: captureRate) { return .uncommon }
        return .common
    }
}

/// 토큰 경제 — 실측 평균(~253M/일) 기준.
/// 졸업 총량 T 는 같은 희귀도면 진화 단계 수와 무관하게 동일.
/// 형태 k개 라인에서 i번째 형태 성장 비용 = T·i / (k(k+1)/2) → 합 = T, 단계↑일수록 비용↑.
enum PokemonBalance {
    /// 알 부화 임계 — 이만큼 토큰을 써야 알이 깨진다(즉시 부화 대신 기대감). 초과분은 부화체 성장에 이월.
    static let eggHatchThreshold = 5_000_000
    /// A legendary boss's egg's Pokémon graduates for 200M tokens at the one difficulty (×0.1), a third of a legendary's
    /// 600M: its boss was fought already (the owner, 2026-11-05). It hatches as any egg.
    static let legendaryBossGraduationTotal = 2_000_000_000
    static let repeatGrowthMultiplier = 2

    static func graduationTotal(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common:    return    750_000_000
        case .uncommon:  return  1_875_000_000
        case .rare:      return  3_000_000_000
        case .legendary: return  6_000_000_000
        }
    }
    /// stageIndex(0-based)에서 다음 단계/졸업까지 필요한 토큰.
    static func phaseThreshold(rarity: Rarity, totalForms k: Int, stageIndex: Int,
                               growthMultiplier: Int = 1) -> Int {
        phaseThreshold(total: graduationTotal(rarity), totalForms: k, stageIndex: stageIndex, growthMultiplier: growthMultiplier)
    }
    /// The same for a whole growth of `total` tokens (`MonState.graduationTotal`).
    static func phaseThreshold(total graduation: Int, totalForms k: Int, stageIndex: Int,
                               growthMultiplier: Int = 1) -> Int {
        let kk = max(1, k)
        let i = stageIndex + 1                         // 1-based
        let total = Double(graduation)
        let denom = Double(kk * (kk + 1)) / 2.0
        let standardThreshold = Int((total * Double(i) / denom).rounded())
        return max(1, Int((Double(standardThreshold) / Double(max(1, growthMultiplier))).rounded()))
    }

    // MARK: Difficulty

    /// The balance every player has: thresholds and prices at a tenth of the tables above, Rare Candies at their full
    /// EXP. It used to be two Settings sliders, from 10% to 200%; the players had all set both to the lowest, so it is
    /// the one value now.
    static let difficulty: Double = 0.1

    /// A table value at the difficulty, for thresholds and prices. **The tables themselves are not scaled**: the tier
    /// eggs' prices derive from the ratios of `graduationTotal` (FreshEgg.price).
    static func scaled(_ base: Int, by difficulty: Double = difficulty) -> Int {
        Int((Double(base) * difficulty).rounded())
    }
}

/// 인벤토리 아이템 종류 — 확장 대비 enum(현재 이상한 사탕 1종). rawValue 로 CompanionState.inventory 에 저장.
enum ItemKind: String, Codable, Sendable, CaseIterable {
    case rareCandy
    case mint
    case shinyCharm
    case leafStone
    case fireStone
    case waterStone
    case thunderStone
    case sunStone
    case moonStone
    case duskStone
    case iceStone
    case dawnStone
    case shinyStone
    case legendCharm
    case silverWing
    case oldSeaMap
    case clearBell
    case rainbowWing
    case magmaStone
    case soulDew
    case jadeOrb
    case gracidea
    case griseousOrb
    case libertyPass
    case revealGlass
    case dnaSplicers
    case zygardeCube
    case prisonBottle
    case sparklingStone
    case sunFlute
    case beastBall
    case rustedSword
    case reinsOfUnity
    case boosterEnergy
    case tealMask
    case teraOrb
    case relicStatue
    case lunarWing
    case meteorite
    case oaksLetter
    case seaIncense
    case shockDrive
    case zRing
    case scrollOfDarkness
    case relicVase
    /// Every species of the explorers of the depths graduated (`SpeciesGoal.explorers`): every few Pokémon graduated
    /// dig up a treasure (`ExplorerKit`).
    case explorerKit
    /// Arceus's achievement: claiming it puts a Rare Egg and an Uncommon Egg in the Bag, not the Plate itself.
    case legendPlate
    /// The forms achievements (`ItemUnlock.forms`): every form of one species graduated. The Rotom Catalog stays and
    /// pays a Rare Candy for each Pokémon hatched in a form its line never had; the others put candies or eggs in
    /// the Bag, as the Legend Plate does.
    case rotomCatalog, cometShard, redNectar, smoothRock, sawsbuckSeasons, fairyFeather, furfrouTrims
    case vivillonPatterns, whippedDream, unownLetters
    /// The excavation (`FossilDig`): a Fossil Egg for every few Rock-type Pokémon graduated, one dig per fossil line.
    case excavation
    /// Every fossil line graduated: a Pokémon sent off for an egg gives part of its stage's EXP to the one that hatches
    /// (`CollectorBonus.oldAmberKeptPercent`).
    case oldAmber
    /// What a dig gives: it hatches a fossil line not graduated yet, at random.
    case fossilEgg
    case typeNullEgg
    /// The reward for each region whose every species is in the Pokédex: an egg that hatches a legendary or mythical
    /// Pokémon.
    case legendaryEgg
    /// The reward for every one of Pikachu's costumes: Rare Eggs and Rare Candies (it used to speed up Pikachu's line,
    /// which a player holding every costume no longer raises).
    case lightBall
    /// The birthday gift (`BirthdayGift`): an egg whose hatch is a surprise, a mythical Pokémon not graduated yet.
    case birthdayEgg
    /// The Shop's eggs, kept in the Bag until used: no guarantee, Uncommon or better, Rare or better. The Legend
    /// Plate and the forms achievements give the last two too.
    case pokemonEgg
    case uncommonEgg
    case rareEgg
    /// The eggs of the year's events (`EventEgg`), claimed from a banner.
    case newYearEgg, valentineEgg, pokemonDayEgg, easterEgg, halloweenEgg, christmasEgg, companionEgg
    case springEgg, summerEgg, autumnEgg, winterEgg
    case ovalCharm
    case glimmeringCharm
    /// The rewards for Tauros's four breeds and Necrozma's four forms (the owner, 2026-11-05): a complete line weighs
    /// less in every egg, Tauros's by one step, Necrozma's by two (`HatchDraw.completeLineDivisor`).
    case taurosBreeds, necrozmaForms
    /// #135 (the owner, 2026-11-06: an achievement for every species of three forms or more, items as rewards): each
    /// puts eggs or candies in the Bag, as the Sawsbuck's seasons do (`moreFormsSpecies`).
    case deoxysFormes, wormadamCloaks, darmanitanModes, kyuremFusions, genesectDrives, gourgeistSizes, zygardeFormes
    case lycanrocForms, cramorantForms, calyrexSteeds, squawkabillyPlumages, tatsugiriForms, ogerponMasks, terapagosForms
    case boulderBadge
    case cascadeBadge
    case thunderBadge
    case rainbowBadge
    case soulBadge
    case marshBadge
    case volcanoBadge
    case earthBadge
    case zephyrBadge
    case hiveBadge
    case plainBadge
    case fogBadge
    case stormBadge
    case mineralBadge
    case glacierBadge
    case risingBadge
    case darkBadge
    case fairyBadge
    /// The dungeons' items (Q23, Q24, R12). Great and Ultra Balls raise a boss's capture odds (×1.5, ×2), a Master
    /// Ball makes it sure; berries are eaten in battle, Revives raise the knocked out between battles; Capsules raise IVs; a Treasure Map opens the Ruins of Alph once; an Explorer's
    /// Chest gives an Explorer Kit treasure; a Legendary Key opens a T4 dungeon (R10).
    case greatBall, ultraBall, masterBall, oranBerry, sitrusBerry, revive, maxRevive
    case silverCapsule, goldCapsule, treasureMap, explorerChest, legendaryKey
    /// The Dungeons achievements (Q32), one per tier: a dungeon won once, then the whole tier (`DungeonMedals`).
    case discoveryMedal, adventureMedal, expertMedal, legendsMedal, originMedal
    /// The battle forms won, in steps (`BattleFormsMedal`, 2026-11-02).
    case battleFormsMedal
    /// The costumed Pokémon collected, in steps, and the monthly lots completed (`CostumeMedals`, 2026-11-13).
    case costumeMedal, costumeLotsMedal

    var badgeType: PokemonType? {
        switch self {
        case .boulderBadge: return .rock
        case .cascadeBadge: return .water
        case .thunderBadge: return .electric
        case .rainbowBadge: return .grass
        case .soulBadge:    return .poison
        case .marshBadge:   return .psychic
        case .volcanoBadge: return .fire
        case .earthBadge:   return .ground
        case .zephyrBadge:  return .flying
        case .hiveBadge:    return .bug
        case .plainBadge:   return .normal
        case .fogBadge:     return .ghost
        case .stormBadge:   return .fighting
        case .mineralBadge: return .steel
        case .glacierBadge: return .ice
        case .risingBadge:  return .dragon
        case .darkBadge:    return .dark
        case .fairyBadge:   return .fairy
        default:            return nil
        }
    }

    /// 진화의 돌이 보증하는 포켓몬 타입. nil = 돌이 아님.
    var stoneType: PokemonType? {
        switch self {
        case .leafStone:    return .grass
        case .fireStone:    return .fire
        case .waterStone:   return .water
        case .thunderStone: return .electric
        case .sunStone:     return .psychic
        case .moonStone:    return .fairy
        case .duskStone:    return .dark
        case .iceStone:     return .ice
        case .dawnStone:    return .fighting
        case .shinyStone:   return .dragon
        default:            return nil
        }
    }

    /// PokéAPI 아이템 스프라이트 파일명(.../sprites/items/{name}.png 또는 badge-{id}). nil = 스프라이트 없음.
    /// The species each #135 forms achievement asks every form of, a final one: those that evolve show their forms
    /// as finals only (Meowth's and Basculin's do not, so they have none).
    var moreFormsSpecies: Int? {
        switch self {
        case .deoxysFormes: 386
        case .wormadamCloaks: 413
        case .darmanitanModes: 555
        case .kyuremFusions: 646
        case .genesectDrives: 649
        case .gourgeistSizes: 711
        case .zygardeFormes: 718
        case .lycanrocForms: 745
        case .cramorantForms: 845
        case .calyrexSteeds: 898
        case .squawkabillyPlumages: 931
        case .tatsugiriForms: 978
        case .ogerponMasks: 1017
        case .terapagosForms: 1024
        default: nil
        }
    }

    /// A #135 achievement's rewards: a legendary's, harder to hatch again, a Rare Egg and five Rare Candies; four
    /// forms an Uncommon Egg, as the Sawsbuck's seasons; three, three Rare Candies, as the Red Nectar.
    static func moreFormsRewards(species: Int) -> [(kind: ItemKind, count: Int)] {
        if SpeciesInfo.all[species]?.isLegendary == true { return [(.rareEgg, 1), (.rareCandy, 5)] }
        return PokemonForm.forms(speciesID: species).count >= 4 ? [(.uncommonEgg, 1)] : [(.rareCandy, 3)]
    }

    var spriteName: String? {
        if let badgeType { return badgeType.badgeSpriteName }
        // A #135 achievement shows what it gives: its egg is drawn, its candies are the candy's sprite.
        if let species = moreFormsSpecies {
            return Self.moreFormsRewards(species: species).contains { $0.kind.isEggItem } ? nil : "rare-candy"
        }
        switch self {
        case .rareCandy: return "rare-candy"
        case .mint: return "mental-herb"
        case .shinyCharm: return "shiny-charm"
        case .legendCharm: return "azure-flute"
        case .silverWing: return "silver-wing"
        case .oldSeaMap: return "old-sea-map"
        case .clearBell: return "clear-bell"
        case .rainbowWing: return "rainbow-wing"
        case .magmaStone: return "magma-stone"
        case .soulDew: return "soul-dew"
        case .jadeOrb: return "jade-orb"
        case .gracidea: return "gracidea"
        case .griseousOrb: return "griseous-orb"
        case .libertyPass: return "liberty-pass"
        case .revealGlass: return "reveal-glass"
        case .dnaSplicers: return "dna-splicers"
        case .zygardeCube: return "zygarde-cube"
        case .prisonBottle: return "prison-bottle"
        case .sparklingStone: return "sparkling-stone"
        case .sunFlute: return "sun-flute"
        case .beastBall: return "beast-ball"
        case .rustedSword: return "rusted-sword"
        case .reinsOfUnity: return "reins-of-unity"
        case .boosterEnergy: return "booster-energy"
        case .tealMask: return "teal-mask"
        case .teraOrb: return "tera-orb"
        case .relicStatue: return "relic-statue"
        case .lunarWing: return "lunar-wing"
        case .meteorite: return "meteorite"
        case .oaksLetter: return "oaks-letter"
        case .seaIncense: return "sea-incense"
        case .shockDrive: return "shock-drive"
        case .zRing: return "z-ring"
        case .scrollOfDarkness: return "scroll-of-darkness"
        case .relicVase: return "relic-vase"
        case .explorerKit: return "explorer-kit"
        case .oldAmber: return "old-amber"
        case .legendPlate: return "legend-plate"
        case .rotomCatalog: return "rotom-catalog"
        case .cometShard: return "comet-shard"
        case .redNectar: return "red-nectar"
        case .smoothRock: return "smooth-rock"
        case .fairyFeather: return "fairy-feather"
        case .whippedDream: return "whipped-dream"
        case .excavation: return "helix-fossil"
        case .greatBall: return "great-ball"
        case .ultraBall: return "ultra-ball"
        case .masterBall: return "master-ball"
        case .oranBerry: return "oran-berry"
        case .sitrusBerry: return "sitrus-berry"
        case .revive: return "revive"
        case .maxRevive: return "max-revive"
        case .silverCapsule: return "bottle-cap"
        case .goldCapsule: return "gold-bottle-cap"
        case .legendaryKey: return "secret-key"
        case .lightBall: return "light-ball"
        case .typeNullEgg: return "mystery-egg"
        case .ovalCharm: return "oval-charm"
        case .glimmeringCharm: return "glimmering-charm"
        case .leafStone: return "leaf-stone"
        case .fireStone: return "fire-stone"
        case .waterStone: return "water-stone"
        case .thunderStone: return "thunder-stone"
        case .sunStone: return "sun-stone"
        case .moonStone: return "moon-stone"
        case .duskStone: return "dusk-stone"
        case .iceStone: return "ice-stone"
        case .dawnStone: return "dawn-stone"
        case .shinyStone: return "shiny-stone"
        default: return nil
        }
    }
    /// 스프라이트 로딩 전/미제공/실패 시 폴백 기호.
    var fallbackEmoji: String {
        if let species = moreFormsSpecies {
            return Self.moreFormsRewards(species: species).contains { $0.kind.isEggItem } ? "🥚" : "🍬"
        }
        switch self {
        case .rareCandy: return "🍬"
        case .mint: return "🌿"
        case .shinyCharm: return "✨"
        case .legendCharm: return "🪈"
        case .silverWing: return "🪶"
        case .oldSeaMap: return "🗺️"
        case .clearBell: return "🔔"
        case .rainbowWing: return "🌈"
        case .magmaStone: return "🌋"
        case .soulDew: return "💧"
        case .jadeOrb: return "🟢"
        case .gracidea: return "🌸"
        case .griseousOrb: return "🔮"
        case .libertyPass: return "🎟️"
        case .revealGlass: return "🪞"
        case .dnaSplicers: return "🧬"
        case .zygardeCube: return "🟩"
        case .prisonBottle: return "🏺"
        case .sparklingStone: return "💎"
        case .sunFlute: return "☀️"
        case .beastBall: return "🔵"
        case .rustedSword: return "🗡️"
        case .reinsOfUnity: return "🐎"
        case .boosterEnergy: return "⚡"
        case .tealMask: return "🎭"
        case .teraOrb: return "💠"
        case .relicStatue: return "🗿"
        case .lunarWing: return "🌙"
        case .meteorite: return "☄️"
        case .oaksLetter: return "✉️"
        case .seaIncense: return "🌊"
        case .shockDrive: return "💿"
        case .zRing: return "💍"
        case .scrollOfDarkness: return "📜"
        case .relicVase: return "⚱️"
        case .explorerKit: return "🧰"
        case .oldAmber: return "🟠"
        case .legendPlate: return "🌌"
        case .rotomCatalog: return "📖"
        case .cometShard: return "☄️"
        case .redNectar: return "🌺"
        case .smoothRock: return "🪨"
        case .fairyFeather: return "🪶"
        case .whippedDream: return "🍰"
        case .sawsbuckSeasons, .furfrouTrims, .vivillonPatterns, .unownLetters, .fossilEgg: return "🥚"
        case .excavation: return "🦴"
        case .typeNullEgg, .legendaryEgg, .birthdayEgg, .pokemonEgg, .uncommonEgg, .rareEgg, .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg: return "🥚"
        case .lightBall: return "⚡"
        case .greatBall: return "🔵"
        case .ultraBall: return "🟡"
        case .masterBall: return "🟣"
        case .oranBerry: return "🫐"
        case .sitrusBerry: return "🍋"
        case .revive, .maxRevive: return "💎"
        case .silverCapsule: return "🥈"
        case .goldCapsule: return "🥇"
        case .treasureMap: return "🗺️"
        case .explorerChest: return "🧰"
        case .legendaryKey: return "🗝️"
        case .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal, .battleFormsMedal: return "🏅"
        case .costumeMedal, .costumeLotsMedal: return "🎭"
        case .ovalCharm: return "🔶"
        case .taurosBreeds: return "🐂"
        case .necrozmaForms: return "💠"
        case .glimmeringCharm: return "✨"
        case .boulderBadge, .cascadeBadge, .thunderBadge, .rainbowBadge,
             .soulBadge, .marshBadge, .volcanoBadge, .earthBadge,
             .zephyrBadge, .hiveBadge, .plainBadge, .fogBadge,
             .stormBadge, .mineralBadge, .glacierBadge, .risingBadge,
             .darkBadge, .fairyBadge,
             .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .duskStone, .iceStone, .dawnStone, .shinyStone:
            return "★"
        // Answered above (`moreFormsSpecies`).
        case .deoxysFormes, .wormadamCloaks, .darmanitanModes, .kyuremFusions, .genesectDrives, .gourgeistSizes, .zygardeFormes,
             .lycanrocForms, .cramorantForms, .calyrexSteeds, .squawkabillyPlumages, .tatsugiriForms, .ogerponMasks, .terapagosForms:
            return "🥚"
        }
    }
    /// Items taken out of the game without deleting them: neither sold nor shown in the Bag, while a save keeps
    /// what it holds. None now: the Mint went on 2026-10-28 and came back on 2026-11-09, for the graduated Pokémon.
    var isRetired: Bool { false }

    /// 상점 판매가(재화 = 사용한 토큰). nil = 상점 미판매(업적 보상).
    var shopPrice: Int? {
        switch self {
        case .rareCandy: return RareCandy.price
        case .mint: return Mint.price
        case .shinyCharm: return ShinyCharm.price
        // The Master Ball is never sold. The balls came down on 2026-11-13 (the owner: "la hyper ball est trop chère
        // elle devrait être à 150M"; then 75M for the Great Ball, half): 150M and 75M as the players see them (×0.1),
        // 400M and 250M before, the Rare and Uncommon Eggs' prices.
        case .greatBall: return 750_000_000
        case .ultraBall: return 1_500_000_000
        default: return nil
        }
    }

    /// The dungeons' items: found in dungeons (the two balls sold too), never an achievement.
    var isDungeonItem: Bool {
        switch self {
        case .greatBall, .ultraBall, .masterBall, .oranBerry, .sitrusBerry, .revive, .maxRevive,
             .silverCapsule, .goldCapsule, .treasureMap, .explorerChest, .legendaryKey: true
        // On a graduated Pokémon like the Capsules, and found in the chests from T2 (the owner, 2026-11-09).
        case .mint: true
        default: false
        }
    }
    /// 보유형(패시브) 아이템 — 소비하지 않고 보유하는 동안 상시 효과. 1회 구매(재구매 불가), 가방엔 "적용 중" 표시.
    var isPassive: Bool {
        if moreFormsSpecies != nil { return false }
        switch self {
        case .rareCandy, .mint,
             .typeNullEgg, .legendaryEgg, .birthdayEgg, .pokemonEgg, .uncommonEgg, .rareEgg, .legendPlate, .lightBall,
             .excavation, .fossilEgg,
             .cometShard, .redNectar, .smoothRock, .sawsbuckSeasons, .fairyFeather, .furfrouTrims, .vivillonPatterns, .whippedDream, .unownLetters,
             .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg,
             .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .duskStone, .iceStone, .dawnStone, .shinyStone,
             .greatBall, .ultraBall, .masterBall, .oranBerry, .sitrusBerry, .revive, .maxRevive,
             .silverCapsule, .goldCapsule, .treasureMap, .explorerChest, .legendaryKey,
             .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal, .battleFormsMedal,
             .costumeMedal, .costumeLotsMedal:
            return false
        default:
            return true
        }
    }

    /// Whether this item is claimed as an achievement rather than bought in the shop.
    var isAchievement: Bool { collectorGroup != nil }

    /// How many of this item one claim of its achievement adds to the Bag.
    var achievementRewardCount: Int { stoneType != nil ? EvolutionStone.achievementReward : 1 }

    /// What one claim of this achievement puts in the Bag: the item itself, or for Arceus's Legend Plate and most
    /// forms achievements, candies and eggs.
    var achievementRewards: [(kind: ItemKind, count: Int)] {
        if let species = moreFormsSpecies { return Self.moreFormsRewards(species: species) }
        switch self {
        case .legendPlate: return [(.rareEgg, 1), (.uncommonEgg, 1)]
        case .cometShard: return [(.rareCandy, 5)]
        case .redNectar, .smoothRock: return [(.rareCandy, 3)]
        case .sawsbuckSeasons, .fairyFeather: return [(.uncommonEgg, 1)]
        case .furfrouTrims: return [(.rareEgg, 1)]
        case .vivillonPatterns, .unownLetters: return [(.rareEgg, 2)]
        case .whippedDream, .lightBall: return [(.rareEgg, 2), (.rareCandy, 5)]
        case .excavation: return [(.fossilEgg, 1)]   // per dig
        // A dungeon won; the whole tier's step gives its own (`DungeonMedals.rewards`).
        case .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal:
            return DungeonMedals.rewards(dungeonTier ?? .t1, step: 1)
        case .battleFormsMedal: return BattleFormsMedal.rewards(step: 1)
        case .costumeMedal: return CostumeMedals.rewards(step: 1)
        case .costumeLotsMedal: return CostumeMedals.lotRewards(step: 1)
        default: return [(self, achievementRewardCount)]
        }
    }

    /// Whether claiming this achievement gives other items than itself (the Legend Plate's eggs, a Comet Shard's
    /// candies): the Bag never holds it.
    var givesOtherItems: Bool { achievementRewards.contains { $0.kind != self } }

    /// The rarity a Shop egg of the Bag guarantees. nil for the Pokémon Egg, which guarantees none, and any other item.
    var bagEggTier: Rarity? {
        switch self {
        case .uncommonEgg: return .uncommon
        case .rareEgg: return .rare
        default: return nil
        }
    }

    /// One of the Shop's eggs, which wait in the Bag until used.
    var isShopEgg: Bool { self == .pokemonEgg || bagEggTier != nil }
    /// An egg in the Bag: the Shop's, the Legendary and the Fossil Eggs.
    var isEggItem: Bool { isShopEgg || self == .legendaryEgg || self == .fossilEgg }

    /// The Bag item a Shop egg of `tier` becomes (`FreshEgg.shopTiers`).
    init?(shopEgg tier: Rarity?) {
        switch tier {
        case nil: self = .pokemonEgg
        case .uncommon?: self = .uncommonEgg
        case .rare?: self = .rareEgg
        default: return nil
        }
    }

    /// Achievement group of an item that unlocks through the Pokédex. nil = sold in the shop.
    var collectorGroup: CollectorGroup? {
        if badgeType != nil { return .gymBadges }
        if moreFormsSpecies != nil { return .forms }
        if stoneType != nil { return .evolutionStones }
        switch self {
        case .rareCandy, .mint, .shinyCharm, .birthdayEgg, .pokemonEgg, .uncommonEgg, .rareEgg, .fossilEgg: return nil
        case .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg: return nil
        case _ where self.isDungeonItem: return nil
        case .rotomCatalog, .cometShard, .redNectar, .smoothRock, .sawsbuckSeasons, .fairyFeather, .furfrouTrims, .vivillonPatterns, .whippedDream, .unownLetters,
             .taurosBreeds, .necrozmaForms: return .forms
        case .excavation: return .evolutionStones   // rocks and stones, side by side
        default: return .legendaryArtifacts
        }
    }

    /// Pokédex condition before this item's achievement can be claimed. nil = sold in the shop.
    /// Each item keeps the Pokémon of the achievement that used to award it.
    var unlock: ItemUnlock? {
        if let species = moreFormsSpecies { return .forms(FormGoal(species)) }
        switch self {
        case .rareCandy, .mint, .shinyCharm, .birthdayEgg, .pokemonEgg, .uncommonEgg, .rareEgg, .fossilEgg: return nil
        case .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg: return nil
        case .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal, .battleFormsMedal,
             .costumeMedal, .costumeLotsMedal:
            return regionGoals.map { .species($0.map(\.goal)) }
        case .greatBall, .ultraBall, .masterBall, .oranBerry, .sitrusBerry, .revive, .maxRevive,
             .silverCapsule, .goldCapsule, .treasureMap, .explorerChest, .legendaryKey: return nil
        // The first nine stones follow the generations: each asks for one region's final starters.
        case .leafStone:   return .species([SpeciesGoal([3, 6, 9])])            // Kanto starters
        case .fireStone:   return .species([SpeciesGoal([154, 157, 160])])      // Johto starters
        case .waterStone:  return .species([SpeciesGoal([254, 257, 260])])      // Hoenn starters
        case .thunderStone: return .species([SpeciesGoal([389, 392, 395])])     // Sinnoh starters
        case .sunStone:    return .species([SpeciesGoal([497, 500, 503])])      // Unova starters
        case .moonStone:   return .species([SpeciesGoal([652, 655, 658])])      // Kalos starters
        case .duskStone:   return .species([SpeciesGoal([724, 727, 730])])      // Alola starters
        case .iceStone:    return .species([SpeciesGoal([812, 815, 818])])      // Galar starters
        case .dawnStone:   return .species([SpeciesGoal([908, 911, 914])])      // Paldea starters
        // Dragon is the strongest egg type, so its stone asks for the three Dragon/Flying Pokémon:
        // two pseudo-legendaries (long to raise) and Rayquaza.
        case .shinyStone:  return .species([SpeciesGoal([149, 373, 384])])      // Dragonite, Salamence, Rayquaza
        case .legendCharm: return .duplicateLegendary
        case .silverWing:  return .species([SpeciesGoal([144, 145, 146])])      // Legendary birds
        case .oldSeaMap:   return .species([SpeciesGoal([150, 151])])           // Mewtwo, Mew
        case .clearBell:   return .species([SpeciesGoal([243, 244, 245])])      // Legendary beasts
        case .rainbowWing: return .species([SpeciesGoal([249, 250])])           // Lugia, Ho-Oh
        case .magmaStone:  return .species([SpeciesGoal([377, 378, 379]),       // Legendary titans
                                            SpeciesGoal([894, 895]),            // Regieleki, Regidrago
                                            SpeciesGoal(SpeciesGoal.fossils, needed: 4),
                                            SpeciesGoal([485, 383])])           // Heatran, whose item it is, and Groudon
        case .soulDew:     return .species([SpeciesGoal([380, 381])])           // Latias, Latios
        case .jadeOrb:     return .species([SpeciesGoal([382, 383, 384])])      // Weather trio
        case .gracidea:    return .species([SpeciesGoal([480, 481, 482])])      // Lake guardians
        case .griseousOrb: return .species([SpeciesGoal([483, 484, 487])])      // Creation trio
        case .libertyPass: return .species([SpeciesGoal([638, 639, 640, 647], needed: 3)]) // Swords of Justice, Keldeo
        case .revealGlass: return .species([SpeciesGoal([641, 642, 645, 905], needed: 3)]) // Forces of Nature
        case .dnaSplicers: return .species([SpeciesGoal([643, 644, 646])])      // Reshiram, Zekrom, Kyurem
        case .zygardeCube: return .species([SpeciesGoal([716, 717, 718])])      // Kalos legends
        case .prisonBottle: return .species([SpeciesGoal([719, 720, 721])])     // Diancie, Hoopa, Volcanion
        case .sparklingStone: return .species([SpeciesGoal([785, 786, 787, 788])]) // Island guardians
        case .sunFlute:    return .species([SpeciesGoal([791, 792, 800])])      // Solgaleo, Lunala, Necrozma
        case .beastBall:   return .species([SpeciesGoal(SpeciesGoal.ultraBeasts, needed: 4)])
        case .rustedSword: return .species([SpeciesGoal([888, 889, 890])])      // Zacian, Zamazenta, Eternatus
        case .reinsOfUnity: return .species([SpeciesGoal([896, 897, 898])])     // Glastrier, Spectrier, Calyrex
        case .boosterEnergy: return .species([SpeciesGoal(SpeciesGoal.paradoxes, needed: 4)])
        case .tealMask:    return .species([SpeciesGoal([1017, 1014, 1015, 1016, 1025], needed: 4)]) // Ogerpon, Loyal Three, Pecharunt
        case .teraOrb:     return .species([SpeciesGoal([1007, 1008, 1024])])   // Koraidon, Miraidon, Terapagos
        case .relicStatue: return .species([SpeciesGoal([377, 378, 379, 486, 894, 895])]) // All six Regis
        case .lunarWing:   return .species([SpeciesGoal([488, 491])])           // Cresselia, Darkrai
        case .meteorite:   return .species([SpeciesGoal([385, 386])])           // Jirachi, Deoxys
        case .oaksLetter:  return .species([SpeciesGoal([251, 492])])           // Celebi, Shaymin
        case .seaIncense:  return .species([SpeciesGoal([490, 382])])           // Manaphy (Phione's line too), Kyogre
        case .shockDrive:  return .species([SpeciesGoal([494, 648, 649])])      // Victini, Meloetta, Genesect
        // Silvally, Magearna, Marshadow, Zeraora, Melmetal: the legends of Alola left.
        case .zRing:       return .species([SpeciesGoal([773, 801, 802, 807, 809], needed: 4)])
        case .scrollOfDarkness: return .species([SpeciesGoal([892, 893])])      // Urshifu, Zarude
        case .relicVase:   return .species([SpeciesGoal([1001, 1002, 1003, 1004])]) // Treasures of Ruin
        case .legendPlate: return .species([SpeciesGoal([493])])                // Arceus
        case .excavation: return regionGoals.map { .species($0.map(\.goal)) }
        case .oldAmber: return .species([SpeciesGoal(SpeciesGoal.fossils)])           // every fossil line
        case .explorerKit: return .species([SpeciesGoal(SpeciesGoal.explorers)])      // the explorers of the depths
        case .rotomCatalog: return .forms(FormGoal(479))                        // Rotom's six appliances
        case .cometShard: return .forms(FormGoal(774, excluding: ["meteor"]))   // Minior's seven cores
        case .redNectar: return .forms(FormGoal(741))                           // Oricorio's four styles
        case .smoothRock: return .forms(FormGoal(351))                          // Castform's four weathers
        case .sawsbuckSeasons: return .forms(FormGoal(586))                     // Sawsbuck's four seasons
        case .fairyFeather: return .forms(FormGoal(671))                        // Florges's five colors
        case .furfrouTrims: return .forms(FormGoal(676))                        // Furfrou's ten trims
        case .vivillonPatterns: return .forms(FormGoal(666))                    // Vivillon's twenty patterns
        case .whippedDream: return .forms(FormGoal(869))                        // Alcremie's 63 sweets
        case .unownLetters: return .forms(FormGoal(201))                        // Unown's 28 letters
        case .taurosBreeds: return .forms(FormGoal(128))                        // Tauros's Kanto breed and Paldea's three
        case .necrozmaForms: return .forms(FormGoal(800))                       // Necrozma, Dusk Mane, Dawn Wings, Ultra
        case .typeNullEgg: return .silvallyMemories
        case .legendaryEgg: return regionGoals.map { .species($0.map(\.goal)) }
        case .lightBall: return .allPikachuCostumes
        case .ovalCharm: return .allSpecies
        case .glimmeringCharm: return .allForms
        case .boulderBadge, .cascadeBadge, .thunderBadge, .rainbowBadge,
             .soulBadge, .marshBadge, .volcanoBadge, .earthBadge,
             .zephyrBadge, .hiveBadge, .plainBadge, .fogBadge,
             .stormBadge, .mineralBadge, .glacierBadge, .risingBadge,
             .darkBadge, .fairyBadge:
            // One goal per region (generation); each met goal is a tier to claim (`CompanionStore.regionTiers`).
            return regionGoals.map { .species($0.map(\.goal)) }
        // Answered above (`moreFormsSpecies`).
        case .deoxysFormes, .wormadamCloaks, .darmanitanModes, .kyuremFusions, .genesectDrives, .gourgeistSizes, .zygardeFormes,
             .lycanrocForms, .cramorantForms, .calyrexSteeds, .squawkabillyPlumages, .tatsugiriForms, .ogerponMasks, .terapagosForms:
            return moreFormsSpecies.map { .forms(FormGoal($0)) }
        }
    }

    /// Whether this item's achievement is claimed region by region: one tier per region in `regionGoals`.
    var isRegional: Bool { badgeType != nil || self == .legendaryEgg || self == .excavation || isPlayMedal }

    /// A medal of the dungeons' play: its steps count dungeons won or battle forms won, not the Pokémon raised.
    var isPlayMedal: Bool { dungeonTier != nil || self == .battleFormsMedal || isCostumeMedal }

    /// The costumed collection's medals: their steps count costumes and lots, not species (`CostumeMedals`).
    var isCostumeMedal: Bool { self == .costumeMedal || self == .costumeLotsMedal }

    /// The regions (generations, Kanto first) this item's achievement is claimed in, with the species each asks
    /// for: a gym badge's type in every region that has it, every species of the region for the Legendary Egg.
    /// nil for an item claimed once.
    var regionGoals: [(generation: Int, goal: SpeciesGoal)]? {
        if let type = badgeType {
            return PokemonTypeData.badgeGenerations(for: type).map {
                ($0, SpeciesGoal(PokemonTypeData.badgeSpecies(for: type, generation: $0)))
            }
        }
        if let tier = dungeonTier { return DungeonMedals.goals(tier) }
        if self == .battleFormsMedal { return BattleFormsMedal.goals }
        if self == .costumeMedal { return CostumeMedals.goals }
        if self == .costumeLotsMedal { return CostumeMedals.lotGoals }
        if self == .excavation {
            // Not regions but digs, numbered from 1: each asks `FossilDig.rockPerDig` more Rock-type species.
            return (1...FossilDig.digs).map { ($0, SpeciesGoal(FossilDig.rockSpecies, needed: FossilDig.rockPerDig * $0)) }
        }
        guard self == .legendaryEgg else { return nil }
        return PokemonTypeData.generations.enumerated().map { ($0.offset + 1, SpeciesGoal(Array($0.element))) }
    }
}

/// Groups of the items unlocked by the Pokédex, each a section of the Achievements tab.
enum CollectorGroup: String, CaseIterable, Sendable {
    case evolutionStones, legendaryArtifacts, gymBadges, forms
}

/// The forms of one species an achievement asks for, graduated: every catalogued one but those excluded (Minior's
/// Meteor Form, its shell, beside its seven cores).
struct FormGoal: Equatable, Sendable {
    let speciesID: Int
    let forms: [PokemonForm]

    init(_ speciesID: Int, excluding excluded: [String] = []) {
        self.speciesID = speciesID
        forms = PokemonForm.forms(speciesID: speciesID).filter { !excluded.contains($0.rawValue) }
    }
}

/// One way to unlock a collector item: `needed` of `species` registered in the Pokédex.
struct SpeciesGoal: Equatable, Sendable {
    /// Final fossil Pokémon of Gen 1 to 8 (Gen 9 has none).
    static let fossils = [139, 141, 142, 346, 348, 409, 411, 565, 567, 697, 699, 880, 881, 882, 883]
    /// Ultra Beasts, Naganadel included (it evolves from Poipole).
    static let ultraBeasts = [793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806]
    /// The mythical Pokémon, one per line (Meltan for Melmetal): what the Birthday Egg hatches first.
    static let mythicals = [151, 251, 385, 386, 489, 490, 491, 492, 493, 494, 647, 648, 649, 719, 720, 721, 801, 802, 807,
                            808, 893, 1025]
    /// The legendary Pokémon that are not mythical, one per line (Cosmog for Solgaleo, Type: Null for Silvally): with
    /// `mythicals`, the bases PokéAPI flags `is_legendary` or `is_mythical` (the base index of 2026-10-29). The Birthday
    /// Egg's roll reads them when the index is unavailable.
    static let legendaries = [144, 145, 146, 150, 243, 244, 245, 249, 250, 377, 378, 379, 380, 381, 382, 383, 384, 480, 481,
                              482, 483, 484, 485, 486, 487, 488, 638, 639, 640, 641, 642, 643, 644, 645, 646, 716, 717, 718,
                              772, 785, 786, 787, 788, 789, 800, 888, 889, 890, 891, 894, 895, 896, 897, 898, 905, 1001,
                              1002, 1003, 1004, 1007, 1008, 1014, 1015, 1016, 1017, 1024]
    /// The explorers of the depths: Steelix digs through the earth, Larvitar is born underground, Gible lives in caves,
    /// Sableye digs them for gems, Orthworm burrows (all Rare), and Heatran, from the depths of Sinnoh's volcano like the
    /// Kit: a legendary, so that the treasures every few graduations are earned. The Explorer Kit asks for every one.
    static let explorers = [208, 248, 445, 302, 968, 485]
    /// Paradox Pokémon of Scarlet and Violet and their DLC, ancient then future.
    static let paradoxes = Array(984...995) + [1005, 1006, 1009, 1010] + Array(1020...1023)

    let species: [Int]
    let needed: Int

    init(_ species: [Int], needed: Int? = nil) {
        self.species = species
        self.needed = min(needed ?? species.count, species.count)
    }
}

/// What the Pokédex must hold before a collector item's achievement can be claimed.
/// The Bonuses page's sections: what each passive item improves. Badges are growth, shown together.
enum BonusTheme: CaseIterable, Sendable {
    case growth, eggs, shiny, shop, candies

    static func of(_ kind: ItemKind) -> BonusTheme? {
        if kind.badgeType != nil { return .growth }
        switch kind {
        case .oldSeaMap, .dnaSplicers, .zygardeCube, .clearBell, .griseousOrb, .prisonBottle, .sparklingStone,
             .sunFlute, .gracidea, .relicStatue, .beastBall, .rustedSword, .boosterEnergy, .tealMask,
             .magmaStone, .libertyPass, .lunarWing, .oaksLetter, .zRing, .scrollOfDarkness, .relicVase,
             .oldAmber:
            return .growth
        case .silverWing, .teraOrb, .seaIncense, .legendCharm, .ovalCharm, .taurosBreeds, .necrozmaForms: return .eggs
        case .shinyCharm, .revealGlass, .glimmeringCharm: return .shiny
        case .rainbowWing, .jadeOrb: return .shop
        case .soulDew, .reinsOfUnity, .meteorite, .rotomCatalog, .explorerKit, .shockDrive: return .candies
        default: return nil
        }
    }
}

enum ItemUnlock: Equatable, Sendable {
    /// Any one goal met is enough.
    case species([SpeciesGoal])
    /// The same legendary graduated twice. Released copies don't count: they were never raised to the end.
    case duplicateLegendary
    /// All 17 of Silvally's Memories: a legendary or mythical Pokémon of every type but Normal in the Pokédex.
    case silvallyMemories
    /// Every species in the Pokédex (`CompanionStore.collectionProgress`).
    case allSpecies
    /// Every form of every species in the Pokédex.
    case allForms
    /// Every one of Pikachu's costumes (`PikachuCostume`).
    case allPikachuCostumes
    /// Every form of one species graduated (`FormGoal`).
    case forms(FormGoal)
}

/// Evolution stones are consumables: each one sends the current Pokémon off for an egg of the stone's type.
enum EvolutionStone {
    /// Stones one claim of a stone achievement adds to the Bag.
    static let achievementReward = 5
}

/// Growth bonuses of the passive collector items. Each one only speeds a group of Pokémon up or adds a
/// reward: none of them reweights the egg or form rolls, so owning an item never lowers anyone's chances.
/// (The Azure Flute's legendary weight is the one deliberate exception, now ×2.)
enum CollectorBonus {
    /// Zygarde Cube: +1% token growth EXP per this many registered species, up to `zygardeMaxPercent`.
    static let zygardeSpeciesPerPercent = 25
    static let zygardeMaxPercent = 40
    /// Speed multipliers of the stage thresholds (1.5 = grows 50% faster).
    static let prisonBottleNewForm = 1.5
    static let sparklingStoneFairy = 1.3
    static let sunFluteFinalStage = 1.25
    /// Gracidea: the first stage of a Pokémon that will evolve. It used to double every Rare Candy, bought ones
    /// included, which stacked with the Soul Dew and the Rainbow Wing into four times the EXP per shop token.
    static let gracideaFirstStage = 1.25
    /// Relic Statue: a Pokémon that does not evolve, like the Regis.
    static let relicStatueNoEvolution = 1.25
    static let beastBallUltraBeast = 1.5
    static let rustedSwordLegendary = 1.25
    static let boosterEnergyParadox = 1.5
    static let tealMaskTypes = 1.2
    /// Ogerpon's four masks.
    static let tealMaskTypeList: [PokemonType] = [.grass, .water, .fire, .rock]
    static let clearBellRare = 1.25
    /// Silver Wing: every Pokémon grows 25% faster (and eggs still hatch twice as fast).
    static let silverWingGrowth = 1.25
    /// Tera Orb: a Pokémon from an evolution stone's egg grows 30% faster.
    static let teraOrbStoneGrowth = 1.3
    /// Sea Incense: a Pokémon from an egg of a guaranteed rarity grows 30% faster.
    static let seaIncenseRarityEggGrowth = 1.3
    static let griseousOrbGhostDragon = 1.3
    /// Rare Candies the Reins of Unity add to each graduation.
    static let reinsOfUnityCandies = 1
    /// Lunar Wing: Cresselia's Psychic and Darkrai's Dark.
    static let lunarWingPsychicDark = 1.3
    /// Rare Candies the Meteorite adds to each usage window filled: Jirachi's wish.
    static let meteoriteWindowCandies = 1
    /// Rare Candies the Rotom Catalog gives for each Pokémon graduated in a form its line never graduated in.
    static let rotomCatalogNewFormCandies = 1
    /// Old Amber: the share of its stage's EXP a Pokémon sent off for an egg gives the one that hatches, short of its
    /// first evolution.
    static let oldAmberKeptPercent = 50
    /// Oak's Letter: the starters of every region, at every stage.
    static let oaksLetterStarter = 1.25
    static let starterLines: Set<Int> = Set([1, 152, 252, 387, 495, 650, 722, 810, 906].flatMap { $0...($0 + 8) })
    /// Shock Drive: one Rare Candy used in this many recharges, Genesect's drive charging it again: it stays in the Bag.
    /// It made fossil Pokémon grow 50% faster, which they long were by the time its three mythicals graduated.
    static let shockDriveRechargeOneIn = 4

    /// Whether the Shock Drive recharges the candy of this roll.
    static func shockDriveRecharges(roll: UInt64) -> Bool { roll % UInt64(shockDriveRechargeOneIn) == 0 }
    /// Every species of the fossil lines whose finals are `SpeciesGoal.fossils`.
    static let fossilLines: Set<Int> = [138, 139, 140, 141, 142, 345, 346, 347, 348, 408, 409, 410, 411, 564, 565, 566,
                                        567, 696, 697, 698, 699, 880, 881, 882, 883]
    static let zRingSteelElectric = 1.3
    static let scrollOfDarknessFighting = 1.3
    /// Relic Vase: the stage between the Gracidea's first and the Sun Flute's last.
    static let relicVaseMiddleStage = 1.25
    /// Growth bonus of one regional tier of a gym badge, for Pokémon weak to its type: 2.5% per region, so
    /// 22.5% with the nine regions (20% for Dark, which has no Kanto tier).
    static let badgeRegionBonus = 0.025
}

/// The Explorer Kit's treasures: one for every `graduationsPerTreasure` Pokémon graduated while it is owned.
enum ExplorerKit {
    static let graduationsPerTreasure = 5
    /// Out of `rollRange`: 1 Legendary Egg (0.01%), 300 Rare Eggs (3%), 1,200 Uncommon Eggs (12%), and the rest, one
    /// Rare Candy (84.99%). It was 5%, 20% and 3 candies, too generous (DyRize's #107; the owner chose these,
    /// 2026-11-05). Pure bonuses: nothing here changes what hatches. The Explorer Chest gives one of these too.
    static let rollRange = 10_000
    static let legendaryEggRolls = 1
    static let rareEggRolls = 300
    static let uncommonEggRolls = 1_200
    /// One: the kit's description says "a Rare Candy".
    static let candies = 1

    /// The treasure of one roll in `0..<rollRange`.
    static func treasure(roll: Int) -> (kind: ItemKind, count: Int) {
        if roll < legendaryEggRolls { return (.legendaryEgg, 1) }
        if roll < legendaryEggRolls + rareEggRolls { return (.rareEgg, 1) }
        if roll < legendaryEggRolls + rareEggRolls + uncommonEggRolls { return (.uncommonEgg, 1) }
        return (.rareCandy, candies)
    }
}

/// Azure Flute balance constant (passive collector item).
enum LegendCharm {
    /// 보유 시 전설 포켓몬 부화 가중치 배율 (capture_rate 3 기준 출현 확률 2배 증가). It was 4, which made a legendary
    /// almost one rare egg in five.
    static let weightMultiplier = 2
}

/// 이상한 사탕 밸런스 상수.
enum RareCandy {
    /// The XP (in tokens) one candy gives the Pokémon being raised: 100M at 10% (2026-11-02, the owner: 75M, a whole
    /// common line, was not enough). A common line takes one candy, an uncommon one 2, a rare one 3, a legendary one 6.
    static let xp = PokemonBalance.scaled(1_000_000_000)
    /// Candies a whole week of a Pro plan pays; a whole 5-hour session pays one.
    static let weeklyGrant = 5
    /// The tokens a tool with no limit window pays a candy for (Cursor, Gemini CLI, OpenCode…): what Claude's windows
    /// pay a Max 5x user, measured on 2026-10-28 (40 candies for 2.61B tokens, 68% of the week). Not scaled with the
    /// difficulty: windows pay by usage whatever it is.
    static let tokensPerCandyWithoutLimits = 65_000_000
    /// The Shop's table price, scaled like every price (`PokemonBalance.scaled`): 50M at 10%. The wallet is the tokens
    /// used (usedSinceInstall minus spentTokens), which also grew the Pokémon, so a candy priced at its XP would be
    /// free growth. Candies also come free from the limit windows, paid as they fill (`candiesDue`).
    static let price = 500_000_000

    /// Candies a whole window pays: one 5-hour session of a Pro plan is one candy, a Pro week `weeklyGrant`, and a
    /// bigger plan as many times more as it holds Pro plans (Max 20x: 20 a session).
    static func windowCandies(kind: WindowClass, planMultiplier: Int) -> Int {
        (kind == .weekly ? weeklyGrant : 1) * max(1, planMultiplier)
    }

    /// Candies a window owes at `utilization`, paid as it goes rather than at 100%: a Max 5x session pays one every
    /// fifth, the same usage as a whole Pro session, so every plan earns them at the same pace whether or not it
    /// reaches its limit.
    static func candiesDue(utilization: Double, kind: WindowClass, planMultiplier: Int) -> Int {
        guard utilization.isFinite, utilization > 0 else { return 0 }
        let whole = windowCandies(kind: kind, planMultiplier: planMultiplier)
        return min(whole, Int((min(utilization, 100) / 100 * Double(whole) + 1e-9).rounded(.down)))
    }
}

/// 민트 밸런스 상수.
enum Mint {
    /// 상점 구매가. 성격 변경은 순수 코스메틱(성장·능력치 무관)이라 밸런스 근거가 없어 "느낌" 값 —
    /// 사탕(500M)의 1/5로 싸게 둬서 성격을 마음에 들 때까지 굴려보는 가벼운 재미. 성장을 안 줘서
    /// 이중계산 이슈도 없음(가격 = 순수 소비).
    /// 2026-11-09: back for the graduated Pokémon, at 20M as the players see it (×0.1; the owner: "20M, ça reste du
    /// random"), though a nature counts in battle now.
    static let price = 200_000_000
}

/// 이로치 부적 밸런스 상수 — 보유형(1회 구매·영구, 소비 안 됨).
enum ShinyCharm {
    /// 상점 구매가. 앞으로의 모든 부화에 적용되는 영구 럭 업그레이드라 프리미엄(레어 1마리 졸업분=3B).
    static let price = 3_000_000_000
    /// 보유 시 이로치 부화 확률 분모 — 1/64 → 1/48 (+33%). 본가 '반짝이 부적'(이로치 확률↑) 오마주.
    /// ×2(1/32)는 과해 절제. 이미 부화한 개체엔 소급 없음(이로치는 부화 순간 확정).
    static let shinyDenominator: UInt64 = 48
}

/// The Shop eggs' balance: bought into the Bag; used, an egg sends the current Pokémon off for a new egg.
enum FreshEgg {
    /// 상점 구매가. 마음에 안 드는 부화를 리롤하는 프리미엄(쌓인 토큰의 활용처). 폐기 개체는 졸업이
    /// 아니라 그냥 사라지므로 도감·확률(collectedFinals)에 무영향 — "뽑은 적 없던 것처럼". 새 알은
    /// 처음부터 재인큐베이션(5M) 필요 + 성장(usedAtStage) 소멸이라 스팸/파밍이 자연 억제된다.
    static let price = 1_000_000_000

    /// 상점에서 파는 알 — 보증 없음(기본) → 고급 이상 → 희귀 이상. `nil` = 등급 보증 없는 기존 알.
    /// **전설 전용 알은 팔지 않는다**(등급 하한을 capture_rate 로 표현할 수 없고, 최고 등급을 확정
    /// 상품으로 만들지 않는다). 전설은 고급/희귀 알에서 자연 가중대로 섞여 나온다 — 희귀 알 기준 약 10%.
    static let shopTiers: [Rarity?] = [nil, .uncommon, .rare]

    /// 등급 보증 알의 가격 — 배율은 새 상수를 짓지 않고 **기존 졸업 총량 표**를 그대로 쓴다
    /// (common 750M : uncommon 1.875B : rare 3B = 1 : 2.5 : 4 → 1B / 2.5B / 4B).
    ///
    /// 확률 배율(고급 7.16% : 희귀 6.98% ≈ 1 : 2.03)로 매기면 안 된다 — 그러면 같은 값으로 고급 알
    /// 2개를 사는 쪽이 희귀+ 기대 1.039마리·전설 0.104마리로 희귀 알 1개(1.000·0.100)를 모든 축에서
    /// 앞질러 상위 티어가 완전 열등재가 된다. 졸업량 배율이라야 상위 티어가 희귀+ 1마리당 4.00B 로
    /// 하위 반복 구매(4.81B)보다 싸다.
    static func price(guaranteeing tier: Rarity?) -> Int {
        guard let tier else { return price }
        let multiplier = Double(PokemonBalance.graduationTotal(tier)) / Double(PokemonBalance.graduationTotal(.common))
        return Int((Double(price) * multiplier).rounded())
    }
}

/// One Shop row: an item sold (ItemKind) or an egg, bought into the Bag as `ItemKind(shopEgg:)` and drawn by its own card.
/// `egg` 의 연관값은 **보증 등급 하한**(nil = 보증 없는 기존 알).
/// CompanionStore.shopEntries 가 이 둘을 가격 오름차순으로 병합해 뷰가 단일 목록으로 그린다.
enum ShopEntry: Hashable, Sendable {
    case item(ItemKind)
    case egg(Rarity?)

    var price: Int {
        switch self {
        case .item(let kind): return kind.shopPrice ?? 0
        case .egg(let tier): return FreshEgg.price(guaranteeing: tier)
        }
    }
}

/// The two kinds of limit windows: a session (5 hours) and a week.
enum WindowClass: Sendable { case session, weekly }

/// A Pokémon's raising record (carnet d'élevage), kept from its hatch: the tokens that raised it, by tool and by model,
/// and their estimated cost. A Pokémon hatched before it was kept has none.
struct RaisingRecord: Codable, Sendable, Equatable {
    var hatchedAt: Date
    var tokensByProvider: [String: Int] = [:]
    var tokensByModel: [String: Int] = [:]
    /// The tokens' cost, each refresh priced at its provider's cost per token that day; nil while none reported one.
    var cost: Double?
    /// The Rare Candies used on it.
    var candiesUsed = 0

    init(hatchedAt: Date) { self.hatchedAt = hatchedAt }

    /// Each field but the hatch read leniently: a record written before a field existed keeps the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hatchedAt = try c.decode(Date.self, forKey: .hatchedAt)
        tokensByProvider = (try? c.decodeIfPresent([String: Int].self, forKey: .tokensByProvider)) ?? [:]
        tokensByModel = (try? c.decodeIfPresent([String: Int].self, forKey: .tokensByModel)) ?? [:]
        cost = (try? c.decodeIfPresent(Double.self, forKey: .cost)) ?? nil
        candiesUsed = (try? c.decodeIfPresent(Int.self, forKey: .candiesUsed)) ?? 0
    }

    var tokens: Int { tokensByProvider.values.reduce(0, +) }
    var mainProvider: String? { tokensByProvider.max { $0.value < $1.value }?.key }
    var mainModel: String? { tokensByModel.max { $0.value < $1.value }?.key }

    /// Adds a refresh's new tokens of one provider, spread over the day's models and priced at the day's cost.
    mutating func add(_ tokens: Int, provider: String, day: TodayUsageDetail?) {
        guard tokens > 0 else { return }
        tokensByProvider[provider, default: 0] += tokens
        guard let day, day.tokens > 0 else { return }
        let share = Double(tokens) / Double(day.tokens)
        for (model, modelTokens) in day.models {
            let part = Int((Double(modelTokens) * share).rounded())
            if part > 0 { tokensByModel[model, default: 0] += part }
        }
        if let dayCost = day.cost { cost = (cost ?? 0) + dayCost * share }
    }

    /// A model id as people say it: "claude-opus-5-5" is "Opus 5.5"; an id it does not know stays as it is.
    static func modelName(_ id: String) -> String {
        var name = id.lowercased()
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        if let date = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(date) }
        let parts = name.split(separator: "-").map(String.init)
        guard let family = parts.first, ["opus", "sonnet", "haiku", "fable"].contains(family) else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return family.capitalized + (version.isEmpty ? "" : " " + version)
    }
}

/// One provider's usage today, as the raising record reads it to spread and price a refresh's new tokens.
struct TodayUsageDetail: Sendable, Equatable {
    var tokens: Int
    var cost: Double?
    var models: [String: Int]
}

/// 사탕 지급 판정 입력 — 프로바이더 무관 한도 창 1개. (UsageStore.candyEligibleWindows 가 생성)
struct CandyWindow: Sendable {
    /// The usage provider whose tokens a window pays for, read from its key: a provider that ever had one pays no
    /// candies by tokens (`CompanionStore.paysCandiesByTokens`).
    static func providerID(forKey key: String) -> String? {
        switch key.split(separator: ".").first {
        case "claude": return "claude_code"
        case "codex": return "codex"
        case "antigravity": return "antigravity"
        default: return nil
        }
    }

    let key: String          // 안정 식별자(tier 추적) — resets_at 등 휘발 필드는 key 에 넣지 않는다
    let name: String         // 표시용(알림 "왜 받는지")
    let kind: WindowClass
    let utilization: Double  // 0~100+
    /// 창 epoch (`resets_at` / reset unix). key 는 안정, epoch 가 바뀌면 새 창 → 재무장(#326).
    /// nil 이면 100% 미만 관측으로만 재무장한다(Codex — credits 로 100% 를 넘겨 쓴다).
    let epoch: String?
    /// How many Pro plans the account's limits are worth (`LimitStatus.planMultiplier`): 1 when unknown.
    let planMultiplier: Int

    init(key: String, name: String, kind: WindowClass, utilization: Double, epoch: String? = nil,
         planMultiplier: Int = 1) {
        self.key = key
        self.name = name
        self.kind = kind
        self.utilization = utilization
        self.epoch = epoch
        self.planMultiplier = max(1, planMultiplier)
    }

    func withPlanMultiplier(_ plan: Int) -> CandyWindow {
        CandyWindow(key: key, name: name, kind: kind, utilization: utilization, epoch: epoch, planMultiplier: plan)
    }
}

/// 사탕 지급 1건(순수 판정 결과) — 부수효과(인벤토리·알림)와 분리해 테스트 가능하게.
struct CandyGrant: Equatable, Sendable {
    let windowKey: String
    let windowName: String   // 알림 "왜 받는지"
    let count: Int
    /// The window reached its last candy with this grant: the Meteorite adds one.
    var completesWindow = false
}

/// 현재 서비스가 제공하는 움직이는 포켓몬 스프라이트 범위.
/// 1~5세대는 Gen-V animated 에셋(#1...649), 6~9세대는 Showdown animated 에셋(#650...1025)을 사용한다.
enum PokemonAssets {
    static let animatedSpeciesIDs = 1...1025

    static func hasAnimatedSprite(speciesID: Int) -> Bool {
        animatedSpeciesIDs.contains(speciesID)
    }
}

/// PokéAPI evolution-chain 을 파싱한 트리. 분기(evolves_to 다수)를 children 으로.
struct EvoNode: Codable, Sendable {
    let speciesID: Int
    let children: [EvoNode]

    /// 최장 경로 길이(형태 수). 분기는 보통 같은 깊이라 대표값으로 사용.
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }
    func node(withID id: Int) -> EvoNode? {
        if speciesID == id { return self }
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }
    /// 이 노드에서 도달 가능한 모든 최종체 id
    var finalIDs: [Int] {
        children.isEmpty ? [speciesID] : children.flatMap(\.finalIDs)
    }

    /// 서비스에 GIF 에셋이 있는 종만 남긴 진화 트리. 지원하지 않는 종부터 그 하위 체인도 제외한다.
    func keepingAnimatedSprites() -> EvoNode? {
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return nil }
        return EvoNode(speciesID: speciesID, children: children.compactMap { $0.keepingAnimatedSprites() })
    }
}

struct BranchEvolutionItem: Equatable, Sendable, Identifiable {
    var id: String { "\(speciesID)-\(form?.rawValue ?? "")" }
    let speciesID: Int
    let isCollected: Bool
    /// One form of a stage that will show the individual's hidden one. Nil: the individual's own.
    let form: PokemonForm?

    init(speciesID: Int, isCollected: Bool, form: PokemonForm? = nil) {
        self.speciesID = speciesID
        self.isCollected = isCollected
        self.form = form
    }
}

enum EvoLineItemContent: Equatable, Sendable {
    case species(Int)
    case mystery
    case branch([BranchEvolutionItem])
}

enum EvoLineItemState: Equatable, Sendable {
    case done
    case current
    case future
    /// Not in the Pokédex (a Pokédex page's evolution family): a silhouette that opens nothing.
    case uncaught
}

struct EvoLineItem: Equatable, Sendable {
    let content: EvoLineItemContent
    let state: EvoLineItemState

    init(_ content: EvoLineItemContent, _ state: EvoLineItemState) {
        self.content = content
        self.state = state
    }
}

/// 부화 시 확정되는 라인 정보(트리 + 희귀도 + 다국어 이름).
struct EvoLine: Sendable {
    let baseID: Int
    let tree: EvoNode
    let rarity: Rarity
    /// speciesID → (langCode → name)
    let names: [Int: [String: String]]
    var totalForms: Int { tree.depth }

    init(baseID: Int, tree: EvoNode, rarity: Rarity, names: [Int: [String: String]]) {
        self.baseID = baseID
        self.tree = tree.keepingAnimatedSprites() ?? EvoNode(speciesID: baseID, children: [])
        self.rarity = rarity
        self.names = names
    }

    func localizedName(_ id: Int, _ lang: AppLanguage) -> String {
        lang.resolveName(names[id] ?? [:]) ?? "#\(id)"   // 폴백 순서는 AppLanguage.resolveName 단일 소스
    }
}

/// 성격 — 본가 25종. 부화 시 확정, 능력치 영향 없음(개체 아이덴티티 표시용).
enum PokemonNature: String, Codable, Sendable, CaseIterable {
    case hardy, lonely, brave, adamant, naughty
    case bold, docile, relaxed, impish, lax
    case timid, hasty, serious, jolly, naive
    case modest, mild, quiet, bashful, rash
    case calm, gentle, sassy, careful, quirky

    /// 본가 공식 번역 명칭 (ko/en/ja/es/fr/de).
    /// pt 만 예외 — 본가에 포르투갈어판이 없어 공식 명칭이 없다. "natureza"(여성 명사)에
    /// 맞춘 자체 번역이며 25종이 겹치지 않게 골랐다(`testNatureNamesComplete` 가 중복·공백을 막는다).
    /// ru 도 예외 — 성격 명칭의 공식 러시아어 출처를 찾지 못했다(본가 게임은 러시아어 미지원). 그래서 커뮤니티
    /// 번역(러시아어 Pixelmon 위키의 характеры 표)을 기준으로 "характер"(남성 명사)에 맞춘 남성형이며, 공식 출처가
    /// 확인되면 그쪽으로 바꾼다. 뜻이 어긋난 2종만 고쳤다:
    /// Lax Слабый→Беспечный, Gentle Вежливый→Кроткий.
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String, String, String, String, String, String)
        switch self {
        case .hardy:   names = ("노력", "Hardy", "がんばりや", "Fuerte", "Hardi", "Esforçada", "Robust", "Выносливый")
        case .lonely:  names = ("외로움", "Lonely", "さみしがり", "Huraña", "Solo", "Carente", "Solo", "Одинокий")
        case .brave:   names = ("용감", "Brave", "ゆうかん", "Audaz", "Brave", "Corajosa", "Mutig", "Храбрый")
        case .adamant: names = ("고집", "Adamant", "いじっぱり", "Firme", "Rigide", "Teimosa", "Hart", "Непреклонный")
        case .naughty: names = ("개구쟁이", "Naughty", "やんちゃ", "Pícara", "Mauvais", "Levada", "Frech", "Непослушный")
        case .bold:    names = ("대담", "Bold", "ずぶとい", "Osada", "Assuré", "Ousada", "Kühn", "Смелый")
        case .docile:  names = ("온순", "Docile", "すなお", "Dócil", "Docile", "Dócil", "Sanft", "Послушный")
        case .relaxed: names = ("무사태평", "Relaxed", "のんき", "Plácida", "Relax", "Descontraída", "Locker", "Расслабленный")
        case .impish:  names = ("장난꾸러기", "Impish", "わんぱく", "Agitada", "Malin", "Travessa", "Pfiffig", "Проказливый")
        case .lax:     names = ("촐랑", "Lax", "のうてんき", "Floja", "Lâche", "Despreocupada", "Lasch", "Беспечный")
        case .timid:   names = ("겁쟁이", "Timid", "おくびょう", "Miedosa", "Timide", "Medrosa", "Scheu", "Робкий")
        case .hasty:   names = ("성급", "Hasty", "せっかち", "Activa", "Pressé", "Apressada", "Hastig", "Торопливый")
        case .serious: names = ("성실", "Serious", "まじめ", "Seria", "Sérieux", "Séria", "Ernst", "Серьёзный")
        case .jolly:   names = ("명랑", "Jolly", "ようき", "Alegre", "Jovial", "Alegre", "Froh", "Весёлый")
        case .naive:   names = ("천진난만", "Naive", "むじゃき", "Ingenua", "Naïf", "Ingênua", "Naiv", "Наивный")
        case .modest:  names = ("조심", "Modest", "ひかえめ", "Modesta", "Modeste", "Modesta", "Mäßig", "Скромный")
        case .mild:    names = ("의젓", "Mild", "おっとり", "Afable", "Doux", "Meiga", "Mild", "Мягкий")
        case .quiet:   names = ("냉정", "Quiet", "れいせい", "Mansa", "Discret", "Discreta", "Ruhig", "Тихий")
        case .bashful: names = ("수줍음", "Bashful", "てれや", "Tímida", "Pudique", "Tímida", "Zaghaft", "Застенчивый")
        case .rash:    names = ("덜렁", "Rash", "うっかりや", "Alocada", "Foufou", "Impulsiva", "Hitzig", "Опрометчивый")
        case .calm:    names = ("차분", "Calm", "おだやか", "Serena", "Calme", "Calma", "Still", "Спокойный")
        case .gentle:  names = ("얌전", "Gentle", "おとなしい", "Amable", "Gentil", "Gentil", "Zart", "Кроткий")
        case .sassy:   names = ("건방", "Sassy", "なまいき", "Grosera", "Malpoli", "Atrevida", "Forsch", "Нахальный")
        case .careful: names = ("신중", "Careful", "しんちょう", "Cauta", "Prudent", "Cautelosa", "Sacht", "Внимательный")
        case .quirky:  names = ("변덕", "Quirky", "きまぐれ", "Rara", "Bizarre", "Excêntrica", "Kauzig", "Ловкий")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2; case .es: return names.3; case .fr: return names.4; case .pt: return names.5; case .de: return names.6; case .ru: return names.7 }
    }
}

/// 게임 밸런스 — 개체 롤 확률.
enum PokemonOdds {
    /// 색이 다른 포켓몬(shiny) 부화 확률 분모 — 1/64 (본가 1/4096 은 데스크톱 앱 규모에선 평생 못 봄).
    static let shinyDenominator: UInt64 = 64
    /// R13: Arceus hatches from no egg, no event, no chest: only from the egg of the Hall of Origin's boss.
    static let dungeonOnly: Set<Int> = [493]
    /// 메타몽 위장 확률 분모 — common·≥2형태 부화에 한해 1/128 (GO 변장 메타몽 추정 1/50~70보다 귀하게).
    static let dittoDisguiseDenominator: UInt64 = 128
    /// 메타몽 종 id — 위장 리빌 전용(일반 부화 풀에서 제외).
    static let dittoSpeciesID = 132
    /// Egg-roll weight of every line of a rarity (`BaseSpecies.hatchWeight`). Each rarity keeps the share of eggs
    /// it had when lines weighed their capture rate (the index of 2026-10-23: 252 common, 65 uncommon, 135 rare and
    /// 88 legendary lines, 82.3 / 9.0 / 8.3 / 0.4 %), so the economy does not move; within a rarity every line is
    /// as likely. Whole numbers, so halving a complete line (`CollectionWeight.adjusted`) keeps working.
    static func hatchWeight(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common: return 212
        case .uncommon: return 90
        case .rare: return 40
        case .legendary: return 3
        }
    }
}

/// 현재 키우는 포켓몬.
struct MonState: Codable, Sendable, Equatable {
    var baseID: Int
    var pathIDs: [Int]      // 실제 진화 경로(분기 선택 반영)
    var plannedPathIDs: [Int] // 사전에 선택한 전체 진화 경로
    var stageIndex: Int     // pathIDs 내 현재 위치
    var usedAtStage: Int    // 현재 형태에서 누적 사용량
    var rarity: Rarity
    var totalForms: Int
    var isShiny = false             // 부화 시 확정, 진화해도 유지
    var nature: PokemonNature?      // 부화 시 확정 (구버전 저장은 nil)
    /// Chosen at hatch for the whole line and resolved per species (`PokemonForm.resolved`).
    var form: PokemonForm?
    /// 개체 고유 전투 프로필. 구버전 저장은 nil이며 `CompanionStore`가 한 번만 마이그레이션한다.
    var profile: PokemonProfile?
    var hasGrowthBoost = false
    /// Hatched in a form its line had never registered (Prison Bottle). Fixed at hatch, kept through evolution.
    var hasNewForm = false
    /// Hatched from a Fossil Egg: sent off before it graduates, its egg goes back to the Bag, or its line would be
    /// out of reach (there are as many eggs as fossil lines).
    var fromFossilEgg = false
    /// Hatched from a legendary boss's egg (`DungeonEgg.isLegendary`): won once, it is never sent off for another egg
    /// before it graduates (the owner, 2026-11-04), and graduates for 200M (`graduationTotal`).
    var fromLegendaryBossEgg = false
    /// Hatched from an evolution stone's egg (the Tera Orb grows it faster) or from an egg of a guaranteed rarity,
    /// bought or given by an achievement (the Sea Incense). An event egg's type or rarity is the event's: neither.
    var fromStoneEgg = false
    var fromRarityEgg = false
    /// Its raising record from its hatch on (`RaisingRecord`).
    var raising: RaisingRecord?
    /// Its egg and the draw items its rolls met (`HatchRecord`), for a Pokémon hatched since the record is kept.
    var hatch: HatchRecord?
    /// The costume this individual brought when it became a Pikachu: it wears that one rather than the equipped one.
    var pikachuCostume: PikachuCostume?
    /// The Pokémon GO costume it hatched in from a Costume Egg (`CostumeEntry.code`): it grows only into the stages
    /// that wear it, and wears it for good.
    var costume: String?
    // 메타몽 위장 — nil=일반. 값=정체 메타몽, 이 종으로 위장 중(위장 구간엔 baseID 와 동일, 리빌 후에도 원 위장체 보존).
    var dittoDisguise: Int?
    var dittoRevealed = false       // 위장 → 리빌(정체 공개) 전환 여부
    /// 화면에 이로치로 보여도 되는가 — 위장 중 메타몽은 리빌 전까지 숨긴다. 표시 경로는 전부 이것만 쓴다.
    var displaysShiny: Bool { isShiny && (dittoDisguise == nil || dittoRevealed) }
    // pathIDs 가 비면(손상된 상태 파일) baseID 로 폴백 — 렌더마다 읽히므로 out-of-bounds 크래시 방지.
    var currentID: Int { pathIDs.isEmpty ? baseID : pathIDs[min(stageIndex, pathIDs.count - 1)] }
    /// The look its sprites show: a Pikachu in the costume it brought, otherwise its form at this species.
    var spriteForm: PokemonForm? {
        if let costume {
            return CostumeCatalog.entry(code: costume, speciesID: currentID, form: form)?.displayForm
                ?? CostumeCatalog.displayForm(code: costume, form: nil)
        }
        if currentID == PikachuCostume.speciesID, let pikachuCostume { return pikachuCostume.form }
        return PokemonForm.resolved(speciesID: currentID, form: form)
    }
    /// The tokens its whole growth takes: its rarity's, a legendary boss's egg's Pokémon less (the owner, 2026-11-05).
    /// Its level still counts on its rarity's scale (`CompanionStore.reconcileActiveProfileGrowth`), as with a repeat.
    var graduationTotal: Int {
        fromLegendaryBossEgg ? PokemonBalance.legendaryBossGraduationTotal : PokemonBalance.graduationTotal(rarity)
    }
    var phaseThreshold: Int {
        PokemonBalance.phaseThreshold(
            total: graduationTotal,
            totalForms: totalForms,
            stageIndex: stageIndex,
            growthMultiplier: hasGrowthBoost ? PokemonBalance.repeatGrowthMultiplier : 1)
    }

    init(baseID: Int, pathIDs: [Int], plannedPathIDs: [Int]? = nil, stageIndex: Int, usedAtStage: Int,
         rarity: Rarity, totalForms: Int, isShiny: Bool = false, nature: PokemonNature? = nil,
         profile: PokemonProfile? = nil, hasGrowthBoost: Bool = false,
         dittoDisguise: Int? = nil, dittoRevealed: Bool = false, form: PokemonForm? = nil) {
        self.baseID = baseID
        self.pathIDs = pathIDs
        if let plannedPathIDs, !plannedPathIDs.isEmpty {
            self.plannedPathIDs = plannedPathIDs
        } else {
            self.plannedPathIDs = pathIDs
        }
        self.stageIndex = stageIndex
        self.usedAtStage = usedAtStage
        self.rarity = rarity
        self.totalForms = totalForms
        self.isShiny = isShiny
        self.nature = nature
        self.profile = profile
        self.hasGrowthBoost = hasGrowthBoost
        self.dittoDisguise = dittoDisguise
        self.dittoRevealed = dittoRevealed
        self.form = PokemonForm.resolved(baseID: baseID, form: form)
    }

    // 하위호환 디코딩: 구버전 저장에 없는 부화 속성은 기본값.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseID = try c.decode(Int.self, forKey: .baseID)
        pathIDs = try c.decode([Int].self, forKey: .pathIDs)
        // 빈 pathIDs 는 손상 상태 → 디코드 실패시켜 전체 CompanionState 가 기본(알)로 폴백되게 한다.
        guard !pathIDs.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pathIDs, in: c, debugDescription: "empty pathIDs")
        }
        if let savedPlan = try c.decodeIfPresent([Int].self, forKey: .plannedPathIDs), !savedPlan.isEmpty {
            plannedPathIDs = savedPlan
        } else {
            plannedPathIDs = pathIDs
        }
        let decodedStageIndex = try c.decode(Int.self, forKey: .stageIndex)
        stageIndex = min(max(0, decodedStageIndex), pathIDs.count - 1)
        usedAtStage = try c.decode(Int.self, forKey: .usedAtStage)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        totalForms = try c.decode(Int.self, forKey: .totalForms)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        // A nature this version cannot read is dropped, not the whole individual (the Pokémon raised was lost).
        nature = c.lenientOptional(PokemonNature.self, forKey: .nature)
        // 손상된 신규 프로필 하나 때문에 기존 성장 상태 전체를 잃지 않는다. nil이면 스토어가 재마이그레이션한다.
        profile = (try? c.decodeIfPresent(PokemonProfile.self, forKey: .profile)) ?? nil
        hasGrowthBoost = try c.decodeIfPresent(Bool.self, forKey: .hasGrowthBoost) ?? false
        hasNewForm = try c.decodeIfPresent(Bool.self, forKey: .hasNewForm) ?? false
        fromFossilEgg = (try? c.decodeIfPresent(Bool.self, forKey: .fromFossilEgg)) ?? false
        fromLegendaryBossEgg = (try? c.decodeIfPresent(Bool.self, forKey: .fromLegendaryBossEgg)) ?? false
        fromStoneEgg = (try? c.decodeIfPresent(Bool.self, forKey: .fromStoneEgg)) ?? false
        fromRarityEgg = (try? c.decodeIfPresent(Bool.self, forKey: .fromRarityEgg)) ?? false
        raising = (try? c.decodeIfPresent(RaisingRecord.self, forKey: .raising)) ?? nil
        hatch = (try? c.decodeIfPresent(HatchRecord.self, forKey: .hatch)) ?? nil
        // A costume this version doesn't know is dropped, not the whole individual.
        pikachuCostume = ((try? c.decodeIfPresent(String.self, forKey: .pikachuCostume)) ?? nil)
            .flatMap(PikachuCostume.init(rawValue:))
        dittoDisguise = try c.decodeIfPresent(Int.self, forKey: .dittoDisguise)
        dittoRevealed = try c.decodeIfPresent(Bool.self, forKey: .dittoRevealed) ?? false
        form = PokemonForm.resolved(baseID: baseID, form: PokemonForm.decoded(from: decoder, keys: "form", "unownForm"))
        costume = c.lenientOptional(String.self, forKey: .costume)
    }
}

/// 도감 항목 — 라인 전체(초기→최종) 순서 보존.
struct DexEntry: Codable, Sendable, Identifiable, Equatable {
    /// Version 1 preserves every API language; earlier saves retained only app-supported names.
    static let currentNamesVersion = 1
    var id = UUID().uuidString
    var baseID: Int
    var finalID: Int
    var chainOrder: [Int]   // 초기→최종 종 id
    var rarity: Rarity
    var caughtAt: Date?
    var isShiny = false
    var nature: PokemonNature?
    var form: PokemonForm?
    /// The individual profile at graduation/release. Nil only for pre-profile saves until migration.
    var profile: PokemonProfile?
    /// 진화 체인 각 종의 다국어 이름(speciesID → langCode → name). 졸업 시 로드된 라인에서 저장 →
    /// 도감의 단계별 스프라이트 밑 이름 표시가 네트워크 없이 즉시 + 언어 전환 대응. 구버전 저장분엔
    /// 없어(nil) 뷰가 line fetch 로 조회 후 백필한다.
    var names: [Int: [String: String]]?
    var namesVersion: Int?
    var needsNamesRefresh: Bool {
        namesVersion != Self.currentNamesVersion
            || chainOrder.contains { names?[$0]?.isEmpty != false }
    }
    /// 놓아준 시각 — 알을 새로 사서 육성을 포기한 기록. nil = 졸업분(구버전 저장분 포함).
    ///
    /// 두 기록을 한 배열에 두는 이유: 도감(`dexSpecies`)은 종이 어떻게 확보됐는지와 무관하게
    /// **보유 종**을 접는다. 놓아준 개체를 여기 넣지 않으면 그 종이 도감에서 사라진다 —
    /// 수집 화면이 "쌓이기만 한다"는 약속을 깨는 유일한 경로였다.
    var releasedAt: Date?
    /// The individual brought a form its line had never registered (`MonState.hasNewForm`). False for entries saved
    /// before it was kept.
    var hasNewForm = false
    /// What raised it (`RaisingRecord`), for a Pokémon hatched since the record is kept.
    var raising: RaisingRecord?
    /// How it hatched (`HatchRecord`), for a Pokémon hatched since the record is kept, or the egg its player chose.
    var hatch: HatchRecord?
    /// The Pokémon GO costume it wears (`MonState.costume`), at every stage of its chain that has it.
    var costume: String?
    /// The records it carried while raised (`MonState.raising`, `MonState.hatch`), and its costume.
    func withRecords(of mon: MonState) -> DexEntry {
        var entry = self
        entry.raising = mon.raising
        entry.hatch = mon.hatch
        entry.costume = mon.costume
        return entry
    }
    /// The look its sprites show at `speciesID` (its final species by default): its costume when that stage wears it.
    func spriteForm(at speciesID: Int? = nil) -> PokemonForm? {
        let id = speciesID ?? finalID
        guard let costume, let entry = CostumeCatalog.entry(code: costume, speciesID: id, form: form) else {
            return PokemonForm.resolved(speciesID: id, form: form)
        }
        return entry.displayForm
    }
    /// 졸업이 아니라 놓아준 기록인가 — 포획 로그가 뱃지를 가르는 판정.
    var isReleased: Bool { releasedAt != nil }

    init(id: String = UUID().uuidString,
         baseID: Int, finalID: Int, chainOrder: [Int], rarity: Rarity,
         caughtAt: Date?, isShiny: Bool = false, nature: PokemonNature? = nil,
         profile: PokemonProfile? = nil, names: [Int: [String: String]]? = nil, releasedAt: Date? = nil,
         form: PokemonForm? = nil, hasNewForm: Bool = false) {
        self.id = id
        self.hasNewForm = hasNewForm
        self.baseID = baseID
        self.finalID = finalID
        self.chainOrder = chainOrder
        self.rarity = rarity
        self.caughtAt = caughtAt
        self.isShiny = isShiny
        self.nature = nature
        self.profile = profile
        self.names = names
        self.namesVersion = chainOrder.allSatisfy { names?[$0]?.isEmpty == false }
            ? Self.currentNamesVersion : nil
        self.releasedAt = releasedAt
        self.form = PokemonForm.resolved(baseID: baseID, form: form)
    }

    // 하위호환 디코딩 (MonState 와 동일 이유).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        baseID = try c.decode(Int.self, forKey: .baseID)
        finalID = try c.decode(Int.self, forKey: .finalID)
        chainOrder = try c.decode([Int].self, forKey: .chainOrder)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        caughtAt = try c.decodeIfPresent(Date.self, forKey: .caughtAt)
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        // A nature this version cannot read is dropped, not the whole individual (the Pokémon raised was lost).
        nature = c.lenientOptional(PokemonNature.self, forKey: .nature)
        // 프로필만 손상되면 개체 기록은 보존하고 프로필을 다시 생성한다.
        profile = (try? c.decodeIfPresent(PokemonProfile.self, forKey: .profile)) ?? nil
        // try? — 구버전(최종체 단일 [String:String]) 형식이 남아 있어도 종별 맵 디코딩 실패 시 nil 로
        // 강등(항목 전체 로드는 유지). 뷰가 line 조회로 백필한다.
        names = (try? c.decodeIfPresent([Int: [String: String]].self, forKey: .names)) ?? nil
        namesVersion = try? c.decodeIfPresent(Int.self, forKey: .namesVersion)
        // 이 필드 이전에 저장된 항목은 전부 졸업분이다 — nil 이 곧 "졸업"이라 마이그레이션이 필요 없다.
        releasedAt = try c.decodeIfPresent(Date.self, forKey: .releasedAt)
        hasNewForm = (try? c.decodeIfPresent(Bool.self, forKey: .hasNewForm)) ?? false
        raising = (try? c.decodeIfPresent(RaisingRecord.self, forKey: .raising)) ?? nil
        hatch = (try? c.decodeIfPresent(HatchRecord.self, forKey: .hatch)) ?? nil
        form = PokemonForm.resolved(baseID: baseID, form: PokemonForm.decoded(from: decoder, keys: "form", "unownForm"))
        costume = c.lenientOptional(String.self, forKey: .costume)
    }
}

/// A build of the app: its commit, that commit's date ("yyyy-MM-dd HH:mm" in the committer's time zone, for people)
/// and its time in seconds since 1970 (to order builds), from its Info.plist (`scripts/build-app.sh`). Nil for a build
/// without them (`swift run`, the tests).
struct SaveWriter: Codable, Equatable, Sendable {
    var commit: String
    var date: String
    /// nil in a save the first builds that stamped it wrote.
    var time: Int?

    static let current: SaveWriter? = {
        guard let commit = Bundle.main.object(forInfoDictionaryKey: "PTBCommitSHA") as? String,
              !commit.isEmpty, commit != "unknown",
              let date = Bundle.main.object(forInfoDictionaryKey: "PTBCommitDate") as? String, !date.isEmpty
        else { return nil }
        let time = (Bundle.main.object(forInfoDictionaryKey: "PTBCommitTime") as? String).flatMap { Int($0) }
        return SaveWriter(commit: commit, date: date, time: time)
    }()

    /// Whether a save this writer wrote comes from a build later than `build`. By time only: the dates are each in
    /// their committer's zone, and a commit made in Seoul read as later than one made after it in Paris. Without both
    /// times, not newer: the save is written, as it was before the stamp.
    func isNewer(than build: SaveWriter) -> Bool {
        guard let time, let other = build.time else { return false }
        return commit != build.commit && time > other
    }
}

/// 배열 항목별 격리 디코딩 래퍼 — 손상된 한 항목이 배열 전체(및 상위 상태) 디코드를 실패시키지 않게.
/// 각 항목을 `try?` 로 감싸므로 실패 항목은 `value == nil` 이 되고 배열 디코드 자체는 성공한다.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
        if value == nil { LenientDecoding.lost(decoder.codingPath.map(\.stringValue).joined(separator: ".")) }
    }
}

/// What the lenient decoding left out while a load records it: a field of another shape (a save a newer version wrote,
/// a broken one) falls back to its default, and the load copies the file aside before writing over it. Kept per
/// thread, so a decode elsewhere (a snapshot's summary) is not counted.
enum LenientDecoding {
    private static let key = "PokeTokenBar.LenientDecoding.losses"

    static func recordingLosses<T>(_ body: () throws -> T) rethrows -> (value: T, losses: [String]) {
        let thread = Thread.current
        let outer = thread.threadDictionary[key]
        let losses = NSMutableArray()
        thread.threadDictionary[key] = losses
        defer { thread.threadDictionary[key] = outer }
        let value = try body()
        return (value, losses.compactMap { $0 as? String })
    }

    static func lost(_ path: String) {
        (Thread.current.threadDictionary[key] as? NSMutableArray)?.add(path.isEmpty ? "?" : path)
    }
}

extension KeyedDecodingContainer {
    /// 관대 디코드 — 키 없음/null/타입 불일치를 모두 기본값으로 흡수한다. 한 필드 손상이 상태 전체
    /// (도감·인벤토리)를 날리지 않게(부분 복원 > 전면 리셋). 최상위가 JSON 객체가 아닌 전면 손상은 여전히 throw.
    /// A value present but of another shape is a loss (`LenientDecoding`); a key absent or null is not.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default def: T) -> T {
        do { return try decode(type, forKey: key) } catch {
            noteLoss(key)
            return def
        }
    }
    func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do { return try decode(type, forKey: key) } catch {
            noteLoss(key)
            return nil
        }
    }
    func noteLoss(_ key: Key) {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return }
        LenientDecoding.lost((codingPath + [key]).map(\.stringValue).joined(separator: "."))
    }
}

/// The forms each species was graduated in, read in one pass over the Pokédex: a roll asks for them line after line.
struct GraduatedForms: Sendable {
    private var bySpecies: [Int: Set<PokemonForm>] = [:]

    /// `includingReleased`: the rule until #89 of `HatchRules`, when a form counted once registered.
    init(_ dex: [DexEntry], includingReleased: Bool = false) {
        for entry in dex where includingReleased || !entry.isReleased {
            for id in entry.chainOrder where PokemonForm.hasForms(speciesID: id) {
                if let form = PokemonForm.resolved(speciesID: id, form: entry.form) { bySpecies[id, default: []].insert(form) }
            }
        }
    }

    subscript(speciesID: Int) -> Set<PokemonForm> { bySpecies[speciesID] ?? [] }
}

/// 영속 상태(Application Support JSON). 포켓몬 전환 — 이전 커스텀 캐릭터 상태는 폐기(새로 시작).
struct CompanionState: Codable, Sendable, Equatable {
    // 토큰: 설치 이후만 측정
    var installBaselineSet = false
    var usedSinceInstall = 0
    // 상점에서 쓴 토큰 누적(재화 지출 원장). 쓸 수 있는 재화 = usedSinceInstall − spentTokens.
    // 성장 미터(usedSinceInstall)는 불변 — 구매는 이 값만 올려 잔액을 깎는다(성장 되감김 없음).
    var spentTokens = 0
    /// What the travelling merchant paid (2026-11-09): added to the wallet, never to growth. Apart from `spentTokens`,
    /// which a save's import clamps at zero (`SaveTransfer.sanitized`).
    var merchantTokens = 0
    // 현재 알이 생긴 뒤 쓴 토큰(부화 인큐베이션). 누적(usedSinceInstall)과 별개 — 졸업 후 새 알마다 0.
    var eggUsage = 0
    // 현재 알이 보증하는 등급 하한(프리미엄 알). nil = 보증 없음(무료 알·기본 알).
    // ★영속이어야 한다 — 구매 시점엔 종을 못 정한다(롤에 네트워크가 필요). 보증을 상태에 적어 두고
    // 롤이 그것을 읽어야 오프라인·재시작을 건너서도 산 것을 받는다. 부화·졸업 때 nil 로 소비된다.
    var eggTier: Rarity?
    // 알에서 특정 타입의 포켓몬이 부화하도록 보증하는 타입(진화의 돌 사용). nil = 타입 보증 없음.
    var eggTypeGuarantee: PokemonType?
    /// The egg came from the Type: Null Egg: it is drawn as that egg. A plain egg that pre-rolled Type: Null stays a
    /// plain egg, so the roll is not given away before the hatch. Consumed with the egg's other guarantees.
    var eggFromTypeNullEgg = false
    /// The egg came from a Legendary Egg: it hatches a legendary or mythical Pokémon, and is drawn as that egg.
    /// Consumed with the egg's other guarantees.
    var eggFromLegendaryEgg = false
    /// The egg came from the Birthday Egg: it hatches a mythical Pokémon not graduated yet (`BirthdayGift`), and is
    /// drawn as that egg. Consumed with the egg's other guarantees.
    var eggFromBirthdayEgg = false
    /// The egg in incubation is a Fossil Egg (`FossilDig`).
    var eggFromFossilEgg = false
    /// The egg in incubation was won in a dungeon (`DungeonEgg`): it hatches its line, shiny when it was.
    var eggFromDungeon: DungeonEgg?
    /// The Costume Eggs of the Bag (`CostumeEgg`), the one in incubation, and the tokens toward the next one
    /// (`CostumeCatalog.tokensPerEgg`).
    var costumeEggs: [CostumeEgg] = []
    var eggFromCostume: CostumeEgg?
    var costumeEggTokens = 0
    /// Fossil Eggs hatched so far.
    var fossilEggsHatched = 0
    /// The fossil lines graduated when the save first met the digs: their digs are done with nothing to claim. Taken
    /// once: a line hatched from a Fossil Egg afterwards must never free a dig (`FossilDig`).
    var fossilLinesBeforeDigs: Set<Int>?
    /// The pre-rolled hatch is shiny whatever its roll: a Birthday Egg once every legendary and mythical graduated.
    var pendingShiny = false
    /// The line of the last Pokémon hatched: the next egg never brings it again while another line is left.
    var lastHatchedBaseID: Int?
    /// The player's birthday, without the year; nil until they enter it in Settings.
    var birthday: Birthday?
    /// The build that wrote the save last (`SaveWriter.current`): a build older than it does not write over what it
    /// may not understand.
    var writer: SaveWriter?
    /// The year of the last birthday whose gift was claimed; nil for a save that never got one.
    var lastBirthdayGiftYear: Int?
    /// When that gift was claimed: a December birthday's gift claimed in January counts for the year before.
    var lastBirthdayGiftClaimedAt: Date?
    /// The birthday the last gift was for: typing it again after clearing it is no change of date.
    var lastBirthdayGiftDate: Birthday?
    /// Set when the birthday changes after a gift: the calendar year that gift was claimed in. The next gift must be
    /// for a later birthday year, so a new date never brings a second egg within a year of the last.
    var birthdayChangedAfterGiftYear: Int?
    /// The event eggs claimed (`EventEgg.key`, "christmas@2026"): one a year each, kept with the save.
    var claimedEventEggs: Set<String> = []
    /// The event eggs announced, so the notification comes once.
    var eventEggsNotified: Set<String> = []
    /// The egg came from an event egg: it hatches that event's Pokémon (`CompanionStore.chooseBase`).
    var eggEvent: EventEgg?
    /// The claim of the event egg incubating (`EventEgg.key`), and the base each claimed one hatched, from 2026-10-29:
    /// the calendar says what came out of each egg taken.
    var eggEventKey: String?
    var eventEggHatches: [String: Int] = [:]
    /// The EXP the Old Amber kept of the Pokémon sent off for the egg incubating, given to the one that hatches.
    var amberCarry = 0
    /// Pokémon graduated toward the Explorer Kit's next treasure, and the treasures not seen yet (item, count), which
    /// the news strip shows until the player opens the Bag or closes it.
    var graduationsTowardTreasure = 0
    var unseenTreasures: [String: Int] = [:]
    /// The year of the last birthday the gift was announced for, so the notification comes once.
    var birthdayNotifiedYear: Int?
    // 알 상태에서 미리 롤해둔 부화 종(프리패칭) — 부화 순간 네트워크 딜레이 제거. 재시작에도 유지.
    var pendingHatchID: Int?
    /// The form is chosen with the species so prefetch warms the exact sprite that will hatch.
    var pendingForm: PokemonForm?
    /// The draw items owned when `pendingHatchID` was rolled (`HatchRecord.rollItems`); nil for an egg that rolls nothing.
    var pendingHatchItems: Set<ItemKind>?
    /// 오늘 사용량 적립 기준값 — 프로바이더별로 독립 관리한다.
    ///
    /// `nil`은 aggregate `claimedTodayTokens`만 가지고 있던 구버전 세이브가 아직 첫 유효
    /// snapshot을 기준으로 seed되지 않았다는 뜻이다. 첫 update에서 현재 프로바이더 값을
    /// 기준값으로만 저장하고, 과거 사용량은 소급 지급하지 않는다. 빈 map은 이미 seed된 뒤
    /// 오늘 보고한 프로바이더가 없는 정상 상태와 구분되어야 하므로 `nil`과 별도로 유지한다.
    /// 키는 `UsageProvider.id`를 그대로 사용한다.
    var claimedTodayTokensByProvider: [String: Int]? = nil
    var lastDate = ""
    // 현재 포켓몬(없으면 알)
    var active: MonState?
    // 메뉴바와 플로팅 펫에 고정한 대표 종. nil = 현재 키우는 포켓몬(또는 알)을 그대로 따라간다.
    // 종 단위 선택이라 성격 같은 개체 정보는 들고 있지 않는다. 선택 가능한 범위는 도감과 동일하게
    // 졸업분 + 현재 개체의 도달 단계이며, 그 범위에서 빠지면 reconcileRepresentativeSelection 이 nil 로 복구한다.
    var representativeSpeciesID: Int? = nil
    var representativeForm: PokemonForm? = nil
    // 도감
    var dex: [DexEntry] = []
    // 소유한 (base,final) 쌍 — 분기 다양성용
    var collectedFinals: Set<String> = []
    var language: AppLanguage = .systemDefault   // 신규 설치 = 시스템 로케일
    // 인벤토리 (ItemKind.rawValue → 개수)
    var inventory: [String: Int] = [:]
    // Achievements already claimed (ItemKind.rawValue). The Bag cannot tell: stones are used up, and an
    // empty slot must not make their achievement claimable again.
    var claimedAchievements: Set<String> = []
    /// Pikachu's costumes won so far, one per Pikachu that arrived (`PikachuCostume`).
    var pikachuCostumes: Set<PikachuCostume> = []
    /// The costume Pikachu wears, chosen on its Pokédex page; nil, its own look.
    var equippedPikachuCostume: PikachuCostume?
    /// The graduated Pokémon the player liked on their Pokédex page (`DexEntry.id`): the ♥ filter's.
    var favoriteIDs: Set<String> = []
    // Candies already paid by each limit window (key) in its current epoch. ★영속: 재시작 무한지급 방지.
    // Before `candyGrantsAsYouGo`, 1 meant "paid at 100%".
    var candyGrantTier: [String: Int] = [:]
    // 창 key → 마지막으로 본 epoch(`resets_at`). util 이 계속 100%여도 epoch 교체로 재무장(#326).
    var candyWindowEpoch: [String: String] = [:]
    /// The plan (`CandyWindow.planMultiplier`) each window was last seen at. A window first seen, or seen at another
    /// plan, is recorded as paid up to what it owes then (`CompanionStore.grantCandies`): its usage so far was used
    /// before the app knew it, or counted at another plan (#79).
    var candyWindowPlan: [String: Int] = [:]
    /// Tokens of the tools without limit windows since their last candy (`RareCandy.tokensPerCandyWithoutLimits`),
    /// and the candies they paid.
    var tokenCandyTokens = 0
    var tokenCandiesEarned = 0
    // 사탕 지급 첫 실행 시드 완료 — 업데이트 직후 이미 100%였던 창의 소급 지급 차단.
    var candyFeatureSeeded = false
    /// Windows pay their candies as they go (`RareCandy.candiesDue`). A save from before has `false`: its windows'
    /// ledger said only whether 100% was paid, and is carried over once by `CompanionStore.grantCandies`.
    var candyGrantsAsYouGo = false
    /// The growth bonuses add up (they used to multiply). A save from before that has `false`, and its current
    /// stage is carried over once by `CompanionStore.migrateToAdditiveGrowthIfNeeded`.
    var additiveGrowthBonuses = true
    /// The dungeons: the expedition under way, the victories, the bosses met, the move loops, the moves unlocked, the
    /// eggs won (`DungeonProgress`).
    var dungeons = DungeonProgress()

    init() {}

    // 하위호환 + 손상 복원 디코딩: 누락 키·타입 불일치·일부 손상 필드를 모두 기본값으로 흡수한다 —
    // 한 필드가 깨져도 상태 전체(도감·인벤토리)를 날리지 않는다(부분 복원). 최상위가 JSON 객체가 아닌
    // 전면 손상만 throw → load() 가 원본을 .corrupt 로 백업하고 fresh 로 시작.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installBaselineSet = c.lenient(Bool.self, forKey: .installBaselineSet, default: false)
        usedSinceInstall   = c.lenient(Int.self, forKey: .usedSinceInstall, default: 0)
        spentTokens        = c.lenient(Int.self, forKey: .spentTokens, default: 0)
        merchantTokens     = c.lenient(Int.self, forKey: .merchantTokens, default: 0)
        eggUsage           = c.lenient(Int.self, forKey: .eggUsage, default: 0)
        // 모르는 rawValue 는 nil(보증 없음)로 강등 — 관대 디코딩의 안전한 방향(있지도 않은 보증을 만들지 않는다).
        eggTier            = c.lenientOptional(Rarity.self, forKey: .eggTier)
        eggTypeGuarantee   = c.lenientOptional(PokemonType.self, forKey: .eggTypeGuarantee)
        pendingHatchID     = c.lenientOptional(Int.self, forKey: .pendingHatchID)
        pendingForm        = PokemonForm.resolved(baseID: pendingHatchID ?? 0,
            form: PokemonForm.decoded(from: decoder, keys: "pendingForm", "pendingUnownForm"))
        pendingHatchItems = (try? c.decodeIfPresent([String].self, forKey: .pendingHatchItems))?
            .map { Set($0.compactMap(ItemKind.init(rawValue:))) }
        if c.contains(.claimedTodayTokensByProvider) {
            claimedTodayTokensByProvider = c.lenient([String: Int].self,
                                                      forKey: .claimedTodayTokensByProvider,
                                                      default: [:])
        } else {
            // 구버전의 aggregate claimedTodayTokens 키는 의도적으로 읽지 않는다. 프로바이더별
            // 분해가 불가능하므로 다음 CompanionStore.update에서 현재 snapshot을 기준점으로 seed한다.
            claimedTodayTokensByProvider = nil
        }
        lastDate           = c.lenient(String.self, forKey: .lastDate, default: "")
        // active 손상(빈 pathIDs 등) → 알로 폴백하되 도감·인벤토리는 보존.
        active             = c.lenientOptional(MonState.self, forKey: .active)
        representativeSpeciesID = c.lenientOptional(Int.self, forKey: .representativeSpeciesID)
        representativeForm = PokemonForm.resolved(speciesID: representativeSpeciesID ?? 0,
            form: PokemonForm.decoded(from: decoder, keys: "representativeForm", "representativeUnownForm"))
        // 도감은 항목별 격리 — 손상 항목 하나가 도감 전체를 날리지 않게.
        dex                = c.lenient([Lossy<DexEntry>].self, forKey: .dex, default: []).compactMap(\.value)
        collectedFinals    = c.lenient(Set<String>.self, forKey: .collectedFinals, default: [])
        language           = c.lenient(AppLanguage.self, forKey: .language, default: .systemDefault)
        inventory          = c.lenient([String: Int].self, forKey: .inventory, default: [:])
        claimedAchievements = c.lenient(Set<String>.self, forKey: .claimedAchievements, default: [])
        // Unknown costumes (a later version's) are dropped one by one, never the whole set.
        pikachuCostumes = Set(c.lenient([String].self, forKey: .pikachuCostumes, default: []).compactMap(PikachuCostume.init(rawValue:)))
        equippedPikachuCostume = c.lenientOptional(String.self, forKey: .equippedPikachuCostume)
            .flatMap(PikachuCostume.init(rawValue:)).flatMap { pikachuCostumes.contains($0) ? $0 : nil }
        favoriteIDs        = c.lenient(Set<String>.self, forKey: .favoriteIDs, default: [])
        candyGrantTier     = c.lenient([String: Int].self, forKey: .candyGrantTier, default: [:])
        candyWindowEpoch   = c.lenient([String: String].self, forKey: .candyWindowEpoch, default: [:])
        candyWindowPlan    = c.lenient([String: Int].self, forKey: .candyWindowPlan, default: [:])
        tokenCandyTokens   = c.lenient(Int.self, forKey: .tokenCandyTokens, default: 0)
        tokenCandiesEarned = c.lenient(Int.self, forKey: .tokenCandiesEarned, default: 0)
        candyFeatureSeeded = c.lenient(Bool.self, forKey: .candyFeatureSeeded, default: false)
        candyGrantsAsYouGo = c.lenient(Bool.self, forKey: .candyGrantsAsYouGo, default: false)
        additiveGrowthBonuses = c.lenient(Bool.self, forKey: .additiveGrowthBonuses, default: false)
        eggFromTypeNullEgg = c.lenient(Bool.self, forKey: .eggFromTypeNullEgg, default: false)
        eggFromLegendaryEgg = c.lenient(Bool.self, forKey: .eggFromLegendaryEgg, default: false)
        eggFromBirthdayEgg = c.lenient(Bool.self, forKey: .eggFromBirthdayEgg, default: false)
        eggFromFossilEgg = c.lenient(Bool.self, forKey: .eggFromFossilEgg, default: false)
        eggFromDungeon = c.lenientOptional(DungeonEgg.self, forKey: .eggFromDungeon)
        costumeEggs = c.lenient([CostumeEgg].self, forKey: .costumeEggs, default: [])
        eggFromCostume = c.lenientOptional(CostumeEgg.self, forKey: .eggFromCostume)
        costumeEggTokens = c.lenient(Int.self, forKey: .costumeEggTokens, default: 0)
        fossilEggsHatched = c.lenient(Int.self, forKey: .fossilEggsHatched, default: 0)
        fossilLinesBeforeDigs = c.lenientOptional(Set<Int>.self, forKey: .fossilLinesBeforeDigs)
        pendingShiny = c.lenient(Bool.self, forKey: .pendingShiny, default: false)
        lastHatchedBaseID = c.lenientOptional(Int.self, forKey: .lastHatchedBaseID)
        birthday = c.lenientOptional(Birthday.self, forKey: .birthday)
        lastBirthdayGiftYear = c.lenientOptional(Int.self, forKey: .lastBirthdayGiftYear)
        lastBirthdayGiftClaimedAt = c.lenientOptional(Date.self, forKey: .lastBirthdayGiftClaimedAt)
        lastBirthdayGiftDate = c.lenientOptional(Birthday.self, forKey: .lastBirthdayGiftDate)
        birthdayChangedAfterGiftYear = c.lenientOptional(Int.self, forKey: .birthdayChangedAfterGiftYear)
        claimedEventEggs = c.lenient(Set<String>.self, forKey: .claimedEventEggs, default: [])
        eventEggsNotified = c.lenient(Set<String>.self, forKey: .eventEggsNotified, default: [])
        eggEvent = c.lenientOptional(EventEgg.self, forKey: .eggEvent)
        birthdayNotifiedYear = c.lenientOptional(Int.self, forKey: .birthdayNotifiedYear)
        writer = c.lenientOptional(SaveWriter.self, forKey: .writer)
        eggEventKey = c.lenientOptional(String.self, forKey: .eggEventKey)
        eventEggHatches = c.lenient([String: Int].self, forKey: .eventEggHatches, default: [:])
        amberCarry = c.lenient(Int.self, forKey: .amberCarry, default: 0)
        graduationsTowardTreasure = c.lenient(Int.self, forKey: .graduationsTowardTreasure, default: 0)
        unseenTreasures = c.lenient([String: Int].self, forKey: .unseenTreasures, default: [:])
        dungeons = c.lenient(DungeonProgress.self, forKey: .dungeons, default: DungeonProgress())
        if dungeons.bossesCaught == nil { dungeons.bossesCaught = bossesCaughtBefore }
    }

    /// The bosses a save from before the record had caught in their dungeon, from what it kept: the runs whose throws
    /// hit, the legendary bosses' eggs won, the boss eggs in the Bag or hatching, the Pokémon hatched from one. Only a
    /// dungeon's own bosses, never the Ruins of Alph's (any species) nor a secret boss's egg (Galarian Articuno's is
    /// no Articuno's).
    var bossesCaughtBefore: Set<String> {
        let dungeons = DungeonCatalog.all.filter { !$0.id.isChallenge && !$0.id.isHideout && $0.id != .ruinsOfAlph }
        var caught = Set<String>()
        func mark(_ species: Int) {
            for dungeon in dungeons where dungeon.bosses.contains(species) {
                caught.insert(DungeonProgress.bossKey(dungeon.id, species))
            }
        }
        func markLine(_ baseID: Int) {
            for dungeon in dungeons {
                for species in dungeon.bosses where SpeciesInfo.baseID(of: species) == baseID {
                    caught.insert(DungeonProgress.bossKey(dungeon.id, species))
                }
            }
        }
        for run in self.dungeons.history where run.won && run.caught {
            // A secret boss in the boss's place left the same species in the record: its egg's form tells them apart.
            guard !SecretBosses.candidates(run.dungeon).contains(where: { $0.speciesID == run.bossSpeciesID }) else { continue }
            if dungeons.contains(where: { $0.id == run.dungeon && $0.bosses.contains(run.bossSpeciesID) }) {
                caught.insert(DungeonProgress.bossKey(run.dungeon, run.bossSpeciesID))
            }
        }
        self.dungeons.legendaryEggsWon.forEach(mark)
        for egg in self.dungeons.eggs + [eggFromDungeon].compactMap({ $0 }) where egg.isSecret != true && egg.form == nil {
            mark(egg.sourceSpeciesID)
        }
        for entry in dex {
            if case .dungeon(let baseID, nil, _)? = entry.hatch?.egg { markLine(baseID) }
        }
        return caught
    }

    /// 졸업 기록 또는 현재 개체가 실제로 도달한 단계에 이 종이 포함되는가.
    /// 도감 전체 표시 모델을 만들지 않고 대표 종 하나만 확인하는 경량 경로다.
    func ownsSpecies(_ speciesID: Int, form: PokemonForm? = nil) -> Bool {
        let form = PokemonForm.resolved(speciesID: speciesID, form: form)
        // An Arceus in the Pokédex shows every form its Plates unlock.
        if PokemonForm.unlockSource(speciesID: speciesID) != nil, let form,
           form == PokemonForm.forms(speciesID: speciesID).first || itemUnlockedForms(speciesID: speciesID).contains(form) {
            return ownsSpeciesInAnyForm(speciesID)
        }
        if dex.contains(where: {
            $0.chainOrder.contains(speciesID)
                && PokemonForm.resolved(speciesID: speciesID, form: $0.form) == form
        }) { return true }
        guard let active else { return false }
        return active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID)
            && PokemonForm.resolved(speciesID: speciesID, form: active.form) == form
    }

    /// Ledger key of one regional tier of an achievement ("volcanoBadge@3" for the Volcano Badge's Hoenn tier).
    static func regionTierKey(_ kind: ItemKind, generation: Int) -> String { "\(kind.rawValue)@\(generation)" }

    /// Gym badges became regional tiers. A badge claimed or owned before that asked for its Kanto Pokémon
    /// (Johto for Dark): it becomes that tier, once. Idempotent; runs wherever a state comes in.
    mutating func migrateLegacyBadgeClaims() {
        for kind in ItemKind.allCases {
            guard let type = kind.badgeType else { continue }
            let legacy = claimedAchievements.contains(kind.rawValue) || (inventory[kind.rawValue] ?? 0) > 0
            let hasTiers = claimedAchievements.contains { $0.hasPrefix("\(kind.rawValue)@") }
            claimedAchievements.remove(kind.rawValue)
            if legacy, !hasTiers {
                claimedAchievements.insert(Self.regionTierKey(kind, generation: PokemonTypeData.badgeGeneration(for: type)))
            }
        }
    }

    /// Species of the Pokémon raised to the end: graduated entries, never released ones nor the Pokémon being raised.
    var graduatedSpeciesIDs: Set<Int> {
        Set(dex.lazy.filter { !$0.isReleased }.flatMap(\.chainOrder))
    }

    /// Most graduated copies of a single legendary species (released copies excluded).
    var registeredSpeciesIDs: Set<Int> {
        var ids = Set<Int>()
        for entry in dex { ids.formUnion(entry.chainOrder) }
        if let active { ids.formUnion(active.pathIDs.prefix(active.stageIndex + 1)) }
        return ids
    }

    var graduatedLegendaryCopies: Int {
        let graduated = dex.filter { $0.rarity == .legendary && !$0.isReleased }
        return Dictionary(grouping: graduated, by: \.finalID).values.map(\.count).max() ?? 0
    }

    /// The line the Friendship Egg brings back: the first catch's, unless it was a Ditto (`CompanionStore.companionLineID`).
    var companionLineID: Int? {
        dex.filter { $0.baseID != PokemonOdds.dittoSpeciesID }
            .compactMap { e in e.caughtAt.map { (date: $0, baseID: e.baseID) } }
            .min { $0.date < $1.date }?.baseID
    }

    func hasCollectedFinal(forBaseID baseID: Int) -> Bool {
        collectedFinals.contains { $0.hasPrefix("\(baseID):") }
    }

    /// Whether this line already graduated in this form. The repeat growth boost (and the Magma Stone and
    /// Liberty Pass split) is for an appearance already in the Pokédex: a Kanto Dugtrio graduated does not
    /// make an Alolan one a repeat. Lines without forms, and saves whose Pokédex no longer holds the
    /// graduated record, fall back to the line.
    func hasCollectedFinal(forBaseID baseID: Int, form: PokemonForm?) -> Bool {
        guard let form = PokemonForm.resolved(baseID: baseID, form: form) else {
            return hasCollectedFinal(forBaseID: baseID)
        }
        let graduated = dex.filter { $0.baseID == baseID && !$0.isReleased }
        guard !graduated.isEmpty else { return hasCollectedFinal(forBaseID: baseID) }
        return graduated.contains { PokemonForm.resolved(baseID: baseID, form: $0.form) == form }
    }

    /// The forms `hasCollectedFinal(forBaseID:form:)` holds for, read once for the many forms of a line.
    func collectedFinalForms(forBaseID baseID: Int) -> Set<PokemonForm> {
        let graduated = dex.filter { $0.baseID == baseID && !$0.isReleased }
        guard !graduated.isEmpty else { return hasCollectedFinal(forBaseID: baseID) ? Set(PokemonForm.lineForms(baseID: baseID)) : [] }
        return Set(graduated.compactMap { PokemonForm.resolved(baseID: baseID, form: $0.form) })
    }

    /// Match Pokédex ownership, including the active Pokémon and released catch records.
    /// Normal and shiny individuals of the same form contribute once.
    /// `graduatedOnly`: only the Pokémon raised to the end, what achievements count (not the one being raised, nor
    /// those sent off).
    func collectedForms(speciesID: Int, graduatedOnly: Bool = false) -> Set<PokemonForm> {
        if graduatedOnly { return graduatedForms(speciesID: speciesID, GraduatedForms(dex)) }
        guard PokemonForm.hasForms(speciesID: speciesID) else { return [] }
        var forms = Set(dex.lazy.filter { $0.chainOrder.contains(speciesID) }
            .compactMap { PokemonForm.resolved(speciesID: speciesID, form: $0.form) })
        if let active, active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID),
           let form = PokemonForm.resolved(speciesID: speciesID, form: active.form) {
            forms.insert(form)
        }
        return withItemForms(forms, speciesID: speciesID, graduatedOnly: false)
    }

    /// `collectedForms(graduatedOnly: true)`, from the forms the Pokédex was read for once.
    func graduatedForms(speciesID: Int, _ graduated: GraduatedForms) -> Set<PokemonForm> {
        withItemForms(graduated[speciesID], speciesID: speciesID, graduatedOnly: true)
    }

    /// Once in the Pokédex, Arceus has its default form and every form its Plates unlock.
    private func withItemForms(_ forms: Set<PokemonForm>, speciesID: Int, graduatedOnly: Bool) -> Set<PokemonForm> {
        guard !forms.isEmpty, PokemonForm.unlockSource(speciesID: speciesID) != nil else { return forms }
        var forms = forms
        if let first = PokemonForm.forms(speciesID: speciesID).first { forms.insert(first) }
        forms.formUnion(itemUnlockedForms(speciesID: speciesID, graduatedOnly: graduatedOnly))
        return forms
    }

    /// Whether the Pokédex has this species, in any form.
    func ownsSpeciesInAnyForm(_ speciesID: Int) -> Bool {
        if dex.contains(where: { $0.chainOrder.contains(speciesID) }) { return true }
        guard let active else { return false }
        return active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID)
    }

    /// Types whose gym badge has at least one region claimed: one Plate each.
    var plateTypes: Set<PokemonType> {
        Set(PokemonType.allCases.filter { type in
            claimedAchievements.contains { $0.hasPrefix("\(type.badgeItem.rawValue)@") }
        })
    }

    /// Types of the legendary and mythical Pokémon in the Pokédex, released ones included: one of Silvally's
    /// Memories each. Each gives the types of its own form, like everywhere else: a Galarian Moltres gives Dark and
    /// Flying, not Fire. Arceus's Plates and Silvally's Memories change a look, not the individual: they give their
    /// Normal type, even for one hatched in a type form before Plates and Memories existed.
    var silvallyMemoryTypes: Set<PokemonType> { memoryTypes(graduatedOnly: false) }

    /// Silvally's Memories won by graduated Pokémon only: what the Type: Null Egg's achievement counts.
    var graduatedSilvallyMemoryTypes: Set<PokemonType> { memoryTypes(graduatedOnly: true) }

    private func memoryTypes(graduatedOnly: Bool) -> Set<PokemonType> {
        let entries = graduatedOnly ? dex.filter { !$0.isReleased } : dex
        var individuals = entries.filter { $0.rarity == .legendary }.flatMap { entry in
            entry.chainOrder.map { (speciesID: $0, form: entry.form) }
        }
        if !graduatedOnly, let active, active.rarity == .legendary {
            individuals += active.pathIDs.prefix(active.stageIndex + 1).map { (speciesID: $0, form: active.form) }
        }
        return Set(individuals.flatMap { individual in
            let form = PokemonForm.unlockSource(speciesID: individual.speciesID) == nil ? individual.form : nil
            return PokemonTypeData.types(forSpeciesID: individual.speciesID, form: form)
        }).subtracting([.normal])
    }

    /// Forms a species unlocks through items (Arceus's Plates, Silvally's Memories), whether or not it is in the
    /// Pokédex yet: they count as collected once it is. Its default form needs no item. `graduatedOnly`: the Memories
    /// of graduated legendaries only, what a goal counts.
    func itemUnlockedForms(speciesID: Int, graduatedOnly: Bool = false) -> Set<PokemonForm> {
        guard let source = PokemonForm.unlockSource(speciesID: speciesID) else { return [] }
        let types: Set<PokemonType>
        switch source {
        case .gymBadge: types = plateTypes
        case .legendaryType: types = memoryTypes(graduatedOnly: graduatedOnly)
        }
        return Set(PokemonForm.forms(speciesID: speciesID).filter {
            PokemonForm.unlockType(speciesID: speciesID, form: $0).map(types.contains) ?? false
        })
    }

    /// Whether the egg roll treats a line as collected (its weight halved): every final of the line graduated,
    /// branches and form-gated finals included, and every form of the line graduated. One graduated
    /// final is not enough: after a Vaporeon, Eevee keeps its full chance while seven evolutions are missing.
    func isLineComplete(baseID: Int, forms: [PokemonForm]? = nil, graduated: GraduatedForms? = nil) -> Bool {
        let finals = PokemonEvolutionData.finals(from: baseID)
        guard finals.allSatisfy({ collectedFinals.contains("\(baseID):\($0)") }) else { return false }
        let forms = forms ?? PokemonForm.rollableLineForms(baseID: baseID)
        return forms.isEmpty || Set(forms).isSubset(of: graduatedLineForms(baseID: baseID, graduated: graduated))
    }

    /// Whether an egg of `type` (a stone's) has nothing new to give from this line: the forms that hatch with its
    /// type and the finals they reach are all collected. A Galarian Stunfisk, Ground and Steel, never comes from a
    /// Thunder Stone, so it does not keep a Stunfisk line open for one, as it does for a plain egg.
    func isLineComplete(baseID: Int, type: PokemonType, graduated: GraduatedForms? = nil) -> Bool {
        let forms = Self.eggForms(baseID: baseID, type: type)
        let finals = forms.isEmpty ? PokemonEvolutionData.finals(from: baseID)
            : Array(Set(forms.flatMap { PokemonEvolutionData.finals(from: baseID, form: $0, anyForm: false) }))
        guard finals.allSatisfy({ collectedFinals.contains("\(baseID):\($0)") }) else { return false }
        return !lineMissesForms(baseID: baseID, types: [type], graduated: graduated)
    }

    /// Hatch roll weights: a form counts as collected once every species of the line that shows it
    /// is owned in it, so a Sandy Burmy that became Mothim still leaves Sandy Wormadam to find.
    /// Forms an egg of this line rolls. A stone egg only rolls the forms that hatch with its type (no Alolan
    /// Vulpix, Ice, from a Fire Stone), unless none does.
    static func eggForms(baseID: Int, type: PokemonType?) -> [PokemonForm] {
        eggForms(baseID: baseID, types: type.map { [$0] } ?? [])
    }

    /// The forms an egg whose Pokémon must have one of `types` can roll (a stone's type, a season's): every form
    /// when `types` is empty or no form has one.
    static func eggForms(baseID: Int, types: [PokemonType]) -> [PokemonForm] {
        eggForms(among: PokemonForm.rollableLineForms(baseID: baseID), baseID: baseID, types: types)
    }

    static func eggForms(among forms: [PokemonForm], baseID: Int, types: [PokemonType]) -> [PokemonForm] {
        guard !types.isEmpty else { return forms }
        let typed = forms.filter { form in PokemonTypeData.types(forSpeciesID: baseID, form: form).contains(where: types.contains) }
        return typed.isEmpty ? forms : typed
    }

    /// Whether this egg can still bring a form of the line not graduated yet (the Oval Charm's target): only the
    /// forms it can roll count, so a Fire Stone egg does not pick Vulpix for its missing Alolan form.
    func lineMissesForms(baseID: Int, type: PokemonType? = nil) -> Bool {
        lineMissesForms(baseID: baseID, types: type.map { [$0] } ?? [])
    }

    func lineMissesForms(baseID: Int, types: [PokemonType], graduated: GraduatedForms? = nil) -> Bool {
        let forms = Self.eggForms(baseID: baseID, types: types)
        return !forms.isEmpty && !Set(forms).isSubset(of: graduatedLineForms(baseID: baseID, graduated: graduated))
    }

    /// The line's forms every one of its species graduated in, what the game counts as had: the roll, the Oval
    /// Charm, a new form's bonuses, as the goals do. Neither a Pokémon sent off nor the one being raised: a form
    /// counts once a Pokémon of it is kept.
    /// `graduated`: the forms read once (`GraduatedForms`), for the many lines of a roll.
    func graduatedLineForms(baseID: Int, graduated: GraduatedForms? = nil) -> Set<PokemonForm> {
        let graduated = graduated ?? GraduatedForms(dex)
        let owned = PokemonForm.formSpecies(baseID: baseID).map { ($0, graduatedForms(speciesID: $0, graduated)) }
        return Set(PokemonForm.lineForms(baseID: baseID).filter { form in
            owned.allSatisfy { speciesID, forms in
                PokemonForm.ownForm(speciesID: speciesID, lineForm: form).map(forms.contains) ?? true
            }
        })
    }

    /// 보유한 특정 종의 이로치 여부. 졸업 기록과 현재 도달 단계만 훑으며 이름·정렬·희귀도 등
    /// 도감 표시 모델은 계산하지 않는다. 위장 중인 메타몽의 이로치는 리빌 전까지 숨긴다.
    func ownsShinySpecies(_ speciesID: Int, form: PokemonForm? = nil) -> Bool {
        let form = PokemonForm.resolved(speciesID: speciesID, form: form)
        // A Plate or Memory changes the look, not the individual: a shiny Arceus is shiny in every form it has.
        if PokemonForm.unlockSource(speciesID: speciesID) != nil {
            guard let form, collectedForms(speciesID: speciesID).contains(form) else { return false }
            if dex.contains(where: { $0.isShiny && $0.chainOrder.contains(speciesID) }) { return true }
            guard let active, active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID) else { return false }
            return active.displaysShiny
        }
        if dex.contains(where: {
            $0.isShiny && $0.chainOrder.contains(speciesID)
                && PokemonForm.resolved(speciesID: speciesID, form: $0.form) == form
        }) { return true }
        guard let active,
              active.pathIDs.prefix(active.stageIndex + 1).contains(speciesID),
              PokemonForm.resolved(speciesID: speciesID, form: active.form) == form else { return false }
        return active.displaysShiny
    }

    /// 대표 포켓몬은 사용자가 현재 보유한 종만 가리킨다. Fresh Egg·메타몽 리빌·손편집 세이브가
    /// 유령 종을 메뉴바와 플로팅 펫에 영구히 남기지 않게 한다.
    mutating func reconcileRepresentativeSelection() {
        guard let selected = representativeSpeciesID else {
            representativeForm = nil
            return
        }
        representativeForm = PokemonForm.resolved(speciesID: selected, form: representativeForm)
        if !ownsSpecies(selected, form: representativeForm) {
            representativeSpeciesID = nil
            representativeForm = nil
        }
    }

    /// The years kept before the events and the birthday were counted in the Gregorian calendar were the system
    /// calendar's: 2569 on a Mac in the Buddhist calendar held the birthday gift back 543 years, 8 in the Japanese one
    /// gave it and the season's eggs twice. A year that no Gregorian year of the app can be (the gift came on 2026-10-26,
    /// the events the day after: never before 2026) is read in `recorded`, the calendar it was most likely counted in, at
    /// the middle of that year, and is never after this one: a claim is past.
    mutating func convertCalendarYears(recordedIn recorded: Calendar, now: Date) {
        guard recorded.identifier != .gregorian else { return }
        let gregorian = LocalUsageReader.gregorianCalendar(timeZone: recorded.timeZone)
        let thisYear = gregorian.component(.year, from: now)
        let era = recorded.component(.era, from: now)
        // Bounded both ways: a clock set years back made `2026...thisYear + 1` an empty range, which traps.
        let plausible = 2026...max(2026, thisYear + 1)
        func converted(_ year: Int) -> Int {
            guard !plausible.contains(year),
                  let middle = recorded.date(from: DateComponents(era: era, year: year, month: 6, day: 1))
            else { return year }
            return min(gregorian.component(.year, from: middle), thisYear)
        }
        if let year = lastBirthdayGiftYear { lastBirthdayGiftYear = converted(year) }
        if let year = birthdayChangedAfterGiftYear { birthdayChangedAfterGiftYear = converted(year) }
        claimedEventEggs = Set(claimedEventEggs.map { key in
            guard let at = key.lastIndex(of: "@"), let year = Int(key[key.index(after: at)...]) else { return key }
            return "\(key[..<at])@\(converted(year))"
        })
    }
}

// NOTE: 부화 후보는 더 이상 하드코딩하지 않는다 — CompanionStore.chooseBase() 가
// PokéAPI 전수(1~5세대)를 capture_rate 가중 rejection sampling 으로 선정한다.
