import XCTest
import PokeTokenBarShared

/// Mac → iPhone 페이로드(PhoneLimitStatus) 스키마 회귀 — 새 필드는 구 버전과 양방향 호환돼야 한다.
/// TokenFormatter 가 app target 과 shared package 양쪽에 있어 import 를 섞으면 모호해지므로
/// shared 타입만 쓰는 테스트를 별도 파일로 둔다.
final class PhonePayloadCodableTests: XCTestCase {
    /// 구 Mac 이 보낸 페이로드(OpenCode Go·claudeScoped 필드 없음)도 폰 코드에서 깨지지 않는다 — nil 로 디코드.
    func testLimitStatusDecodesLegacyPayloadWithoutOpenCodeGo() throws {
        let legacy = Data("""
        {"claude5h":{"label":"5h Session","utilization":42,"resetsAt":null},
         "planDisplay":null}
        """.utf8)
        let status = try JSONDecoder().decode(PhoneLimitStatus.self, from: legacy)
        XCTAssertEqual(status.claude5h?.label, "5h Session")
        XCTAssertNil(status.claudeScoped)
        XCTAssertNil(status.opencodeGo5h)
        XCTAssertNil(status.opencodeGoWeekly)
        XCTAssertNil(status.opencodeGoMonthly)
    }

