import Foundation

/// 파트너가 물어 왔는데 **아직 사용자가 확인하지 않은** 도구.
///
/// 왜 확인 단계를 두나: 채집이 조용히 굴러가기만 하면 무슨 일이 있었는지 알 수가 없어
/// 가방을 열어 봐야 안다. 발견의 순간이 없으면 리본을 오래 유지할 이유도 잘 안 보인다.
///
/// **왜 확인이 다음 채집을 막지 않나**(이게 알과 다른 점이다): 채집은 벽시계가 아니라
/// **토큰**으로 돈다. 확인해야 다음이 돌게 하면, 하루 종일 일하고 저녁에 앱을 연 사용자는
/// 실제로 일한 만큼을 못 받는다 — `Ribbon` 이 세운 축("앱을 켜 두는 쪽이 아니라 실제로 일한
/// 쪽에 보상")을 정면으로 뒤집는다. 알이 확인 방식인 건 알이 벽시계 기반이라 자연스러웠던 것이고,
/// 채집은 성격이 다르다. 그래서 여기서는 **연출만 하고 흐름은 안 막는다.**
struct Discovery: Codable, Equatable, Sendable, Hashable {
    /// `EvolutionItem` 또는 `FormItem` 의 rawValue. 둘을 한 목록에 담으려고 문자열로 둔다
    /// (인벤토리도 같은 이유로 문자열 키다).
    let itemKey: String
    /// 물어 온 개체의 종 — 카드가 "피카츄가 물어 왔어요" 라고 말할 수 있어야 한다.
    let speciesID: Int

    /// 표시 이름. 어느 쪽 도구인지 몰라도 되도록 여기서 흡수한다.
    /// 모르는 키면 nil — 옛 세이브나 사라진 품목이 카드에 빈 줄로 남지 않게 한다.
    func label(_ lang: AppLanguage) -> String? {
        if let item = EvolutionItem.named(itemKey) { return item.label(lang) }
        if let item = FormItem.named(itemKey) { return item.label(lang) }
        return nil
    }
}

extension PlayerStore {
    /// 아직 확인 안 한 발견들. 화면이 이걸로 카드를 낸다.
    var pendingDiscoveries: [Discovery] { state.discoveries }

    /// 확인했다 — 카드를 지운다. 도구는 이미 인벤토리에 들어가 있으므로 여기서 주는 건 없다.
    /// 확인이 늦어도 잃는 게 없다는 것이 이 설계의 요점이다.
    func acknowledgeDiscoveries() {
        guard !state.discoveries.isEmpty else { return }
        mutate { $0.discoveries.removeAll() }
    }
}
