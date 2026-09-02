import Foundation

/// 부적 단계 — 한 번 사면 끝이던 부적을 **계속 올릴 수 있는 사다리**로 바꾼 것.
///
/// **혜택은 선형, 가격은 기하급수.** 단계마다 이득은 일정하게 붙는데 값은 두 배로 뛰므로
/// *단위 이득당 비용이 매 단계 두 배*가 된다 — 상한을 안 둬도 경제가 스스로 멈춘다.
/// 실제로 행운의 부적 10단계(128B)는 누적 수입 1000B 를 넘겨야 본전이라, 폭주가 안 난다.
///
/// **단계를 저장하고 누적 지출액은 저장하지 않는다.** 지출액에서 단계를 파생시키면 나중에
/// 가격표를 손보는 순간 이미 산 사람의 단계가 *내려갈 수* 있다. 되돌릴 수 없는 구매에는
/// "얻은 것은 안 사라진다"가 더 중요하다.
enum CharmLadder {
    /// 1단계 값. 이후 단계마다 두 배(`price(t) = base × 2^(t-1)`).
    static let basePrice = 250_000_000
    static let growth = 2

    /// 이 단계를 사는 값. 1단계 미만은 값이 없다.
    static func price(tier: Int) -> Int? {
        guard tier >= 1, tier <= maxSafeTier else { return nil }
        return basePrice * pow2(tier - 1)
    }

    /// 여기까지 올리는 데 든 총액 — 화면이 "지금까지 얼마 썼나" 를 보여줄 때 쓴다.
    static func cumulative(through tier: Int) -> Int {
        guard tier >= 1 else { return 0 }
        return basePrice * (pow2(min(tier, maxSafeTier)) - 1)
    }

    /// **오버플로 방어 — 값에서 유도한다.** 가격이 2배씩 뛰므로 단계가 커지면 `Int` 를 넘고,
    /// Swift 의 곱셈은 트랩이라 프로세스가 죽는다(CLAUDE.md 의 값 범위 검증).
    ///
    /// 손으로 40 이라고 적었다가 실제로 밟았다 — `basePrice` 가 2.5억이라 누적이 `Int.max` 를
    /// 넘는 지점은 40 이 아니라 **35** 다. 상한은 `basePrice` 를 고치면 같이 움직여야 하므로
    /// 상수로 두지 않고 여기서 센다(누적 `base × (2^t − 1)` 이 들어가는 가장 큰 t).
    static let maxSafeTier: Int = {
        var tier = 1
        while Int.max / basePrice >= (1 << (tier + 1)) - 1 { tier += 1 }
        return tier
    }()

    private static func pow2(_ n: Int) -> Int { 1 << min(max(0, n), 62) }

    /// 단계마다 붙는 이득. 부적마다 다르고, **지금 효과가 4단계에 오도록** 역산한 값이다 —
    /// 그래야 기존 구매자를 4단계에 놓았을 때 손해도 이득도 아니게 된다.
    static func step(_ item: ShopItem) -> Double {
        switch item {
        case .expCharm: 0.25          // 4단계 = 2.0배 (옛 효과)
        case .fortuneCharm: 0.125     // 4단계 = 1.5배 (옛 효과)
        case .shinyCharm: 1.0 / 12    // 4단계 = 1/48 (옛 효과)
        default: 0
        }
    }

    /// 이 단계의 배율. 0단계(미보유)는 1.0 — 아무 효과가 없다는 뜻이다.
    static func multiplier(_ item: ShopItem, tier: Int) -> Double {
        1 + step(item) * Double(max(0, tier))
    }

    /// **옛 세이브의 보유 부적이 놓일 단계.** 값이 아니라 *효과* 로 매핑한다 — 사다리를
    /// 나중에 바꿔도 "기존 구매자는 손해 안 본다" 가 코드에 남아야 한다.
    static let legacyTier = 4

    /// **무지개 부적이 딸려 주는 이로치 단계.** 옛 무지개 부적은 분모를 1/32 로 *고정*했는데
    /// 지금의 −8 만으로는 1/56 이라 전국도감을 채운 사람이 오히려 손해를 본다. 이 단계를
    /// 얹으면 `round(64 / (1 + 7/12)) − 8 = 32` — 옛 값과 정확히 같다. 옛 세이브 이전과
    /// **새로 받는 보상 양쪽에 같이** 건다: 갈라 두면 "언제 받았나"로 세기가 달라진다.
    static let rainbowShinyTier = 7

    /// 사다리를 타는 부적인가. 무지개 부적은 도감 완성 보상이라 단계가 없다(아래 참고).
    static func isTiered(_ item: ShopItem) -> Bool {
        item == .expCharm || item == .fortuneCharm || item == .shinyCharm
    }
}

/// 이로치 확률 — **배율이 아니라 분모라서 따로 다룬다.**
enum ShinyOdds {
    /// 부적이 없을 때의 분모.
    static let base = 64

    /// **바닥값.** 배율이 커지면 분모가 0 으로 수렴하므로 반드시 있어야 한다 — 설계 취향이
    /// 아니라 수학적 요구다. 1/16 은 20단계 즈음(누적 260조 토큰)이라 사실상 도달 불가지만,
    /// 값이 깨지는 것만은 여기서 막는다.
    static let floor = 16

    /// 무지개 부적이 깎아 주는 분모. **단계와 무관하게 언제나 −8**(사용자 결정) — 도감을
    /// 다 채운 보상이 사다리 어디에 있든 의미를 갖게 하려는 것이다. 예전에는 1/32 고정이라
    /// 이로치 부적을 올리면 무지개가 무의미해지는 구간이 생겼다.
    static let rainbowBonus = 8

    /// 지금 분모. 낮을수록 이로치가 잘 나온다.
    static func denominator(shinyTier: Int, rainbowCharm: Bool) -> Int {
        let multiplier = CharmLadder.multiplier(.shinyCharm, tier: shinyTier)
        let scaled = Int((Double(base) / multiplier).rounded())
        return max(floor, scaled - (rainbowCharm ? rainbowBonus : 0))
    }
}
