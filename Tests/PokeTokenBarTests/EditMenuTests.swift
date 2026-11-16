import AppKit
import XCTest
@testable import PokeTokenBar

/// ⌘V pasted nothing in the session key's field: an accessory app has no Edit menu for the key to go through.
@MainActor
final class EditMenuTests: XCTestCase {
    func testTheEditMenuCarriesTheTextShortcuts() throws {
        let items = EditMenu.make().items.flatMap { $0.submenu?.items ?? [] }
        func item(_ action: Selector) throws -> NSMenuItem { try XCTUnwrap(items.first { $0.action == action }, "\(action)") }
        XCTAssertEqual(try item(#selector(NSText.paste(_:))).keyEquivalent, "v")
        XCTAssertEqual(try item(#selector(NSText.copy(_:))).keyEquivalent, "c")
        XCTAssertEqual(try item(#selector(NSText.cut(_:))).keyEquivalent, "x")
        XCTAssertEqual(try item(#selector(NSText.selectAll(_:))).keyEquivalent, "a")
        XCTAssertEqual(try item(Selector(("undo:"))).keyEquivalent, "z")
        XCTAssertEqual(try item(Selector(("redo:"))).keyEquivalentModifierMask, [.command, .shift])
        XCTAssertTrue(items.allSatisfy { $0.isSeparatorItem || $0.keyEquivalentModifierMask.contains(.command) })
    }

    /// ⌘V finds Paste in the app's main menu once installed (none before: the key went nowhere), and Paste fills a
    /// secure field being edited, as the session key's is. A test process is never the active app, so the key's
    /// way to the field is AppKit's, checked in two steps rather than by stealing the focus.
    func testCommandVFindsPasteAndPasteFillsASecureField() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        app.mainMenu = nil
        EditMenu.install(on: app)
        let menu = try XCTUnwrap(app.mainMenu)
        let editItems: [NSMenuItem] = menu.items.flatMap { item -> [NSMenuItem] in item.submenu?.items ?? [] }
        let commandV: NSMenuItem? = editItems.first { item in
            item.keyEquivalent == "v" && item.keyEquivalentModifierMask == NSEvent.ModifierFlags.command
        }
        XCTAssertEqual(commandV?.action, #selector(NSText.paste(_:)))
        EditMenu.install(on: app)
        XCTAssertEqual(app.mainMenu?.items.count, 1, "installed once")

        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 60), styleMask: .titled,
                              backing: .buffered, defer: false)
        let field = NSSecureTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer { pasteboard.clearContents(); if let saved { pasteboard.setString(saved, forType: .string) } }
        pasteboard.clearContents()
        pasteboard.setString("sk-ant-sid01-test", forType: .string)
        let editor = try XCTUnwrap(window.firstResponder as? NSText)
        XCTAssertTrue(editor.tryToPerform(try XCTUnwrap(commandV?.action), with: commandV))
        XCTAssertEqual(editor.string, "sk-ant-sid01-test")
    }

    /// SwiftUI swaps the app's main menu for its own, without Paste, once the popover's content shows up.
    func testThePopoverShowingBringsPasteBack() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        view.submenu = NSMenu(title: "View")
        view.submenu?.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        let swiftUIMenu = NSMenu(title: "Main")
        swiftUIMenu.addItem(view)
        app.mainMenu = swiftUIMenu

        AppDelegate().popoverDidShow(Notification(name: NSPopover.didShowNotification))

        let items = app.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
        XCTAssertEqual(items.first { $0.keyEquivalent == "v" && $0.keyEquivalentModifierMask == .command }?.action,
                       #selector(NSText.paste(_:)))
    }
}