    /// 모델별(scoped) 주간 창 왕복 + orderedWindows 순서/포함 검증.
    func testLimitStatusRoundTripsScopedAndOrders() throws {
        let status = PhoneLimitStatus(
            claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 2, resetsAt: nil),
            claudeWeekly: PhoneLimitWindow(label: "Claude Weekly", utilization: 13, resetsAt: nil),
            claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            claudeScoped: [PhoneLimitWindow(label: "Claude Weekly Fable", utilization: 41, resetsAt: nil)],
            codexPrimary: PhoneLimitWindow(label: "Codex 5h", utilization: 61, resetsAt: nil),
            codexSecondary: nil,
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 92, resetsAt: nil),
            opencodeGoWeekly: nil, opencodeGoMonthly: nil,
            planDisplay: "Max 20x")
        let decoded = try JSONDecoder().decode(
            PhoneLimitStatus.self, from: JSONEncoder().encode(status))
        XCTAssertEqual(decoded.claudeScoped?.map(\.label), ["Claude Weekly Fable"])
        XCTAssertEqual(decoded.orderedWindows.map(\.label),
                       ["Claude 5h", "Claude Weekly", "Claude Weekly Fable", "Codex 5h", "Go 5h"])
    }

    // MARK: 한도 이력

    /// 이력 필드가 없는 구 Mac 페이로드는 nil 로 떨어져야 한다 — 폰이 카드를 안 그리면 그만이고,
    /// 디코드 전체가 깨지면 구 Mac 과 페어링된 폰이 사용량까지 통째로 잃는다.
    func testLimitStatusDecodesPayloadWithoutHistory() throws {
        let legacy = Data("""
        {"claude5h":{"label":"5h Session","utilization":42,"resetsAt":null},
         "planDisplay":null}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(PhoneLimitStatus.self, from: legacy).history)
    }

    func testLimitHistoryRoundTrips() throws {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let status = PhoneLimitStatus(
            claude5h: nil, claudeWeekly: nil, claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            codexPrimary: nil, codexSecondary: nil, planDisplay: nil,
            warnThreshold: 80, critThreshold: 95,
            history: [PhoneLimitHistorySeries(
                label: "Claude 5h",
                windows: [
                    PhoneLimitHistoryWindow(peak: 40, end: end, truncated: false),
                    PhoneLimitHistoryWindow(peak: 97, end: end.addingTimeInterval(3600), truncated: true),
                ],
                peak: 97, median: 68.5, atOrAbove: 1)])

        let decoded = try JSONDecoder().decode(
            PhoneLimitStatus.self, from: JSONEncoder().encode(status))
        let series = try XCTUnwrap(decoded.history?.first)
        XCTAssertEqual(series.label, "Claude 5h")
        XCTAssertEqual(series.windows.map(\.peak), [40, 97])
        XCTAssertEqual(series.median, 68.5)
        XCTAssertEqual(series.atOrAbove, 1)
        XCTAssertTrue(series.hasTruncated, "관측 공백이 섞인 시리즈는 폰이 그렇게 표시해야 한다")
    }

    /// 창이 전부 완전 관측이면 "일부 미관측" 안내를 띄우면 안 된다 — 반대 방향 가드.
    func testFullyObservedSeriesIsNotFlaggedTruncated() {
        let series = PhoneLimitHistorySeries(
            label: "Claude Weekly",
            windows: [PhoneLimitHistoryWindow(peak: 12, end: .distantPast, truncated: false)],
            peak: 12, median: 12, atOrAbove: 0)
        XCTAssertFalse(series.hasTruncated)
    }

    /// 프로바이더 그룹(위젯 파이+퍼센트 행용) — 제목·순서·빈 그룹 제외를 고정한다.
    func testLimitGroupsByProviderOmitEmpty() {
        let status = PhoneLimitStatus(
            claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 2, resetsAt: nil),
            claudeWeekly: PhoneLimitWindow(label: "Claude Weekly", utilization: 13, resetsAt: nil),
            claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            claudeScoped: [PhoneLimitWindow(label: "Claude Weekly Fable", utilization: 41, resetsAt: nil)],
            codexPrimary: nil, codexSecondary: nil,   // Codex 미사용 → 그룹 없음
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 92, resetsAt: nil),
            opencodeGoWeekly: PhoneLimitWindow(label: "Go Weekly", utilization: 74, resetsAt: nil),
            opencodeGoMonthly: PhoneLimitWindow(label: "Go Monthly", utilization: 38, resetsAt: nil),
            planDisplay: nil)

        let groups = status.limitGroups
        XCTAssertEqual(groups.map(\.title), ["Claude", "Go"], "창 없는 프로바이더는 그룹 생성 안 함")
        XCTAssertEqual(groups[0].windows.count, 3, "Claude = 5h+주간+scoped(Fable)")
        XCTAssertEqual(groups[1].windows.map(\.label), ["Go 5h", "Go Weekly", "Go Monthly"])
        // 그룹 창 순서는 orderedWindows 와 동일 소스여야 한다(두 순서가 어긋나면 위젯/앱 불일치).
        XCTAssertEqual(groups.flatMap(\.windows).map(\.label), status.orderedWindows.map(\.label))
    }

    /// 새 필드 왕복 — Go 세 창이 인코딩·디코딩을 그대로 통과한다.
    func testLimitStatusRoundTripsOpenCodeGoWindows() throws {
        let status = PhoneLimitStatus(
            claude5h: nil, claudeWeekly: nil, claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            codexPrimary: nil, codexSecondary: nil,
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 2, resetsAt: Date(timeIntervalSince1970: 1_785_000_000)),
            opencodeGoWeekly: PhoneLimitWindow(label: "Go Weekly", utilization: 41, resetsAt: nil),
            opencodeGoMonthly: PhoneLimitWindow(label: "Go Monthly", utilization: 20, resetsAt: nil),
            planDisplay: nil)
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(PhoneLimitStatus.self, from: data)
        XCTAssertEqual(decoded.opencodeGo5h?.label, "Go 5h")
        XCTAssertEqual(decoded.opencodeGo5h?.utilization, 2)
        XCTAssertEqual(decoded.opencodeGoWeekly?.label, "Go Weekly")
        XCTAssertEqual(decoded.opencodeGoMonthly?.utilization, 20)
    }

    /// 새 필드(antigravity·임계값·주/월 비용·burn·컴패니언 확장)가 없는 구 페이로드도 nil/기본값으로 디코드된다.
    func testNewOptionalFieldsDecodeAsNilFromLegacyPayload() throws {
        let legacy = Data("""
        {"todayTokens":1,"todayCost":0.5,"weekTokens":2,"monthTokens":3,
         "lastUpdated":0,"serverVersion":"1.0",
         "limits":{"claude5h":{"label":"Claude 5h","utilization":42,"resetsAt":null},"planDisplay":null},
         "companion":{"name":"Pikachu","speciesID":25,"isShiny":false,"isEgg":false,"progress":0.1,
                      "stageText":"Stage 1/3","rarity":"common","dexCount":1,"eggProgress":0,"displayState":"idle"},
         "providers":[]}
        """.utf8)
        let payload = try JSONDecoder().decode(PhonePayload.self, from: legacy)
        XCTAssertNil(payload.weekCost)
        XCTAssertNil(payload.monthCost)
        XCTAssertNil(payload.burn)
        XCTAssertNil(payload.limits?.antigravity)
        XCTAssertNil(payload.limits?.warnThreshold)
        XCTAssertEqual(payload.limits?.effectiveWarnThreshold, 80)
        XCTAssertEqual(payload.limits?.effectiveCritThreshold, 95)
        XCTAssertNil(payload.companion?.representativeSpeciesID)
        XCTAssertNil(payload.companion?.statusText)
        XCTAssertNil(payload.companion?.lineNodes)
    }

    /// `lockedReason` 없는 구 Mac 의 상점 엔트리도 nil 로 디코드된다 — 새 폰이 구 Mac 과 붙었을 때
    /// 상점 전체가 빈 목록으로 떨어지지 않게 (PhonePayload 의 shop 은 실패 시 통째로 [] 가 된다).
    func testShopEntryDecodesLegacyPayloadWithoutLockedReason() throws {
        let legacy = Data("""
        {"id":"egg:plain","isEgg":true,"name":"Fresh Egg","itemDescription":"Reroll",
         "price":100,"ownedCount":0,"isPassive":false,"isOwned":false,"canAfford":true,
         "fallbackEmoji":"🥚"}
        """.utf8)
        let entry = try JSONDecoder().decode(PhoneShopEntry.self, from: legacy)
        XCTAssertNil(entry.lockedReason)
        XCTAssertTrue(entry.canAfford)
    }

    /// 확장 필드 왕복 + Antigravity 그룹이 orderedWindows 의 마지막에 온다.
    func testExtendedFieldsRoundTrip() throws {
        let limits = PhoneLimitStatus(
            claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 2, resetsAt: nil),
            claudeWeekly: nil, claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            codexPrimary: nil, codexSecondary: nil,
            antigravity: [PhoneLimitWindow(label: "Antigravity Gemini 5h", utilization: 75, resetsAt: nil)],
            planDisplay: "Max", warnThreshold: 60, critThreshold: 90)
        let companion = PhoneCompanionState(
            name: "Pikachu", speciesID: 25, isShiny: false, isEgg: false, progress: 0.4,
            stageText: "Stage 1/3", rarity: "common", dexCount: 3, eggProgress: 0, displayState: "focus",
            representativeSpeciesID: 6, representativeIsShiny: true, statusText: "In focus mode now.",
            natureText: "Jolly",
            lineNodes: [PhoneEvoNode(speciesID: 25, name: "Pikachu", state: .current),
                        PhoneEvoNode(speciesID: nil, name: nil, state: .future)])
        let payload = PhonePayload(
            todayTokens: 1, todayCost: 0.5, weekTokens: 2, monthTokens: 3,
            lastUpdated: Date(timeIntervalSince1970: 0), serverVersion: "2.6.0",
            limits: limits, companion: companion, providers: [],
            weekCost: 12.5, monthCost: 40,
            burn: PhoneBurnForecast(depletionDate: Date(timeIntervalSince1970: 100), beforeReset: true, tokensPerMinute: 900))
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(PhonePayload.self, from: data)
        XCTAssertEqual(back, payload)
        XCTAssertEqual(back.limits?.limitGroups.map(\.title), ["Claude", "Antigravity"])
        XCTAssertEqual(back.limits?.orderedWindows.last?.label, "Antigravity Gemini 5h")
        XCTAssertEqual(back.companion?.lineNodes?.last?.speciesID, nil)
    }
}
