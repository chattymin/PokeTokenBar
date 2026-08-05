import Foundation

/// 알·개체의 등급. 경계는 업스트림 `Rarity` 와 같고 이 게임의 어휘로 이름만 바꿨다
/// (uncommon → 레어, rare → 에픽). 뽑기 확률·진화 임계·표시가 이 값을 쓴다.
enum Grade: String, Codable, Sendable, CaseIterable {
    case common, rare, epic, legendary

    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Grade {
        if isLegendary || isMythical { return .legendary }
        if captureRate <= 45 { return .epic }
        if captureRate <= 120 { return .rare }
        return .common
    }

    init(rarity: Rarity) {
        switch rarity {
        case .common: self = .common
        case .uncommon: self = .rare
        case .rare: self = .epic
        case .legendary: self = .legendary
        }
    }

    var label: String {
        switch self {
        case .common: "커먼"
        case .rare: "레어"
        case .epic: "에픽"
        case .legendary: "레전더리"
        }
    }
}
