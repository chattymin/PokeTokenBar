import Foundation

/// 박사에게 보내기 — 필요 없는 개체를 보내고 포인트를 받는다.
///
/// **이 앱에서 개체가 박스에서 빠지는 유일한 경로다.** 되돌릴 수 없으므로 확인은 화면이 맡고,
/// 여기서는 파트너만 막는다(파트너 시계·폼 상태가 통째로 사라지는 것을 원천 차단).
extension PlayerStore {
    /// 이 개체를 보내면 받을 포인트. **파트너면 nil** — 보낼 수 없다는 뜻이고, 화면은 이 nil 로
    /// 버튼을 안 만든다(조건을 화면이 따로 적으면 스토어와 갈린다).
    func releaseValue(_ individual: Individual) -> Int? {
        guard individual.id != state.partnerID else { return nil }
        return ReleaseBalance.points(for: individual)
    }

    /// 박사에게 보낸다. 박스에서 빼고 포인트를 더한다. 보낼 수 없으면 nil.
    ///
    /// **`dex` 는 건드리지 않는다** — 도감은 만난 기록이지 소유 기록이 아니다.
    @discardableResult
    func releaseToProfessor(individualID: UUID) -> Int? {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return nil }
        guard let points = releaseValue(state.box[index]) else { return nil }
        mutate { s in
            // 인덱스를 다시 찾는다 — 위 계산과 이 변형 사이에 배열이 바뀔 일은 없지만,
            // id 로 다시 찾는 것이 이 저장소가 정한 형태다.
            guard let i = s.box.firstIndex(where: { $0.id == individualID }) else { return }
            s.box.remove(at: i)
            s.researchPoints = min(ReleaseBalance.maxPoints, s.researchPoints + points)
        }
        return points
    }
}
