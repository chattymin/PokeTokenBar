import XCTest
import SwiftUI
@testable import PokeTokenBar

// Provider-stacked daily trend bars (`DailyTrendStack` → `MonthDailyTrend`).
//
// Two contracts matter: the stacked split must add up to the same bar height the single-color
// row would draw, and a month with one provider must render exactly as before — stacking is
// only ever additive for multi-provider users.

final class DailyTrendStackTests: XCTestCase {

    private func days(_ values: [(String, Int)], cost: Double = 0) -> [DailyUsage] {
        values.map { DailyUsage(date: $0.0, inputTokens: 0, outputTokens: $0.1,
                                cacheCreationTokens: 0, cacheReadTokens: 0,
                                totalTokens: $0.1, totalCost: cost) }
    }

    private func provider(_ id: String, _ values: [(String, Int)],
                          reportsCost: Bool = true) -> DailyTrendStack.ProviderSeries {
        DailyTrendStack.ProviderSeries(id: id, name: id, days: days(values), reportsCost: reportsCost)
    }

    // MARK: 순서 — 이번 달 합계 큰 순, 0 은 제외

    func testOrderIsByMonthTotalWithUnusedProvidersDroppedAndTiesBrokenById() {
        let ordered = DailyTrendStack.ordered([
            provider("small", [("2026-08-01", 10), ("2026-08-02", 3)]),
            provider("idle", [("2026-08-01", 0), ("2026-08-02", 0)]),
            provider("big", [("2026-08-01", 1), ("2026-08-02", 900)]),
            provider("tie-b", [("2026-08-01", 15)]),
            provider("tie-a", [("2026-08-02", 15)]),
        ])
        XCTAssertEqual(ordered.map(\.id), ["big", "tie-a", "tie-b", "small"],
                       "월 합계 내림차순, 동률은 id — 0 토큰 프로바이더는 스택에 없다")
    }

    // MARK: 단색 경로 — 프로바이더 1개 이하

    /// 시리즈를 넘기는 프로바이더가 둘이어도 **이번 달에 쓴** 게 하나면 쌓지 않는다.
    func testStackingNeedsTwoProvidersThatActuallyUsedSomethingThisMonth() {
        XCTAssertFalse(DailyTrendStack.isStacked(DailyTrendStack.ordered([])))
        XCTAssertFalse(DailyTrendStack.isStacked(DailyTrendStack.ordered([
            provider("a", [("2026-08-01", 10)]),
        ])))
        XCTAssertFalse(DailyTrendStack.isStacked(DailyTrendStack.ordered([
            provider("a", [("2026-08-01", 10)]),
            provider("b", [("2026-08-01", 0)]),
        ])), "0 토큰 프로바이더는 쌓기 판정에 세지 않는다")
        XCTAssertTrue(DailyTrendStack.isStacked(DailyTrendStack.ordered([
            provider("a", [("2026-08-01", 10)]),
            provider("b", [("2026-08-02", 1)]),
        ])))
    }

    /// 프로바이더 1개 월은 **이전과 픽셀 단위로 같다** — `providers:` 를 안 넘긴 뷰와 비트맵을 비교한다.
    /// 높이만 비교하면 색(오늘 accent → 팔레트)이 바뀌어도 통과하므로 실제로 그려서 본다.
    @MainActor
    func testASingleProviderMonthRendersPixelIdenticalToTheUnstackedRow() throws {
        let values = (1...24).map { (String(format: "2026-08-%02d", $0), $0 * 1_000) }
        let series = days(values, cost: 0.3)
        let one = [DailyTrendStack.ProviderSeries(id: "only", name: "Only", days: series,
                                                  reportsCost: true)]
        let idle = DailyTrendStack.ProviderSeries(id: "idle", name: "Idle",
                                                  days: days(values.map { ($0.0, 0) }),
                                                  reportsCost: true)

        let before = try pixels(MonthDailyTrend(series: series, showsCost: true,
                                                today: "2026-08-24", l: L(.en)))
        let single = try pixels(MonthDailyTrend(series: series, providers: one,
                                                providerOrder: ["only", "idle"], showsCost: true,
                                                today: "2026-08-24", l: L(.en)))
        let withIdle = try pixels(MonthDailyTrend(series: series, providers: one + [idle],
                                                  providerOrder: ["only", "idle"], showsCost: true,
                                                  today: "2026-08-24", l: L(.en)))
        XCTAssertEqual(single, before, "프로바이더 1개인데 추이 행이 달라졌다")
        XCTAssertEqual(withIdle, before, "이번 달 0 토큰 프로바이더가 쌓기를 켰다")
    }

