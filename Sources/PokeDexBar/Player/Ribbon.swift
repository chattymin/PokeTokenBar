import Foundation

/// 리본 — 한 개체와 오래 함께 다닌 기록. **얻는 기준은 시간, 쓰는 방식은 토큰**이다.
///
/// 단계는 파트너로 지낸 누적 시간으로 오르고(애착에 대한 보상), 그 단계가 정하는 건
/// "토큰을 얼마나 쓸 때마다 경험치 사탕이 하나 나오나"다(실제로 일한 것에 대한 보상).
/// 벽시계로 생산하면 앱을 켜 두는 쪽에 보상이 가는데, 이 앱은 사용량 추적기라 그건 어긋난다.
///
/// 왜 경험치 배율이 아니라 사탕인가: 배율은 그 파트너에게만 갇히지만 **사탕은 다른 개체에게
/// 먹일 수 있다.** 도감 1025칸 중 485칸은 진화로만 열리는데 경험치는 파트너 하나만 받으므로
/// 진화가 직렬 병목이 된다. 오래 함께한 파트너를 사탕 공장으로 만들면 그 병목이 풀리고,
/// "한 마리를 오래 데리고 다닌다"와 "도감을 채운다"가 같은 방향을 보게 된다.
enum Ribbon: Int, CaseIterable, Codable, Sendable, Comparable {
    case bond = 1       // 인연
    case trust = 2      // 신뢰
    case kinship = 3    // 유대
    case lifelong = 4   // 반려

    static func < (a: Ribbon, b: Ribbon) -> Bool { a.rawValue < b.rawValue }

    /// 이 리본을 얻는 데 필요한 파트너 누적 시간(초).
    var requiredPartnerSeconds: Int {
        switch self {
        case .bond: 86_400            // 1일
        case .trust: 7 * 86_400       // 7일
        case .kinship: 30 * 86_400    // 30일
        case .lifelong: 90 * 86_400   // 90일
        }
    }

    /// 경험치 사탕 하나가 나오는 데 필요한 토큰. 단계가 오를수록 짧아진다.
    /// 사탕 하나는 경험치 1억이므로, 이 값이 곧 실효 경험치 배율이다(150M → 0.7배, 20M → 5배).
    var tokensPerCandy: Int {
        switch self {
        case .bond: 150_000_000
        case .trust: 75_000_000
        case .kinship: 40_000_000
        case .lifelong: 20_000_000
        }
    }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .bond: ("인연", "Bond", "きずな")
        case .trust: ("신뢰", "Trust", "しんらい")
        case .kinship: ("유대", "Kinship", "つながり")
        case .lifelong: ("반려", "Lifelong", "しょうがい")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 이 시간만큼 함께 다닌 개체가 지금 달고 있는 리본. 아직 하나도 없으면 nil.
    static func earned(partnerSeconds: Int) -> Ribbon? {
        allCases.last { partnerSeconds >= $0.requiredPartnerSeconds }
    }

    /// 다음 리본과 거기까지 남은 시간(초). 최고 단계면 nil.
    static func next(after seconds: Int) -> (ribbon: Ribbon, remaining: Int)? {
        guard let upcoming = allCases.first(where: { seconds < $0.requiredPartnerSeconds }) else {
            return nil
        }
        return (upcoming, upcoming.requiredPartnerSeconds - seconds)
    }
}
