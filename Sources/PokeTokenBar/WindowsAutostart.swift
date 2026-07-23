#if os(Windows)
import Foundation
import WinSDK

/// Start-at-login via the HKCU Run registry key — the Windows counterpart of the macOS
/// `SMAppService` login item. Value `PokeTokenBar` = "<exe path>" --tray.
enum WindowsAutostart {
    private static let subKey = #"Software\Microsoft\Windows\CurrentVersion\Run"#
    private static let valueName = "PokeTokenBar"
    private static var hkcu: HKEY? { HKEY(bitPattern: 0x8000_0001) }   // HKEY_CURRENT_USER

    /// Absolute path to this exe (GetModuleFileNameW), quoted + `--tray`.
    static var command: String {
        var buf = [UInt16](repeating: 0, count: 1024)
        let n = GetModuleFileNameW(nil, &buf, DWORD(buf.count))
        let path = n > 0 ? String(decoding: buf[0..<Int(n)], as: UTF16.self) : "PokeTokenBar.exe"
        return "\"\(path)\" --tray"
    }

    static func isEnabled() -> Bool { readValue() != nil }

    @discardableResult
    static func enable() -> Bool {
        guard let key = openRunKey(write: true) else { return false }
        defer { RegCloseKey(key) }
        var value = command.wide
        let bytes = DWORD(value.count * MemoryLayout<UInt16>.size)
        let status = value.withUnsafeBufferPointer { p in
            p.baseAddress!.withMemoryRebound(to: BYTE.self, capacity: Int(bytes)) { bp in
                RegSetValueExW(key, valueName.wide, 0, DWORD(REG_SZ), bp, bytes)
            }
        }
        return status == ERROR_SUCCESS
    }

    @discardableResult
    static func disable() -> Bool {
        guard let key = openRunKey(write: true) else { return false }
        defer { RegCloseKey(key) }
        let status = RegDeleteValueW(key, valueName.wide)
        return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND
    }

    static func toggle() { if isEnabled() { disable() } else { enable() } }

    // MARK: registry helpers

    private static func openRunKey(write: Bool) -> HKEY? {
        var key: HKEY?
        let access = DWORD(write ? KEY_SET_VALUE | KEY_QUERY_VALUE : KEY_QUERY_VALUE)
        let status = RegOpenKeyExW(hkcu, subKey.wide, 0, REGSAM(access), &key)
        return status == ERROR_SUCCESS ? key : nil
    }

    private static func readValue() -> String? {
        guard let key = openRunKey(write: false) else { return nil }
        defer { RegCloseKey(key) }
        var size: DWORD = 0
        guard RegQueryValueExW(key, valueName.wide, nil, nil, nil, &size) == ERROR_SUCCESS, size > 0
        else { return nil }
        var buf = [UInt16](repeating: 0, count: Int(size) / MemoryLayout<UInt16>.size + 1)
        let status = buf.withUnsafeMutableBufferPointer { p -> LSTATUS in
            var sz = size
            return p.baseAddress!.withMemoryRebound(to: BYTE.self, capacity: Int(sz)) { bp in
                RegQueryValueExW(key, valueName.wide, nil, nil, bp, &sz)
            }
        }
        guard status == ERROR_SUCCESS else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF16.self)
    }
}
#endif
