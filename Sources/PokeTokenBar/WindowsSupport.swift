#if os(Windows)
import Foundation
import WinSDK

// Shared Win32 helpers for the tray + popup UI.

extension String {
    /// UTF-16, NUL-terminated buffer for Win32 wide-string APIs.
    var wide: [UInt16] { Array(utf16) + [0] }
}

/// COLORREF (0x00BBGGRR) from 0–255 components — the `RGB` macro doesn't import into Swift.
func rgb(_ r: Int, _ g: Int, _ b: Int) -> COLORREF {
    COLORREF(r & 0xFF) | (COLORREF(g & 0xFF) << 8) | (COLORREF(b & 0xFF) << 16)
}
#endif
