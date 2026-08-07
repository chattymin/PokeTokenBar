import AppKit
import XCTest
@testable import PokeDexBar

/// 위장의 순수 규칙.
final class DittoDisguiseRuleTests: XCTestCase {
    /// 커먼에서만, 1/128 로. 등급을 안 보면 레전더리 알에서도 메타몽이 나온다.
    func testOnlyCommonEggsHide() {
        XCTAssertTrue(DittoDisguise.hits(grade: .common, roll: 0))
        for grade in [Grade.rare, .epic, .legendary] {
            XCTAssertFalse(DittoDisguise.hits(grade: grade, roll: 0), "\(grade) 에서도 나온다")
        }
    }

    /// 확률이 선언한 분모와 실제로 맞나 — 경계 바로 안쪽은 걸리고 바깥은 안 걸려야 한다.
    func testTheOddsMatchTheStatedDenominator() {
        let threshold = 1.0 / Double(DittoDisguise.denominator)
        XCTAssertTrue(DittoDisguise.hits(grade: .common, roll: threshold - 0.000_001))
        XCTAssertFalse(DittoDisguise.hits(grade: .common, roll: threshold))
        // 균등 난수를 통째로 훑어 실제 적중률이 1/128 근처인지 본다.
        let trials = 128_000
        let hits = (0..<trials).count {
            DittoDisguise.hits(grade: .common, roll: Double($0) / Double(trials))
        }
        XCTAssertEqual(Double(hits) / Double(trials), threshold, accuracy: 0.001)
    }

    /// 10분. 경계를 정확히 잠근다 — 이 값이 조용히 바뀌면 이스터에그의 리듬이 달라진다.
    func testTheDisguiseHoldsUntilTenMinutes() {
        XCTAssertEqual(DittoDisguise.revealSeconds, 600)
        XCTAssertFalse(DittoDisguise.isReady(partnerSeconds: 599))
        XCTAssertTrue(DittoDisguise.isReady(partnerSeconds: 600))
    }
}

