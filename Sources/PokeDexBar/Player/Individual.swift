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

    /// 지금 그려야 할 Showdown 슬러그. 메가·거다이맥스가 우선이고(그 폼일 때만 지정된다),
    /// 다음이 지방 모습, 둘 다 없으면 nil 을 돌려 종 번호 기본 슬러그로 떨어진다.
    var spriteForm: String? {
        if let form { return form }
        guard let region else { return nil }
        return RegionalFormCatalog.form(speciesID: speciesID, region: region,
                                        variant: regionVariant)?.slug
    }

    /// 몇 번째 형태인가(0 = 아직 안 진화). 경로가 비어도 음수로 새지 않는다.
    var stageIndex: Int { max(0, pathIDs.count - 1) }

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
         grade: Grade, form: String? = nil, region: Region? = nil, regionVariant: String? = nil) {
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
        return fixed
    }
}
