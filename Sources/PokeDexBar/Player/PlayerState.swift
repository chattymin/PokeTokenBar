import Foundation

/// 영속 상태. 업스트림 `CompanionState`(한 마리·졸업)를 대체한다.
struct PlayerState: Codable, Sendable {
    /// 첫 실행 스타터 선택을 마쳤나. false 면 팝오버가 선택 화면만 띄운다.
    var starterChosen = false
    /// 설치 이후 누적 사용 토큰 — 재화의 원천이자 파트너 경험치의 원천.
    var earnedTokens = 0
    /// 상점 지출 누적.
    var spentTokens = 0
    /// 오늘 어디까지 적립했나(이 기기 장부). 날짜가 바뀌면 0으로.
    var claimedTodayTokens = 0
    var lastDate = ""
    /// 설치 기준선을 잡았나 — 설치 이전 사용량은 세지 않는다.
    var installBaselineSet = false
    var partnerID: UUID?
    /// 보유 개체. 중복 허용.
    var box: [Individual] = []
    /// 한 번이라도 보유한 종 번호.
    var dex: Set<Int> = []
    /// 동시 부화 슬롯 수(2b 에서 쓴다). 기본 3, 상한 6.
    var slots = 3
    /// 아이템 종류 → 개수.
    var inventory: [String: Int] = [:]
    var ownsShinyCharm = false
    /// 앱 언어. 단일 소스 — 구 CompanionStore.language 를 대체한다. 포켓몬 이름은 PokéAPI 다국어
    /// names 에서 따로 온다(EvoLine.localizedName).
    var language: AppLanguage = .systemDefault

    /// 상점에서 쓸 수 있는 재화.
    var wallet: Int { max(0, earnedTokens - spentTokens) }
    /// 데리고 다니는 개체. 박스에서 사라졌으면 nil.
    var partner: Individual? { box.first { $0.id == partnerID } }

    init() {}

    // 관대 디코딩 — 형식이 자라는 중에 한 필드가 빠져도 박스·도감을 통째로 날리지 않는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        starterChosen = value(.starterChosen, false)
        earnedTokens = value(.earnedTokens, 0)
        spentTokens = value(.spentTokens, 0)
        claimedTodayTokens = value(.claimedTodayTokens, 0)
        lastDate = value(.lastDate, "")
        installBaselineSet = value(.installBaselineSet, false)
        partnerID = try? c.decode(UUID.self, forKey: .partnerID)
        // 박스는 원소 단위로 관대 디코딩한다. 위의 `value(.box, [])` 방식(배열 전체를 한 번에 디코드)을
        // 쓰면 개체 하나가 깨져도(2b 에서 필드가 느는 시점 등) 배열 디코드 자체가 던져 박스 전체가 빈
        // 채로 떨어진다 — 도감·지갑은 살아남는데 박스만 사라지는 손상. 실패한 원소만 드롭하고 나머지는 지킨다.
        let wrappedBox = (try? c.decode([LossyIndividual].self, forKey: .box)) ?? []
        box = wrappedBox.compactMap(\.individual)
        if box.count != wrappedBox.count {
            AppLog.write("PlayerState: dropped \(wrappedBox.count - box.count) malformed individual(s) from box on decode")
        }
        dex = value(.dex, [])
        slots = value(.slots, 3)
        inventory = value(.inventory, [:])
        ownsShinyCharm = value(.ownsShinyCharm, false)
        language = value(.language, .systemDefault)
    }
}

/// `[Individual]` 원소 단위 관대 디코딩 래퍼 — 이 원소만 실패로 삼키고(nil) 배열 디코드 자체는
/// 계속 진행시킨다(Swift 는 배열 하나가 던지면 전체가 던지므로, 원소를 이 타입으로 감싸 여기서 흡수).
private struct LossyIndividual: Decodable {
    let individual: Individual?
    init(from decoder: Decoder) throws {
        individual = try? Individual(from: decoder)
    }
}
