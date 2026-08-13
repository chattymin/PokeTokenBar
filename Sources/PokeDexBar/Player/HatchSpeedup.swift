import Foundation

/// 알을 빨리 깨우는 포켓몬.
///
/// 원작에서 **불꽃몸 · 마그마의무장 · 증기기관** 을 가진 포켓몬이 파티에 있으면 알의 부화 사이클이
/// 절반이 된다. 기절해 있어도 되고, 여러 마리 있어도 절반 그대로다(중첩 없음).
///
/// **이 앱에서는 박스에 있기만 하면 된다.** 파티가 파트너 한 마리뿐이라 원작대로 하면 "좋아하는
/// 아이 대신 마그마그를 데리고 다녀야" 하고, 그건 감면을 얻는 게 아니라 파트너를 파는 일이 된다.
///
/// **감면은 지금 가지고 있는 동안만 걸린다.** 박사에게 보내면 끝난다 — 그게 보내기의 대가고,
/// 유일한 마그마그를 박스에 남겨 둘 이유다. `present` 와 `warmer` 가 같은 것(박스)을 본다.
enum HatchSpeedup {
    /// 감면 배율 — 원작대로 절반.
    static let multiplier = 0.5

    /// 해당 특성을 가진 종. PokéAPI 의 `ability/{flame-body,magma-armor,steam-engine}` 에서
    /// 받아 적었다(폼 번호 10000번대는 뺐다 — 같은 종의 거다이맥스 등이라 종 단위로 중복이다).
    ///
    /// 포니타·날쌩마 · 마그마 · 파이어 · 마그마그 · 마그카르고 · 마그비 · 폭타 · 마그마번 ·
    /// 히드런 · 불켜미 · 램프라 · 샹델라 · 활화르바 · 불카모스 · 불화살빈 · 파이어로 ·
    /// 탄동 · 탄차곤 · 석탄산 · 태우지네 · 다태우지네 · 카르본
    static let species: Set<Int> = [
        77, 78, 126, 146, 218, 219, 240, 323, 467, 485, 607, 608, 609,
        636, 637, 662, 663, 837, 838, 839, 850, 851, 935,
    ]

    /// 이 개체들 중에 알을 빨리 깨우는 아이가 있나.
    static func present(in box: [Individual]) -> Bool { warmer(in: box) != nil }

    /// 알을 데워 주는 아이. 여럿이면 **가장 먼저 얻은** 아이다 — 화면에 이름을 내밀 때
    /// 그쪽이 말이 된다.
    ///
    /// **배열 순서와 무관하게 `obtainedAt` 으로 고른다.** 박스 정리(`BoxSort`)가 생긴 뒤로
    /// 배열 순서는 더 이상 획득 순서가 아니다 — `box.first { … }` 로 짰다면, 정리로 배열이
    /// 뒤집히기만 해도 감면을 준 적 없는 다른 개체의 이름이 튀어나온다.
    static func warmer(in box: [Individual]) -> Individual? {
        box.filter { species.contains($0.speciesID) }.min { $0.obtainedAt < $1.obtainedAt }
    }

    /// 남은 시간을 절반으로 줄인 부화 시각.
    ///
    /// **지나간 시간은 안 건드린다.** 원작에서도 그 시점부터 카운터가 두 배로 도는 것이지
    /// 이미 걸은 걸음이 두 배로 쳐지지는 않는다. 30분짜리를 20분 굴리다 얻으면 남은 10분이
    /// 5분이 되지, 유효 시간이 15분이 되어 이미 익어 있지는 않다.
    static func halvedRemaining(hatchesAt: Date, now: Date) -> Date {
        guard hatchesAt > now else { return hatchesAt }
        return now.addingTimeInterval(hatchesAt.timeIntervalSince(now) * multiplier)
    }
}