@MainActor
final class DittoDisguiseStoreTests: XCTestCase {
    private func makeStore(now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) }) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ditto-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: now,
                           defaults: UserDefaults(suiteName: "ptb-ditto-\(UUID().uuidString)")!)
    }

    /// 알에 메타몽이 들어 있으면 뮤의 모습으로 거둬진다 — 정체는 그대로 메타몽이다.
    func testADittoEggHatchesWearingMew() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 0)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now.addingTimeInterval(86_400)))

        XCTAssertEqual(hatched.speciesID, DittoDisguise.speciesID, "정체가 메타몽이 아니다")
        XCTAssertEqual(hatched.disguisedAs, DittoDisguise.disguisedAs)
        XCTAssertEqual(hatched.displaySpeciesID, DittoDisguise.disguisedAs, "화면에 메타몽이 그대로 보인다")
        XCTAssertEqual(hatched.spriteForm, DittoDisguise.formSlug)
    }

    /// **위장 중엔 도감에 안 들어간다.** 들어가면 정체가 도감에서 먼저 새어 연출이 통째로 무의미해진다.
    func testTheDexStaysQuietWhileDisguised() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 0)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        _ = store.claimHatch(eggID: egg.id, at: now.addingTimeInterval(86_400))

        XCTAssertFalse(store.state.dex.contains(DittoDisguise.speciesID), "메타몽이 도감에 새어 나갔다")
        XCTAssertFalse(store.state.dex.contains(DittoDisguise.disguisedAs), "잡지도 않은 뮤가 도감에 있다")
    }

    /// 보통 알은 예전 그대로 도감에 들어간다 — 위 규칙이 모든 부화를 막아 버리면 안 된다.
    func testOrdinaryHatchesStillReachTheDex() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 0)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        let egg = try XCTUnwrap(store.startEgg(grade: .common, speciesID: 25, shiny: false))
        _ = store.claimHatch(eggID: egg.id, at: now.addingTimeInterval(86_400))
        XCTAssertTrue(store.state.dex.contains(25))
    }

    /// 파트너로 10분을 지내면 정체가 드러난다 — 그리고 그때 도감에 들어간다.
    func testTenMinutesAsPartnerDropsTheDisguise() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        clock = clock.addingTimeInterval(86_400)
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: clock))
        store.setPartner(hatched.id)

        // 9분 59초 — 아직이다.
        XCTAssertTrue(store.revealDisguises(at: clock.addingTimeInterval(599)).isEmpty)
        XCTAssertNotNil(store.state.box.first { $0.id == hatched.id }?.disguisedAs)

        let revealed = store.revealDisguises(at: clock.addingTimeInterval(600))
        XCTAssertEqual(revealed.count, 1)
        XCTAssertNil(store.state.box.first { $0.id == hatched.id }?.disguisedAs, "위장이 안 풀렸다")
        XCTAssertTrue(store.state.dex.contains(DittoDisguise.speciesID), "정체가 도감에 안 들어갔다")
    }

    /// **파트너가 아니면 시간이 안 흐른다.** 박스에 넣어 두기만 해도 풀리면 "곁에 두어야 드러난다"가
    /// 성립하지 않는다 — 이 이스터에그의 조건 그 자체다.
    func testSittingInTheBoxNeverRevealsIt() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        clock = clock.addingTimeInterval(86_400)
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: clock))
        // 파트너로 지정하지 않는다.
        XCTAssertTrue(store.revealDisguises(at: clock.addingTimeInterval(86_400)).isEmpty,
                      "박스에 두기만 했는데 하루 만에 풀렸다")
    }

    /// 한 번 풀리면 다시 안 걸린다 — 여러 곳에서 불리므로(사용량 틱·팝오버·1초 틱) 두 번
    /// 알리거나 도감을 두 번 건드리면 안 된다.
    func testRevealingTwiceReportsNothingTheSecondTime() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        clock = clock.addingTimeInterval(86_400)
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: clock))
        store.setPartner(hatched.id)
        let at = clock.addingTimeInterval(600)
        XCTAssertEqual(store.revealDisguises(at: at).count, 1)
        XCTAssertTrue(store.revealDisguises(at: at).isEmpty, "같은 개체가 두 번 공개됐다")
    }

    /// 위장 중엔 이로치를 숨긴다. 티가 나면 위장이 아니다 — 정체가 드러난 뒤에 공개된다.
    func testShininessHidesBehindTheDisguise() {
        var individual = Individual(baseID: DittoDisguise.speciesID, speciesID: DittoDisguise.speciesID,
                                    pathIDs: [DittoDisguise.speciesID], shiny: true, nature: .modest,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        individual.disguisedAs = DittoDisguise.disguisedAs
        XCTAssertFalse(individual.showsShiny, "위장 중인데 ✨ 가 보인다")
        XCTAssertTrue(individual.shiny, "이로치라는 사실 자체는 남아 있어야 한다")

        individual.disguisedAs = nil
        XCTAssertTrue(individual.showsShiny, "정체가 드러났는데도 이로치가 안 보인다")
    }

    /// 이름은 **위장한 종의 라인**에서 찾아야 한다. 정체의 라인엔 뮤의 이름이 없어 "#151" 로 떨어진다.
    func testTheNameComesFromTheDisguisedSpeciesLine() {
        var individual = Individual(baseID: DittoDisguise.speciesID, speciesID: DittoDisguise.speciesID,
                                    pathIDs: [DittoDisguise.speciesID], nature: .modest,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        individual.disguisedAs = DittoDisguise.disguisedAs
        XCTAssertEqual(individual.displayLineID, DittoDisguise.disguisedAs)
        individual.disguisedAs = nil
        XCTAssertEqual(individual.displayLineID, DittoDisguise.speciesID)
    }

    /// 메뉴바·플로팅 펫도 위장을 따라간다 — 팝오버만 고치면 상태아이템에서 정체가 샌다.
    func testTheMenuBarWearsTheDisguiseToo() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: true))
        clock = clock.addingTimeInterval(86_400)
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: clock))
        store.setPartner(hatched.id)

        XCTAssertEqual(store.displayedSpeciesID, DittoDisguise.disguisedAs)
        XCTAssertEqual(store.displayedForm, DittoDisguise.formSlug)
        XCTAssertFalse(store.displayedIsShiny, "메뉴바에서 이로치가 새어 나갔다")

        _ = store.revealDisguises(at: clock.addingTimeInterval(600))
        XCTAssertEqual(store.displayedSpeciesID, DittoDisguise.speciesID)
        XCTAssertTrue(store.displayedIsShiny)
    }

    /// 위장 상태가 세이브를 건너 살아남나 — 필드를 더할 때마다 이 저장소가 밟아 온 부류다.
    func testTheDisguiseSurvivesASaveRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ditto-save-\(UUID().uuidString).json")
        let now = Date(timeIntervalSince1970: 0)
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { now },
                                defaults: UserDefaults(suiteName: "ptb-ditto-\(UUID().uuidString)")!)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        let egg = try XCTUnwrap(store.startEgg(grade: .common,
                                               speciesID: DittoDisguise.speciesID, shiny: false))
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now.addingTimeInterval(86_400)))

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { now },
                                   defaults: UserDefaults(suiteName: "ptb-ditto-\(UUID().uuidString)")!)
        XCTAssertEqual(reloaded.state.box.first { $0.id == hatched.id }?.disguisedAs,
                       DittoDisguise.disguisedAs, "다시 켜니 위장이 풀려 있다")
    }
}

