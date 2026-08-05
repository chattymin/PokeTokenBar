import Foundation

/// 상점 품목(알 뽑기·슬롯 확장 제외 — 그 둘은 값이 상황에 따라 달라 따로 다룬다).
enum ShopItem: String, CaseIterable, Sendable {
    case expCandy, shinyCandy, shinyCharm

    var price: Int {
        switch self {
        case .expCandy: 500_000_000
        case .shinyCandy: 2_000_000_000
        case .shinyCharm: 3_000_000_000
        }
    }

    var label: String {
        switch self {
        case .expCandy: "경험치 사탕"
        case .shinyCandy: "반짝이는 사탕"
        case .shinyCharm: "이로치 부적"
        }
    }

    /// 부적은 보유형이라 개수를 세지 않고 한 번만 산다.
    var isConsumable: Bool { self != .shinyCharm }

    var detail: String {
        switch self {
        case .expCandy: "지정한 포켓몬에게 경험치를 줍니다"
        case .shinyCandy: "지정한 포켓몬을 이로치로 만듭니다"
        case .shinyCharm: "이후 부화의 이로치 확률이 올라갑니다"
        }
    }
}
