import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

// README 스크린샷 생성기.
//
// 실행:
//   PTB_SCREENSHOTS=1 swift test --filter ScreenshotGeneratorTests
//   (릴리스 버전을 설정 화면 푸터에 찍으려면: PTB_APP_VERSION=2.6.0 을 함께 준다)
//
// 환경변수 없이는 전부 skip 된다 — 평소 `swift test` 는 `assets/` 를 건드리지 않는다.
//
// 왜 이렇게 만드나: 예전 스크린샷은 손으로 쓴 HTML 을 헤드리스 크롬으로 찍은 목업이라, 앱에서
// 사라진 화면(가방 탭·직접 구매 상점)이 README 에 몇 달째 남아 있었다. 여기서는 **앱이 실제로
// 그리는 SwiftUI 뷰**를 그대로 오프스크린 렌더한다(`BoxViewTests`/`FormTests` 의 NSHostingView
// 패턴). 뷰가 바뀌면 다음 실행에서 그림도 같이 바뀌므로 목업처럼 드리프트하지 않는다.
//
// 세이브는 절대 건드리지 않는다 — 임시 파일 URL 로 스토어를 만들고 `#if DEBUG` 시드 헬퍼만 쓴다.
// 스프라이트는 읽기 전용으로 디스크 캐시(`~/Library/Application Support/PokeDexBar/sprites`)에서
// `SpriteView.init` 이 동기 시드하므로 네트워크 없이도 그림이 나온다.
//
// **한 가지 한계 — 도감 실루엣.** `cacheDisplay` 는 뷰의 그리기 경로를 찍는 것이라 SwiftUI 가
// CALayer 필터로 내리는 효과는 담기지 않는다. `.opacity` 는 레이어 alpha 라 그대로 나오지만,
// `NationalDexView` 의 `.brightness(-1)`(못 잡은 종을 검게 만드는 실루엣)은 `CAFilter` 로 붙어
// 빠진다 — 그래서 `screenshot-collection.png` 의 미포획 종은 검은 실루엣이 아니라 55% 로 흐려진
// 컬러로 나온다. 확인한 대안은 전부 더 나빴다: `ImageRenderer`/`.drawingGroup()` 은 필터는 살리지만
// `LazyVGrid` 를 아예 안 그려 격자가 빈 채로 나오고, `CALayer.render(in:)` 은 문서대로 필터를 무시하며,
// `CARenderer`(Metal)는 창 밖 레이어 트리에서 아무것도 그리지 않았다. 창을 실제로 띄워 윈도우 서버로
// 캡처하면 필터까지 나오지만 화면 기록 권한에 묶여 "다시 돌릴 수 있는 생성기"가 못 된다.