    // MARK: 구간 높이

    /// 구간 합 == 막대 높이. 각 구간을 독립적으로 비율 계산하면 부동소수 오차가 쌓여 단색 막대와
    /// 높이가 어긋난다 — 나누어 떨어지지 않는 값들로 여러 높이에서 확인한다.
    func testSegmentsAddUpExactlyToTheBarHeight() {
        let stack = DailyTrendStack.ordered([
            provider("a", [("d", 333_333)]),
            provider("b", [("d", 222_221)]),
            provider("c", [("d", 7)]),
        ])
        for height in [DailyTrendMetrics.baseline, 1.7, 9.3, 17.77, DailyTrendMetrics.track] {
            let segments = DailyTrendStack.segments(on: "d", stack: stack, barHeight: height)
            XCTAssertEqual(segments.map(\.providerID), ["a", "b", "c"])
            XCTAssertEqual(segments.reduce(0) { $0 + $1.height }, height, "\(height) 에서 합이 어긋났다")
            XCTAssertTrue(segments.allSatisfy { $0.height >= 0 })
        }
        let twoToOne = DailyTrendStack.segments(
            on: "d", stack: DailyTrendStack.ordered([provider("a", [("d", 200)]),
                                                     provider("b", [("d", 100)])]),
            barHeight: 24)
        XCTAssertEqual(twoToOne.map(\.height), [16, 8], "구간 높이는 그날 토큰 비율")
    }

    /// 그날 안 쓴 프로바이더는 구간이 없다(0pt 뷰를 쌓지 않는다). 순서는 **그날이 아니라 이번 달**
    /// 기준이라, 그날 작게 쓴 월간 1위도 맨 아래에 남는다 — 날마다 색 순서가 뒤집히지 않게.
    func testZeroTokenProvidersAreOmittedAndTheMonthLeaderStaysAtTheBottom() {
        let stack = DailyTrendStack.ordered([
            provider("leader", [("2026-08-01", 1_000), ("2026-08-02", 10)]),
            provider("second", [("2026-08-01", 0), ("2026-08-02", 90)]),
        ])
        XCTAssertEqual(DailyTrendStack.segments(on: "2026-08-01", stack: stack, barHeight: 20)
                        .map(\.providerID), ["leader"])
        XCTAssertEqual(DailyTrendStack.segments(on: "2026-08-02", stack: stack, barHeight: 20)
                        .map(\.providerID), ["leader", "second"])
        XCTAssertEqual(DailyTrendStack.segments(on: "2026-08-03", stack: stack, barHeight: 20), [],
                       "아무도 안 쓴 날(또는 시리즈에 없는 날)은 구간이 없다")
    }

    // MARK: 색 — 등록 순서 고정

    /// 사용량 순위가 바뀌어도 색은 그대로다. 순위로 색을 매기면 월중에 한 프로바이더가 다른 걸
    /// 추월하는 순간 두 색이 맞바뀌어, 같은 막대가 다른 서비스로 읽힌다.
    func testColorsFollowRegistrationOrderNotUsageRank() {
        let registry = ["first", "second", "third"]
        let claudeLeads = DailyTrendStack.ordered([
            provider("first", [("d", 900)]), provider("second", [("d", 100)]),
        ])
        let codexLeads = DailyTrendStack.ordered([
            provider("first", [("d", 100)]), provider("second", [("d", 900)]),
        ])
        XCTAssertNotEqual(claudeLeads.map(\.id), codexLeads.map(\.id), "전제: 순위가 실제로 뒤집혔다")

        let a = DailyTrendStack.colorIndices(for: claudeLeads.map(\.id), registry: registry, paletteCount: 8)
        let b = DailyTrendStack.colorIndices(for: codexLeads.map(\.id), registry: registry, paletteCount: 8)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, ["first": 0, "second": 1])

