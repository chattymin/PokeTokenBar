import Foundation

/// 도감 행 하나 — 어떤 키로 등록되고, 어떤 그림·이름으로 보이는가.
struct DexFormCandidate: Equatable, Sendable {
    /// 도감 키. `PlayerState.dexForms` 에 이 값이 있으면 등록된 폼이다.
    let key: String
    /// 스프라이트 슬러그. nil 이면 종 기본 그림(`SpriteView` 의 form 인자에 그대로 넘긴다).
    let slug: String?
    /// 폼 이름. nil 이면 원종 행이다(UI 가 "원종" 문자열로 대체).
    let label: FormLabel?
}

/// 폼 단위 도감의 키 체계. 원종은 `"37"`, 태생 폼은 `"37/vulpix-alola"`(종 번호 + Showdown 슬러그).
///
/// 도감 항목이 되는 폼은 **태어날 때 정해져 평생 가는 것**만이다 — 지방 모습·태생 무늬·
/// 스트린더의 성격 폼. 메가·거다이맥스·위장·깨진 탈처럼 켜고 끄는 변신은 종 등록에 포함된다.
/// 변종의 슬러그가 종의 기본 슬러그와 같으면(안농 A 의 `unown` 등) bare 키로 접는다 —
/// 같은 그림에 키 두 개가 생기면 옛 세이브의 종 번호 이전과도 어긋난다.
enum DexKey {
    static let speciesRange = 1...1025

    /// 스트린더 — 성격에서 폼이 갈리는 유일한 종(`Individual.spriteForm` 과 같은 특례).
    private static let toxtricityID = 849

    /// 개체 → 도감 키. `Individual.spriteForm` 의 태생 분기(성격 폼 → 태생 무늬 → 지방 모습)와
    /// 같은 우선순위를 따르되, 도구·상태 분기(메가·깨짐·위장·히어로)는 무시한다.
    static func key(for individual: Individual) -> String {
        let id = individual.speciesID
        if id == toxtricityID {
            return key(speciesID: id, slug: BirthFormBalance.toxtricitySlug(nature: individual.nature))
        }
        if let variant = individual.birthForm,
           let known = BirthFormCatalog.form(speciesID: id, variant: variant) {
            return key(speciesID: id, slug: known.slug)
        }
        if let region = individual.region,
           let form = RegionalFormCatalog.form(speciesID: id, region: region,
                                               variant: individual.regionVariant) {
            return key(speciesID: id, slug: form.slug)
        }
        return String(id)
    }

    /// 종 + 슬러그 → 키. 기본 슬러그는 bare 키로 접는다.
    static func key(speciesID: Int, slug: String?) -> String {
        guard let slug, slug != SpeciesSlug.slug(speciesID) else { return String(speciesID) }
        return "\(speciesID)/\(slug)"
    }

    static func speciesID(of key: String) -> Int? {
        Int(key.prefix(while: { $0 != "/" }))
    }

    /// 키 집합 → 종 집합. `PlayerState.dex`(종 단위 파생)의 구현이다.
    static func species(of keys: Set<String>) -> Set<Int> {
        Set(keys.compactMap(speciesID(of:)))
    }

    /// 관대 디코딩의 짝 — 신뢰경계 값 범위 검증(CLAUDE.md 결함 대응 프로토콜). 종 범위 밖이거나
    /// 그 종의 후보에 없는 키(메가 슬러그·엉뚱한 종의 슬러그)는 버린다 — 유령 키가 도감
    /// 카운터를 부풀리지 않게. 항목 삭제가 아니라 형식 위반 제거라 데이터 손실이 아니다.
    static func sanitized(_ keys: Set<String>) -> Set<String> {
        let valid = keys.filter { key in
            guard let id = speciesID(of: key), speciesRange.contains(id) else { return false }
            return candidates(speciesID: id).contains { $0.key == key }
        }
        if valid.count != keys.count {
            AppLog.write("DexKey: dropped \(keys.count - valid.count) bogus dex key(s) at the boundary")
        }
        return Set(valid)
    }

    /// 이 종의 도감 행 후보 — 표시 순서대로. 대다수 종은 원종 한 행이다.
    /// 태생 무늬 종은 원종 행이 따로 없다 — 기본 슬러그 변종(안농 A·화원 비비용)이 그 자리다.
    static func candidates(speciesID id: Int) -> [DexFormCandidate] {
        if id == toxtricityID {
            return [DexFormCandidate(key: String(id), slug: nil, label: BirthFormBalance.ampedLabel),
                    DexFormCandidate(key: "\(id)/toxtricity-lowkey", slug: "toxtricity-lowkey",
                                     label: BirthFormBalance.lowKeyLabel)]
        }
        let births = BirthFormCatalog.forms(speciesID: id)
        if !births.isEmpty {
            return births.map { birth in
                let key = key(speciesID: id, slug: birth.slug)
                return DexFormCandidate(key: key, slug: key == String(id) ? nil : birth.slug,
                                        label: birth.label)
            }
        }
        var rows = [DexFormCandidate(key: String(id), slug: nil, label: nil)]
        rows += RegionalFormCatalog.forms(speciesID: id).map {
            DexFormCandidate(key: "\(id)/\($0.slug)", slug: $0.slug, label: label(for: $0))
        }
        return rows
    }

    /// 지방 폼 행의 이름 — 지방 이름에 변종 구분(팔데아 켄타로스)을 붙인다.
    private static func label(for form: RegionalForm) -> FormLabel {
        let region = FormLabel(form.region.label(.ko), form.region.label(.en), form.region.label(.ja))
        guard let variant = form.variant else { return region }
        let breed: FormLabel = switch variant {
        case "combat": FormLabel("컴뱃종", "Combat Breed", "コンバットしゅ")
        case "blaze": FormLabel("블레이즈종", "Blaze Breed", "ブレイズしゅ")
        case "aqua": FormLabel("워터종", "Aqua Breed", "ウォーターしゅ")
        default: FormLabel(variant, variant, variant)
        }
        return FormLabel("\(region.ko) \(breed.ko)", "\(region.en) \(breed.en)",
                         "\(region.ja)\(breed.ja)")
    }
}
