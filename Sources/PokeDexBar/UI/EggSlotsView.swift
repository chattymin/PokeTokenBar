import SwiftUI

/// 홈의 부화 슬롯 줄. 알은 종을 숨긴 채 남은 시간만 보여준다 — 무엇이 나올지는 깨야 안다.
///
/// 슬롯 폭은 `PopoverMetrics.contentWidth`(332pt)를 넘을 수 있다 — `EggBalance.maxSlots`(6)까지
/// 슬롯을 늘리면 `rowWidth(forSlotCount:)` 가 342pt(= 6×52 + 5×6)를 반환해 6pt 초과한다.
/// `ProviderTabBar`(PopoverView.swift, 프로바이더 탭 줄이 439pt vs 332pt 로 넘쳤을 때와 같은 문제)와
/// 동일하게 가로 `ScrollView` 로 감싸 잘리는 대신 스크롤되게 한다.
struct EggSlotsView: View {
    let store: PlayerStore
    /// 1초 틱 — 남은 시간이 살아 움직이게. 호출부(PopoverView)가 이 뷰만 `TimelineView` 로
    /// 감싸 넘긴다 — 홈 탭 전체를 매초 다시 그리지 않기 위해서다.
    let now: Date

    nonisolated private static let tileSize: CGFloat = 52
    nonisolated private static let tileSpacing: CGFloat = 6

    private var l: L { store.l }

    /// 남은 시간 표기. 단위는 큰 것 두 개까지만 — "1일 1시간", "3시간 12분", "1분 30초".
    /// 올림(`rounded(.up)`) — 잘라내면(`Int(remaining)`) 0.x초가 남았을 때도 0으로 떨어져
    /// 실제로 부화하기 최대 1초 전부터 "부화!"라고 먼저 말해버린다.
    nonisolated static func countdownText(_ remaining: TimeInterval, _ lang: AppLanguage) -> String {
        let l = L(lang)
        let s = Int(remaining.rounded(.up))
        guard s > 0 else { return l.eggHatchingNow }
        let days = s / 86_400, hours = (s % 86_400) / 3600
        let minutes = (s % 3600) / 60, seconds = s % 60
        if days > 0 { return l.eggCountdownDaysHours(days, hours) }
        if hours > 0 { return l.eggCountdownHoursMinutes(hours, minutes) }
        if minutes > 0 { return l.eggCountdownMinutesSeconds(minutes, seconds) }
        return l.eggCountdownSeconds(seconds)
    }

    /// 슬롯 `count`개를 한 줄에 나란히 놓았을 때 필요한 폭. `ScrollView` 없이 이 값이
    /// `PopoverMetrics.contentWidth` 를 넘으면 잘린다 — 타일 크기를 바꿀 때 이 함수와
    /// `slot(_:)`/`emptySlot` 의 프레임이 항상 같은 상수(`tileSize`/`tileSpacing`)를 쓰므로 드리프트 없이 같이 움직인다.
    nonisolated static func rowWidth(forSlotCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tileSize + CGFloat(count - 1) * tileSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.eggSlotsHeader).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.state.eggs.count) / \(store.state.slots)")
                    .font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.tileSpacing) {
                    ForEach(store.state.eggs) { egg in
                        slot(egg)
                    }
                    ForEach(0..<max(0, store.state.slots - store.state.eggs.count), id: \.self) { _ in
                        emptySlot
                    }
                }
            }
            // 슬롯이 적으면(대부분의 사용자) 스크롤·바운스가 생기지 않아 기존과 동일하게 보인다.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func slot(_ egg: Egg) -> some View {
        let remaining = egg.remaining(at: now)
        return VStack(spacing: 2) {
            Text("🥚").font(.system(size: 20))
            Text(Self.countdownText(remaining, store.language))
                .font(.system(size: 8)).monospacedDigit()
                .foregroundStyle(remaining <= 0 ? Color.accentColor : .secondary)
            Text(egg.grade.label(store.language))
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .frame(width: Self.tileSize, height: Self.tileSize)
    }
}
