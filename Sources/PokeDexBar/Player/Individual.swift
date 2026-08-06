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