/// 위장 그림 — 뮤의 눈을 지우고 메타몽의 눈·입을 얹는다.
final class DittoDisguiseSpriteTests: XCTestCase {
    /// 뮤의 얼굴을 흉내 낸 최소 픽스처: 살색 바탕 + **얼굴 선** + 파란 눈 둘.
    /// 실제 뮤 스프라이트는 네트워크라 테스트가 못 쓴다.
    ///
    /// - Parameter line: 얼굴 선 색. 그린 얼굴이 이 색을 쓰는지 확인하는 데 쓴다.
    private func face(line: (r: Int, g: Int, b: Int) = (98, 80, 87)) -> CGImage {
        let (w, h) = (28, 28)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 254/255.0, green: 213/255.0, blue: 229/255.0, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 20, height: 20))          // 살색 얼굴
        // 얼굴 선 — 눈 위에 눈꺼풀처럼. 실루엣이 아니라 안쪽 선이어야 표본이 된다.
        context.setFillColor(CGColor(red: Double(line.r)/255, green: Double(line.g)/255,
                                     blue: Double(line.b)/255, alpha: 1))
        context.fill(CGRect(x: 8, y: 19, width: 3, height: 1))
        context.fill(CGRect(x: 17, y: 19, width: 3, height: 1))
        context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 8, y: 16, width: 3, height: 2))           // 왼눈
        context.fill(CGRect(x: 17, y: 16, width: 3, height: 2))          // 오른눈
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage, where matches: (Int, Int, Int, Int) -> Bool) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let bytes = rep.bitmapData else { return 0 }
        let bpp = rep.bitsPerPixel / 8
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let o = y * rep.bytesPerRow + x * bpp
                if matches(Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]),
                           bpp > 3 ? Int(bytes[o + 3]) : 255) { count += 1 }
            }
        }
        return count
    }

    /// 파란 눈이 사라지고 어두운 얼굴이 생긴다 — 위장의 전부가 이것이다.
    func testTheBlueEyesBecomeADittoFace() throws {
        let before = face()
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before))
        let blue = { (r: Int, g: Int, b: Int, a: Int) in a > 128 && b > r + 25 && b > g + 10 }
        let dark = { (r: Int, g: Int, b: Int, a: Int) in a > 128 && r < 150 && g < 150 && b < 170 }
        XCTAssertGreaterThan(pixels(before, where: blue), 0, "픽스처에 파란 눈이 없다")
        XCTAssertEqual(pixels(after, where: blue), 0, "뮤의 파란 눈이 남아 있다")
        XCTAssertGreaterThan(pixels(after, where: dark), pixels(before, where: dark),
                             "메타몽의 눈·입이 안 생겼다")
    }

    /// **선 색은 뮤에게서 빌린다.** 순수한 검정으로 그리면 얹은 티가 나고, 스프라이트마다 선 색이
    /// 다르다(움직이는 쪽 (98,80,87) · 정적 쪽 (90,41,82) — 실측). 그림이 쓰는 색을 그대로 써야 한다.
    ///
    /// **기대 색은 그림에서 읽는다.** 그릴 때 지정한 값과 비교하면 안 된다 — `NSBitmapImageRep` 가
    /// 색공간을 옮기면서 값이 달라진다(실측: (98,80,87) 로 그린 픽셀이 (118,99,106) 으로 읽혔다).
    /// 확인하려는 건 "내가 적은 숫자"가 아니라 "그림이 실제로 쓰는 선 색"이다.
    func testTheFaceIsDrawnInMewsOwnLineColor() throws {
        for line in [(r: 98, g: 80, b: 87), (r: 90, g: 41, b: 82)] {
            let before = face(line: line)
            // 픽스처에서 가장 많이 쓰인 어두운 색 = 그 그림의 얼굴 선.
            var tally: [[Int]: Int] = [:]
            forEachPixel(before) { r, g, b, a in
                if a > 128, r < 150, g < 150, b < 170 { tally[[r, g, b], default: 0] += 1 }
            }
            let expected = try XCTUnwrap(tally.max { $0.value < $1.value }?.key, "픽스처에 선이 없다")

            let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before))
            let drawn = pixels(after) { r, g, b, a in a > 128 && [r, g, b] == expected }
            let black = pixels(after) { r, g, b, a in a > 128 && r < 60 && g < 60 && b < 60 }
            XCTAssertGreaterThan(drawn, pixels(before) { r, g, b, a in a > 128 && [r, g, b] == expected },
                                 "얼굴이 그림의 선 색(\(expected))으로 안 그려졌다")
            XCTAssertEqual(black, 0, "순수 검정으로 그렸다 — 뮤의 선 색을 안 썼다")
        }
    }

    private func forEachPixel(_ image: CGImage, _ body: (Int, Int, Int, Int) -> Void) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let bytes = rep.bitmapData else { return }
        let bpp = rep.bitsPerPixel / 8
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let o = y * rep.bytesPerRow + x * bpp
                body(Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]),
                     bpp > 3 ? Int(bytes[o + 3]) : 255)
            }
        }
    }

    /// 입은 눈보다 넓어야 한다 — 메타몽 얼굴을 메타몽으로 읽히게 하는 건 그 폭이다.
    func testTheMouthIsWiderThanAnEye() {
        let cells = DittoDisguiseSprite.mouthCells(x: 10, y: 10)
        let span = cells.map(\.x).max()! - cells.map(\.x).min()! + 1
        XCTAssertGreaterThanOrEqual(span, 6, "입이 좁아 점 몇 개로 보인다: \(span)픽셀")
        // 두 줄로 층지게 — 한 줄짜리 직선은 메타몽이 아니라 그냥 선이다.
        XCTAssertEqual(Set(cells.map(\.y)).count, 2)
    }

    /// **실루엣은 그대로다.** 눈이 몸의 외곽선에 닿아 있어, 지우는 범위를 잘못 잡으면
    /// 머리에 구멍이 뚫린다 — 실제로 처음 짤 때 밟은 결함이다.
    func testTheBodyKeepsItsShape() throws {
        let before = face()
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before))
        let opaque = { (_: Int, _: Int, _: Int, a: Int) in a > 128 }
        XCTAssertEqual(pixels(after, where: opaque), pixels(before, where: opaque),
                       "불투명 픽셀 수가 달라졌다 — 몸에 구멍이 뚫렸거나 넘쳤다")
    }

    /// 눈이 없으면(눈 감은 프레임) 손대지 않는다. 위조할 것이 없을 때 억지로 그리면 얼굴이 망가진다.
    func testAFaceWithNoEyesIsLeftAlone() {
        let (w, h) = (8, 8)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.84, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertNil(DittoDisguiseSprite.disguise(context.makeImage()!))
    }
}

