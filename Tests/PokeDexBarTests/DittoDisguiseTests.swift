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
        _ = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: clock))
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

    /// **위장 중엔 이름을 감춘다.** 위장한 종의 이름을 그대로 쓰면 라인을 못 받아온 화면에서
    /// 번호가 튀어나오고(홈이 "#151" 로 나왔다), 이름을 정확히 대는 것 자체가 정체를 반쯤
    /// 알려 주는 일이다.
    func testTheNameIsHiddenWhileDisguised() {
        var individual = Individual(baseID: DittoDisguise.speciesID, speciesID: DittoDisguise.speciesID,
                                    pathIDs: [DittoDisguise.speciesID], nature: .modest,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        individual.disguisedAs = DittoDisguise.disguisedAs
        XCTAssertEqual(individual.displayName(speciesName: "뮤", .ko), Individual.unknownName)
        // 라인을 못 받아 번호로 떨어진 경우에도 번호가 새면 안 된다 — 홈이 정확히 그 경로였다.
        XCTAssertEqual(individual.displayName(speciesName: "#151", .ko), Individual.unknownName)

        // 정체가 드러나면 진짜 이름으로 돌아온다.
        individual.disguisedAs = nil
        XCTAssertEqual(individual.displayName(speciesName: "메타몽", .ko), "메타몽")
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

/// 위장 그림 — 뮤의 눈에서 색을 뺀다.
final class DittoDisguiseSpriteTests: XCTestCase {
    /// 뮤의 얼굴을 흉내 낸 최소 픽스처: 살색 바탕 + **얼굴 선** + 파란 홍채 + 흰 하이라이트.
    /// 실제 뮤 스프라이트는 네트워크라 테스트가 못 쓴다.
    private func face(line: (r: Int, g: Int, b: Int) = (98, 80, 87)) -> CGImage {
        let (w, h) = (28, 28)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 254/255.0, green: 213/255.0, blue: 229/255.0, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 20, height: 20))          // 살색 얼굴
        // 눈 테두리 — 이 선이 눈의 생김새다. 변환 뒤에도 그대로 남아 있어야 한다.
        context.setFillColor(CGColor(red: Double(line.r)/255, green: Double(line.g)/255,
                                     blue: Double(line.b)/255, alpha: 1))
        context.fill(CGRect(x: 7, y: 15, width: 5, height: 5))
        context.fill(CGRect(x: 16, y: 15, width: 5, height: 5))
        context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 8, y: 16, width: 3, height: 2))           // 왼쪽 홍채
        context.fill(CGRect(x: 17, y: 16, width: 3, height: 2))          // 오른쪽 홍채
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 8, y: 18, width: 3, height: 1))           // 흰 하이라이트
        context.fill(CGRect(x: 17, y: 18, width: 3, height: 1))
        return context.makeImage()!
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

    private func pixels(_ image: CGImage, where matches: (Int, Int, Int, Int) -> Bool) -> Int {
        var count = 0
        forEachPixel(image) { r, g, b, a in if matches(r, g, b, a) { count += 1 } }
        return count
    }

    /// 그림이 실제로 쓰는 얼굴 선 색 — 그릴 때 지정한 값과 다를 수 있다(아래 테스트 참고).
    private func lineColor(of image: CGImage) throws -> [Int] {
        var tally: [[Int]: Int] = [:]
        forEachPixel(image) { r, g, b, a in
            if a > 128, r < 150, g < 150, b < 170 { tally[[r, g, b], default: 0] += 1 }
        }
        return try XCTUnwrap(tally.max { $0.value < $1.value }?.key, "픽스처에 선이 없다")
    }

    /// **초점이 사라진다.** 파란 홍채도 흰 하이라이트도 남으면 안 된다 —
    /// 하이라이트가 남으면 눈이 여전히 살아 있는 눈으로 보인다.
    func testTheEyesLoseTheirColor() throws {
        let before = face()
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before)?.image)
        let blue = { (r: Int, g: Int, b: Int, a: Int) in a > 128 && b > r + 25 && b > g + 10 }
        let white = { (r: Int, g: Int, b: Int, a: Int) in a > 128 && r > 235 && g > 232 && b > 232 }
        XCTAssertGreaterThan(pixels(before, where: blue), 0, "픽스처에 홍채가 없다")
        XCTAssertGreaterThan(pixels(before, where: white), 0, "픽스처에 하이라이트가 없다")
        XCTAssertEqual(pixels(after, where: blue), 0, "파란 홍채가 남아 있다")
        XCTAssertEqual(pixels(after, where: white), 0, "흰 하이라이트가 남아 있다 — 눈에 초점이 살아 있다")
    }

    /// **메타몽 얼굴의 구조가 실제로 나와야 한다** — 위쪽에 작은 점 둘, 그 아래 넓은 입.
    /// 이게 이 그림이 존재하는 이유다. 그냥 어두운 픽셀이 늘었는지만 보면, 눈을 시커멓게 칠하기만
    /// 해도 통과한다 — 실제로 그렇게 만들었다가 "벌레 같지 메타몽이 아니다"라는 지적을 받았다.
    func testTheFaceHasDittosShape() throws {
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(face())?.image)
        // 줄마다 가장 긴 어두운 가로 연속 길이를 잰다.
        var runs: [Int: Int] = [:]
        let rep = NSBitmapImageRep(cgImage: after)
        let bytes = try XCTUnwrap(rep.bitmapData)
        let bpp = rep.bitsPerPixel / 8
        for y in 0..<rep.pixelsHigh {
            var run = 0, best = 0
            for x in 0..<rep.pixelsWide {
                let o = y * rep.bytesPerRow + x * bpp
                let dark = Int(bytes[o + 3]) > 128 && Int(bytes[o]) < 150
                    && Int(bytes[o + 1]) < 150 && Int(bytes[o + 2]) < 170
                run = dark ? run + 1 : 0
                best = max(best, run)
            }
            runs[y] = best
        }
        let mouth = try XCTUnwrap(runs.filter { $0.value >= 4 }.max { $0.value < $1.value },
                                  "넓은 입이 없다 — 줄별 최대 길이: \(runs.sorted { $0.key < $1.key })")
        XCTAssertGreaterThanOrEqual(mouth.value, 4, "입이 좁아 점 몇 개로 보인다")
        // 눈은 입보다 **위에** 있고 **좁아야** 한다.
        let eyeRows = runs.filter { $0.key < mouth.key && $0.value > 0 }
        XCTAssertFalse(eyeRows.isEmpty, "입 위에 눈이 없다")
        XCTAssertLessThan(try XCTUnwrap(eyeRows.map(\.value).max()), mouth.value,
                          "눈이 입만큼 넓다 — 점이 아니라 덩어리로 보인다")
    }

    /// **원래 눈은 자리째 사라진다.** 눈두덩 그늘이 남으면 원래 눈의 윤곽이 그대로 보이고,
    /// 그 위에 메타몽 눈을 얹으면 눈이 둘로 겹쳐 보인다(사용자 지적).
    func testTheOriginalEyeIsGone() throws {
        let before = face()
        let expected = try lineColor(of: before)
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before)?.image)
        let outline = { (r: Int, g: Int, b: Int, a: Int) in a > 128 && [r, g, b] == expected }
        XCTAssertLessThan(pixels(after, where: outline), pixels(before, where: outline),
                          "원래 눈 테두리가 그대로 남아 있다")
    }

    /// 몸의 실루엣은 그대로다 — 지우는 범위를 잘못 잡으면 머리에 구멍이 뚫린다.
    func testTheBodyKeepsItsShape() throws {
        let before = face()
        let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before)?.image)
        let opaque = { (_: Int, _: Int, _: Int, a: Int) in a > 128 }
        XCTAssertEqual(pixels(after, where: opaque), pixels(before, where: opaque),
                       "불투명 픽셀 수가 달라졌다 — 몸에 구멍이 뚫렸거나 넘쳤다")
    }

    /// **선 색은 뮤에게서 빌린다.** 순수한 검정으로 그리면 얹은 티가 나고, 스프라이트마다 선 색이
    /// 다르다(움직이는 쪽 (98,80,87) · 정적 쪽 (90,41,82) — 실측).
    ///
    /// **기대 색은 그림에서 읽는다.** 그릴 때 지정한 값과 비교하면 안 된다 — `NSBitmapImageRep` 가
    /// 색공간을 옮기면서 값이 달라진다(실측: (98,80,87) 로 그린 픽셀이 (118,99,106) 으로 읽혔다).
    func testTheFaceIsDrawnInMewsOwnLineColor() throws {
        for line in [(r: 98, g: 80, b: 87), (r: 90, g: 41, b: 82)] {
            let before = face(line: line)
            let expected = try lineColor(of: before)
            let after = try XCTUnwrap(DittoDisguiseSprite.disguise(before)?.image)
            XCTAssertGreaterThan(pixels(after) { r, g, b, a in a > 128 && [r, g, b] == expected }, 6,
                                 "얼굴이 그림의 선 색(\(expected))으로 안 그려졌다")
            XCTAssertEqual(pixels(after) { r, g, b, a in a > 128 && r < 60 && g < 60 && b < 60 }, 0,
                           "순수 검정으로 그렸다 — 뮤의 선 색을 안 썼다")
        }
    }

    /// **눈과 입 사이에 빈 줄이 있어야 한다.** 붙어 있으면 어디까지가 눈이고 어디부터가 입인지
    /// 구분이 안 된다(사용자 지적) — 처음엔 입을 지운 네모의 아래끝에 걸어 한 줄 차이로 닿았다.
    func testTheMouthKeepsItsDistanceFromTheEyes() throws {
        let layout = try XCTUnwrap(DittoDisguiseSprite.disguise(face())).layout
        let mouth = try XCTUnwrap(layout.mouth, "입이 없다")
        let lowestEye = try XCTUnwrap(layout.eyeDots.map(\.y).max())
        let mouthTop = try XCTUnwrap(DittoDisguiseSprite.mouthCells(x: mouth.x, y: mouth.y)
                                        .map(\.y).min())
        XCTAssertGreaterThanOrEqual(mouthTop - lowestEye, 2,
                                    "눈(y\(lowestEye))과 입(y\(mouthTop))이 붙어 있다")
    }

    /// 입은 **웃는 모양**이어야 한다 — 가운데가 처지고 양 끝이 그 위로 올라간다.
    /// 예전의 계단 모양(한쪽이 통째로 한 칸 아래)은 웃는 게 아니라 비스듬한 선으로 읽혔다.
    func testTheMouthSmiles() {
        let cells = DittoDisguiseSprite.mouthCells(x: 10, y: 10)
        let rows = Dictionary(grouping: cells, by: \.y)
        XCTAssertEqual(rows.count, 2, "입이 두 줄이 아니다")
        let top = try? XCTUnwrap(rows.keys.min()), bottom = rows.keys.max()
        let ends = rows[top!]!.map(\.x).sorted(), middle = rows[bottom!]!.map(\.x).sorted()
        // 윗줄은 양 끝 둘뿐이고, 아랫줄이 그 사이를 채운다.
        XCTAssertEqual(ends.count, 2, "윗줄이 양 끝이 아니다: \(ends)")
        XCTAssertLessThan(ends[0], middle.min()!, "왼쪽 끝이 가운데보다 안쪽이다")
        XCTAssertGreaterThan(ends[1], middle.max()!, "오른쪽 끝이 가운데보다 안쪽이다")
        // 폭 — 좁으면 얼굴이 아니라 점 몇 개로 보인다.
        XCTAssertGreaterThanOrEqual(ends[1] - ends[0] + 1, 7, "입이 좁다")
    }

    /// **얼굴이 프레임마다 흔들리면 안 된다.** 뮤는 위아래로 까딱이는데, 얼굴이 그 움직임과
    /// 따로 놀면 붙었다 떨어졌다 하는 것처럼 보인다(사용자 지적).
    ///
    /// 여기서 재현하는 건 실제로 겪은 결함이다: **눈 테두리가 프레임마다 다르게 잡히는 것**.
    /// 자리를 지운 네모에 걸면 그 변화가 그대로 얼굴로 새어 나온다. 홍채에 걸면 안 그렇다.
    func testTheFaceDoesNotJitterWhenTheEyeOutlineChanges() throws {
        var positions: [Int] = []
        for extra in 0...3 {
            // 홍채는 그대로 두고 눈 테두리만 위로 늘린다 — 프레임마다 잡히는 양이 달라지는 상황.
            let (w, h) = (28, 28)
            let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 254/255.0, green: 213/255.0, blue: 229/255.0, alpha: 1))
            context.fill(CGRect(x: 2, y: 2, width: 24, height: 24))
            context.setFillColor(CGColor(red: 98/255.0, green: 80/255.0, blue: 87/255.0, alpha: 1))
            context.fill(CGRect(x: 7, y: 15, width: 5, height: 5 + extra))
            context.fill(CGRect(x: 16, y: 15, width: 5, height: 5 + extra))
            context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1))
            context.fill(CGRect(x: 8, y: 16, width: 3, height: 2))
            context.fill(CGRect(x: 17, y: 16, width: 3, height: 2))
            let layout = try XCTUnwrap(DittoDisguiseSprite.disguise(context.makeImage()!)).layout
            positions.append(try XCTUnwrap(layout.eyeDots.first).y)
        }
        XCTAssertEqual(Set(positions).count, 1,
                       "눈 테두리가 달라졌다고 얼굴이 따라 움직였다: \(positions)")
    }

    /// **눈 감는 프레임에서 얼굴이 사라지면 안 된다.** 뮤는 깜빡이지만 메타몽은 안 깜빡인다 —
    /// 그 한 프레임만 얼굴이 없으면 그게 곧 깜빡임으로 보인다(실제 GIF 의 42번 프레임).
    func testAClosedEyeFrameKeepsTheFace() throws {
        let previous = try XCTUnwrap(DittoDisguiseSprite.disguise(face())).layout
        let (w, h) = (28, 28)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 254/255.0, green: 213/255.0, blue: 229/255.0, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 20, height: 20))   // 파랑이 하나도 없는 얼굴
        let blink = context.makeImage()!

        XCTAssertNil(DittoDisguiseSprite.disguise(blink), "이어받을 자리가 없으면 손대지 않는다")
        let carried = try XCTUnwrap(DittoDisguiseSprite.disguise(blink, reusing: previous),
                                    "눈 감은 프레임에서 얼굴이 사라졌다")
        XCTAssertEqual(carried.layout, previous, "이어받은 자리가 달라졌다")
        XCTAssertGreaterThan(pixels(carried.image) { r, g, b, a in
            a > 128 && r < 150 && g < 150 && b < 170 }, 0, "얼굴이 안 그려졌다")
    }

    /// 눈이 없으면(눈 감은 프레임) 손대지 않는다.
    func testAFaceWithNoEyesIsLeftAlone() {
        let (w, h) = (8, 8)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.84, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertNil(DittoDisguiseSprite.disguise(context.makeImage()!)?.image)
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


