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
    /// 종 번호 → 진화 라인. 거둔 개체의 **이름**을 보여주려면 필요하다(번호만으로는 무엇이
    /// 나왔는지 와닿지 않는다). 아직 없으면 `onNeedLine` 으로 요청하고 번호로 떨어진다.
    var lines: [Int: EvoLine] = [:]
    var onNeedLine: (Int) -> Void = { _ in }
    /// 방금 거둔 개체 — 연출 중에만 non-nil. 이미 박스에 들어가 있어서 닫아도 잃는 것이 없다.
    @State private var hatched: Individual?

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
            // **툴팁이 아니라 인라인 한 줄이다.** 팝오버 안에서는 `.help` 가 안 뜬다(실사용 확인) —
            // 이 앱의 다른 `.help` 들도 마찬가지라, 안 보이는 곳에 설명을 두면 없는 것과 같다.
            //
            // 감면은 알마다가 아니라 부화 전체에 걸리는 상태라 슬롯이 아니라 줄 아래 한 번 적는다.
            // 이게 없으면 카운트다운만 짧아져서 왜 빨라졌는지 알 길이 없다.
            if let warmer = HatchSpeedup.warmer(in: store.state.box) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 8)).foregroundStyle(.orange)
                    Text(warmedHint).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .task(id: warmer.displayLineID) {
                    // 이름은 네트워크로 오는 값이다 — 없으면 요청해 두고, 오는 대로 문장이 채워진다.
                    if lines[warmer.displayLineID] == nil { onNeedLine(warmer.displayLineID) }
                }
            }
        }
        .onChange(of: now) { _, date in announceRipeEggs(at: date) }
        // 거둔 개체를 한 번 보여준다 — 확인을 누른 보람이 있어야 하고, 이걸 안 보면 무엇이
        // 나왔는지 박스에 들어가서야 알게 된다.
        .overlay {
            if let hatched {
                HatchedRevealView(individual: hatched, store: store,
                                  line: lines[hatched.displayLineID], onNeedLine: onNeedLine) {
                    self.hatched = nil
                }
            }
        }
    }

    /// 카운트다운이 부화 시각을 지나면 그 틱에서 알린다. 이게 없으면 팝오버를 열어 둔 채 시간이
    /// 찬 알이 조용히 "부화!"로만 바뀌고 알림은 다음 사용량 새로고침에야 나간다 — 새로고침을
    /// "수동"으로 둔 사용자(`UsageStore` 의 0초 프리셋)는 타이머가 아예 없어 영영 안 나간다.
    /// 이미 도는 1초 틱에 얹으므로 새 타이머는 없고, 익은 알이 없으면 아무 일도 하지 않는다.
    /// **거두는 건 여기서 하지 않는다** — 그건 사용자가 확인을 눌러야 한다.
    /// 감면을 준 아이의 이름을 넣은 안내. 라인이 아직 없으면 요청하고 일반 문구로 떨어진다 —
    /// 이름이 번호(`#663`)로 나오느니 "어떤 아이 덕"이라고만 말하는 편이 낫다.
    private var warmedHint: String {
        guard let warmer = HatchSpeedup.warmer(in: store.state.box) else { return l.eggWarmedHint }
        guard let name = lines[warmer.displayLineID]?
                .localizedName(warmer.displaySpeciesID, store.language) else {
            return l.eggWarmedHint
        }
        return l.eggWarmedBy(warmer.displayName(speciesName: name, store.language))
    }

    private func announceRipeEggs(at date: Date) {
        guard store.readyEggCount(at: date) > 0 else { return }
        store.announceReadyEggsAndNotify(at: date)
    }

    private func slot(_ egg: Egg) -> some View {
        let remaining = egg.remaining(at: now)
        let ready = remaining <= 0
        return VStack(spacing: 1) {
            EggIcon(grade: egg.grade, size: ready ? 19 : 21, cracked: ready)
            if ready {
                // 확인을 눌러야 개체가 되어 박스로 간다 — 무엇이 나왔는지 못 보고 지나가지 않게.
                Button(l.eggClaim) { claim(egg) }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.accentColor, in: Capsule())
            } else {
                Text(Self.countdownText(remaining, store.language))
                    .font(.system(size: 8)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(egg.grade.label(store.language))
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(ready ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func claim(_ egg: Egg) {
        guard let individual = store.claimHatch(eggID: egg.id, at: now) else { return }
        hatched = individual
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .frame(width: Self.tileSize, height: Self.tileSize)
    }
}