/// 관대 디코딩의 짝 — 말이 안 되는 위장 값은 경계에서 버린다.
final class DittoDisguiseSanitizeTests: XCTestCase {
    private func make(speciesID: Int, disguisedAs: Int?) -> Individual {
        var individual = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                                    nature: .modest, obtainedAt: Date(timeIntervalSince1970: 0),
                                    grade: .common)
        individual.disguisedAs = disguisedAs
        return individual
    }

    /// 제대로 된 위장은 살아남는다.
    func testTheRealDisguiseSurvives() {
        XCTAssertEqual(make(speciesID: DittoDisguise.speciesID,
                            disguisedAs: DittoDisguise.disguisedAs).sanitized().disguisedAs,
                       DittoDisguise.disguisedAs)
    }

    /// 메타몽이 아닌데 위장 중이라고 적혀 있으면 버린다 — 피카츄가 뮤로 보이면 안 된다.
    func testOnlyDittoCanWearIt() {
        XCTAssertNil(make(speciesID: 25, disguisedAs: DittoDisguise.disguisedAs).sanitized().disguisedAs)
    }

    /// 뮤가 아닌 것으로 위장했다고 적혀 있으면 버린다 — 만들 줄 모르는 그림을 영영 요청하게 된다.
    func testOnlyMewCanBeWorn() {
        XCTAssertNil(make(speciesID: DittoDisguise.speciesID, disguisedAs: 9999).sanitized().disguisedAs)
    }
}

