import SwiftUI

/// 홈의 부화 슬롯 줄. 알은 종을 숨긴 채 남은 시간만 보여준다 — 무엇이 나올지는 깨야 안다.
struct EggSlotsView: View {
    let store: PlayerStore
    /// 1초 틱 — 남은 시간이 살아 움직이게. 호출부(PopoverView)가 이 뷰만 `TimelineView` 로
    /// 감싸 넘긴다 — 홈 탭 전체를 매초 다시 그리지 않기 위해서다.
    let now: Date

    private var l: L { store.l }

    /// 남은 시간 표기. 단위는 큰 것 두 개까지만 — "1일 1시간", "3시간 12분", "1분 30초".
    nonisolated static func countdownText(_ remaining: TimeInterval, _ lang: AppLanguage) -> String {
        let l = L(lang)
        let s = Int(remaining)
        guard s > 0 else { return l.eggHatchingNow }
        let days = s / 86_400, hours = (s % 86_400) / 3600
        let minutes = (s % 3600) / 60, seconds = s % 60
        if days > 0 { return l.eggCountdownDaysHours(days, hours) }
        if hours > 0 { return l.eggCountdownHoursMinutes(hours, minutes) }
        if minutes > 0 { return l.eggCountdownMinutesSeconds(minutes, seconds) }
        return l.eggCountdownSeconds(seconds)
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
            HStack(spacing: 6) {
                ForEach(store.state.eggs) { egg in
                    slot(egg)
                }
                ForEach(0..<max(0, store.state.slots - store.state.eggs.count), id: \.self) { _ in
                    emptySlot
                }
            }
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
        .frame(width: 52, height: 52)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .frame(width: 52, height: 52)
    }
}
