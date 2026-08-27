import Foundation

/// 컬렉션 — 주제로 묶은 수집 세트. 도감 미션이 "숫자" 라면 이쪽은 "이야기" 다
/// (포켓몬 GO 의 메달, HOME 의 챌린지 자리).
///
/// **완성 = 배지 + 보상 한 번.** 배지는 도감에서 파생될 뿐 받는 동작이 없고, 보상 수령만
/// 기록이 남는다. 처음엔 전승 세트들을 "배지만"으로 뒀는데, 배지가 명예로 읽히기엔 표시가
/// 작아서 모든 세트가 뭔가를 주는 걸로 바꿨다(사용자 결정 — "경험치 사탕이라도 주는 게").
struct CollectionSet: Identifiable, Equatable, Sendable {
    let id: String
    /// 이 세트를 이루는 종들(도감 등록 기준).
    let speciesIDs: [Int]
    /// 완성 보상 — 모든 세트가 준다. **반짝사탕은 여기 못 온다**(미션 쪽 희소성 가드와
    /// 별개 경로로 새는 걸 막는다 — 테스트가 잠근다).
    let rewards: [DexMissionReward]
}

enum CollectionCatalog {
    /// 전체 세트. 순서가 곧 화면 순서다 — 쉬운 것부터.
    static let all: [CollectionSet] = [
        // 전승 트리오·듀오 — 전설을 두셋씩 모으는 난도라 시공의 신과 같은 급(사탕 20)을 준다.
        CollectionSet(id: "legendary-birds", speciesIDs: [144, 145, 146],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "legendary-beasts", speciesIDs: [243, 244, 245],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "tower-duo", speciesIDs: [249, 250],
                      rewards: [.item(.expCandy, 20)]),
        // 뮤·뮤츠·메타몽 — 복제 실험 전승(메타몽 = 실패한 뮤 복제설).
        CollectionSet(id: "clone-truth", speciesIDs: [132, 150, 151],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "weather-trio", speciesIDs: [382, 383, 384],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "lake-guardians", speciesIDs: [480, 481, 482],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "tao-trio", speciesIDs: [643, 644, 646],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "aura-trio", speciesIDs: [716, 717, 718],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "sword-shield", speciesIDs: [888, 889, 890],
                      rewards: [.item(.expCandy, 20)]),
        // 해와 달 — 루나톤·솔록(3세대의 달·해)과 솔가레오·루나아라(7세대의 해·달)를 잇는다.
        CollectionSet(id: "sun-moon", speciesIDs: [337, 338, 791, 792],
                      rewards: [.item(.expCandy, 20)]),
        // 중간 크기 — 진화가 필요한 세트는 경험치 사탕이 어울린다(그 사탕으로 마저 진화시킨다).
        CollectionSet(id: "eevee-friends",
                      speciesIDs: [133, 134, 135, 136, 196, 197, 470, 471, 700],
                      rewards: [.item(.expCandy, 10)]),
        CollectionSet(id: "kanto-starters",
                      speciesIDs: [1, 2, 3, 4, 5, 6, 7, 8, 9],
                      rewards: [.item(.expCandy, 10)]),
        CollectionSet(id: "johto-starters",
                      speciesIDs: [152, 153, 154, 155, 156, 157, 158, 159, 160],
                      rewards: [.item(.expCandy, 10)]),
        // 피카츄 닮은꼴 — 세대마다 하나씩 나오는 "전기 마스코트" 계보(따라큐는 위장으로 합류).
        CollectionSet(id: "pika-clones",
                      speciesIDs: [25, 311, 312, 417, 587, 702, 777, 778, 877, 921],
                      rewards: [.item(.expCandy, 10)]),
        // 되살린 화석 — 여섯 세대의 화석 25종 전부(복원 라인 포함).
        CollectionSet(id: "fossils",
                      speciesIDs: [138, 139, 140, 141, 142, 345, 346, 347, 348,
                                   408, 409, 410, 411, 564, 565, 566, 567,
                                   696, 697, 698, 699, 880, 881, 882, 883],
                      rewards: [.item(.expCandy, 20)]),
        CollectionSet(id: "creation-gods", speciesIDs: [483, 484, 487, 493],
                      rewards: [.item(.expCandy, 20)]),
        // 레지 패밀리 — 다섯 기둥을 모으면 **레지기가스가 깨어난다**(본가 전승 그대로: 세 거인을
        // 데려가야 설산의 신전이 열린다). 레지기가스는 알에서 안 나오므로
        // (`EggBalance.rewardOnlySpecies`) 이 보상이 유일한 입수처다 — 4세대 완성 미션도
        // 그래서 이 세트를 지나가게 된다.
        CollectionSet(id: "regi-family", speciesIDs: [377, 378, 379, 894, 895],
                      rewards: [.pokemon(speciesID: 486, grade: .legendary, growthRate: .slow)]),
        // 큰 세트 — 레전더리 열·열하나라 확정권이 걸맞다.
        CollectionSet(id: "ultra-beasts",
                      speciesIDs: [793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806],
                      rewards: [.eggTicket(.legendary)]),
        // 600족 — **최종 진화형만** 센다. "유사 전설" 이라는 이름은 완성형의 것이라,
        // 미뇽을 잡았다고 이 세트가 차오르면 이름이 거짓말이 된다.
        CollectionSet(id: "pseudo-legendaries",
                      speciesIDs: [149, 248, 373, 376, 445, 635, 706, 784, 887, 998],
                      rewards: [.eggTicket(.legendary)]),
        // 파라독스 — 고대와 미래를 가른다(본가의 스칼렛/바이올렛 구분 그대로).
        CollectionSet(id: "paradox-past",
                      speciesIDs: [984, 985, 986, 987, 988, 989, 1005, 1009, 1020, 1021],
                      rewards: [.eggTicket(.legendary)]),
        CollectionSet(id: "paradox-future",
                      speciesIDs: [990, 991, 992, 993, 994, 995, 1006, 1010, 1022, 1023],
                      rewards: [.eggTicket(.legendary)]),
    ]

