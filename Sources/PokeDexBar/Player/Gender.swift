import Foundation

/// 개체의 성별. **부화할 때 한 번 정해져 평생 간다** — 지방 모습·태생 무늬와 같은 부류다.
///
/// `genderless` 를 따로 두는 이유: 옵셔널의 nil 은 "아직 안 정해졌다"(성별을 모르는 옛 세이브)를
/// 뜻해야 하고, "이 종엔 성별이 없다"(메타몽·메탕·전설 대부분)는 그것과 다른 사실이기 때문이다.
/// 둘을 nil 하나로 합치면 옛 세이브 보정(`backfillGenders`)이 무성별 개체를 영원히 다시 굴린다.
enum Gender: String, Codable, Sendable, CaseIterable {
    case male, female, genderless

    /// 기호 — 본가 표기 그대로라 번역하지 않는다.
    var symbol: String {
        switch self {
        case .male: "♂"
        case .female: "♀"
        case .genderless: "—"
        }
    }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .male: names = ("수컷", "Male", "オス")
        case .female: names = ("암컷", "Female", "メス")
        case .genderless: names = ("무성별", "Genderless", "せいべつなし")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 성비와 성별 굴림. 순수 함수라 굴려 보지 않고도 잠근다.
enum GenderBalance {
    /// PokéAPI `gender_rate` — **8분의 몇이 암컷인가**. `-1` 은 무성별이다.
    /// (0=수컷만, 1=12.5%, 2=25%, 4=50%, 6=75%, 7=87.5%, 8=암컷만)
    static let genderless = -1
    /// 성비를 모를 때의 기본값. 절반이 실제로 가장 흔하다(1025종 중 630종).
    static let defaultRate = 4

    /// 스타터 27마리의 성비 — **전부 같다**(실측: 9세대 27마리 모두 `gender_rate == 1`).
    /// 스타터를 고르는 자리에는 `BaseSpecies` 인덱스가 없어서(첫 실행·네트워크 이전) 여기 적어 둔다.
    /// 성장 곡선처럼 나중에 고칠 기회가 없으므로 — 성별은 진화해도 안 바뀐다 — 기본값에 맡기지 않는다.
    static let starterRate = 1

    /// **성별이 고정된 종.** 성별로 갈리는 진화의 도착점 여섯이다 — 이 아이들은 그 성별이
    /// *아니면 존재할 수 없다*(암컷 엘레이드, 수컷 염뉴트는 본가에 없다).
    ///
    /// 왜 필요한가: 옛 세이브 보정은 **base 종의 성비**로 굴리는데(성별은 부화 때 정해지므로
    /// 그게 맞는 키다), 성별 갈래는 정의상 base 와 진화형의 성비가 다르다 — 랄토스는 절반이
    /// 암컷이라 그 굴림이 그대로 엘레이드에 얹히면 **암컷 엘레이드가 생긴다**(실측: 여섯 종
    /// 전부에서 발생 가능). 그래서 굴림 앞에 이 표가 선다.
    ///
    /// **퍼퓨돈(916)은 일부러 뺐다.** 전수 조회에는 걸리지만(PokéAPI 가 성비를 0=수컷만으로
    /// 적어 뒀다) 실제로는 암수가 다 있고, 이 앱이 도감을 가르는 넷 중 하나다. 여기 넣으면
    /// 암컷 퍼퓨돈이 사라진다 — API 를 그대로 믿으면 안 되는 자리다.
    static let locked: [Int: Gender] = [
        413: .female,   // 도롱마담
        414: .male,     // 나메일
        416: .female,   // 비퀸
        475: .male,     // 엘레이드
        478: .female,   // 눈여아
        758: .female,   // 염뉴트
    ]

    static func lockedGender(_ speciesID: Int) -> Gender? { locked[speciesID] }

