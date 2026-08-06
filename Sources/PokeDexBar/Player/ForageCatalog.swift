import Foundation

/// 리본을 단 파트너가 물어 오는 도구는 **그 개체에게 필요한 것**이다 — 어떤 종이 진화하는 데
/// 무엇이 필요한지 적어 둔 표다.
///
/// **왜 바꿨나.** 예전에는 특수 도구 23종류에서 무작위로 하나를 물어 왔다. 원하는 도구 하나를
/// 기다리는 시간이 인연 리본 기준 57.5B 토큰이라 사실상 반려 리본 전용 기능이었고, 마그마그를
/// 데리고 다녀도 엉뚱한 심해의비늘이 나왔다. 대상을 그 개체가 쓸 것으로 좁히면 같은 확률에서
/// 23배 빨라진다.
///
/// **왜 정적 표인가.** 채집은 사용량 틱에서 도는데 진화 트리(`EvoLine`)는 팝오버를 열 때
/// PokéAPI 에서 비동기로 온다 — 채집 시점에는 트리가 없다. `FormCatalog`·`RegionalFormCatalog`
/// 와 같이 PokéAPI 를 한 번 조회해 만든 표를 싣는다.
enum ForageCatalog {
    /// 이 갈래가 어느 지방 개체에게 해당하는가. 대개 지방과 무관하지만, 같은 종이 지방에 따라
    /// 다른 도구를 요구하는 경우가 10건 있다(알로라 식스테일=얼음의돌 vs 관동=불꽃의돌).
    /// `RegionBalance.branchesByRegion` 이 *도착 종*이 갈리는 경우를 다루는 것과 짝이다 —
    /// 여기는 도착 종이 같고 **도구만** 갈리는 경우다.
    enum RegionScope: Sendable, Equatable, Hashable {
        case any
        /// 그 지방 개체만. `nil` 은 원종(관동 식스테일 등).
        case only(Region?)

        func covers(_ region: Region?) -> Bool {
            switch self {
            case .any: true
            case .only(let r): r == region
            }
        }
    }

    struct Need: Sendable, Equatable, Hashable {
        /// 이 도구로 갈 수 있는 종.
        let to: Int
        let item: EvolutionItem
        let scope: RegionScope
    }