/// 개발 시드 — 이 이스터에그를 눈으로 확인하려면 1/128 과 10분이 필요해서 있다.
@MainActor
final class DittoDevSeedTests: XCTestCase {
    private func makeStore(now: @escaping () -> Date) -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("ditto-seed-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 5), now: now,
                    defaults: UserDefaults(suiteName: "ptb-ditto-seed-\(UUID().uuidString)")!)
    }

    /// 위장한 메타몽이 **파트너로** 들어가고, 그 순간부터 시계가 돈다.
    ///
    /// 시계가 도는지를 반드시 확인한다 — `partnerID` 를 직접 넣으면 `setPartner` 가 조기 반환해
    /// `partnerSince` 가 비고, 박스에는 있는데 10분이 영영 안 차는 상태가 된다(실제로 그렇게 짰다가
    /// 여기서 잡혔다).
    func testTheSeedMakesItThePartnerWithARunningClock() {
        var clock = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { clock })
        store.seedDisguisedDittoIfRequested(["PTB_SEED_DITTO": "1"])

        let ditto = store.state.partner
        XCTAssertEqual(ditto?.speciesID, DittoDisguise.speciesID)
        XCTAssertEqual(ditto?.disguisedAs, DittoDisguise.disguisedAs)
        XCTAssertNotNil(ditto?.partnerSince, "동행 시계가 안 돈다 — 위장이 영영 안 풀린다")

        clock = clock.addingTimeInterval(600)
        XCTAssertEqual(store.revealDisguises(at: clock).count, 1, "10분이 지나도 안 풀렸다")
    }

    /// 숫자를 주면 그만큼 이미 함께한 상태로 시작한다 — 다만 문턱은 못 넘는다.
    /// 넘기면 기동하자마자 풀려 정작 위장한 모습을 못 본다.
    func testTheSeedCanStartPartwayButNeverPastTheThreshold() {
        let now = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { now })
        store.seedDisguisedDittoIfRequested(["PTB_SEED_DITTO": "570"])
        XCTAssertEqual(store.state.partner?.partnerSeconds, 570)

        let overshoot = makeStore(now: { now })
        overshoot.seedDisguisedDittoIfRequested(["PTB_SEED_DITTO": "99999"])
        XCTAssertEqual(overshoot.state.partner?.partnerSeconds, DittoDisguise.revealSeconds - 1)
        XCTAssertTrue(overshoot.revealDisguises(at: now).isEmpty, "기동하자마자 풀렸다")
    }

    /// 변수가 없으면 아무 일도 없다. 개발 빌드를 그냥 켰을 때 박스에 메타몽이 쌓이면 안 된다.
    func testWithoutTheVariableNothingHappens() {
        let now = Date(timeIntervalSince1970: 0)
        for environment in [[:], ["PTB_SEED_DITTO": "0"], ["PTB_SEED_DITTO": ""]] as [[String: String]] {
            let store = makeStore(now: { now })
            store.seedDisguisedDittoIfRequested(environment)
            XCTAssertTrue(store.state.box.isEmpty, "\(environment) 에서 개체가 생겼다")
        }
    }

    /// 두 번 켜도 하나만 — 켤 때마다 늘어나면 박스가 찬다.
    func testSeedingTwiceKeepsOne() {
        let now = Date(timeIntervalSince1970: 0)
        let store = makeStore(now: { now })
        store.seedDisguisedDittoIfRequested(["PTB_SEED_DITTO": "1"])
        store.seedDisguisedDittoIfRequested(["PTB_SEED_DITTO": "1"])
        XCTAssertEqual(store.state.box.count { $0.disguisedAs != nil }, 1)
    }
}

/// 눈을 몇 개로 볼 것인가 — 가운데로 자르면 한쪽 눈만 보이는 그림이 망가진다.
final class DittoEyeSplitTests: XCTestCase {
    private func points(_ xs: [Int]) -> [DittoDisguiseSprite.Point] {
        xs.map { DittoDisguiseSprite.Point(x: $0, y: 10) }
    }

    /// 멀리 떨어진 두 무리는 두 눈이다(움직이는 스프라이트: 왼눈 14~16, 오른눈 23~26).
    func testTwoSeparatedClustersAreTwoEyes() {
        let split = DittoDisguiseSprite.splitEyes(points([14, 15, 16, 23, 24, 25, 26]))
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].map(\.x).sorted(), [14, 15, 16])
        XCTAssertEqual(split[1].map(\.x).sorted(), [23, 24, 25, 26])
    }

    /// **붙어 있으면 눈 하나다.** 정적 스프라이트가 이 경우이고, 가운데로 자르면 눈 하나에
    /// 점 두 개와 입이 구겨 들어간다.
    func testOneContiguousClusterStaysOneEye() {
        XCTAssertEqual(DittoDisguiseSprite.splitEyes(points([32, 33, 34, 35])).count, 1)
    }

    /// 한 칸 벌어진 정도로는 안 가른다 — 눈동자와 하이라이트 사이가 그렇게 비어 있을 수 있다.
    func testASinglePixelGapIsNotTwoEyes() {
        XCTAssertEqual(DittoDisguiseSprite.splitEyes(points([32, 33, 35, 36])).count, 1)
    }
}