/// 라인 조회를 즉답으로 대신한다 — 오프스크린 렌더는 `.task` 를 돌릴 기회가 없어 네트워크 조회가
/// 착지하지 않는다. 진화 후보는 뷰에 `lines:` 로 직접 주입한다.
private struct StubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        ScreenshotFixture.line(baseID: baseSpeciesID)
            ?? EvoLine(baseID: baseSpeciesID,
                       tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 스크린샷에 담을 세이브 픽스처 — "그럴듯한 플레이 중반"의 상태. 값은 전부 여기서만 정한다.
enum ScreenshotFixture {
    /// 기준 시각(2026-01-01 00:00 UTC). 알 카운트다운이 실행할 때마다 달라지지 않게 고정한다.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    /// 박스에 넣을 개체들 — 목록 순서가 곧 화면 순서다(획득 시각을 내림차순으로 배정한다).
    /// 파트너는 진화까지 절반쯤 온 리자드, 그 옆에 임계를 넘긴 피카츄(진화 배지·상세 화면용),
    /// 이로치 하나, 같은 라인의 서로 다른 단계(파이리·리자드·리자몽 / 피카츄·라이츄), 지방 모습 넷.
    static let roster: [(species: Int, path: [Int], grade: Grade, nature: PokemonNature,
                         exp: Int, shiny: Bool, region: Region?)] = [
        (5, [4, 5], .epic, .brave, 380_000_000, false, nil),          // 파트너 — 리자몽까지 63%
        (25, [25], .common, .jolly, 55_000_000, false, nil),          // 임계 초과 → 진화 배지
        (700, [700], .epic, .modest, 90_000_000, true, nil),          // 이로치
        (37, [37], .rare, .timid, 40_000_000, false, .alola),         // 알로라 식스테일
        (52, [52], .common, .naughty, 12_000_000, false, .galar),     // 가라르 나옹
        (26, [25, 26], .common, .hasty, 30_000_000, false, nil),      // 피카츄 라인의 진화형
        (6, [4, 5, 6], .epic, .adamant, 120_000_000, false, nil),     // 파이리 라인의 최종형
        (133, [133], .rare, .calm, 130_000_000, false, nil),          // 임계 초과 → 진화 배지
        (94, [92, 93, 94], .epic, .quiet, 300_000_000, false, nil),
        (143, [143], .rare, .relaxed, 60_000_000, false, nil),
        (215, [215], .rare, .sassy, 25_000_000, false, .hisui),       // 히스이 포푸니
        (448, [447, 448], .epic, .serious, 150_000_000, false, nil),
        (9, [7, 8, 9], .epic, .bold, 200_000_000, false, nil),
        (194, [194], .common, .docile, 8_000_000, false, .paldea),    // 팔데아 우파
        (131, [131], .rare, .gentle, 45_000_000, false, nil),
        (212, [123, 212], .epic, .impish, 90_000_000, false, nil),
        (282, [280, 281, 282], .epic, .mild, 250_000_000, false, nil),
        (384, [384], .legendary, .lonely, 500_000_000, false, nil),
        (150, [150], .legendary, .bashful, 380_000_000, false, nil),
    ]

    /// 진화 라인 — 앱에서는 PokéAPI 가 주지만 스크린샷은 네트워크를 타지 않으므로 필요한 것만 적어 둔다.
    private static let names: [Int: [Int: [String: String]]] = [
        25: [25: ["ko": "피카츄", "en": "Pikachu", "ja": "ピカチュウ"],
             26: ["ko": "라이츄", "en": "Raichu", "ja": "ライチュウ"]],
        133: [133: ["ko": "이브이", "en": "Eevee", "ja": "イーブイ"],
              134: ["ko": "샤미드", "en": "Vaporeon", "ja": "シャワーズ"],
              135: ["ko": "쥬피썬더", "en": "Jolteon", "ja": "サンダース"],
              136: ["ko": "부스터", "en": "Flareon", "ja": "ブースター"]],
        4: [4: ["ko": "파이리", "en": "Charmander", "ja": "ヒトカゲ"],
            5: ["ko": "리자드", "en": "Charmeleon", "ja": "リザード"],
            6: ["ko": "리자몽", "en": "Charizard", "ja": "リザードン"]],
    ]

    private static let trees: [Int: EvoNode] = [
        25: EvoNode(speciesID: 25, children: [EvoNode(speciesID: 26, children: [])]),
        133: EvoNode(speciesID: 133, children: [EvoNode(speciesID: 134, children: []),
                                                EvoNode(speciesID: 135, children: []),
                                                EvoNode(speciesID: 136, children: [])]),
        4: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5,
                                                    children: [EvoNode(speciesID: 6, children: [])])]),
    ]

    static func line(baseID: Int) -> EvoLine? {
        guard let tree = trees[baseID] else { return nil }
        return EvoLine(baseID: baseID, tree: tree, rarity: .common, names: names[baseID] ?? [:])
    }

    static var lines: [Int: EvoLine] {
        trees.keys.reduce(into: [:]) { $0[$1] = line(baseID: $1) }
    }
}

@MainActor
final class ScreenshotGeneratorTests: XCTestCase {
    // MARK: 시드

