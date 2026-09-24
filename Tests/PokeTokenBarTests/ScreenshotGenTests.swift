import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 릴리스 에셋 생성기 — **기본적으로 건너뛴다.** 환경변수로 출력 폴더를 주면 그때만 그린다:
///
///     PTB_SCREENSHOT_DIR=assets swift test --filter ScreenshotGenTests
///
/// 왜 테스트 안에 있나: 이 스크린샷은 `gen-settings-screenshots.py`(설정 화면 = HTML 목업)와 달리
/// **프로덕션 SwiftUI 뷰를 그대로 렌더**한다. HTML 로 다시 그리면 목업과 실제 UI 가 조용히 갈라져
/// "스크린샷에는 있는데 앱에는 없는" 상태가 만들어진다 — 실제 뷰를 쓰려면 모듈에 접근할 수 있는
/// 이 자리가 유일하게 새 빌드 타깃이 필요 없는 곳이다.
///
/// 배경·크기는 기존 다크 스크린샷과 맞춰 뒀다(720px 폭 = 팝오버 360pt × 2, 배경 rgb(41,41,42)).
///
/// 함정: `ScrollView` 를 품은 뷰(`ProviderTabBar`)는 `ImageRenderer` 에서 빈 칸으로 나온다 —
/// 스크린샷에 넣지 말 것. 헤더처럼 스크롤 없는 부분만 렌더된다.
///
/// 같은 부류: AppKit 컨트롤을 감싼 뷰(`ProgressView` → `NSProgressIndicator`, 즉 한도 막대)는
/// `ImageRenderer` 에서 "미지원" 플레이스홀더로 그려진다. 그런 뷰를 담으려면
/// `NSWindow` 에 올려 `cacheDisplay(in:to:)` 로 떠야 실제 모습이 나온다
/// (`LimitProgressRenderingTests` 가 그 방식으로 페이스 눈금을 검증한다).
///
/// 다만 **색까지는 재현되지 않는다.** 테스트 프로세스는 앱으로 활성화되지 않아
/// (`NSApp.isActive == false`) AppKit 이 컨트롤을 비강조 스타일로 그린다 — 막대 채움이 tint
/// 대신 회색으로 나온다. 활성화 정책 `.regular`, `NSApp.activate`, key/main 오버라이드,
/// 화면에 띄운 창의 컴포지터 캡처(`CGWindowListCreateImage`)까지 모두 회색이었다.
/// 그래서 이 헬퍼의 출력은 **배치·크기 확인용**이고, 색이 중요한 홍보용 이미지는 실행 중인
/// 앱을 직접 캡처해서 쓴다(`assets/screenshot-quota-alignment.png` 도 그렇게 만들어졌다).
final class ScreenshotGenTests: XCTestCase {

    /// 데모용 한 달치 일별 사용량 — 실제 로그처럼 쉬는 날(0)과 몰아친 날이 섞여야 기능이 읽힌다.
    /// **한 달 전체(31일)를 채운다**: 막대가 가장 좁아지는 조건이고, 날짜 축 라벨(1·7·14·21·28·오늘)이
    /// 다 나오는 것도 그때뿐이라, 21일치로 찍으면 실제로 좁을 때의 모습을 못 보여준다.
    /// 주말(8/1 토 시작)에 낮은 값을 둬서 주말 밑줄 틱이 데이터와 함께 읽히게 했다.
    private static let demoDailyTokens = [
        0, 0, 3_100_000, 4_800_000, 2_050_000, 5_600_000, 1_240_000,
        480_000, 0, 4_100_000, 6_900_000, 3_300_000, 5_100_000, 900_000,
        0, 140_000, 4_400_000, 2_600_000, 6_100_000, 3_900_000, 1_700_000,
        0, 2_200_000, 5_400_000, 4_700_000, 3_050_000, 6_400_000, 2_800_000,
        0, 1_900_000, 5_800_000,
    ]