    /// 종을 아는 굴림 — **고정 성별이 굴림을 이긴다.** 성별을 정하는 자리는 전부 이걸 쓴다.
    static func roll(species speciesID: Int, rate: Int, roll r: Double) -> Gender {
        lockedGender(speciesID) ?? roll(rate: rate, roll: r)
    }

    /// 성비 + 0…1 굴림 → 성별.
    ///
    /// 경계는 `roll < rate/8`. 정수 비교로 바꿔(`Int(roll * 8) < rate`) 하지 않는 이유는
    /// 그러면 `rate == 8`(암컷만)일 때 `roll == 1.0` 이 수컷으로 새기 때문이다 —
    /// 확정 성별은 굴림과 무관하게 확정이어야 한다. 그래서 양 끝을 먼저 처리한다.
    static func roll(rate: Int, roll: Double) -> Gender {
        if rate <= genderless { return .genderless }
        if rate <= 0 { return .male }
        if rate >= 8 { return .female }
        return min(1, max(0, roll)) < Double(rate) / 8 ? .female : .male
    }

    /// 관대 디코딩의 짝 — 값 범위 검증(CLAUDE.md). 알에 적힌 성비가 범위를 벗어나면
    /// 기본값으로 되돌린다. 자르지 않으면 `Int.max` 가 그대로 굴림에 들어간다.
    static func sanitizedRate(_ rate: Int) -> Int {
        (rate == genderless || (0...8).contains(rate)) ? rate : defaultRate
    }
}

/// 암컷 전용 그림이 있는 종. **실측이다** — 1025종 전부에 대해 Showdown 의
/// `<슬러그>-f.png` 존재를 직접 확인해 98종이 나왔다(추측한 목록이 아니다).
///
/// 대부분은 꼬리·무늬 같은 작은 차이라 **도감은 나누지 않는다**. 나누는 넷은 따로 있다
/// (`formSpecies` — 본가에서도 별개 폼으로 세는 아이들).
enum GenderSpriteCatalog {
    /// 암컷 그림이 실제로 존재하는 종.
    static let femaleSprite: Set<Int> = [
        3, 12, 19, 20, 25, 26, 41, 42, 44, 45, 64, 65, 84, 85,
        97, 111, 112, 118, 119, 123, 129, 130, 154, 165, 166, 178, 185, 186,
        190, 194, 195, 198, 202, 203, 207, 208, 212, 214, 215, 217, 221, 224,
        229, 232, 256, 257, 267, 269, 272, 274, 275, 307, 308, 315, 316, 317,
        322, 323, 332, 350, 369, 396, 397, 398, 399, 400, 401, 402, 403, 404,
        405, 407, 415, 417, 424, 443, 444, 445, 449, 450, 453, 454, 456, 457,
        459, 460, 461, 464, 465, 473, 521, 592, 593, 668, 678, 876, 902, 916,
    ]

    /// **암수가 별개의 폼인 넷.** 본가가 폼으로 세는 아이들이라 도감도 따로 센다
    /// (냐오닉스·에써르·대쓰여너·퍼퓨돈). 나머지 94종의 차이는 겉모습일 뿐이라 도감을 안 나눈다 —
    /// 하트 모양 꼬리 때문에 피카츄를 두 번 모으게 하지 않는다.
    static let formSpecies: Set<Int> = [678, 876, 902, 916]

    static func hasFemaleSprite(_ speciesID: Int) -> Bool { femaleSprite.contains(speciesID) }
    static func isFormSpecies(_ speciesID: Int) -> Bool { formSpecies.contains(speciesID) }

    /// 암컷 그림의 슬러그. 종 슬러그 표(`SpeciesSlug`)에서 파생한다 — 이름을 또 적으면
    /// 두 표가 갈라진다.
    static func femaleSlug(_ speciesID: Int) -> String? {
        guard hasFemaleSprite(speciesID), let base = SpeciesSlug.slug(speciesID) else { return nil }
        return "\(base)-f"
    }
}