        // 중간 프로바이더가 이번 달 안 써도 나머지 색은 밀리지 않는다.
        XCTAssertEqual(DailyTrendStack.colorIndices(for: ["third", "first"], registry: registry,
                                                    paletteCount: 8),
                       ["first": 0, "third": 2])
    }

    /// 다른 프로바이더가 이번 달 쓰기 시작하거나 멈춰도 기존 프로바이더 색은 그대로다. 화면에 보이는
    /// 집합으로 빈 칸을 골라 주면 새 프로바이더 하나에 기존 색이 밀린다(#348 리뷰).
    func testAProvidersColorDoesNotDependOnWhichOthersAreActive() {
        let registry = (0..<14).map { "p\($0)" }
        let alone = DailyTrendStack.colorIndices(for: ["p8"], registry: registry, paletteCount: 8)
        let withFirst = DailyTrendStack.colorIndices(for: ["p0", "p8"], registry: registry, paletteCount: 8)
        let crowded = DailyTrendStack.colorIndices(for: registry, registry: registry, paletteCount: 8)
        XCTAssertEqual(alone["p8"], 0)
        XCTAssertEqual(withFirst["p8"], 0, "p0 이 활성화돼도 p8 의 색은 그대로 — 겹치면 이름이 가른다")
        XCTAssertEqual(crowded["p8"], 0)
        XCTAssertEqual(crowded["p13"], 5)
        XCTAssertEqual(crowded.count, 14, "팔레트보다 많아도 전부 칸을 받는다")
    }

    /// 등록된 프로바이더는 전부 서로 다른 색이다 — 팔레트가 등록 수보다 작으면 9번째(Copilot)가
    /// 1번째(Claude)와 같은 색이 됐다. 프로바이더를 추가하면 이 테스트가 팔레트 색 추가를 요구한다.
    @MainActor
    func testEveryRegisteredProviderGetsItsOwnColor() {
        let defaults = UserDefaults(suiteName: "DailyTrendStackTests.\(UUID().uuidString)")!
        let registry = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        let slots = DailyTrendStack.colorIndices(for: registry, registry: registry,
                                                 paletteCount: MonthDailyTrend.providerPalette.count)
        XCTAssertEqual(Set(slots.values).count, registry.count,
                       "\(registry.count) providers but \(MonthDailyTrend.providerPalette.count) colors")
    }

    // MARK: Caption readout

    /// Opening the popover shows today's combined total and cost without hovering — the stacked
    /// row keeps the same caption as the single-provider row.
    func testTheCaptionReadsTodaysCombinedTotalAndCost() {
        let total = days([("2026-08-23", 4_000_000), ("2026-08-24", 2_500_000)], cost: 7)
        let l = L(.en)
        let stamp = DailyTrendMetrics.dayStamp("2026-08-24", language: .en)
        XCTAssertEqual(MonthDailyTrend.readout(series: total, today: "2026-08-24", showsCost: true, l: l),
                       "\(stamp) \(TokenFormatter.compact(2_500_000)) \(total[1].usageCost.text(l))")
        XCTAssertEqual(MonthDailyTrend.readout(series: total, today: "2026-08-24", showsCost: false, l: l),
                       "\(stamp) \(TokenFormatter.compact(2_500_000))")
    }

    // MARK: Legend

    /// The legend is its own block under the axis: absent for one provider, and with many providers
    /// and long names it wraps onto more lines instead of overflowing the popover.
    @MainActor
    func testTheLegendWrapsWithinThePopoverWidth() {
        let values = (1...31).map { (String(format: "2026-08-%02d", $0), 888_888_888) }
        func series(_ count: Int) -> [DailyTrendStack.ProviderSeries] {
            (0..<count).map { index in
                DailyTrendStack.ProviderSeries(id: "p\(index)", name: "Provider Name \(index)",
                                               days: days(values, cost: 8_888.88), reportsCost: true)
            }
        }
        let total = days(values.map { ($0.0, $0.1 * 4) }, cost: 8_888.88 * 4)
        func size(_ providers: [DailyTrendStack.ProviderSeries], _ language: AppLanguage) -> CGSize {
            let view = MonthDailyTrend(series: total, providers: providers,
                                       providerOrder: providers.map(\.id), showsCost: true,
                                       today: "2026-08-24", l: L(language))
                .environment(\.locale, language.displayLocale)
            return NSHostingController(rootView: view)
                .sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 600))
        }

        let unstacked = size(series(1), .en).height
        XCTAssertGreaterThan(size(series(2), .en).height, unstacked, "two providers show a legend")
        XCTAssertGreaterThan(size(series(14), .en).height, size(series(2), .en).height,
                             "fourteen long names wrap onto more lines")
        for language in AppLanguage.allCases {
            for count in [2, 8, 14] {
                XCTAssertLessThanOrEqual(size(series(count), language).width,
                                         PopoverMetrics.contentWidth + 0.5,
                                         "\(language) · \(count) providers: the trend overflowed")
            }
        }
    }

    // MARK: Hover tooltip

    func testTheTooltipNamesTheDayTotalAndEachProviderThatUsedIt() throws {
        let claude = DailyTrendStack.ProviderSeries(
            id: "claude_code", name: "Claude Code",
            days: days([("2026-08-23", 3_000_000), ("2026-08-24", 2_000_000)], cost: 5), reportsCost: true)
        let codex = DailyTrendStack.ProviderSeries(
            id: "codex", name: "Codex",
            days: days([("2026-08-23", 1_000_000), ("2026-08-24", 0)], cost: 2), reportsCost: false)
        let total = days([("2026-08-23", 4_000_000), ("2026-08-24", 2_000_000)], cost: 7)
        let stack = DailyTrendStack.ordered([claude, codex])
        let l = L(.en)

        let info = try XCTUnwrap(DailyTrendHover.info(day: "2026-08-23", series: total, stack: stack,
                                                      showsCost: true, l: l))
        XCTAssertEqual(info.stamp, DailyTrendMetrics.dayStamp("2026-08-23", language: .en))
        XCTAssertEqual(info.tokens, TokenFormatter.compact(4_000_000))
        XCTAssertEqual(info.cost, total[0].usageCost.text(l))
        XCTAssertEqual(info.providers.map(\.name), ["Claude Code", "Codex"])
        XCTAssertNotNil(info.providers[0].cost)
        XCTAssertNil(info.providers[1].cost, "a provider that does not bill shows no cost")

        let quiet = try XCTUnwrap(DailyTrendHover.info(day: "2026-08-24", series: total, stack: stack,
                                                       showsCost: false, l: l))
        XCTAssertEqual(quiet.providers.map(\.id), ["claude_code"], "a provider idle that day is left out")
        XCTAssertNil(quiet.cost)
        XCTAssertNil(quiet.providers[0].cost, "no cost anywhere when costs are hidden")
    }

    func testASingleProviderTooltipHasNoSplit() throws {
        let only = provider("claude_code", [("2026-08-24", 1_000)])
        let info = try XCTUnwrap(DailyTrendHover.info(day: "2026-08-24", series: days([("2026-08-24", 1_000)]),
                                                      stack: DailyTrendStack.ordered([only]),
                                                      showsCost: true, l: L(.en)))
        XCTAssertEqual(info.providers, [])
    }

    // MARK: 렌더 헬퍼

    @MainActor
    private func pixels(_ view: MonthDailyTrend) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: PopoverMetrics.contentWidth))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "렌더 실패")
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertGreaterThan(image.height, 0)
        return data
    }
}
