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

    /// 몇 번째 형태인가(0 = 아직 안 진화). 경로가 비어도 음수로 새지 않는다.
    var stageIndex: Int { max(0, pathIDs.count - 1) }

    /// 관대 디코딩의 짝 — 값 범위 검증(CLAUDE.md 결함 대응 프로토콜).
    /// 카탈로그에 없는 폼 슬러그는 버린다. 그대로 두면 스프라이트가 없는 슬러그로 계속 요청이 나가
    /// 그 개체만 영영 빈칸으로 남는다(앱은 안 죽으니 원인이 안 보인다). 그 종의 폼이 아닌 슬러그도
    /// 마찬가지 — 리자몽 세이브에 이상해꽃 메가가 들어 있으면 엉뚱한 그림이 뜬다.
    func sanitized() -> Individual {
        guard let slug = form else { return self }
        guard let known = FormCatalog.form(slug: slug), known.speciesID == speciesID else {
            var fixed = self
            fixed.form = nil
            AppLog.write("Individual: dropped unknown form slug \(slug) for species \(speciesID)")
            return fixed
        }
        return self
    }
}
