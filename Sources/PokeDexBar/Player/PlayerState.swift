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
    /// 한 번이라도 보유한 도감 키(`DexKey`) — 원종 `"37"`, 태생 폼 `"37/vulpix-alola"`.
    /// 폼 단위 도감의 단일 저장 소스다.
    var dexForms: Set<String> = []
    /// 동시 부화 슬롯 수(2b 에서 쓴다). 기본 3, 상한 6.
    var slots = 3
    /// 부화 중인 알. 개수는 `slots` 를 넘지 않는다.
    var eggs: [Egg] = []
    /// 아이템 종류 → 개수.
    var inventory: [String: Int] = [:]
    /// 박사에게 쌓인 포인트. `wallet`(토큰) 과 완전히 별개다 — 포인트로는 알을 못 사고
    /// 토큰으로는 박사와 거래할 수 없다. 섞으면 토큰을 안 쓰고도 재화가 도는 순환이 생겨,
    /// "쓴 토큰이 곧 재화" 라는 이 앱의 전제가 흐려진다.
    var researchPoints = 0
    /// 무지개 부적 — 전국도감 완성 미션의 보상. 진행(어느 기기에서든 참).
    var ownsRainbowCharm = false
    /// 수령한 도감 미션 id 들. 진행.
    var claimedDexMissions: Set<String> = []
    /// 보상을 받은 컬렉션 id 들. 배지는 도감에서 파생되므로 기록이 없고, **보상 수령만** 남는다.
    var claimedCollections: Set<String> = []
    /// 이 세이브만의 굴림 시드. **박사의 제안이 사람마다 달라지게 하는 유일한 근거**다.
    ///
    /// 처음엔 없었고, 그래서 제안이 날짜·자리·용도로만 결정돼 **같은 날 모든 설치가 같은 세 마리**를
    /// 받았다(2026-08-12 사용자 리포트: 주리비얀·깨봉이가 전원에게 동일). 도감 가중은 방어가 못 됐다 —
    /// 도감이 비었거나 꽉 찼으면 모든 후보가 같은 배수를 받아 경계가 안 움직인다.
    ///
    /// **세이브 안에 산다**(설정이 아니라). 사람에 붙는 값이라 세이브를 옮기면 같이 가야 하고,
    /// 기기마다 달라지면 옮긴 순간 제안이 통째로 갈린다. 0 = 아직 없음 → 첫 기동에 만들어 저장한다.
    var offerSeed: UInt64 = 0
    /// 오늘의 제안을 뽑은 날짜. `lastDate` 와 다르면 새로 뽑는다.
    var professorOfferDate = ""
    /// 오늘의 제안. 데려간 자리는 빠지지 않고 `claimed` 로 남는다.
    var professorOffers: [ProfessorOffer] = []
    /// 파트너가 물어 왔는데 아직 확인 안 한 것(`Discovery`). 도구는 이미 `inventory` 에 들어가
    /// 있고 이 목록은 **알림용**이다 — 확인이 늦어도 잃는 게 없다.
    var discoveries: [Discovery] = []
    var ownsShinyCharm = false
    /// 마지막으로 토큰이 들어온 시각. 모르페코의 배고픔이 여기서 나온다 — "언제 마지막으로
    /// 먹었나"는 개체가 아니라 사용자에게 붙는 사실이라 여기 둔다.
    var lastTokenAt: Date?
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

    /// 종 단위 도감(파생). 카운터(`N / 1025`)·박사의 미조우 가중·진단 리포트처럼 종만 필요한
    /// 소비자용 — 저장하지 않는다(저장하면 `dexForms` 와 어긋날 수 있다).
    var dex: Set<Int> { DexKey.species(of: dexForms) }
    /// 상점에서 쓸 수 있는 재화.
    var wallet: Int { max(0, earnedTokens - spentTokens) }
    /// 데리고 다니는 개체. 박스에서 사라졌으면 nil.
    var partner: Individual? { box.first { $0.id == partnerID } }

    /// 폼 도감 이전(구 세이브)의 옛 키. `dex` 는 이제 계산 프로퍼티라 합성 CodingKeys 에 없다.
    private enum LegacyKeys: String, CodingKey { case dex }

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
        // 폼 도감. 경계 검증(sanitized)이 관대 디코딩의 짝이다 — 종 범위 밖·카탈로그에 없는
        // 유령 키가 도감 카운터를 부풀리지 않게 여기 한 곳에서 버린다.
        dexForms = DexKey.sanitized(value(.dexForms, []))
        // 구 세이브 이전 — 옛 종 단위 `dex` 를 원종 키로 인정한다. 저장 프로퍼티가 사라져
        // CodingKeys 에서 빠졌으므로 디코드 전용 키를 따로 쓴다. **태생 무늬 종은 제외** —
        // 그 종의 bare 키는 원종이 아니라 특정 변종(안농 A)이라, 종 번호만으로는 인정할 수
        // 없다. 보유 중인 실물은 아래 박스 재스캔이 정확한 폼으로 등록한다.
        if dexForms.isEmpty, let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let old = try? legacy.decode(Set<Int>.self, forKey: .dex) {
            dexForms = Set(old.filter {
                DexKey.speciesRange.contains($0) && DexKey.bareKeyIsAPlainBase(speciesID: $0)
            }.map(String.init))
        }
        // 박스 재스캔 — 지금 보유 중인 개체의 폼을 등록한다. 매 디코드에 돌아도 멱등이라
        // 이전 플래그가 필요 없다. 위장 중인 개체는 제외 — 정체가 도감에서 먼저 새면 안 된다.
        dexForms.formUnion(box.filter { $0.disguisedAs == nil }.map(DexKey.key(for:)))
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
        // 관대 디코딩의 짝 — 값 범위 검증. 산술에 쓰이는 수치이므로 자른다.
        researchPoints = min(ReleaseBalance.maxPoints, max(0, value(.researchPoints, 0)))
        ownsRainbowCharm = value(.ownsRainbowCharm, false)
        claimedDexMissions = value(.claimedDexMissions, [])
        claimedCollections = value(.claimedCollections, [])
        // 값 범위를 안 자른다 — 해시 입력일 뿐이라 어떤 값이 와도 산술이 넘치지 않는다
        // (`ProfessorRoll` 은 전부 `&+`/`&*`). 0 만 "아직 없음"으로 취급한다.
        offerSeed = value(.offerSeed, 0)
        professorOfferDate = value(.professorOfferDate, "")
        // 제안도 박스·알과 같은 이유로 원소 단위 관대 디코딩한다 — 한 자리가 깨졌다고 오늘 치가
        // 통째로 날아가면 안 된다. 항목이므로 개수는 안 자르고, 말이 안 되는 원소만 버린다.
        let wrappedOffers = (try? c.decode([LossyProfessorOffer].self, forKey: .professorOffers)) ?? []
        professorOffers = wrappedOffers.compactMap(\.offer)
        if professorOffers.count != wrappedOffers.count {
            AppLog.write("PlayerState: dropped \(wrappedOffers.count - professorOffers.count) malformed professor offer(s) on decode")
        }
        ownsShinyCharm = value(.ownsShinyCharm, false)
        lastTokenAt = value(.lastTokenAt, nil)
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

/// `[ProfessorOffer]` 원소 단위 관대 디코딩 래퍼 — `LossyEgg` 와 같은 패턴에, 개체 자체의
/// 값 범위 검증(`Individual.sanitized`)을 겸한다.
private struct LossyProfessorOffer: Decodable {
    let offer: ProfessorOffer?
    init(from decoder: Decoder) throws {
        guard var decoded = try? ProfessorOffer(from: decoder), decoded.individual.speciesID >= 1
        else { offer = nil; return }
        decoded.individual = decoded.individual.sanitized()
        offer = decoded
    }
}
