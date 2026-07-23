#if os(Windows)
import Foundation
import WinSDK

/// Spawn a child process with **no console window** (`CREATE_NO_WINDOW`), stdio redirected to
/// files + a stdin pipe. `Foundation.Process` pops a console for console-subsystem children
/// (`codex.cmd`, `where.exe`) — that flashes a terminal AND steals focus, which dismissed the
/// popover. This Win32 spawn avoids the window entirely.
final class WindowsProcess {
    private var pi = PROCESS_INFORMATION()
    private var hStdinWrite: HANDLE?
    private(set) var launched = false

    /// `commandLine`: full command line (already quoted). stdout/stderr are created/truncated at the
    /// given paths; a stdin pipe is opened for `writeStdin`. Child inherits the parent environment.
    init?(commandLine: String, stdoutPath: String, stderrPath: String) {
        var sa = SECURITY_ATTRIBUTES()
        sa.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        sa.bInheritHandle = true

        guard let out = Self.createFile(stdoutPath, sa: &sa),
              let err = Self.createFile(stderrPath, sa: &sa) else { return nil }
        defer { CloseHandle(out); CloseHandle(err) }

        var readEnd: HANDLE?
        var writeEnd: HANDLE?
        guard CreatePipe(&readEnd, &writeEnd, &sa, 0), let readEnd, let writeEnd else { return nil }
        SetHandleInformation(writeEnd, DWORD(HANDLE_FLAG_INHERIT), 0)   // parent's write end: not inherited
        defer { CloseHandle(readEnd) }

        var si = STARTUPINFOW()
        si.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        si.dwFlags = DWORD(STARTF_USESTDHANDLES)
        si.hStdInput = readEnd
        si.hStdOutput = out
        si.hStdError = err

        var cmd = Array(commandLine.utf16) + [0]
        let ok = cmd.withUnsafeMutableBufferPointer { buf in
            CreateProcessW(nil, buf.baseAddress, nil, nil, true,
                           DWORD(CREATE_NO_WINDOW), nil, nil, &si, &pi)
        }
        guard ok else { CloseHandle(writeEnd); return nil }
        hStdinWrite = writeEnd
        launched = true
    }

    func writeStdin(_ data: Data) {
        guard let h = hStdinWrite else { return }
        var written: DWORD = 0
        _ = data.withUnsafeBytes { WriteFile(h, $0.baseAddress, DWORD($0.count), &written, nil) }
    }

    func closeStdin() {
        if let h = hStdinWrite { CloseHandle(h); hStdinWrite = nil }
    }

    var isRunning: Bool {
        var code: DWORD = 0
        guard GetExitCodeProcess(pi.hProcess, &code) else { return false }
        return code == 259   // STILL_ACTIVE
    }

    var exitCode: Int32 {
        var code: DWORD = 0
        _ = GetExitCodeProcess(pi.hProcess, &code)
        return Int32(bitPattern: code)
    }

    func terminate() { _ = TerminateProcess(pi.hProcess, 1) }

    /// Wait up to `seconds` for exit; returns true if it exited.
    func waitFor(_ seconds: Double) -> Bool {
        WaitForSingleObject(pi.hProcess, DWORD(seconds * 1000)) == WAIT_OBJECT_0
    }

    func cleanup() {
        closeStdin()
        if pi.hProcess != nil { CloseHandle(pi.hProcess) }
        if pi.hThread != nil { CloseHandle(pi.hThread) }
    }

    private static func createFile(_ path: String, sa: inout SECURITY_ATTRIBUTES) -> HANDLE? {
        var wpath = Array(path.utf16) + [0]
        let h = wpath.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_WRITE),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), &sa,
                        DWORD(CREATE_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        if h == INVALID_HANDLE_VALUE { return nil }
        return h
    }
}
#endif