    @MainActor
    func testGenerateDailyTrendScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_SCREENSHOT_DIR"] else {
            throw XCTSkip("PTB_SCREENSHOT_DIR 미지정 — 에셋 생성은 릴리스 때만 실행한다")
        }
        for (language, suffix) in [(AppLanguage.en, ""), (.ko, "-ko"), (.ja, "-ja")] {
            let data = try render(language: language)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("screenshot-daily-trend\(suffix).png")
            try data.write(to: url)
            print("wrote \(url.path) (\(data.count) bytes)")
        }
    }

    @MainActor
    private func render(language: AppLanguage) throws -> Data {
        let l = L(language)
        // "오늘"은 반드시 시리즈의 **마지막** 날이다 — 프로덕션 시리즈는 오늘에서 끝나므로,
        // 31개 막대에 오늘을 24일로 찍으면 앱이 절대 도달할 수 없는 상태를 문서에 싣는 셈이다
        // (오늘 이후 7일이 그려진 그림). 달이 다 찬 시점 = 오늘이 말일.
        let today = "2026-08-31"
        let series = Self.demoDailyTokens.enumerated().map { index, value in
            DailyUsage(date: String(format: "2026-08-%02d", index + 1),
                       inputTokens: value / 4, outputTokens: value / 4,
                       cacheCreationTokens: value / 4, cacheReadTokens: value / 4,
                       totalTokens: value, totalCost: Double(value) / 1_000_000 * 3.2)
        }
        // 합계는 "오늘"(=강조된 막대)까지로 잘라야 한다 — series.last 로 잡으면 헤더의 오늘 숫자와
        // 리드아웃의 날짜가 어긋난 스크린샷이 나온다(8/24 라고 쓰고 8/31 값을 보여주는 식).
        let todayIndex = try XCTUnwrap(series.firstIndex { $0.date == today })
        let throughToday = series[...todayIndex]
        let monthTotal = throughToday.reduce(0) { $0 + $1.totalTokens }
        let monthCost = throughToday.reduce(0.0) { $0 + $1.totalCost }
        let weekTotal = throughToday.suffix(7).reduce(0) { $0 + $1.totalTokens }
        let weekCost = throughToday.suffix(7).reduce(0.0) { $0 + $1.totalCost }
        let todayUsage = series[todayIndex]

        let content = VStack(alignment: .leading, spacing: 6) {
            Text(l.todayTokens).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(TokenFormatter.compact(todayUsage.totalTokens))
                    .font(.system(size: 28, weight: .bold)).monospacedDigit()
                Text(TokenFormatter.grouped(todayUsage.totalTokens))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(TokenFormatter.cost(todayUsage.totalCost))
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                periodLabel(l.thisWeek, weekTotal, weekCost)
                periodLabel(l.thisMonth, monthTotal, monthCost)
                Spacer()
            }
            .padding(.top, 2)

            MonthDailyTrend(series: series, showsCost: true, today: today, l: l)

        }
        .padding(.horizontal, PopoverMetrics.padding)
        .padding(.vertical, 16)
        .frame(width: PopoverMetrics.width, alignment: .leading)
        .background(Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, language.displayLocale)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: 페이스 눈금

    /// 눈금 하나로 읽히게 두 행만 쓴다 — 설명 문구·화살표를 얹지 않는다.
    /// 5시간은 눈금 바로 앞(페이스대로), 주간은 눈금을 크게 넘어섬(빠름). 두 행의 대비가 곧 설명이다.
    @MainActor
    func testGeneratePaceMarkerScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_SCREENSHOT_DIR"] else {
            throw XCTSkip("PTB_SCREENSHOT_DIR 미지정 — 에셋 생성은 릴리스 때만 실행한다")
        }
        for (language, suffix) in [(AppLanguage.en, ""), (.ko, "-ko"), (.ja, "-ja")] {
            let data = try renderPaceMarker(language: language)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("screenshot-pace-marker\(suffix).png")
            try data.write(to: url)
            print("wrote \(url.path) (\(data.count) bytes)")
        }
    }

    @MainActor
    private func renderPaceMarker(language: AppLanguage) throws -> Data {
        let l = L(language)
        let suite = "PaceShot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)

        /// PopoverView.quotaRow 와 같은 구성 — 그 함수는 private 이라 여기서 형태만 맞춘다.
        /// 리셋 라벨이 퍼센트 **앞**에 온다(후행 정렬, #292). 순서가 어긋나면 스크린샷이
        /// 실제 UI 와 갈라지므로 quotaRow 를 고칠 때 여기도 같이 본다.
        func row(_ name: String, used: Double, resetIn: TimeInterval, pace: Double) -> some View {
            let reset = Date().addingTimeInterval(resetIn)
            let formatter = DateFormatter()
            formatter.locale = language.displayLocale
            formatter.setLocalizedDateFormatFromTemplate(resetIn <= 6 * 3600 ? "HHmm" : "EEEEdHHmm")
            return VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).font(.callout)
                    Spacer()
                    (Text("\(reset, style: .relative)") + Text(" (\(formatter.string(from: reset)))"))
                        .font(.caption).foregroundStyle(.tertiary)
                    Text(TokenFormatter.percent(used))
                        .font(.callout).monospacedDigit().foregroundStyle(Color.green)
                }
                LimitProgressBar(usedPercent: used, tint: .green, pace: pace)
            }
        }

        let content = VStack(alignment: .leading, spacing: 8) {
            Text(l.limitsOfficial).font(.caption).foregroundStyle(.secondary)
            row(l.fiveHourSession, used: 62, resetIn: 2 * 3600, pace: 0.6)
            row(l.weekly, used: 78, resetIn: 3 * 24 * 3600, pace: 4.0 / 7.0)
        }
        .environment(store)
        .padding(.horizontal, PopoverMetrics.padding)
        .padding(.vertical, 16)
        .frame(width: PopoverMetrics.width, alignment: .leading)
        .background(Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, language.displayLocale)

        // ImageRenderer 로는 막대가 플레이스홀더로 나온다(파일 상단 함정 참조) → 창에 올려 캡처.
        let host = NSHostingController(rootView: content)
        host.view.setFrameSize(NSSize(width: PopoverMetrics.width, height: host.view.fittingSize.height))
        let window = NSWindow(contentRect: host.view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host.view
        host.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // 기존 에셋과 같은 2배 해상도(720px 폭). rep 의 픽셀 크기는 2배, 논리 크기는 pt 로 둔다.
        let bounds = host.view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width) * 2, pixelsHigh: Int(bounds.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.view.cacheDisplay(in: bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    @MainActor
    private func periodLabel(_ name: String, _ tokens: Int, _ cost: Double) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(tokens)).font(.caption.weight(.semibold)).monospacedDigit()
            Text(TokenFormatter.cost(cost)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
