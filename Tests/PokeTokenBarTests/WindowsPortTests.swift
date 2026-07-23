#if os(Windows)
import XCTest
import WinSDK
@testable import PokeTokenBar

/// Windows-port unit tests — deterministic checks of the new Win32-facing helpers.
final class WindowsPortTests: XCTestCase {
    /// `rgb` must pack components as COLORREF 0x00BBGGRR (Win32 order), not RGB.
    func testRGBPacksBGROrder() {
        XCTAssertEqual(rgb(0x12, 0x34, 0x56), COLORREF(0x0056_3412))
        XCTAssertEqual(rgb(255, 0, 0), COLORREF(0x0000_00FF))   // red → low byte
        XCTAssertEqual(rgb(0, 0, 255), COLORREF(0x00FF_0000))   // blue → high byte
    }

    /// `String.wide` yields a NUL-terminated UTF-16 buffer for Win32 wide-string APIs.
    func testWideIsNulTerminatedUTF16() {
        XCTAssertEqual("Hi".wide, [72, 105, 0])
        XCTAssertEqual("".wide, [0])
        XCTAssertEqual("한".wide, [0xD55C, 0])   // BMP codepoint stays one UTF-16 unit
    }

    /// The autostart Run-key command points at this exe (quoted) and launches the tray.
    func testAutostartCommandFormat() {
        let cmd = WindowsAutostart.command
        XCTAssertTrue(cmd.hasPrefix("\""), "exe path must be quoted")
        XCTAssertTrue(cmd.hasSuffix("--tray"), "must launch the tray, got: \(cmd)")
    }

    /// Update tags (`win-2.4.5` / `v2.4.5` / `2.4.5`) normalize to a bare version, 4-segment included.
    func testUpdateTagNormalize() {
        XCTAssertEqual(WindowsUpdate.normalize("win-2.4.5"), "2.4.5")
        XCTAssertEqual(WindowsUpdate.normalize("v2.4.5"), "2.4.5")
        XCTAssertEqual(WindowsUpdate.normalize("2.4.5"), "2.4.5")
        XCTAssertEqual(WindowsUpdate.normalize("win-2.4.4.1"), "2.4.4.1")   // Windows MAJOR.MINOR.PATCH.WINFIX
    }

    /// Version compare is numeric (not lexical), strict, and handles the 4-segment Windows scheme
    /// (shorter side zero-padded, so `win-2.4.4` == `2.4.4.0` < `2.4.4.1`).
    func testUpdateIsNewer() {
        XCTAssertTrue(WindowsUpdate.isNewer("2.4.5", than: "2.4.4"))
        XCTAssertTrue(WindowsUpdate.isNewer("2.4.10", than: "2.4.9"))   // numeric, not "10" < "9"
        XCTAssertTrue(WindowsUpdate.isNewer("2.5.0", than: "2.4.99"))
        XCTAssertFalse(WindowsUpdate.isNewer("2.4.4", than: "2.4.4"))   // equal is not newer
        XCTAssertFalse(WindowsUpdate.isNewer("2.4.3", than: "2.4.4"))
        // 4-segment Windows build counter
        XCTAssertTrue(WindowsUpdate.isNewer("2.4.4.1", than: "2.4.4"))    // .1 beats the padded .0
        XCTAssertTrue(WindowsUpdate.isNewer("2.4.4.2", than: "2.4.4.1"))
        XCTAssertTrue(WindowsUpdate.isNewer("2.4.5.0", than: "2.4.4.9"))  // upstream base wins
        XCTAssertFalse(WindowsUpdate.isNewer("2.4.4", than: "2.4.4.1"))   // .0 is older than .1
        XCTAssertFalse(WindowsUpdate.isNewer("2.4.4.1", than: "2.4.4.1"))
    }
}
#endif
