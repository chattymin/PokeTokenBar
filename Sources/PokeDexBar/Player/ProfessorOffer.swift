import Foundation

/// 오늘의 제안 한 자리.
///
/// **완성된 개체를 그대로 품는다.** 종·이로치·성격·태생폼을 따로 담아 뒀다가 교환할 때 다시
/// 만들면, 화면에 보인 것과 손에 들어오는 것이 갈릴 수 있다. 미리 만들어 두면 그럴 여지가 없다.
struct ProfessorOffer: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var individual: Individual
    /// 오늘 이미 열어 봤나. **제안은 가려진 채로 온다** — 미리 등급을 보이면 전설은 열기 전에
    /// 이미 알아버려서 터지는 연출이 확인 절차로 전락한다.
    ///
    /// 개체 자체는 뽑을 때 이미 다 정해져 여기 들어 있다(그래야 보이는 것과 받는 것이 안 갈린다).
    /// 이 플래그는 데이터가 아니라 **아직 안 보여준다**는 표시다.
    var opened = false
    /// 오늘 이미 데려갔나. 배열에서 빼지 않고 표시로 남긴다 — 빈 칸 두 개보다 "셋 중 하나는
    /// 이미 데려갔다" 가 사용자에게 더 정확하다.
    var claimed = false
}

/// 박사와의 거래 밸런스.
enum ProfessorBalance {
    /// 하루에 내미는 마릿수.
    static let offerCount = 3

    /// 값 — 보내기 등급기본의 5배. 확정된 한 마리를 고르는 값이므로 보내는 값보다 비싸다.
    static func price(grade: Grade) -> Int { ReleaseBalance.base(grade: grade) * 5 }
}
