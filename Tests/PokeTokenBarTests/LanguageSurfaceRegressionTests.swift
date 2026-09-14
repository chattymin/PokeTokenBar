import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

final class LanguageSurfaceRegressionTests: XCTestCase {
    @MainActor
    func testBackupTimestampUsesSelectedLanguageAndEveryLanguageRenders() throws {
        let date = Date(timeIntervalSince1970: 1_783_680_000)
        var images: [NSImage] = []
        for language in AppLanguage.allCases {
            let l = L(language)
            let formatter = DateFormatter()
            formatter.locale = language.displayLocale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let stamp = SettingsView.exportedAtText(date, language: language)
            XCTAssertEqual(stamp, formatter.string(from: date))
            let labels = [l.tokenInput, l.tokenOutput, l.tokenCacheWrite, l.tokenCacheRead,
                          l.website, l.sponsor, l.evolutionScrollPrevious, l.evolutionScrollNext,
                          l.moveMethod(.init(method: "light-ball-egg", level: 0)),
                          l.moveMethod(.init(method: "form-change", level: 0))]
            XCTAssertFalse(labels.contains(where: { $0.isEmpty }))
            XCTAssertFalse(labels.contains("light ball egg"))
            XCTAssertFalse(labels.contains("form change"))
            let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 6) {
                Text(language.label).bold()
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in Text(label) }
                Text(stamp)
            }.padding().frame(width: 332).background(.white).foregroundStyle(.black)
                .environment(\.locale, language.displayLocale))
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertGreaterThan(image.size.height, 100)
            images.append(image)
        }
        XCTAssertNotEqual(SettingsView.exportedAtText(date, language: .ko),
                          SettingsView.exportedAtText(date, language: .en))
        if let path = ProcessInfo.processInfo.environment["PTB_LANGUAGE_SURFACES_PREVIEW"] {
            let sheet = NSImage(size: NSSize(width: CGFloat(332 * images.count), height: 420))
            sheet.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: sheet.size).fill()
            for (index, image) in images.enumerated() {
                image.draw(at: NSPoint(x: CGFloat(index * 332), y: 420 - image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            sheet.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(sheet.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    func testVisibleCopyAndSettingsControlsAreRoutedToLocalization() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/SettingsView.swift"), encoding: .utf8)
        XCTAssertFalse(settings.contains("Picker(\"\""), "Hidden visual labels must retain accessible localized names")
        XCTAssertFalse(settings.contains("Toggle(\"\""), "Hidden visual labels must retain accessible localized names")
        XCTAssertFalse(settings.contains("footerLink(\"Web\""))
        XCTAssertFalse(settings.contains("footerLink(\"♥ Sponsor\""))
        let popover = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/PopoverView.swift"), encoding: .utf8)
        for label in ["in", "out", "cache w", "cache r"] {
            XCTAssertFalse(popover.contains("tokenTypeLabel(\"\(label)\""))
        }
        let companion = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/CompanionView.swift"), encoding: .utf8)
        XCTAssertTrue(companion.contains(".accessibilityLabel(forward ? L(language).evolutionScrollNext"))
    }
}
