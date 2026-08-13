import Foundation

/// 박스 정리 — 저장된 순서를 다시 배열한다.
extension PlayerStore {
    /// 박스를 이 기준으로 **한 번** 재배치하고 저장한다.
    ///
    /// 정렬 기준은 저장하지 않는다 — 재배치된 배열 자체가 결과이고, 이후에 들어오는 개체는
    /// `box.append` 로 맨 뒤에 붙는다(결정 2). 되돌리려면 `.obtained` 로 다시 부르면 된다.
    func sortBox(_ sort: BoxSort) {
        let now = currentDate()
        mutate { $0.box = sort.apply(to: $0.box, at: now) }
    }
}
