import Foundation

/// 알·개체의 등급. 경계는 업스트림 `Rarity` 와 같고 이 게임의 어휘로 이름만 바꿨다
/// (uncommon → 레어, rare → 에픽). 뽑기 확률·진화 임계·표시가 이 값을 쓴다.
enum Grade: String, Codable, Sendable, CaseIterable {
    case common, rare, epic, legendary

    /// 표시 서열 — 정렬에만 쓴다. 커먼 0 … 레전더리 3.
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

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

    /// 표시용 등급 이름 — 언어별(ko/en/ja). 앱 언어에 따라 두 화면(박스·홈)에서 쓰인다.
    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .common:    names = ("커먼", "Common", "コモン")
        case .rare:      names = ("레어", "Rare", "レア")
        case .epic:      names = ("에픽", "Epic", "エピック")
        case .legendary: names = ("레전더리", "Legendary", "レジェンダリー")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
