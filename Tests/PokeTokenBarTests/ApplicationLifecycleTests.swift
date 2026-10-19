import AppKit
import XCTest
@testable import PokeTokenBar

private final class ApplicationLifecycleTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testMainMenuPreservesEditingCommandsWithoutASettingsCommand() throws {
        let menu = PokeTokenBarApp.makeMainMenu()
        let editMenu = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })
        let expected: [(String, String, NSEvent.ModifierFlags)] = [
            ("undo:", "z", .command), ("redo:", "z", [.command, .shift]),
            ("cut:", "x", .command), ("copy:", "c", .command),
            ("paste:", "v", .command), ("selectAll:", "a", .command),
        ]
        let commands = editMenu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(commands.count, expected.count)
        for (item, command) in zip(commands, expected) {
            XCTAssertEqual(item.action.map(NSStringFromSelector), command.0)
            XCTAssertEqual(item.keyEquivalent, command.1)
            XCTAssertEqual(item.keyEquivalentModifierMask, command.2)
            XCTAssertNil(item.target, "editing actions must follow the active responder chain")
        }
        let allItems = menu.items + menu.items.flatMap { $0.submenu?.items ?? [] }
        XCTAssertFalse(allItems.contains { $0.keyEquivalent == "," })
        XCTAssertFalse(allItems.contains { $0.title.localizedCaseInsensitiveContains("settings") })
    }

    func testMainMenuKeyEquivalentSelectsAllInTheTextResponder() throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        let previousResponder = application.nextResponder
        let menu = PokeTokenBarApp.makeMainMenu()
        application.mainMenu = menu
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        editor.string = "settings input"
        // XCTest has no active application key window. Use the application's real responder
        // chain so menu items retain their production nil targets without changing desktop focus.
        application.nextResponder = editor
        XCTAssertTrue(application.target(forAction: #selector(NSText.selectAll(_:))) as? NSTextView === editor)
        defer {
            application.nextResponder = previousResponder
            application.mainMenu = previousMenu
        }

        editor.setSelectedRange(NSRange(location: 3, length: 0))
        menu.update()
        XCTAssertTrue(menu.performKeyEquivalent(with: try commandEvent("a")))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: editor.string.utf16.count))
    }

    func testReopenWithoutVisibleWindowsDoesNotRestoreAWindow() {
        let application = NSApplication.shared
        let delegate: any NSApplicationDelegate = AppDelegate()
        let window = makeWindow()
        defer { window.close() }
        window.orderOut(nil)
        let windowsBefore = Set(application.windows.map(ObjectIdentifier.init))

        // Finder/open can reopen an already running menu bar app with no visible windows.
        for _ in 0..<3 {
            XCTAssertEqual(
                delegate.applicationShouldHandleReopen?(application, hasVisibleWindows: false),
                false,
                "reopen must decline AppKit's default window handling")
            XCTAssertFalse(window.isVisible, "reopen must not restore a hidden window")
            XCTAssertEqual(Set(application.windows.map(ObjectIdentifier.init)), windowsBefore)
        }
    }

    func testReopenWithAVisibleWindowDoesNotCreateOrDismissWindows() {
        let application = NSApplication.shared
        let delegate: any NSApplicationDelegate = AppDelegate()
        let window = makeWindow()
        defer { window.close() }
        window.orderFrontRegardless()
        XCTAssertTrue(window.isVisible)
        let windowsBefore = Set(application.windows.map(ObjectIdentifier.init))

        // The floating pet can be visible when Finder/open sends another reopen request.
        XCTAssertEqual(
            delegate.applicationShouldHandleReopen?(application, hasVisibleWindows: true),
            false)
        XCTAssertTrue(window.isVisible, "existing user-visible surfaces must remain available")
        XCTAssertEqual(Set(application.windows.map(ObjectIdentifier.init)), windowsBefore)
    }

    private func makeWindow() -> NSWindow {
        let window = ApplicationLifecycleTestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 64, height: 64),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func commandEvent(_ key: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: key, charactersIgnoringModifiers: key,
            isARepeat: false, keyCode: 0))
    }
}
