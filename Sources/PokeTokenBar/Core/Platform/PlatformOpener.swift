import Foundation

#if os(macOS)
import AppKit
#endif

/// Opening URLs and files — LaunchServices on macOS, xdg-open on Linux.
enum PlatformOpener {
    /// Open a URL with the default handler (release page, mailto, …); `true` if it opened.
    /// Callers validate the scheme before calling (`UpdateChecker`'s https + github.com allowlist).
    ///
    /// Only one caller needs the result — "report a problem". If no mail handler exists it has to
    /// show the address instead, and swallowing the outcome would leave the user pressing a button
    /// that does nothing.
    @discardableResult
    static func open(_ url: URL) -> Bool {
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        return launch("/usr/bin/xdg-open", [url.absoluteString])
        #endif
    }

    /// Reveal a file in the file manager, selected ("show log file").
    static func reveal(_ fileURL: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        #else
        // The freedesktop interface Dolphin and Nautilus implement, which opens the folder with
        // the file *selected*. On desktops that do not implement it gdbus fails and we fall back
        // to opening the parent directory — no selection, but the user can still find the file,
        // which beats nothing opening at all.
        let ok = launch("/usr/bin/gdbus", [
            "call", "--session",
            "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1",
            "--method", "org.freedesktop.FileManager1.ShowItems",
            "[\"\(fileURL.absoluteString)\"]", "",
        ])
        if !ok { launch("/usr/bin/xdg-open", [fileURL.deletingLastPathComponent().path]) }
        #endif
    }

    #if !os(macOS)
    /// Launch an external handler and **wait for it** — xdg-open returns immediately and gdbus
    /// finishes quickly, so there is no blocking cost, and it lets gdbus's exit status drive the
    /// fallback decision.
    @discardableResult
    private static func launch(_ binary: String, _ arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
    #endif
}
