import XCTest
@testable import PokeDexBar

/// 부화 후보 인덱스의 디스크 캐시는 "언제 만들었나"만 보고 30일을 살아남는다. 종 범위를 넓혀도
/// (649 → 1025) 그 사실을 모르면 옛 인덱스가 계속 쓰이고, 새 세대는 부화 풀에 영영 안 들어온다.
/// 실제로 그 상태의 캐시가 만들어져 6~9세대가 0마리로 남아 있었다.
final class BaseIndexCacheTests: XCTestCase {
    private typealias Snapshot = PokeAPIClient.BaseIndexSnapshot

    func testSnapshotFromCurrentRangeIsUsable() {
        let snapshot = Snapshot(fetchedAt: Date(), entries: [BaseSpecies(id: 1, captureRate: 45)],
                                maxSpeciesID: PokemonAssets.speciesIDs.upperBound)
        XCTAssertTrue(snapshot.matchesCurrentRange())
    }

    /// 범위가 넓어지기 전에 만든 캐시는 버려야 한다 — 이게 이 버그의 핵심이다.
    func testSnapshotFromNarrowerRangeIsRejected() {
        let snapshot = Snapshot(fetchedAt: Date(), entries: [BaseSpecies(id: 1, captureRate: 45)],
                                maxSpeciesID: 649)
        XCTAssertFalse(snapshot.matchesCurrentRange())
    }

    /// 범위 필드가 없던 구 형식은 0으로 읽혀 항상 재구축된다.
    func testLegacySnapshotWithoutRangeIsRejected() throws {
        let json = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45}]}"#
        let decoded = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.maxSpeciesID, 0)
        XCTAssertFalse(decoded.matchesCurrentRange())
    }

    func testRoundTripKeepsRange() throws {
        let snapshot = Snapshot(fetchedAt: Date(timeIntervalSince1970: 0),
                                entries: [BaseSpecies(id: 7, captureRate: 45)], maxSpeciesID: 1025)
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
