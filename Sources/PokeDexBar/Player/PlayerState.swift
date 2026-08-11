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
    /// 부화 중인 알. 개수는 `slots` 를 넘지 않는다.
    var eggs: [Egg] = []
    /// 아이템 종류 → 개수.
    var inventory: [String: Int] = [:]
    /// 확정 알 교환권. 장수는 원소 개수다 — 같은 종 두 장이면 원소가 둘.
    /// `inventory`(도구용 문자열 키)와 섞지 않는다 — 종 번호가 키인 다른 성격의 물건이라,
    /// 가방 탭이 모르는 키를 만나게 된다.
    var eggVouchers: [EggVoucher] = []
    /// 파트너가 물어 왔는데 아직 확인 안 한 것(`Discovery`). 도구는 이미 `inventory` 에 들어가
    /// 있고 이 목록은 **알림용**이다 — 확인이 늦어도 잃는 게 없다.
    var discoveries: [Discovery] = []
    var ownsShinyCharm = false
    /// 경험치 부적 — 토큰·사탕으로 얻는 경험치가 2배가 된다. 보유형이라 개수를 세지 않는다.
    var ownsExpCharm = false
    /// 행운의 부적 — 재화 획득이 1.5배가 된다. 경험치와 재화는 별개 트랙이라 서로 안 겹친다.
    var ownsFortuneCharm = false
    /// 세이브를 손으로 고친 적이 있나. 한 번 켜지면 절대 안 꺼진다 — 지우려고 파일을 또 고치면
    /// 봉인이 다시 깨져 그대로 켜진다. 게임 진행에는 영향이 없고 스프라이트만 좌우로 뒤집힌다.
    var tampered = false
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
        tampered = value(.tampered, false)
        ownsExpCharm = value(.ownsExpCharm, false)
        ownsFortuneCharm = value(.ownsFortuneCharm, false)
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
        // 알림 목록이라 통째로 관대하게 — 깨져도 도구는 인벤토리에 이미 있으므로 잃는 게 없다.
        discoveries = value(.discoveries, [])
        // 관대 디코딩의 짝 — 값 범위 검증(CLAUDE.md 결함 대응 프로토콜). `"slots": 0` 은 디코드에
        // 성공해 경제를 영구히 잠근다: freeSlots 0 → canDraw false → nextSlotPrice nil 이라 상점은
        // "슬롯을 최대까지 늘렸어요"라고 말하는데 다시는 뽑을 수 없다. 상한도 자른다 — 거대한 값은
        // 빈 슬롯 타일을 그 수만큼 만들어 화면을 세운다.
        // 하한은 1 이 아니라 기본 슬롯(3)이다 — `slotPrice` 는 4~6 만 값을 매기므로 1·2 로 잘라 두면
        // 뽑기는 되살아나도 `nextSlotPrice` 가 nil 이라 상점이 계속 "최대까지 늘렸어요"라고 거짓말한다.
        // 3 은 모든 정상 플레이어의 출발점이고, 거기서부터 가격표가 다시 이어진다.
        slots = min(EggBalance.maxSlots, max(EggBalance.baseSlots, value(.slots, EggBalance.baseSlots)))
        // 알도 박스와 같은 이유로 원소 단위 관대 디코딩한다 — 알 하나가 깨졌다고 부화 중인
        // 나머지 알까지 통째로 날아가면 안 된다.
        let wrappedEggs = (try? c.decode([LossyEgg].self, forKey: .eggs)) ?? []
        eggs = wrappedEggs.compactMap(\.egg)
        if eggs.count != wrappedEggs.count {
            AppLog.write("PlayerState: dropped \(wrappedEggs.count - eggs.count) malformed egg(s) from eggs on decode")
        }
        inventory = value(.inventory, [:])
        // 교환권도 박스·알과 같은 이유로 원소 단위 관대 디코딩한다 — 한 장이 깨졌다고 나머지
        // 교환권까지 통째로 날아가면 안 된다(한 장이 5000만 토큰어치다). 값 범위 검증(`isSane`)이
        // 짝으로 붙는다: 항목이므로 개수는 안 자르고, 말이 안 되는 원소만 버린다.
        let wrappedVouchers = (try? c.decode([LossyEggVoucher].self, forKey: .eggVouchers)) ?? []
        eggVouchers = wrappedVouchers.compactMap(\.voucher)
        if eggVouchers.count != wrappedVouchers.count {
            AppLog.write("PlayerState: dropped \(wrappedVouchers.count - eggVouchers.count) malformed egg voucher(s) on decode")
        }
        ownsShinyCharm = value(.ownsShinyCharm, false)
        language = value(.language, .systemDefault)
    }
}

/// `[Individual]` 원소 단위 관대 디코딩 래퍼 — 이 원소만 실패로 삼키고(nil) 배열 디코드 자체는
/// 계속 진행시킨다(Swift 는 배열 하나가 던지면 전체가 던지므로, 원소를 이 타입으로 감싸 여기서 흡수).
private struct LossyIndividual: Decodable {
    let individual: Individual?
    init(from decoder: Decoder) throws {
        individual = (try? Individual(from: decoder))?.sanitized()
    }
}

/// `[Egg]` 원소 단위 관대 디코딩 래퍼 — `LossyIndividual` 과 같은 패턴에, 값 범위 검증(`Egg.sanitized`)을
/// 겸한다. 관대 디코딩은 말이 안 되는 시각도 통과시키고, 그 값이 나중에 산술 트랩을 낸다.
private struct LossyEgg: Decodable {
    let egg: Egg?
    init(from decoder: Decoder) throws {
        egg = (try? Egg(from: decoder))?.sanitized()
    }
}

/// `[EggVoucher]` 원소 단위 관대 디코딩 래퍼 — `LossyEgg` 와 같은 패턴에, 값 범위 검증을 겸한다.
private struct LossyEggVoucher: Decodable {
    let voucher: EggVoucher?
    init(from decoder: Decoder) throws {
        let decoded = try? EggVoucher(from: decoder)
        voucher = decoded?.isSane == true ? decoded : nil
    }
}
