import Foundation

/// 위장이 풀리는 순간.
///
/// 알 부화와 같은 모양으로 짰다: **저절로 일어나되, 사용자가 못 보고 지나가지 않게** 알린다.
/// 다른 점은 확인 버튼이 없다는 것이다 — 알은 사용자가 열어야 무엇인지 알 수 있지만, 위장은
/// 파트너로 곁에 두는 동안 이미 보고 있는 개체라 그 자리에서 바뀌는 편이 낫다.
extension PlayerStore {
    /// 위장이 풀릴 때가 된 개체를 전부 공개하고, 공개된 개체를 돌려준다.
    ///
    /// 여러 곳에서 불린다(사용량 틱·팝오버 열기·파트너 카드의 1초 틱). 한 번 풀린 개체는
    /// `disguisedAs` 가 nil 이라 다시 걸리지 않으므로, 몇 번을 불러도 결과는 같다.
    @discardableResult
    func revealDisguises(at now: Date) -> [Individual] {
        let ready = state.box.filter {
            $0.disguisedAs != nil && DittoDisguise.isReady(partnerSeconds: $0.bondDuration(at: now))
        }
        guard !ready.isEmpty else { return [] }
        let ids = Set(ready.map(\.id))
        mutate { state in
            for index in state.box.indices where ids.contains(state.box[index].id) {
                state.box[index].disguisedAs = nil
                // 정체가 드러난 지금이 도감에 들어갈 때다 — 위장 중엔 미뤄 두었다.
                state.dexForms.insert(DexKey.key(for: state.box[index]))
            }
        }
        return state.box.filter { ids.contains($0.id) }
    }

    /// 공개하고, 공개할 게 있었으면 알린다. 호출 지점이 여럿이라 "한 번 공개 = 한 번 알림"이
    /// 지점마다 갈라지지 않게 여기 한 곳에 묶는다(`announceReadyEggsAndNotify` 와 같은 형태).
    @discardableResult
    func revealDisguisesAndNotify(at now: Date) -> [Individual] {
        let revealed = revealDisguises(at: now)
        DisguiseNotifier().notify(revealed: revealed, language: language)
        return revealed
    }
}
