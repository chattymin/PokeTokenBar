import Foundation
import XCTest
@testable import PokeTokenBar

// Identifiers (language codes, version names, the error body) are copied from live PokéAPI responses.
// Entry text is synthetic: the repository does not commit Pokémon data. It keeps what the tests rely on —
// line and page breaks, Japanese ideographic spaces, and kana vs. kanji.
private let kanaX = "かなの\u{3000}せつめい\u{3000}ぶん\nつぎの\u{3000}ぎょう"
private let kanjiX = "漢字の\u{3000}説明\u{3000}文\n次の\u{3000}行"
/// The body PokéAPI GraphQL returns, with HTTP 200, for a query it rejects.
private let graphQLErrorBody = #"{"errors":[{"message":"field 'x' not found in type: 'query_root'","extensions":{"path":"$.selectionSet.x","code":"validation-failed"}}]}"#

private struct GraphQLRow {
    let versionID: Int
    let version: String
    let language: String
    let text: String
    var labels: [String: String] = [:]
}

private func graphQLBody(_ rows: [GraphQLRow]) -> Data {
    let json: [String: Any] = ["data": ["pokemonspeciesflavortext": rows.map { row in
        ["flavor_text": row.text, "language": ["name": row.language],
         "version": ["id": row.versionID, "name": row.version,
                     "versionnames": row.labels.map { ["name": $0.value, "language": ["name": $0.key]] }]]
    }]]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func restBody(_ rows: [GraphQLRow]) -> Data {
    let json: [String: Any] = ["flavor_text_entries": rows.map { row in
        ["flavor_text": row.text,
         "language": ["name": row.language, "url": "https://pokeapi.co/api/v2/language/1/"],
         "version": ["name": row.version, "url": "https://pokeapi.co/api/v2/version/\(row.versionID)/"]]
    }]
    return try! JSONSerialization.data(withJSONObject: json)
}

private actor RequestLog {
    private(set) var graphQLBodies: [String] = []
    private(set) var restCount = 0
    func record(_ request: URLRequest) {
        if request.url?.host == "graphql.pokeapi.co" {
            graphQLBodies.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        } else {
            restCount += 1
        }
    }
}

private enum TransportFailure: Error { case offline }

/// Routes GraphQL and REST to separate handlers; the GraphQL handler sees the request body.
private func client(log: RequestLog,
                    graphQL: @escaping @Sendable (String) throws -> (Data, Int),
                    rest: @escaping @Sendable () throws -> (Data, Int)) -> PokemonFlavorTextClient {
    PokemonFlavorTextClient { request in
        await log.record(request)
        if request.url?.host == "graphql.pokeapi.co" {
            return try graphQL(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        }
        return try rest()
    }
}

final class DexFlavorTextSanitizeTests: XCTestCase {
    func testCollapsesGameLineBreaksAndPageFeeds() {
        XCTAssertEqual(PokemonFlavorTextClient.sanitize("First line\nsecond line\u{000C}third part\rfourth part"),
                       "First line second line third part fourth part")
    }

    func testRemovesSoftHyphen() {
        XCTAssertEqual(PokemonFlavorTextClient.sanitize("electri\u{00AD}city"), "electricity")
    }

    func testKeepsIdeographicSpaceWhileCollapsingNewlines() {
        XCTAssertEqual(PokemonFlavorTextClient.sanitize(kanaX), "かなの\u{3000}せつめい\u{3000}ぶん つぎの\u{3000}ぎょう")
    }

    func testCollapsesRunsAndTrimsEdges() {
        XCTAssertEqual(PokemonFlavorTextClient.sanitize("  a \n\n b  "), "a b")
    }
}

final class DexFlavorTextCollapseTests: XCTestCase {
    private func rows(_ graphQL: [GraphQLRow]) -> [FlavorRow] {
        graphQL.map { FlavorRow(versionKey: $0.version, versionID: $0.versionID, languageCode: $0.language,
                                text: $0.text, labels: $0.labels) }
    }

    /// GraphQL orders by version only, so `ja` and `ja-hrkt` rows of one version arrive in either order.
    func testJapaneseFollowsAppLanguagePriorityWhicheverRowArrivesFirst() {
        let kana = GraphQLRow(versionID: 23, version: "x", language: "ja-hrkt", text: kanaX)
        let kanji = GraphQLRow(versionID: 23, version: "x", language: "ja", text: kanjiX)
        XCTAssertEqual(AppLanguage.ja.apiCodes.first, "ja-hrkt")
        for order in [[kana, kanji], [kanji, kana]] {
            let result = PokemonFlavorTextClient.collapse(rows(order), language: .ja)
            XCTAssertEqual(result.map(\.text), [PokemonFlavorTextClient.sanitize(kanaX)])
        }
    }

    func testVersionLabelUsesTheRequestedLanguageAndFallsBackToTheSlug() {
        let localized = GraphQLRow(versionID: 25, version: "omega-ruby", language: "ja-hrkt", text: "a",
                                   labels: ["ja-hrkt": "オメガルビー"])
        XCTAssertEqual(PokemonFlavorTextClient.collapse(rows([localized]), language: .ja).first?.versionLabel, "オメガルビー")
        let unlabeled = GraphQLRow(versionID: 25, version: "omega-ruby", language: "ja-hrkt", text: "a")
        XCTAssertEqual(PokemonFlavorTextClient.collapse(rows([unlabeled]), language: .ja).first?.versionLabel, "Omega Ruby")
    }

    func testDropsLanguagesThatWereNotRequested() {
        let result = PokemonFlavorTextClient.collapse(rows([
            GraphQLRow(versionID: 23, version: "x", language: "en", text: "english"),
            GraphQLRow(versionID: 23, version: "x", language: "ko", text: "한국어"),
            GraphQLRow(versionID: 24, version: "y", language: "fr", text: "français"),
        ]), language: .ko)
        XCTAssertEqual(result.map(\.text), ["한국어"])
    }

    func testOrdersVersionsByReleaseID() {
        let result = PokemonFlavorTextClient.collapse(rows([
            GraphQLRow(versionID: 33, version: "sword", language: "en", text: "c"),
            GraphQLRow(versionID: 1, version: "red", language: "en", text: "a"),
            GraphQLRow(versionID: 23, version: "x", language: "en", text: "b"),
        ]), language: .en)
        XCTAssertEqual(result.map(\.versionKey), ["red", "x", "sword"])
    }

    func testGraphQLAndRESTYieldTheSameVersionsAndText() throws {
        let fixture = [GraphQLRow(versionID: 23, version: "x", language: "ko", text: "첫 번째\n설명",
                                  labels: ["ko": "X"]),
                       GraphQLRow(versionID: 27, version: "sun", language: "ko", text: "두 번째\n설명",
                                  labels: ["ko": "썬"])]
        let graphQL = try PokemonFlavorTextClient.parseGraphQL(graphQLBody(fixture), status: 200, language: .ko)
        let rest = try PokemonFlavorTextClient.parseREST(restBody(fixture), status: 200, language: .ko)
        XCTAssertEqual(graphQL.map(\.versionKey), rest.map(\.versionKey))
        XCTAssertEqual(graphQL.map(\.versionID), rest.map(\.versionID))
        XCTAssertEqual(graphQL.map(\.text), rest.map(\.text))
        XCTAssertEqual(graphQL.map(\.versionLabel), ["X", "썬"])
        XCTAssertEqual(rest.map(\.versionLabel), ["X", "Sun"], "REST has no localized version names")
    }
}

final class DexFlavorTextFallbackDecisionTests: XCTestCase {
    private let one = [DexFlavorText(versionKey: "x", versionID: 23, versionLabel: "X", text: "t")]

    func testEmptyNonEnglishLanguageFallsBackToEnglish() {
        XCTAssertTrue(PokemonFlavorTextClient.needsEnglishFallback(entries: [], language: .pt))
        XCTAssertTrue(PokemonFlavorTextClient.needsEnglishFallback(entries: [], language: .ko))
    }

    func testEmptyEnglishDoesNotFallBack() {
        XCTAssertFalse(PokemonFlavorTextClient.needsEnglishFallback(entries: [], language: .en))
    }

    func testPartialCoverageKeepsTheRequestedLanguage() {
        XCTAssertFalse(PokemonFlavorTextClient.needsEnglishFallback(entries: one, language: .ko))
    }
}

final class DexFlavorTextClientTests: XCTestCase {
    private let koRows = [GraphQLRow(versionID: 23, version: "x", language: "ko", text: "한국어 설명",
                                     labels: ["ko": "X"])]

    func testGraphQLResultIsLocalizedAndServedFromCacheAfterwards() async throws {
        let log = RequestLog()
        let body = graphQLBody(koRows)
        let sut = client(log: log, graphQL: { _ in (body, 200) }, rest: { XCTFail("REST must not run"); throw TransportFailure.offline })
        let first = try await sut.flavorTexts(speciesID: 25, language: .ko)
        let second = try await sut.flavorTexts(speciesID: 25, language: .ko)
        XCTAssertFalse(first.isDegraded)
        XCTAssertEqual(first.entries.map(\.versionLabel), ["X"])
        XCTAssertEqual(second, first)
        let graphQLCount = await log.graphQLBodies.count
        XCTAssertEqual(graphQLCount, 1)
    }

    /// Transport errors, HTTP errors, GraphQL `errors` payloads and undecodable bodies all recover
    /// through REST. The REST result is shown as degraded and never cached.
    func testEveryGraphQLFailureFallsBackToRESTWithoutCaching() async throws {
        let failures: [(String, @Sendable (String) throws -> (Data, Int))] = [
            ("transport", { _ in throw TransportFailure.offline }),
            ("http status", { _ in (Data("{}".utf8), 503) }),
            ("errors payload", { _ in (Data(graphQLErrorBody.utf8), 200) }),
            ("undecodable body", { _ in (Data("<html>".utf8), 200) }),
        ]
        let rest = restBody(koRows)
        for (name, graphQL) in failures {
            let log = RequestLog()
            let sut = client(log: log, graphQL: graphQL, rest: { (rest, 200) })
            let first = try await sut.flavorTexts(speciesID: 25, language: .ko)
            XCTAssertTrue(first.isDegraded, name)
            XCTAssertEqual(first.entries.map(\.text), ["한국어 설명"], name)
            _ = try await sut.flavorTexts(speciesID: 25, language: .ko)
            let graphQLCount = await log.graphQLBodies.count
            let restCount = await log.restCount
            XCTAssertEqual(graphQLCount, 2, "\(name): a degraded result must not be cached")
            XCTAssertEqual(restCount, 2, name)
        }
    }

    func testRESTFailureAfterGraphQLFailureThrows() async {
        let sut = client(log: RequestLog(), graphQL: { _ in throw TransportFailure.offline },
                         rest: { (Data(), 500) })
        do {
            _ = try await sut.flavorTexts(speciesID: 25, language: .ko)
            XCTFail("both sources failed")
        } catch {}
    }

    /// PokéAPI has no `pt`: the request comes back empty and the client asks again in English.
    func testLanguageWithoutEntriesFallsBackToEnglish() async throws {
        let log = RequestLog()
        let english = graphQLBody([GraphQLRow(versionID: 1, version: "red", language: "en",
                                              text: "English entry", labels: ["en": "Red"])])
        let empty = graphQLBody([])
        let sut = client(log: log, graphQL: { body in (body.contains("\\\"pt\\\"") ? empty : english, 200) },
                         rest: { throw TransportFailure.offline })
        let result = try await sut.flavorTexts(speciesID: 25, language: .pt)
        XCTAssertEqual(result.language, .en)
        XCTAssertEqual(result.entries.map(\.text), ["English entry"])
        XCTAssertFalse(result.isDegraded)
        let bodies = await log.graphQLBodies
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(bodies[0].contains("\\\"pt\\\""), bodies[0])
        XCTAssertTrue(bodies[1].contains("\\\"en\\\""), bodies[1])
    }
}
