import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private actor NameServer {
    private(set) var calls = 0
    var response: Data
    var fails = false
    init(_ response: Data) { self.response = response }
    func setFailure(_ value: Bool) { fails = value }
    func fetch(_ url: URL) async throws -> Data {
        calls += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        if fails { throw URLError(.notConnectedToInternet) }
        return response
    }
}

final class PokemonNameLocalizationTests: XCTestCase {
    private let resource = PokemonNameResource(kind: .move, name: "tackle")
    private func response(_ values: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["names": values.map { ["name": $0.value, "language": ["name": $0.key]] }])
    }
    private func tempDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("PokemonNames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func testSelectedLanguageThenEnglishWithCurrentAndLegacyCodes() {
        let names = ["en": "Tackle", "ko": "몸통박치기", "ja-Hrkt": "たいあたり", "ja": "体当たり", "pt_BR": "Investida"]
        XCTAssertEqual(AppLanguage.ko.resolveName(names), "몸통박치기")
        XCTAssertEqual(AppLanguage.ja.resolveName(names), "たいあたり")
        XCTAssertEqual(AppLanguage.pt.resolveName(names), "Investida")
        XCTAssertEqual(AppLanguage.de.resolveName(names), "Tackle")
        XCTAssertEqual(AppLanguage.ko.resolveName(["ko": " \n", "en": " Tackle "]), "Tackle")
        XCTAssertNil(AppLanguage.ko.resolveName(["fr": "Charge"]))
        XCTAssertEqual(AppLanguage.pt.apiCodes, ["pt-br", "pt"])
        XCTAssertEqual(AppLanguage.ja.apiCodes, ["ja-hrkt", "ja"])
        XCTAssertEqual(PokeAPIClient.langCodes, AppLanguage.allCases.flatMap(\.apiCodes))
    }

    func testParserPreservesFutureLanguagesAndIgnoresEmptyValues() throws {
        struct Envelope: Decodable { let names: [NameDTO] }
        let data = try response(["ko": "몸통박치기", "en": "Tackle", "it": "Azione", "pt_BR": "Investida", "": "Bad", "fr": " "])
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        let names = PokemonNameLocalization.collect(decoded.names)
        XCTAssertEqual(names["it"], "Azione", "Keep languages outside the current AppLanguage enum")
        XCTAssertEqual(names["pt-br"], "Investida")
        XCTAssertNil(names[""])
        XCTAssertNil(names["fr"])
        XCTAssertEqual(PokemonNameLocalization.resolve(names, preferredCodes: ["it"]), "Azione")
        XCTAssertEqual(PokemonNameLocalization.resolve(names, preferredCodes: ["not-yet-supported"]), "Tackle")
    }

    func testMemoryAndDiskCacheKeepAllLanguagesWithoutRefetchOnLanguageChange() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = NameServer(try response(["en": "Tackle", "ko": "몸통박치기", "it": "Azione"]))
        let client = PokemonNameClient(directory: directory, fetch: { try await server.fetch($0) })
        let first = try await client.names(for: resource)
        XCTAssertEqual(AppLanguage.ko.resolveName(first), "몸통박치기")
        let second = try await client.names(for: resource)
        XCTAssertEqual(AppLanguage.en.resolveName(second), "Tackle")
        let restored = PokemonNameClient(directory: directory, fetch: { try await server.fetch($0) })
        let disk = try await restored.names(for: resource)
        XCTAssertEqual(PokemonNameLocalization.resolve(disk, preferredCodes: ["it"]), "Azione")
        let calls = await server.calls
        XCTAssertEqual(calls, 1)
    }

    func testDuplicateVisibleRowsShareOneRequest() async throws {
        let resource = self.resource
        let server = NameServer(try response(["en": "Tackle", "ko": "몸통박치기"]))
        let client = PokemonNameClient(directory: nil, fetch: { try await server.fetch($0) })
        async let a = client.names(for: resource)
        async let b = client.names(for: resource)
        let values = try await (a, b)
        XCTAssertEqual(values.0, values.1)
        let calls = await server.calls
        XCTAssertEqual(calls, 1)
    }

    func testExpiredDiskSurvivesOfflineAndDoesNotBecomeFresh() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let server = NameServer(try response(["en": "Tackle", "ko": "몸통박치기"]))
        let initial = PokemonNameClient(directory: directory, now: { time }, fetch: { try await server.fetch($0) })
        _ = try await initial.names(for: resource)
        await server.setFailure(true)
        let stale = PokemonNameClient(directory: directory, now: { time.addingTimeInterval(31 * 86400) }, fetch: { try await server.fetch($0) })
        let offline = try await stale.names(for: resource)
        XCTAssertEqual(AppLanguage.ko.resolveName(offline), "몸통박치기")
        await server.setFailure(false)
        _ = try await stale.names(for: resource)
        let calls = await server.calls
        XCTAssertEqual(calls, 3, "Offline fallback must preserve the original timestamp so it can recover")
    }

    func testColdFailureCanRetryAndInvalidResourceNeverFetches() async throws {
        let server = NameServer(try response(["en": "Tackle"]))
        await server.setFailure(true)
        let client = PokemonNameClient(directory: nil, fetch: { try await server.fetch($0) })
        do { _ = try await client.names(for: resource); XCTFail("Expected network failure") } catch { }
        await server.setFailure(false)
        let recovered = try await client.names(for: resource)
        XCTAssertEqual(recovered["en"], "Tackle")
        for name in ["", "../move/tackle", "tackle?language=ko", "tackle/../../"] {
            do {
                _ = try await client.names(for: .init(kind: .move, name: name))
                XCTFail("Invalid resource must fail")
            } catch { }
        }
        let calls = await server.calls
        XCTAssertEqual(calls, 2)
    }

    func testResourceKindsDoNotCollideAndCorruptCacheRefetches() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("move-tackle.json"))
        let server = NameServer(try response(["en": "Tackle"]))
        let client = PokemonNameClient(directory: directory, fetch: { try await server.fetch($0) })
        _ = try await client.names(for: resource)
        _ = try await client.names(for: .init(kind: .ability, name: "tackle"))
        _ = try await client.names(for: .init(kind: .type, name: "tackle"))
        let calls = await server.calls
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testRenderedNamesResolveLanguageAndEnglishFallbackWithoutChangingKeys() throws {
        let ability = PokemonNameResource(kind: .ability, name: "overgrow")
        let type = PokemonNameResource(kind: .type, name: "grass")
        let maps = [resource: ["en": "Tackle", "ko": "몸통박치기", "ja-hrkt": "たいあたり", "es": "Placaje", "fr": "Charge", "de": "Tackle"],
                    ability: ["en": "Overgrow", "ko": "심록"], type: ["en": "Grass", "ko": "풀"]]
        let items = [PokemonNameItem(resource: ability), PokemonNameItem(resource: resource), PokemonNameItem(resource: type)]
        let korean = PokemonNameText(items: items, language: .ko, names: maps)
        XCTAssertEqual(korean.text, "심록 · 몸통박치기 · 풀")
        XCTAssertEqual(PokemonNameText(items: items, language: .pt, names: maps).text, "Overgrow · Tackle · Grass")
        XCTAssertEqual(PokemonNameText(items: items, language: .ko, names: [:]).text, "Overgrow · Tackle · Grass")
        let hidden = PokemonNameText(items: [.init(resource: ability, suffix: " (숨겨진 특성)")], language: .ko, names: maps)
        XCTAssertEqual(hidden.text, "심록 (숨겨진 특성)")
        XCTAssertEqual(items[0].resource.name, "overgrow", "Translated labels never replace persistent identifiers")
        for language in AppLanguage.allCases {
            let view = PokemonNameText(items: items, language: language, names: maps)
                .padding(16).frame(width: 320).foregroundStyle(.black).background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 640)
            XCTAssertGreaterThan(image.height, 40)
            if language == .ko, let path = ProcessInfo.processInfo.environment["PTB_NAMES_PREVIEW"] {
                let bitmap = NSBitmapImageRep(cgImage: image)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
