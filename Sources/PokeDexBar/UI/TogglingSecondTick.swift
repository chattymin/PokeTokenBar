import SwiftUI

/// 껐다 켤 수 있는 1초 틱.
///
/// **왜 `if/else` 로 감싸면 안 되나.** `TimelineView` 로 감싼 가지와 안 감싼 가지는 SwiftUI 에게
/// 서로 다른 뷰다. 조건이 뒤집히는 순간 안쪽 뷰가 통째로 새로 만들어지고 **그 안의 `@State` 가
/// 날아간다.**
///
/// 실제로 그렇게 잃었다: 마지막 알을 확인하면 알이 0개가 되어 "알이 있을 때만 틱" 조건이 뒤집히고,
/// 그 바람에 `EggSlotsView` 가 새로 만들어지면서 방금 심은 `hatched` 가 지워졌다 — 부화 연출이
/// 아예 안 떴다(사용자 리포트). 알이 하나라도 남으면 조건이 안 바뀌므로 **마지막 알에서만** 났다.
///
/// 가지를 없애고 일정만 끄면 뷰는 제자리에 남는다. 꺼진 동안에는 시각을 하나만 내주고 끝나므로
/// 타이머가 돌지 않는다 — 알이 없는 사용자에게 매초 재렌더를 시키지 않는다는 에너지 규율은 그대로다.
struct TogglingSecondTick: TimelineSchedule {
    var isOn: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        let isOn = isOn
        return AnyIterator {
            defer { next = isOn ? next?.addingTimeInterval(1) : nil }
            return next
        }
    }

    /// 이 일정이 실제로 몇 번 깨우는지 — 순수 계산이라 테스트로 잠근다.
    /// 꺼져 있으면 1(한 번 그리고 끝), 켜져 있으면 요청한 만큼.
    func firstEntries(_ count: Int, from startDate: Date) -> [Date] {
        var found: [Date] = []
        let iterator = entries(from: startDate, mode: .normal)
        while found.count < count, let date = iterator.next() { found.append(date) }
        return found
    }
}
