import Foundation

/// 태어날 때 겉모습을 정하는 규칙. 부수효과 없이 미리 뽑은 난수로만 판정한다 —
/// `RegionBalance` 와 같은 모양이라 테스트가 굴림을 그대로 재현한다.
enum BirthFormBalance {
    /// 다른 지역 무늬가 섞일 확률(천분율). 지방 모습과 같은 값으로 뒀다.
    ///
    /// 이게 없으면 한국에서 쓰는 사람은 **비비용 무늬를 평생 하나만 본다** — 한국 지역에 배정된
    /// 무늬가 대륙 하나뿐이기 때문이다(실측). 원작에서 다른 무늬는 해외 사람과 교환해야 얻으니,
    /// 낮은 확률로 섞이는 편이 그 구조를 옮긴 것에 가깝다.
    static let foreignPermille = RegionBalance.regionalPermille

    /// 태어날 때 겉모습을 굴린다. 겉모습이 갈리지 않는 종이면 nil.
    ///
    /// - Parameters:
    ///   - baseID: **부화하는 종**(라인의 시작). 분이벌레로 태어나도 비비용의 무늬를 정해 둬야 한다.
    ///   - roll: 해외 무늬 판정용(0~1). 비비용이 아니면 안 쓴다.
    ///   - pick: 후보 중 하나를 고르는 값(0~1).
    ///   - homeRegion: 이 기기의 지역(ISO 국가 코드). 비비용 무늬가 여기서 갈린다.
    static func rollBirthForm(baseID: Int, roll: Double, pick: Double,
                              homeRegion: String?) -> String? {
        let candidates = candidateVariants(baseID: baseID, roll: roll, homeRegion: homeRegion)
        guard !candidates.isEmpty else { return nil }
        let index = min(candidates.count - 1, max(0, Int(pick * Double(candidates.count))))
        return candidates[index]
    }

    /// 고를 후보. 비비용만 지역을 본다 — 나머지는 언제나 전체가 후보다.
    ///
    /// **확률 게이트가 없다는 점이 지방 모습과 다르다.** 지방은 "20% 확률로 변종, 아니면 원종"이지만
    /// 여기엔 원종이 없다 — 모든 안농은 어떤 글자이고 모든 비비용은 어떤 무늬다.
    static func candidateVariants(baseID: Int, roll: Double, homeRegion: String?) -> [String] {
        let all = BirthFormCatalog.variants(forLineStartingAt: baseID)
        guard baseID == 664, !all.isEmpty else { return all }
        // 해외에서 흘러온 것 — 전체에서 고른다.
        if Int(roll * 1000) < foreignPermille { return all }
        return VivillonRegions.patterns(forCountry: homeRegion)
    }

    /// 스트린더의 폼 — **성격에서 나온다.** 굴리지도, 저장하지도 않는다.
    ///
    /// 원작에서 일레즌은 성격에 따라 두 모습 중 하나로 진화한다. 이 앱은 부화할 때 이미 성격을
    /// 굴려 두므로 새로 정할 것이 없다. 25종이 정확히 두 갈래로 나뉜다(합쳐서 25 — 테스트로 잠근다).
    static func toxtricitySlug(nature: PokemonNature) -> String {
        lowKeyNatures.contains(nature) ? "toxtricity-lowkey" : "toxtricity"
    }

    /// 로우한 모습이 되는 성격 12종. 나머지 13종은 하이한 모습(기본 슬러그).
    static let lowKeyNatures: Set<PokemonNature> = [
        .lonely, .bold, .relaxed, .timid, .serious, .modest,
        .mild, .quiet, .bashful, .calm, .gentle, .careful,
    ]

    /// 스트린더 폼의 배지 이름 — 도감 후보 행(`DexKey.candidates`)과 배지가 같은 값을 쓴다.
    static let ampedLabel = FormLabel("하이한 모습", "Amped", "ハイなすがた")
    static let lowKeyLabel = FormLabel("로우한 모습", "Low Key", "ローなすがた")

    /// 스트린더 폼의 배지 이름.
    static func toxtricityLabel(nature: PokemonNature) -> FormLabel {
        lowKeyNatures.contains(nature) ? lowKeyLabel : ampedLabel
    }
}

/// 비비용 무늬를 정하는 지역 표.
///
/// 원작에서 무늬는 **본체의 지역 설정**으로 정해진다. 그런데 실제 규칙은 나라 단위가 아니라
/// **3DS 지역(American·Japanese·Korean·PAL·Taiwanese) 단위로 "쓸 수 있는 무늬 집합"** 이고,
/// 그 안에서 세부 지역(주·도)이 무늬를 가른다(Bulbapedia 원본 표에서 확인).
///
/// macOS 는 나라까지만 알려 주므로 세부 지역은 알 수 없다. 그래서 **집합까지만 고증을 지키고**
/// 그 안에서는 균등하게 고른다 — "네 지역에서 나올 수 있는 무늬 중 하나"까지가 알 수 있는 전부다.
enum VivillonRegions {
    /// 3DS 지역별로 쓸 수 있는 무늬. 개수까지 원본 표 그대로다.
    static let american = ["archipelago", "highplains", "icysnow", "jungle", "marine",
                           "modern", "ocean", "polar", "sandstorm", "savanna", "sun"]
    static let japanese = ["elegant", "monsoon", "tundra"]
    static let korean = ["continental"]
    static let taiwanese = ["monsoon"]
    static let pal = ["archipelago", "continental", "garden", "highplains", "icysnow",
                      "jungle", "marine", "meadow", "monsoon", "ocean", "polar",
                      "river", "sandstorm", "sun", "tundra"]

    /// 아메리카 대륙 — 3DS 의 American 지역.
    private static let americas: Set<String> = [
        "US", "CA", "MX", "BR", "AR", "CL", "CO", "PE", "VE", "EC", "BO", "PY", "UY",
        "CR", "PA", "GT", "HN", "NI", "SV", "DO", "PR", "JM", "TT", "BS", "BB",
    ]

    /// 이 나라에서 나올 수 있는 무늬. 모르는 나라는 PAL 로 본다 — 가장 넓은 집합(15종)이고,
    /// 3DS 의 PAL 지역이 실제로 유럽·오세아니아·아프리카·아시아 상당수를 포함했다.
    static func patterns(forCountry code: String?) -> [String] {
        switch code?.uppercased() {
        case "KR": korean
        case "JP": japanese
        case "TW", "HK", "MO": taiwanese
        case let country? where americas.contains(country): american
        default: pal
        }
    }

    /// 이 기기의 지역. 설정이 없으면 nil → PAL 로 떨어진다.
    static var current: String? { Locale.current.region?.identifier }
}