    /// 시드된 스토어 + 파트너/상세에 쓸 개체 id. 실제 세이브는 절대 열지 않는다(임시 파일).
    private struct Fixture {
        let player: PlayerStore
        let usage: UsageStore
        let updater: UpdateChecker
        /// 상세 화면에 띄울 개체(임계를 넘긴 피카츄).
        let detailID: UUID
    }

    private func makeFixture() -> Fixture {
        let base = ScreenshotFixture.now
        var clock = base
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString).json")
        let player = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7),
                                 now: { clock },
                                 defaults: UserDefaults(suiteName: "ptb-shot-\(UUID().uuidString)")!)

        // 스타터는 실제 경로로 고른다 — 이걸 지나야 팝오버가 스타터 픽커 대신 본 화면을 그린다.
        clock = base.addingTimeInterval(-90 * 86_400)
        player.chooseStarter(speciesID: 4, grade: .epic)
        clock = base

        var detailID: UUID?
        var partnerID: UUID?
        for (index, entry) in ScreenshotFixture.roster.enumerated() {
            var individual = Individual(baseID: entry.path.first ?? entry.species,
                                        speciesID: entry.species, pathIDs: entry.path,
                                        shiny: entry.shiny, nature: entry.nature, exp: entry.exp,
                                        obtainedAt: base.addingTimeInterval(-Double(index) * 3600),
                                        grade: entry.grade)
            individual.region = entry.region
            player.addForTesting(individual)
            if index == 0 { partnerID = individual.id }
            if index == 1 { detailID = individual.id }
        }
        if let partnerID { player.setPartner(partnerID) }

        // 도감은 "꾸준히 모은 중" 정도로 — 실루엣과 잡은 종이 섞여 보여야 도감 화면이 설명된다.
        for id in 1...40 where id % 3 != 0 { player.registerInDex(id) }
        for id in stride(from: 41, through: 300, by: 5) { player.registerInDex(id) }

        // 지갑·슬롯 → 아이템 구매 → 알 뽑기 순. 전부 실제 구매 경로를 지나 값이 어긋나지 않게 한다.
        // 지갑은 마지막 품목(가장 비싼 것)까지 살 수 있게 남긴다 — 전부 회색인 상점은 상점처럼 안 보인다.
        player.seedForTesting(wallet: 15_000_000_000, slots: 4, eggs: 0, at: base)
        // 구매 결과를 확인한다 — 가격이 오르면 조용히 실패해 재고 없는 상점이 찍힌다.
        for item in [ShopItem.expCandy, .expCandy, .expCandy, .shinyCandy, .megaStone, .dynamaxMushroom] {
            XCTAssertTrue(player.buy(item), "\(item) 를 못 샀다 — 시드 지갑이 가격을 못 따라간다")
        }

        // 알은 서로 다른 단계로 — 카운트다운이 슬롯마다 다르게 보여야 한다.
        for (minutesAgo, grade, species) in [(22, Grade.common, 172), (60, .epic, 133), (1_200, .legendary, 384)] {
            clock = base.addingTimeInterval(-Double(minutesAgo) * 60)
            player.startEgg(grade: grade, speciesID: species, shiny: false)
        }
        clock = base

        let usage = UsageStore(providers: [], autoRefresh: false,
                               defaults: UserDefaults(suiteName: "ptb-shot-usage-\(UUID().uuidString)")!)
        return Fixture(player: player, usage: usage,
                       updater: UpdateChecker(currentVersion: AppEnv.appVersion ?? "0"),
                       detailID: detailID!)
    }

    // MARK: 렌더

    /// 팝오버 탭 화면 한 장. 앱에서 탭 뷰가 받는 폭·여백(`PopoverMetrics`)을 그대로 씌운다.
    private func tabChrome<V: View>(_ view: V) -> some View {
        view
            .padding(PopoverMetrics.padding)
            .frame(width: PopoverMetrics.width)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 뷰를 다크 모드로 오프스크린 렌더해 2배 스케일 PNG 바이트를 만든다.
    /// (`bitmapImageRepForCachingDisplay` 는 백킹 스케일을 따라 2x 픽셀 버퍼를 준다.)
    ///
    /// - Parameter fullScroll: 세로 스크롤 영역을 끝까지 훑어 한 장으로 잇는다. 팝오버는 세로가
    ///   좁아(상점 320pt·설정 460pt) 화면이 한 번에 다 안 들어가는데 README 는 전체를 보여줘야 한다.
    ///   스크롤해서 찍은 조각도 전부 같은 실제 뷰다. 목록이 무한히 긴 화면(도감 1025칸)에는 쓰지 않는다.
    private func png<V: View>(_ view: V, fullScroll: Bool = false) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()

        let rep = try fullScroll ? scrolledSnapshot(host) : snapshot(host)
        XCTAssertEqual(CGFloat(rep.pixelsWide) / host.bounds.width, Self.scale,
                       "2배 스케일이 아니다 — 레티나가 아닌 디스플레이에서 돌렸다")
        // 기존 에셋과 같이 픽셀=포인트(72dpi)로 기록한다 — 뷰어가 반쪽 크기로 그리지 않게.
        rep.size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]), "PNG 인코딩 실패")
    }

    private static let scale: CGFloat = 2

    /// 지금 보이는 그대로 한 장.
    private func snapshot(_ host: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                "비트맵 버퍼를 못 만들었다")
        // 스크롤 뒤에는 바뀐 영역만 다시 그려져 나머지가 빈 채로 남는다 — 매번 전체를 무효화한다.
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func firstScrollView(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap(firstScrollView).first
    }

    /// 스크롤 영역을 끝까지 찍어 이어 붙인 한 장. 고정된 머리말·꼬리말은 한 번씩만 들어간다.
    private func scrolledSnapshot(_ host: NSView) throws -> NSBitmapImageRep {
        guard let scroll = firstScrollView(host) else { return try snapshot(host) }
        let clip = scroll.convert(scroll.contentView.frame, to: host)
        let bandHeight = clip.height
        let hostHeight = host.bounds.height

        func capture(at offset: CGFloat) throws -> NSBitmapImageRep {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            return try snapshot(host)
        }

        // SwiftUI 스크롤은 콘텐츠 높이를 AppKit 쪽에 알려주지 않는다(documentView 가 0×0). 대신
        // 콘텐츠를 완전히 지나친 위치를 "빈 밴드" 기준으로 삼아, 그와 같아지는 지점까지 훑는다.
        let blank = try capture(at: 200_000)
        var lastFilled = 0
        var band = 1
        while band < 40 {
            let shot = try capture(at: CGFloat(band) * bandHeight)
            if bandRows(shot, differFrom: blank, clip: clip).isEmpty { break }
            lastFilled = band
            band += 1
        }
        XCTAssertLessThan(band, 40, "스크롤이 끝나지 않는다 — fullScroll 을 쓸 화면이 아니다")

        // 마지막으로 내용이 있던 밴드에서 실제 바닥을 찾아 빈 여백을 잘라낸다.
        let lastShot = try capture(at: CGFloat(lastFilled) * bandHeight)
        let filledRows = bandRows(lastShot, differFrom: blank, clip: clip)
        let bottomInBand = filledRows.last.map { CGFloat($0 + 1) / Self.scale } ?? bandHeight
        let contentHeight = CGFloat(lastFilled) * bandHeight + bottomInBand
        let maxOffset = max(0, contentHeight - bandHeight)

        var offsets = stride(from: CGFloat(0), to: maxOffset, by: bandHeight).map { $0 }
        offsets.append(maxOffset)

        let canvasHeight = clip.minY + contentHeight + (hostHeight - clip.maxY)
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * Self.scale),
            pixelsHigh: Int((canvasHeight * Self.scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "캔버스 생성 실패")
        canvas.size = CGSize(width: host.bounds.width, height: canvasHeight)

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas), "컨텍스트 생성 실패")
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        /// 원본(호스트 좌표, 위에서부터)의 한 구간을 캔버스의 지정 위치(역시 위에서부터)에 그린다.
        func draw(_ rep: NSBitmapImageRep, srcTop: CGFloat, height: CGFloat, dstTop: CGFloat) {
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            image.draw(at: NSPoint(x: 0, y: canvasHeight - dstTop - height),
                       from: NSRect(x: 0, y: hostHeight - srcTop - height,
                                    width: host.bounds.width, height: height),
                       operation: .copy, fraction: 1)
        }

        let first = try capture(at: 0)
        draw(first, srcTop: 0, height: clip.minY, dstTop: 0)                       // 머리말
        for offset in offsets {
            let shot = try capture(at: offset)
            draw(shot, srcTop: clip.minY, height: bandHeight, dstTop: clip.minY + offset)
        }
        let last = try capture(at: maxOffset)
        draw(last, srcTop: clip.maxY, height: hostHeight - clip.maxY,
             dstTop: clip.minY + contentHeight)                                     // 꼬리말

        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    /// 스크롤 밴드 안에서 기준(빈 화면)과 다른 픽셀 줄들의 인덱스(밴드 위에서부터, 픽셀 단위).
    private func bandRows(_ shot: NSBitmapImageRep, differFrom blank: NSBitmapImageRep,
                          clip: NSRect) -> [Int] {
        guard let a = shot.bitmapData, let b = blank.bitmapData,
              shot.bytesPerRow == blank.bytesPerRow else { return [] }
        let bytesPerRow = shot.bytesPerRow
        let top = Int(clip.minY * Self.scale), height = Int(clip.height * Self.scale)
        return (0..<height).filter { row in
            let offset = (top + row) * bytesPerRow
            return memcmp(a + offset, b + offset, bytesPerRow) != 0
        }
    }

    private static let assetsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PokeDexBarTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 저장소 루트
        .appendingPathComponent("assets")

    private func write(_ data: Data, _ name: String) throws {
        let url = Self.assetsDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        print("screenshot: \(name) (\(data.count / 1024) KB)")
    }

    // MARK: 화면들

    /// 언어별로 다시 그리는 화면(상점·설정)의 파일 접미 — `.en` 만 접미가 없다(README 기본).
    private static let languages: [(AppLanguage, String)] = [(.en, ""), (.ko, "-ko"), (.ja, "-ja")]

    private func setLanguage(_ language: AppLanguage, _ fixture: Fixture) {
        fixture.player.setLanguage(language)
        fixture.usage.localizationLanguage = language
    }

    func testGenerateScreenshots() throws {
        guard ProcessInfo.processInfo.environment["PTB_SCREENSHOTS"] == "1" else {
            throw XCTSkip("set PTB_SCREENSHOTS=1 to regenerate assets/ screenshots")
        }
        if let version = ProcessInfo.processInfo.environment["PTB_APP_VERSION"] {
            AppEnv.appVersionOverride = version
        }
        defer { AppEnv.appVersionOverride = nil }

        let fixture = makeFixture()
        setLanguage(.en, fixture)

        // 박스 — 보유 개체 그리드(진화 배지·이로치 테두리·지방 배지).
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in }, selection: .constant(nil)))),
                  "screenshot-box.png")

        // 개체 상세 — 진화·폼(거다이맥스)·사탕 버튼이 한 화면에 나오는 개체를 고른다.
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in },
                                           selection: .constant(fixture.detailID))),
                      fullScroll: true),
                  "screenshot-detail.png")

        // 도감 — 번호순 그리드 + 못 잡은 종 실루엣.
        try write(png(tabChrome(NationalDexView(store: fixture.player))), "screenshot-collection.png")

        for (language, suffix) in Self.languages {
            setLanguage(language, fixture)
            try write(png(tabChrome(ShopTabView(store: fixture.player, provider: StubProvider())),
                          fullScroll: true),
                      "screenshot-shop\(suffix).png")
            try write(png(SettingsView(onClose: { })
                .environment(fixture.usage).environment(fixture.player).environment(fixture.updater)
                .frame(width: PopoverMetrics.width)
                .background(Color(nsColor: .windowBackgroundColor)),
                          fullScroll: true),
                      "settings\(suffix).png")
        }
    }
}
