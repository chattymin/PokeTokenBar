import Foundation

/// 박스 정리 — 저장된 순서를 **한 번 재배치하는 명령**.
///
/// 보기 설정이 아니다. 누른 그 시점에 `state.box` 자체가 다시 배열되고 저장되며, 이후에 들어오는
/// 개체는 정렬 기준과 무관하게 맨 뒤에 붙는다. 그래서 "지금 무슨 정렬 상태인가" 라는 상태가
/// 아예 없다 — 재배치된 배열이 곧 결과다.
///
/// `obtained` 는 **유일한 되돌리기**다. `obtainedAt` 은 개체마다 그대로 남으므로 언제든 원래
/// 배치로 돌아올 수 있다. 정렬이 파괴적인 동작인 만큼 이 항목은 메뉴에서 빠지면 안 된다.
enum BoxSort: CaseIterable, Sendable {
    case obtained
    /// 별표 먼저 — 아끼는 개체를 위로 모아 훑어본다(포켓몬 GO 의 즐겨찾기 정렬).
    case starred
    case levelHigh, levelLow
    case grade
    case dex
    case shiny
    case ribbon

    /// 재배치. 순수 함수라 테스트로 잠근다.
    ///
    /// `now` 를 받는 이유: 리본은 함께한 시간에서 파생되므로(`Individual.ribbon(at:)`) 시계가
    /// 있어야 읽을 수 있다. 인자로 받아야 테스트가 결정적이 된다.
    func apply(to box: [Individual], at now: Date) -> [Individual] {
        box.sorted { a, b in
            let ka = key(a, at: now), kb = key(b, at: now)
            if ka != kb { return ka < kb }
            // **동률은 획득순 → id.** 이차 키가 없으면 배치가 호출마다 달라지고, 그 배치가
            // 디스크에 저장되므로 열 때마다 박스가 뒤섞인 것처럼 보인다. `obtainedAt` 도
            // 동률일 수 있어(한 순간에 둘이 들어오는 경로가 있다) `id` 까지 간다.
            if a.obtainedAt != b.obtainedAt { return a.obtainedAt < b.obtainedAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// 1차 정렬 키. 내림차순은 음수로 만든다 — 비교를 한 방향으로만 두면 동률 처리가 한 곳이 된다.
    /// `obtained` 는 모두 같은 키를 내어 위의 획득순 폴백으로 그대로 떨어진다.
    private func key(_ individual: Individual, at now: Date) -> Int {
        switch self {
        case .obtained: 0
        case .starred: individual.starred ? 0 : 1
        case .levelHigh: -individual.level
        case .levelLow: individual.level
        case .grade: -individual.grade.rank
        // **화면에 보이는 번호로 정렬한다.** 진짜 `speciesID` 를 쓰면 뮤로 위장한 메타몽이
        // 132번 자리에 서서, 눌러 확인하기 전에 정체가 샌다.
        case .dex: individual.displaySpeciesID
        // 같은 이유로 `showsShiny` — 위장 중이면 이로치를 감춘다.
        case .shiny: individual.showsShiny ? 0 : 1
        case .ribbon: -(individual.ribbon(at: now)?.rawValue ?? 0)
        }
    }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .obtained:  names = ("획득순", "By when you got it", "手にいれた順")
        case .starred:   names = ("별표 먼저", "Starred first", "★を先に")
        case .levelHigh: names = ("레벨 높은 순", "Highest level", "レベルの高い順")
        case .levelLow:  names = ("레벨 낮은 순", "Lowest level", "レベルの低い順")
        case .grade:     names = ("등급 높은 순", "Highest grade", "ランクの高い順")
        case .dex:       names = ("도감번호순", "By Dex number", "図鑑番号順")
        case .shiny:     names = ("이로치 먼저", "Shinies first", "色違いを先に")
        case .ribbon:    names = ("리본 높은 순", "Highest Ribbon", "リボンの高い順")
        }
        switch lang {
        case .ko: return names.0
        case .en: return names.1
        case .ja: return names.2
        }
    }
}
