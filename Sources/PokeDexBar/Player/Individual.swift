import Foundation

/// 보유 개체 하나. 종(speciesID)이 아니라 개체가 단위다 — 같은 종을 여러 마리 가질 수 있고
/// 각자 이로치·성격·경험치·진화 단계가 따로 간다.
struct Individual: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    /// 처음 만난 형태(스타터로 고르거나 부화한 종). 진화해도 바뀌지 않는다.
    var baseID: Int
    /// 지금 형태.
    var speciesID: Int
    /// 실제로 지나온 경로(baseID 로 시작). 분기 진화에서 어느 쪽으로 갔는지 남는다.
    var pathIDs: [Int]
    var shiny = false
    var nature: PokemonNature
    /// 현재 단계에서 쌓은 경험치. 진화하면 0으로 돌아가고 초과분만 이월한다.
    var exp = 0
    /// 이 개체를 파트너로 두고 쓴 토큰의 누적. 경험치와 달리 진화해도 안 줄고, 경험치 부적으로
    /// 2배가 되지도 않는다 — "이 아이와 얼마나 함께 일했나"의 기록이라 실제 쓴 토큰만 센다.
    var partnerTokens = 0
    /// 파트너로 지낸 시간의 누적(초). 파트너를 바꿀 때 그 구간을 여기 더한다.
    var partnerSeconds = 0
    /// 다음 사탕까지 쌓인 토큰. 리본 단계가 오르면 필요량이 줄어드는데, 진행분은 그대로 이어진다.
    var candyProgress = 0
    /// 지금 파트너라면 언제부터인가. 파트너가 아니면 nil — 지금 구간은 아직 안 닫혀서
    /// `partnerSeconds` 에 안 들어가 있다(표시할 땐 둘을 더한다).
    var partnerSince: Date?
    var obtainedAt: Date
    var grade: Grade
    /// 지금 취하고 있는 폼의 Showdown 슬러그(`charizard-megax`). nil 이면 보통 모습.
    /// 종이 아니라 겉모습이라 `speciesID`·`pathIDs` 는 그대로 두고, 진화하면 풀린다.
    var form: String?
    /// 태어난 지방. nil 이면 원종이다. 폼(메가)과 달리 **아이템으로 바뀌지 않고 진화해도 이어진다** —
    /// 알로라 식스테일은 알로라 나인테일이 된다.
    var region: Region?
    /// 같은 지방에 모습이 여럿인 종의 구분(팔데아 켄타로스 combat/blaze/aqua).
    var regionVariant: String?
    /// 파트너 자리에서 **몇 번 물러났나.**
    ///
    /// 돌핀맨(#964)의 모습이 여기서 나온다 — 홀수 번 물러났으면 마이티폼, 짝수면 평소 모습.
    /// 곁에 뒀다 내렸다 할 때마다 번갈아 바뀐다.
    ///
    /// **횟수를 담고 해석은 읽는 쪽에서 한다.** 뒤집힌 상태를 불리언으로 담으면 저장된 값이
    /// "몇 번 물러났나"가 아니라 "지금 어느 폼인가"가 되어, 규칙을 바꾸는 순간 옛 세이브의 뜻이
    /// 달라진다. `partnerSeconds > 0` 으로 파생시키지 않는 이유도 같다 — 1초 미만으로 교체하면
    /// 그 값이 0이라, 대체로 맞을 뿐 사실 자체가 아니다.
    var partnerStintsEnded = 0
    /// 이 개체의 경험치 곡선. **개체가 들고 다니는** 이유는 `GrowthRate` 주석에 있다 —
    /// 레벨 계산 자리에 네트워크가 없기 때문이다. 진화하면 새 종의 것으로 갱신한다.
    var growthRate: GrowthRate = .mediumFast
    /// 알 계량기. 파트너인 동안 쓴 **토큰**만큼 찬다(EXP 가 아니다 — 임계가 토큰 단위다).
    /// `exp` 와 서로를 깎지 않는다. 예전에는 `exp` 하나가 두 역할을 겸했고, 그것 때문에
    /// 등급이 경험치에 끼어들어야 했다.
    var eggProgress = 0
    /// **경험치로 못 바꾼 토큰의 나머지.** 환율(`ExpBalance.tokensPerExp`)로 나눈
    /// 정수 나눗셈은 매 갱신(`PlayerStore.update`, 기본 120초 주기)마다 자투리를 버린다 —
    /// 이월이 없으면 한 번에 500토큰을 못 채우는 가벼운 사용자는 `exp` 가 **영원히 0**이다
    /// (하루 10만 토큰이면 한 틱에 약 400토큰 → 400/8000=0). 그래서 여기 남겨 뒀다가 다음
    /// 갱신의 몫과 합쳐서 나눈다 — 사탕처럼 이미 "몫과 나머지" 로 정산하는 자리(`candyYield`)
    /// 와 같은 패턴이다.
    var expRemainder = 0
    /// 맞아서 겉모습이 깨졌나(따라큐의 탈, 빙큐보의 얼음머리).
    ///
    /// 파트너에서 내려오면 돌아온다(`PlayerStore.closePartnerStint`) — 그 아이의 배틀이
    /// 끝나는 것에 해당한다. 앱을 껐다 켜도 유지되므로 저장한다.
    var formBroken = false
    /// 태어날 때 정해진 겉모습의 변종 키(`"c"` · `"polar"` · `"blue"` · `"east"`).
    ///
    /// 지방(`region`)과 성격이 같다 — 부화할 때 정해지고 평생 안 바뀌며 진화해도 이어진다.
    /// 다만 지방은 "어디서 왔나"이고 이건 **그냥 그렇게 태어난 것**이다.
    /// 슬러그가 아니라 키를 담는 이유는 단계마다 슬러그가 다르기 때문이다
    /// (`flabebe-blue` → `floette-blue` → `florges-blue`).
    var birthForm: String?
    /// 위장 중이면 그 모습의 종 번호(메타몽이 뮤로 위장 중이면 151). 풀리면 nil 이 되고 다시 안 붙는다.
    ///
    /// **정체는 `speciesID` 에 그대로 둔다.** 위장 중에도 이 개체는 메타몽이고, 진화·리본·경험치가
    /// 전부 메타몽 기준으로 돈다. 위장은 이름과 그림에만 얹는다 — 반대로 하면(뮤로 저장했다가
    /// 나중에 바꾸기) 정체가 드러나는 순간 개체의 정체성이 통째로 바뀌어 여기저기가 어긋난다.
    var disguisedAs: Int?

    /// 화면에 보여야 할 종. 위장 중이면 위장한 쪽, 아니면 정체.
    var displaySpeciesID: Int { disguisedAs ?? speciesID }

    /// 정체를 알 수 없는 종의 표기. 원작이 쓰는 그대로라 번역하지 않는다.
    static let unknownName = "???"

    /// 태어날 때 정해진 겉모습의 이름 — 배지에 쓴다. 없으면 nil.
    ///
    /// **이름 앞에 붙이지 않는다.** "알로라 라이츄"는 자연스럽지만 "설국의 모양 비비용"은 아니다.
    /// 지방 배지와 같은 자리에 같은 모양으로 놓는다(둘 다 붙는 개체는 없다 — 이 다섯 라인에는
    /// 지방 모습이 없다).
    func birthFormLabel(_ lang: AppLanguage) -> String? {
        // 위장 중이면 아무것도 안 내민다 — 정체를 알려 주는 단서가 된다.
        guard disguisedAs == nil else { return nil }
        if speciesID == 849 { return BirthFormBalance.toxtricityLabel(nature: nature).text(lang) }
        guard let birthForm,
              let known = BirthFormCatalog.form(speciesID: speciesID, variant: birthForm)
        else { return nil }
        return known.label.text(lang)
    }

    /// 이름을 찾을 때 볼 진화 라인의 키. 위장 중이면 **위장한 종의 라인**을 봐야 한다 —
    /// 정체(메타몽)의 라인에는 위장한 종(뮤)의 이름이 없어서 "#151" 로 떨어진다.
    var displayLineID: Int { disguisedAs ?? baseID }

    /// 화면에 이로치로 보여야 하나. **위장 중에는 숨긴다** — 위장이 들킬 단서를 스스로 내밀면
    /// 위장이 아니다. 정체가 드러난 뒤 진짜 모습에서 공개된다.
    var showsShiny: Bool { shiny && disguisedAs == nil }

    /// 지금 그려야 할 Showdown 슬러그. 메가·거다이맥스가 우선이고(그 폼일 때만 지정된다),
    /// 다음이 지방 모습, 둘 다 없으면 nil 을 돌려 종 번호 기본 슬러그로 떨어진다.
    var spriteForm: String? {
        // 위장이 가장 앞이다 — 위장 중엔 다른 무엇도 그려지면 안 된다.
        if disguisedAs != nil { return DittoDisguise.formSlug }
        if let form { return form }
        // 테라파고스 — 곁에 두면 테라스탈 폼. 특성 「테라체인지」가 *배틀에 나오면* 발동하는
        // 그대로다(테라스탈 기믹과는 별개로, 등장 자체가 트리거다). 저장할 값이 없다.
        //
        // **도구로 연 스텔라가 이걸 이긴다** — 위의 `form` 분기가 먼저라 이 줄까지 안 온다.
        // 원작에서도 스텔라는 테라스탈 폼에서 한 단계 더 간 모습이다.
        if speciesID == 1024, partnerSince != nil { return "terapagos-terastal" }
        // 돌핀맨 — 물러난 횟수가 홀수면 마이티폼. 저장된 슬러그가 아니라 그 횟수에서 나온다.
        //
        // 원작의 「제로 투 히어로」는 *배틀에서 물러날 때* 발동하고 그 배틀 동안 유지된다.
        // 이 앱엔 배틀 경계가 없어서 "언제 노말로 돌아가나"에 답이 없다 — 그래서 곁에 뒀다
        // 내렸다 할 때마다 번갈아 바뀌게 뒀다. 사용자가 직접 오가게 만드는 조작이라 변신을
        // 눈으로 보게 된다.
        if speciesID == 964, partnerStintsEnded.isMultiple(of: 2) == false { return "palafin-hero" }
        // 깨진 모습이 가장 먼저다 — 깨져 있으면 그게 지금 이 아이의 모습이다.
        if formBroken, let broken = BrokenForm.slugs[speciesID] { return broken }
        // 스트린더는 저장된 값이 없다 — 성격에서 나온다.
        if speciesID == 849 { return BirthFormBalance.toxtricitySlug(nature: nature) }
        // 태어날 때 정해진 겉모습. **그 단계에 해당 그림이 없으면 그냥 넘어간다** —
        // 분이벌레는 무늬를 갖고 있어도 겉모습이 같아서 카탈로그에 항목이 없다.
        if let birthForm,
           let known = BirthFormCatalog.form(speciesID: speciesID, variant: birthForm) {
            return known.slug
        }
        guard let region else { return nil }
        return RegionalFormCatalog.form(speciesID: speciesID, region: region,
                                        variant: regionVariant)?.slug
    }

    /// 몇 번째 형태인가(0 = 아직 안 진화). 경로가 비어도 음수로 새지 않는다.
    var stageIndex: Int { max(0, pathIDs.count - 1) }

    /// 지금 레벨. 경험치에서 파생되므로 따로 저장하지 않는다 — 저장하면 둘이 어긋날 수 있다.
    var level: Int { growthRate.level(forExp: exp) }

    /// 지금 달고 있는 리본. 파트너로 지낸 누적 시간에서 파생되므로 따로 저장하지 않는다 —
    /// 저장하면 시간과 리본이 어긋날 수 있고, 어느 쪽이 진실인지 애매해진다.
    func ribbon(at now: Date) -> Ribbon? { Ribbon.earned(partnerSeconds: partnerDuration(at: now)) }

    /// 함께한 시간 표기 — 가장 큰 단위 둘까지. 순수 함수라 테스트로 잠근다.
    static func togetherText(seconds: Int, _ l: L) -> String {
        let s = max(0, seconds)
        let days = s / 86_400, hours = (s % 86_400) / 3_600, minutes = (s % 3_600) / 60
        if days > 0 { return l.togetherDays(days, hours) }
        if hours > 0 { return l.togetherHours(hours, minutes) }
        return l.togetherMinutes(minutes)
    }

    /// 화면에 쓸 이름. 종 이름은 진화 라인(PokéAPI)에서 오므로 호출부가 넘긴다 —
    /// 아직 못 받았으면 `#번호` 를 넘기면 된다. 접두는 하나만 붙는다: 메가·거다이맥스를 취하고
    /// 있으면 그쪽이, 아니면 지방 이름이.
    func displayName(speciesName: String, _ lang: AppLanguage) -> String {
        // **위장 중에는 이름을 감춘다.** 위장한 종의 이름을 그대로 쓰면 라인을 못 받아온 화면에서
        // "#151" 같은 번호가 튀어나오고(홈이 그랬다), 이름을 정확히 대는 것 자체가 정체를 반쯤
        // 알려 주는 일이다. 정체가 드러나면 진짜 이름으로 돌아온다.
        guard disguisedAs == nil else { return Self.unknownName }
        if let slug = form, let known = FormCatalog.form(slug: slug) {
            return known.displayName(base: speciesName, lang)
        }
        // 그 종에 지방 모습이 실제로 있을 때만 이름을 바꾼다 — 나이킹을 "가라르 나이킹"이라
        // 부르지 않는다(가라르에서 왔다는 건 혈통이지 그 종의 모습 이름이 아니다).
        if let region, RegionalFormCatalog.form(speciesID: speciesID, region: region) != nil {
            return region.displayName(base: speciesName, lang)
        }
        return speciesName
    }

    /// 지금까지 파트너로 지낸 총 시간(초) — 닫힌 구간 + 아직 진행 중인 구간.
    /// 시계가 뒤로 뛰어도 음수가 되지 않게 자른다.
    func partnerDuration(at now: Date) -> Int {
        guard let partnerSince else { return partnerSeconds }
        return partnerSeconds + max(0, Int(now.timeIntervalSince(partnerSince)))
    }

    /// 기본 이니셜라이저 — 아래 `init(from:)` 을 직접 쓰면서 합성 이니셜라이저가 사라지므로 명시한다.
    init(id: UUID = UUID(), baseID: Int, speciesID: Int, pathIDs: [Int], shiny: Bool = false,
         nature: PokemonNature, exp: Int = 0, partnerTokens: Int = 0, partnerSeconds: Int = 0,
         partnerSince: Date? = nil, candyProgress: Int = 0, obtainedAt: Date,
         grade: Grade, form: String? = nil, region: Region? = nil, regionVariant: String? = nil,
         growthRate: GrowthRate = .mediumFast, eggProgress: Int = 0, expRemainder: Int = 0) {
        self.id = id
        self.baseID = baseID
        self.speciesID = speciesID
        self.pathIDs = pathIDs
        self.shiny = shiny
        self.nature = nature
        self.exp = exp
        self.partnerTokens = partnerTokens
        self.partnerSeconds = partnerSeconds
        self.partnerSince = partnerSince
        self.candyProgress = candyProgress
        self.obtainedAt = obtainedAt
        self.grade = grade
        self.form = form
        self.region = region
        self.regionVariant = regionVariant
        self.growthRate = growthRate
        self.eggProgress = eggProgress
        self.expRemainder = expRemainder
    }

    /// **필드를 더할 때 박스가 통째로 사라지지 않게 하는 장치.**
    /// Swift 가 합성해 주는 디코더는 프로퍼티에 기본값이 있어도 키가 없으면 그냥 던진다. `Individual`
    /// 은 `LossyIndividual` 이 감싸고 있어서 그 예외가 곧 "이 개체를 버린다"가 되고, 새 필드 하나를
    /// 더한 순간 **기존 세이브의 모든 개체가 조용히 사라진다**(`partnerTokens` 를 더하면서 실제로
    /// 그렇게 됐고, 테스트가 잡았다). 그래서 정체성에 해당하는 필드만 필수로 두고 나머지는 기본값을 쓴다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        // 이 넷이 없으면 어떤 개체인지 알 수 없다 — 여기서만 던진다.
        baseID = try c.decode(Int.self, forKey: .baseID)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        nature = try c.decode(PokemonNature.self, forKey: .nature)
        grade = try c.decode(Grade.self, forKey: .grade)

        id = value(.id, UUID())
        pathIDs = value(.pathIDs, [speciesID])
        shiny = value(.shiny, false)
        exp = value(.exp, 0)
        partnerTokens = value(.partnerTokens, 0)
        partnerSeconds = value(.partnerSeconds, 0)
        partnerSince = value(.partnerSince, nil)
        candyProgress = value(.candyProgress, 0)
        obtainedAt = value(.obtainedAt, Date(timeIntervalSince1970: 0))
        form = value(.form, nil)
        region = value(.region, nil)
        regionVariant = value(.regionVariant, nil)
        disguisedAs = value(.disguisedAs, nil)
        birthForm = value(.birthForm, nil)
        formBroken = value(.formBroken, false)
        partnerStintsEnded = value(.partnerStintsEnded, 0)
        growthRate = value(.growthRate, .mediumFast)
        // 새 필드라 반드시 `value(_:_:)` 를 거친다 — 합성 디코더로 그냥 `decode` 하면 이 키가
        // 없는 기존 세이브의 개체 전부가 `LossyIndividual` 에서 조용히 버려진다(주석 참고).
        expRemainder = value(.expRemainder, 0)
        // **레벨 이전 세이브 판별.** `eggProgress` 키가 없으면 `exp` 는 아직 "쓴 토큰" 이다.
        // 그때는 그 값을 둘로 나눠 준다 — 알 진행분은 그대로 물려주고(쌓아 둔 걸 뺏지 않는다),
        // 경험치는 환율로 나눠 실제 EXP 로 만든다. 키가 있으면 이미 이전이 끝난 세이브다.
        if let carried = try? c.decode(Int.self, forKey: .eggProgress) {
            eggProgress = carried
        } else {
            eggProgress = exp
            exp = exp / ExpBalance.tokensPerExp
        }
    }

    /// 관대 디코딩의 짝 — 값 범위 검증(CLAUDE.md 결함 대응 프로토콜).
    /// 카탈로그에 없는 폼 슬러그는 버린다. 그대로 두면 스프라이트가 없는 슬러그로 계속 요청이 나가
    /// 그 개체만 영영 빈칸으로 남는다(앱은 안 죽으니 원인이 안 보인다). 그 종의 폼이 아닌 슬러그도
    /// 마찬가지 — 리자몽 세이브에 이상해꽃 메가가 들어 있으면 엉뚱한 그림이 뜬다.
    func sanitized() -> Individual {
        var fixed = self
        if let slug = form,
           FormCatalog.form(slug: slug)?.speciesID != speciesID {
            fixed.form = nil
            AppLog.write("Individual: dropped unknown form slug \(slug) for species \(speciesID)")
        }
        // 지방은 진화 뒤 그 지방 모습이 없는 종이 될 수 있으므로(가라르 나옹 → 나이킹) 종에 모습이
        // 없다는 것만으로 버리지 않는다. 변형 이름만, 그 지방에 실제로 있는 것인지 확인한다.
        if let region = fixed.region, let variant = fixed.regionVariant,
           RegionalFormCatalog.forms(speciesID: speciesID)
               .first(where: { $0.region == region && $0.variant == variant }) == nil {
            fixed.regionVariant = nil
        }
        // 깨질 수 없는 종에 깨졌다고 적혀 있으면 버린다 — 그대로 두면 없는 슬러그를 요청한다.
        if fixed.formBroken, BrokenForm.slugs[speciesID] == nil {
            fixed.formBroken = false
            AppLog.write("Individual: dropped formBroken on species \(speciesID)")
        }
        // 카탈로그에 없는 변종은 버린다. 그대로 두면 그 개체만 영영 기본 모습으로 보이는데,
        // 값은 남아 있어 원인이 안 보인다 — 관대 디코딩의 짝인 값 범위 검증이다.
        // **라인 기준으로 본다** — 분이벌레는 자기 단계엔 항목이 없지만 무늬는 가져야 한다.
        if let variant = fixed.birthForm,
           !BirthFormCatalog.variants(forLineStartingAt: baseID).contains(variant) {
            fixed.birthForm = nil
            AppLog.write("Individual: dropped unknown birth form \(variant) for line \(baseID)")
        }
        // 위장은 메타몽이 뮤로 하는 것 하나뿐이다. 다른 값이 들어 있으면(외부 세이브를 들여올 때)
        // 존재하지 않는 그림을 계속 요청하게 되므로 버린다 — 관대 디코딩의 짝인 값 범위 검증이다.
        if let disguise = fixed.disguisedAs,
           disguise != DittoDisguise.disguisedAs || speciesID != DittoDisguise.speciesID {
            fixed.disguisedAs = nil
            AppLog.write("Individual: dropped bogus disguise \(disguise) on species \(speciesID)")
        }
        // 관대 디코딩의 짝 — 산술에 쓰이는 수치는 경계 한 곳에서 자른다(CLAUDE.md).
        // 자르지 않으면 `Int.max` 가 그대로 저장돼 이후 덧셈이 오버플로 트랩으로 프로세스를 죽이고,
        // 재기동해도 같은 파일을 읽어 또 죽는다.
        fixed.exp = min(fixed.growthRate.totalExp(at: GrowthRate.maxLevel), max(0, fixed.exp))
        fixed.eggProgress = min(ExpBalance.eggThreshold(grade: fixed.grade), max(0, fixed.eggProgress))
        // 나머지는 정의상 환율 미만이어야 한다 — 그 이상이면 몫으로 나갔어야 할 값이다.
        fixed.expRemainder = min(ExpBalance.tokensPerExp - 1, max(0, fixed.expRemainder))
        return fixed
    }
}