    /// 진화 전 종 → 그 종이 필요로 하는 도구들. 여기 없는 종은 아무것도 못 물어 온다.
    static let bySpecies: [Int: [Need]] = [
        25: [.init(to: 26, item: .thunderStone, scope: .any)],
        27: [.init(to: 28, item: .iceStone, scope: .only(.alola))],
        30: [.init(to: 31, item: .moonStone, scope: .any)],
        33: [.init(to: 34, item: .moonStone, scope: .any)],
        35: [.init(to: 36, item: .moonStone, scope: .any)],
        37: [
            .init(to: 38, item: .fireStone, scope: .only(nil)),
            .init(to: 38, item: .iceStone, scope: .only(.alola)),
        ],
        39: [.init(to: 40, item: .moonStone, scope: .any)],
        44: [.init(to: 45, item: .leafStone, scope: .any), .init(to: 182, item: .sunStone, scope: .any)],
        58: [.init(to: 59, item: .fireStone, scope: .any)],
        61: [.init(to: 62, item: .waterStone, scope: .any), .init(to: 186, item: .kingsRock, scope: .any)],
        64: [.init(to: 65, item: .linkingCord, scope: .any)],
        67: [.init(to: 68, item: .linkingCord, scope: .any)],
        70: [.init(to: 71, item: .leafStone, scope: .any)],
        75: [.init(to: 76, item: .linkingCord, scope: .any)],
        79: [
            .init(to: 80, item: .galaricaCuff, scope: .only(.galar)),
            .init(to: 199, item: .kingsRock, scope: .only(nil)),
            .init(to: 199, item: .galaricaWreath, scope: .only(.galar)),
        ],
        82: [.init(to: 462, item: .thunderStone, scope: .any)],
        90: [.init(to: 91, item: .waterStone, scope: .any)],
        93: [.init(to: 94, item: .linkingCord, scope: .any)],
        95: [.init(to: 208, item: .metalCoat, scope: .any)],
        100: [.init(to: 101, item: .leafStone, scope: .only(.hisui))],
        102: [.init(to: 103, item: .leafStone, scope: .any)],
        112: [.init(to: 464, item: .protector, scope: .any)],
        117: [.init(to: 230, item: .dragonScale, scope: .any)],
        120: [.init(to: 121, item: .waterStone, scope: .any)],
        123: [
            .init(to: 212, item: .metalCoat, scope: .any),
            .init(to: 900, item: .blackAugurite, scope: .any),
        ],
        125: [.init(to: 466, item: .electirizer, scope: .any)],
        126: [.init(to: 467, item: .magmarizer, scope: .any)],
        133: [
            .init(to: 134, item: .waterStone, scope: .any),
            .init(to: 135, item: .thunderStone, scope: .any),
            .init(to: 136, item: .fireStone, scope: .any),
            .init(to: 470, item: .leafStone, scope: .any),
            .init(to: 471, item: .iceStone, scope: .any),
        ],
        137: [.init(to: 233, item: .upGrade, scope: .any)],
        176: [.init(to: 468, item: .shinyStone, scope: .any)],
        191: [.init(to: 192, item: .sunStone, scope: .any)],
        198: [.init(to: 430, item: .duskStone, scope: .any)],
        200: [.init(to: 429, item: .duskStone, scope: .any)],
        217: [.init(to: 901, item: .peatBlock, scope: .any)],
        233: [.init(to: 474, item: .dubiousDisc, scope: .any)],
        271: [.init(to: 272, item: .waterStone, scope: .any)],
        274: [.init(to: 275, item: .leafStone, scope: .any)],
        281: [.init(to: 475, item: .dawnStone, scope: .any)],
        299: [.init(to: 476, item: .thunderStone, scope: .any)],
        300: [.init(to: 301, item: .moonStone, scope: .any)],
        315: [.init(to: 407, item: .shinyStone, scope: .any)],
        349: [.init(to: 350, item: .prismScale, scope: .any)],
        356: [.init(to: 477, item: .reaperCloth, scope: .any)],
        361: [.init(to: 478, item: .dawnStone, scope: .any)],
        366: [
            .init(to: 367, item: .deepSeaTooth, scope: .any),
            .init(to: 368, item: .deepSeaScale, scope: .any),
        ],
        511: [.init(to: 512, item: .leafStone, scope: .any)],
        513: [.init(to: 514, item: .fireStone, scope: .any)],
        515: [.init(to: 516, item: .waterStone, scope: .any)],
        517: [.init(to: 518, item: .moonStone, scope: .any)],
        525: [.init(to: 526, item: .linkingCord, scope: .any)],
        533: [.init(to: 534, item: .linkingCord, scope: .any)],
        546: [.init(to: 547, item: .sunStone, scope: .any)],
        548: [.init(to: 549, item: .sunStone, scope: .any)],
        554: [.init(to: 555, item: .iceStone, scope: .only(.galar))],
        572: [.init(to: 573, item: .shinyStone, scope: .any)],
        588: [.init(to: 589, item: .linkingCord, scope: .any)],
        603: [.init(to: 604, item: .thunderStone, scope: .any)],
        608: [.init(to: 609, item: .duskStone, scope: .any)],
        616: [.init(to: 617, item: .linkingCord, scope: .any)],
        670: [.init(to: 671, item: .shinyStone, scope: .any)],
        680: [.init(to: 681, item: .duskStone, scope: .any)],
        682: [.init(to: 683, item: .sachet, scope: .any)],
        684: [.init(to: 685, item: .whippedDream, scope: .any)],
        694: [.init(to: 695, item: .sunStone, scope: .any)],
        708: [.init(to: 709, item: .linkingCord, scope: .any)],
        710: [.init(to: 711, item: .linkingCord, scope: .any)],
        737: [.init(to: 738, item: .thunderStone, scope: .any)],
        739: [.init(to: 740, item: .iceStone, scope: .any)],
        840: [
            .init(to: 841, item: .tartApple, scope: .any),
            .init(to: 842, item: .sweetApple, scope: .any),
            .init(to: 1011, item: .syrupyApple, scope: .any),
        ],
        854: [
            .init(to: 855, item: .crackedPot, scope: .any),
            .init(to: 855, item: .chippedPot, scope: .any),
        ],
        884: [.init(to: 1018, item: .metalAlloy, scope: .any)],
        891: [
            .init(to: 892, item: .scrollOfDarkness, scope: .any),
            .init(to: 892, item: .scrollOfWaters, scope: .any),
        ],
        935: [
            .init(to: 936, item: .auspiciousArmor, scope: .any),
            .init(to: 937, item: .maliciousArmor, scope: .any),
        ],
        938: [.init(to: 939, item: .thunderStone, scope: .any)],
        951: [.init(to: 952, item: .fireStone, scope: .any)],
        974: [.init(to: 975, item: .iceStone, scope: .any)],
        1012: [
            .init(to: 1013, item: .unremarkableTeacup, scope: .any),
            .init(to: 1013, item: .masterpieceTeacup, scope: .any),
        ],
    ]

    /// 이 개체가 물어 올 수 있는 도구들. 지방이 안 맞는 갈래는 뺀다.
    /// 이미 가졌는지는 여기서 안 본다 — 그건 인벤토리를 아는 `PlayerStore.forage` 의 `owned`
    /// 가 걸러 낸다. 이 표는 "무엇이 필요한가"만 답한다.
    static func needs(speciesID: Int, region: Region?) -> [EvolutionItem] {
        (bySpecies[speciesID] ?? []).filter { $0.scope.covers(region) }.map(\.item)
    }
}