    /// 이 종이 속한 세트들 — 도감 상세가 "얘는 클론의 진실의 한 조각" 을 말하는 데 쓴다.
    static func containing(species: Int) -> [CollectionSet] {
        all.filter { $0.speciesIDs.contains(species) }
    }

    static func progress(of set: CollectionSet, dex: Set<Int>) -> (done: Int, target: Int) {
        (set.speciesIDs.count(where: { dex.contains($0) }), set.speciesIDs.count)
    }

    static func completed(_ set: CollectionSet, dex: Set<Int>) -> Bool {
        set.speciesIDs.allSatisfy { dex.contains($0) }
    }

    /// 세트 이름 — 세 언어. `BoxSort.label` 과 같은 관례.
    static func label(_ id: String, _ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch id {
        case "legendary-birds": names = ("전설의 새", "Legendary Birds", "でんせつの とりポケモン")
        case "legendary-beasts": names = ("전설의 야수", "Legendary Beasts", "でんせつの けものポケモン")
        case "tower-duo": names = ("탑의 듀오", "Tower Duo", "とうの デュオ")
        case "clone-truth": names = ("클론의 진실", "The Clone Truth", "クローンの しんじつ")
        case "weather-trio": names = ("초대륙 트리오", "Weather Trio", "てんこうトリオ")
        case "lake-guardians": names = ("호수의 수호신", "Lake Guardians", "みずうみの ばんにん")
        case "tao-trio": names = ("타오 트리오", "Tao Trio", "タオトリオ")
        case "aura-trio": names = ("오라 트리오", "Aura Trio", "オーラトリオ")
        case "sword-shield": names = ("검과 방패", "Sword and Shield", "けんと たて")
        case "sun-moon": names = ("해와 달", "Sun and Moon", "たいようと つき")
        case "johto-starters": names = ("성도 스타터", "Johto Starters", "ジョウトの さいしょのポケモン")
        case "pika-clones": names = ("피카츄 닮은꼴", "The Pika Look-alikes", "ピカチュウの にたものたち")
        case "fossils": names = ("되살린 화석", "Revived Fossils", "よみがえった カセキ")
        case "pseudo-legendaries": names = ("600족", "Pseudo-Legendaries", "600ぞく")
        case "paradox-past": names = ("고대의 포켓몬", "Ancient Paradoxes", "パラドックス（こだい）")
        case "paradox-future": names = ("미래의 포켓몬", "Future Paradoxes", "パラドックス（みらい）")
        case "eevee-friends": names = ("이브이 프렌즈", "Eevee Friends", "イーブイフレンズ")
        case "kanto-starters": names = ("관동 스타터", "Kanto Starters", "カントーの さいしょのポケモン")
        case "creation-gods": names = ("시공의 신", "Creation Gods", "じくうの かみがみ")
        case "regi-family": names = ("레지 패밀리", "Regi Family", "レジファミリー")
        case "ultra-beasts": names = ("울트라비스트", "Ultra Beasts", "ウルトラビースト")
        default: names = (id, id, id)
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
