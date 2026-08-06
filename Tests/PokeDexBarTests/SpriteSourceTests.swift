import Foundation
import XCTest
@testable import PokeDexBar

/// `SpriteStore.fetch` seam 을 대체하는 스텁 — 상태 코드·에러를 자유롭게 흉내낸다. 클래스(참조 타입)라
/// 같은 테스트 안에서 모드를 바꿔가며(예: 실패 후 성공) 하나의 SpriteStore 인스턴스에 재사용할 수 있다.
private final class FetchStub: @unchecked Sendable {
    enum Mode {
        case throwError
        case status(Int)
        case success(Data)
    }
    var mode: Mode
    init(_ mode: Mode) { self.mode = mode }

    func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        switch mode {
        case .throwError:
            throw URLError(.timedOut)
        case .status(let code):
            let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        case .success(let data):
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }
    }
}

final class SpriteSourceTests: XCTestCase {
    /// 매 테스트가 서로 다른 임시 디렉터리를 써서 디스크 캐시가 테스트 간 새지 않게 한다.
    private func makeTempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testAnimatedURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani/pikachu.gif")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani-shiny/pikachu.gif")
    }

    func testStaticURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5/mew.png")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5-shiny/mew.png")
    }

    /// 캐시 키는 종 번호 기반을 유지한다 — 슬러그가 바뀌어도 기존 캐시가 무효화되지 않게.
    /// animated/shiny 4 조합 전부(기존 키 "25-a"/"25-s" 불변 + shiny 접두) 잠근다.
    func testCacheKeyStaysNumeric() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: true, shiny: false), "25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: false, shiny: false), "25-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: true, shiny: true), "25-sha")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: false, shiny: true), "25-shs")
    }

    /// 리뷰 지적(critical): 오프라인·타임아웃 같은 일시적 실패는 missingAnimated 에 기록되면 안 된다.
    /// 기록되면 네트워크가 돌아온 뒤에도 해당 종이 프로세스 수명 내내 정적 폴백에 갇힌다.
    func testTransientFailureDoesNotPermanentlyDisableAnimation() async {
        let stub = FetchStub(.throwError)
        let store = SpriteStore(dir: makeTempDir(), fetch: stub.fetch)

        let duringOutage = await store.data(speciesID: 25, animated: true) // pikachu
        XCTAssertNil(duringOutage)

        // 네트워크가 돌아왔다고 가정 — missingAnimated 에 기록됐다면 이 호출도 여전히 nil 이어야 한다.
        let bytes = Data([0x01, 0x02, 0x03])
        stub.mode = .success(bytes)
        let afterReconnect = await store.data(speciesID: 25, animated: true)
        XCTAssertEqual(afterReconnect, bytes)
    }

    /// 404 는 "이 종엔 애니메이션이 없다"는 확정 신호 — 기록되면 이후 호출은 네트워크 없이 nil 로 떨어진다.
    func test404PermanentlyDisablesAnimationForThatSpecies() async {
        let stub = FetchStub(.status(404))
        let store = SpriteStore(dir: makeTempDir(), fetch: stub.fetch)

        let first = await store.data(speciesID: 25, animated: true)
        XCTAssertNil(first)

        // fetch 가 이제 성공을 돌려주더라도, 404 로 기록된 종은 짧게-회로차단되어 여전히 nil 이어야 한다.
        stub.mode = .success(Data([0x09]))
        let second = await store.data(speciesID: 25, animated: true)
        XCTAssertNil(second)
    }

    /// 리뷰 지적(critical): missingAnimated 는 종이 아니라 **변형(종+shiny)** 단위로 기억해야 한다. shiny
    /// 애니메이션 404 를 종 단위로 기억하면, 뒤이은 일반(non-shiny) 애니메이션 요청까지 같은 종이라는 이유로
    /// 네트워크 호출 없이 nil 로 단락되어 — 정적으로도, 일반 GIF 로도 절대 폴백하지 못한다.
    func test404OnShinyVariantDoesNotDisableNonShinyAnimation() async {
        let stub = FetchStub(.status(404))
        let store = SpriteStore(dir: makeTempDir(), fetch: stub.fetch)

        let shinyMiss = await store.data(speciesID: 25, animated: true, shiny: true)
        XCTAssertNil(shinyMiss)

        // shiny 변형만 확정 실패로 기억됐어야 한다 — 같은 종의 non-shiny 변형은 여전히 네트워크를 타야 한다.
        let bytes = Data([0x42])
        stub.mode = .success(bytes)
        let nonShiny = await store.data(speciesID: 25, animated: true, shiny: false)
        XCTAssertEqual(nonShiny, bytes)
    }

    /// 5xx 같은 비-404 상태 코드도 일시적 서버 오류일 수 있다 — 기록하면 안 된다.
    func test500DoesNotPermanentlyDisableAnimation() async {
        let stub = FetchStub(.status(500))
        let store = SpriteStore(dir: makeTempDir(), fetch: stub.fetch)

        let duringOutage = await store.data(speciesID: 25, animated: true)
        XCTAssertNil(duringOutage)

        let bytes = Data([0x0A, 0x0B])
        stub.mode = .success(bytes)
        let afterRecovery = await store.data(speciesID: 25, animated: true)
        XCTAssertEqual(afterRecovery, bytes)
    }

    /// 리뷰 지적(important): 슬러그 조회가 캐시 조회보다 앞에 있으면 번들 슬러그 테이블 로드 실패가
    /// 이미 디스크에 있는 스프라이트까지 막는다. 알려지지 않은 종 번호(슬러그 테이블에 없음)라도 디스크
    /// 캐시 파일이 있으면 슬러그 없이도 그 파일을 돌려줘야 한다 — 네트워크는 전혀 호출되지 않아야 한다.
    func testDiskCacheHitDoesNotRequireSlugLookup() async {
        let dir = makeTempDir()
        let unknownSpeciesID = 999_999 // SpeciesSlug 테이블 범위(1...1025) 밖 — slug(_:) 는 nil 을 돌려준다
        let key = SpriteStore.cacheKey(speciesID: unknownSpeciesID, form: nil, animated: false, shiny: false)
        let bytes = Data([0xAA, 0xBB, 0xCC])
        try? bytes.write(to: dir.appendingPathComponent("\(key).png"))

        let stub = FetchStub(.throwError) // 호출되면 안 됨 — 호출돼도 실패라 캐시 히트와 구분된다
        let store = SpriteStore(dir: dir, fetch: stub.fetch)

        let result = await store.data(speciesID: unknownSpeciesID, animated: false, shiny: false)
        XCTAssertEqual(result, bytes)
    }
}
