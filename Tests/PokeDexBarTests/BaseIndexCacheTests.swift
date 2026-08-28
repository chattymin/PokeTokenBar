import XCTest
@testable import PokeDexBar

/// 부화 후보 인덱스의 디스크 캐시는 "언제 만들었나"만 보고 30일을 살아남는다. 종 범위를 넓혀도
/// (649 → 1025) 그 사실을 모르면 옛 인덱스가 계속 쓰이고, 새 세대는 부화 풀에 영영 안 들어온다.
/// 실제로 그 상태의 캐시가 만들어져 6~9세대가 0마리로 남아 있었다.
final class BaseIndexCacheTests: XCTestCase {
    private typealias Snapshot = PokeAPIClient.BaseIndexSnapshot

    func testSnapshotFromCurrentRangeIsUsable() {
        let snapshot = Snapshot(fetchedAt: Date(),
                                entries: [BaseSpecies(id: 1, captureRate: 45, isLegendary: false, isMythical: false)],
                                maxSpeciesID: PokemonAssets.speciesIDs.upperBound)
        XCTAssertTrue(snapshot.matchesCurrentRange())
    }

    /// 범위가 넓어지기 전에 만든 캐시는 버려야 한다 — 이게 이 버그의 핵심이다.
    func testSnapshotFromNarrowerRangeIsRejected() {
        let snapshot = Snapshot(fetchedAt: Date(),
                                entries: [BaseSpecies(id: 1, captureRate: 45, isLegendary: false, isMythical: false)],
                                maxSpeciesID: 649)
        XCTAssertFalse(snapshot.matchesCurrentRange())
    }

    /// 범위 필드가 없던 구 형식은 0으로 읽혀 항상 재구축된다(entries 자체는 현재 스키마로 채워 둔다 —
    /// entries 스키마 자체가 구식인 경우는 아래 `testLegacyEntryWithoutLegendaryFlagsFailsToDecode`).
    func testLegacySnapshotWithoutRangeIsRejected() throws {
        let json = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45,"isLegendary":false,"isMythical":false,"growthRate":"mediumFast","genderRate":4}]}"#
        let decoded = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.maxSpeciesID, 0)
        XCTAssertFalse(decoded.matchesCurrentRange())
    }

    /// `isLegendary`/`isMythical` 이 없던 옛 `base-index.json` 항목은 디코드 자체가 실패해야 한다.
    /// 기본값을 줘서 조용히 성공시키면 모든 옛 캐시 종이 "전설 아님"으로 읽혀, 전설 뽑기가 절대
    /// 전설을 못 주는 결함이 재발한다(캐시가 30일 살아남으므로 재구축 전까지 계속 잘못된다).
    func testLegacyEntryWithoutLegendaryFlagsFailsToDecode() {
        let json = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45}],"maxSpeciesID":1025}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))) { error in
            XCTAssertTrue(error is DecodingError, "구 스키마는 디코딩 에러로 실패해 재구축을 트리거해야 한다")
        }
    }

    /// `growthRate` 는 기본값(mediumFast)이 있어 메모리와이즈 이니셜라이저는 생략을 허용하지만,
    /// Codable 합성 디코드는 그 기본값을 무시하고 키를 그대로 요구한다 — 이 필드가 없던 구
    /// `base-index.json` 항목은 여전히 디코드가 실패해, 모든 종이 mediumFast 로 조용히 굳는
    /// 대신 자동 재구축된다.
    /// `genderRate` 도 같은 부류다 — 기본값이 있어도 합성 디코드는 키를 요구하므로, 성별이
    /// 없던 캐시는 조용히 "절반이 암컷" 으로 굳는 대신 자동 재구축된다. 조용히 굳으면 성비가
    /// 확정인 종(암컷만·수컷만·무성별)이 전부 절반으로 굴러 성별 진화가 통째로 틀어진다.
    func testLegacyEntryWithoutGenderRateFailsToDecode() {
        let json = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45,"isLegendary":false,"isMythical":false,"growthRate":"mediumFast"}],"maxSpeciesID":1025}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))) { error in
            XCTAssertTrue(error is DecodingError, "성비 없는 구 스키마는 재구축을 트리거해야 한다")
        }
    }

    func testLegacyEntryWithoutGrowthRateFailsToDecode() {
        let json = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45,"isLegendary":false,"isMythical":false}],"maxSpeciesID":1025}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))) { error in
            XCTAssertTrue(error is DecodingError, "growthRate 없는 구 스키마는 디코딩 에러로 실패해야 한다")
        }
    }

    func testRoundTripKeepsRange() throws {
        let snapshot = Snapshot(fetchedAt: Date(timeIntervalSince1970: 0),
                                entries: [BaseSpecies(id: 7, captureRate: 45, isLegendary: false, isMythical: false)],
                                maxSpeciesID: 1025)
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(back.maxSpeciesID, 1025)
        XCTAssertEqual(back.entries.first?.id, 7)
    }
}

// MARK: PokéAPI SSRF 가드 (evolution_chain URL 검증 — 응답 변조 시 임의 호스트 fetch 방지)

final class PokeAPIGuardTests: XCTestCase {
    func testValidatedChainURLAcceptsPokeapiHttps() {
        XCTAssertNotNil(PokeAPIClient.validatedChainURL("https://pokeapi.co/api/v2/evolution-chain/1/"))
    }
    func testValidatedChainURLRejectsUntrusted() {
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://evil.example.com/x"), "임의 호스트 거부(SSRF)")
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://pokeapi.co.evil.com/x"), "유사 호스트 거부")
        XCTAssertNil(PokeAPIClient.validatedChainURL("http://pokeapi.co/x"), "http 거부(https 고정)")
        XCTAssertNil(PokeAPIClient.validatedChainURL(""), "빈 문자열 거부")
    }
}
