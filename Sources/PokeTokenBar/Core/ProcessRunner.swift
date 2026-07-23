import Foundation

enum RunnerError: Error, CustomStringConvertible {
    case timeout(String)
    case nonZeroExit(Int32, String)
    case missingResponse(String)
    case rpcError(String)

    var description: String {
        switch self {
        case .timeout(let bin): return "timeout: \(bin)"
        case .nonZeroExit(let code, let bin): return "exit \(code): \(bin)"
        case .missingResponse(let bin): return "missing JSON-RPC response: \(bin)"
        case .rpcError(let message): return "JSON-RPC error: \(message)"
        }
    }
}

/// Process 실행 지점은 이 파일 하나로 제한한다.
/// 현재 유일한 용도는 Codex app-server rate-limit read(JSON-RPC) — usage 집계는 로컬 로그 직파싱.
enum ProcessRunner {
    /// newline-delimited JSON-RPC 서버에 요청을 보내고 특정 id의 `result` JSON만 반환.
    /// Codex app-server가 stdout에 로그/notification을 섞어 내보낼 수 있어 line 단위로 필터링한다.
    static func runJSONRPC(
        binary: String,
        arguments: [String],
        inputLines: [String],
        responseID: Int,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        #if os(Windows)
        // Use a CREATE_NO_WINDOW spawn so the codex console child doesn't flash a terminal / steal
        // focus (which was dismissing the popover). Foundation.Process can't suppress the window.
        return try await runJSONRPCNoWindow(
            binary: binary, arguments: arguments, inputLines: inputLines,
            responseID: responseID, timeout: timeout)
        #else
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poketokenbar-\(UUID().uuidString).jsonl")
        let errURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poketokenbar-\(UUID().uuidString).stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.qualityOfService = .userInitiated   // Darwin-only power hint
        // GUI 앱의 최소 PATH 로는 mise/asdf shim 이 버전매니저 본체를 못 찾아 exit 1
        // (버그 리포트 실측) — 버전매니저/Homebrew(또는 npm/scoop/winget) 경로를 보강해 전달.
        process.environment = BinaryLocator.augmentedEnvironment(binaryPath: binary)
        let stdoutHandle = try FileHandle(forWritingTo: outURL)
        defer { try? stdoutHandle.close() }
        // stderr 는 버리지 않고 파일로 받아 실패 시 로그에 tail 을 남긴다(원격 진단용).
        let stderrHandle = try FileHandle(forWritingTo: errURL)
        defer { try? stderrHandle.close() }
        let stdinPipe = Pipe()
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.standardInput = stdinPipe
        var stdinClosed = false
        func closeStdin() {
            guard !stdinClosed else { return }
            stdinPipe.fileHandleForWriting.closeFile()
            stdinClosed = true
        }
        defer {
            closeStdin()
            if process.isRunning { process.terminate() }
        }

        do {
            try process.run()
        } catch {
            throw error
        }

        let payload = inputLines.joined(separator: "\n") + "\n"
        // 자식이 stdin 을 읽기 전에 조기 종료하면 broken pipe. non-throwing write 는 (Unix에서)
        // SIGPIPE 로 앱 전체를 죽인다 → throwing API + try? 로 EPIPE 를 삼킨다(앱 기동 시 SIG_IGN 도 설치).
        // write 가 실패해도 아래 폴링이 종료/타임아웃으로 처리하므로 무해.
        try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(payload.utf8))

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let raw = (try? Data(contentsOf: outURL)) ?? Data()
            if let response = try Self.jsonRPCResultData(in: raw, responseID: responseID) {
                return response
            }
            if !process.isRunning {
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        // 프로세스 종료 직전 flush 분이 마지막 in-loop read 보다 늦게 도착할 수 있어
        // 최종 1회 재read (정상 종료 시 유효 응답이 파일에 있는데 놓치던 레이스 방지).
        if let response = try Self.jsonRPCResultData(
            in: (try? Data(contentsOf: outURL)) ?? Data(), responseID: responseID) {
            return response
        }

        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    #if canImport(Darwin)
                    kill(process.processIdentifier, SIGKILL)
                    #else
                    process.terminate()   // Windows: TerminateProcess (no POSIX kill/SIGKILL)
                    #endif
                }
            }
            logStderrTail(errURL, binary: binary)
            throw RunnerError.timeout(binary)
        }
        if process.terminationStatus != 0 {
            logStderrTail(errURL, binary: binary)
            throw RunnerError.nonZeroExit(process.terminationStatus, binary)
        }
        logStderrTail(errURL, binary: binary)
        throw RunnerError.missingResponse(binary)
        #endif
    }

    #if os(Windows)
    /// Windows JSON-RPC spawn with `CREATE_NO_WINDOW` (no console flash). Same polling contract as
    /// the Foundation.Process path: feed stdin, poll the stdout file for the response id, terminate
    /// on timeout. `.cmd`/`.bat` (npm shims) are routed via `cmd.exe /c`; the child inherits the
    /// parent env (the tray already has the user PATH, so no augmentation needed here).
    private static func runJSONRPCNoWindow(
        binary: String, arguments: [String], inputLines: [String],
        responseID: Int, timeout: TimeInterval
    ) async throws -> Data {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poketokenbar-\(UUID().uuidString).jsonl")
        let errURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poketokenbar-\(UUID().uuidString).stderr")
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        func quote(_ s: String) -> String { "\"\(s)\"" }
        let lower = binary.lowercased()
        let commandLine: String
        if lower.hasSuffix(".cmd") || lower.hasSuffix(".bat") {
            let comspec = ProcessInfo.processInfo.environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
            commandLine = ([quote(comspec), "/c", quote(binary)] + arguments).joined(separator: " ")
        } else {
            commandLine = ([quote(binary)] + arguments).joined(separator: " ")
        }

        guard let proc = WindowsProcess(commandLine: commandLine,
                                        stdoutPath: outURL.path, stderrPath: errURL.path),
              proc.launched else {
            throw RunnerError.nonZeroExit(-1, binary)
        }
        defer { proc.cleanup() }

        proc.writeStdin(Data((inputLines.joined(separator: "\n") + "\n").utf8))
        proc.closeStdin()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let raw = (try? Data(contentsOf: outURL)) ?? Data()
            if let response = try Self.jsonRPCResultData(in: raw, responseID: responseID) {
                return response
            }
            if !proc.isRunning { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if let response = try Self.jsonRPCResultData(
            in: (try? Data(contentsOf: outURL)) ?? Data(), responseID: responseID) {
            return response
        }
        if proc.isRunning {
            proc.terminate()
            logStderrTail(errURL, binary: binary)
            throw RunnerError.timeout(binary)
        }
        if proc.exitCode != 0 {
            logStderrTail(errURL, binary: binary)
            throw RunnerError.nonZeroExit(proc.exitCode, binary)
        }
        logStderrTail(errURL, binary: binary)
        throw RunnerError.missingResponse(binary)
    }
    #endif

    /// 실패 경로에서 stderr 마지막 300자를 로그로 — "exit 1" 만으로는 원인 규명이 불가능했던
    /// 버그 리포트 재발 방지. 성공 경로에서는 호출하지 않는다(로그 소음 방지).
    private static func logStderrTail(_ url: URL, binary: String) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppLog.write("stderr [\(URL(fileURLWithPath: binary).lastPathComponent)]: \(String(trimmed.suffix(300)))")
    }

    private static func jsonRPCResultData(in raw: Data, responseID: Int) throws -> Data? {
        guard let text = String(data: raw, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            guard let id = object["id"] as? NSNumber, id.intValue == responseID else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "\(error)"
                throw RunnerError.rpcError(message)
            }
            guard let result = object["result"] else { continue }
            guard JSONSerialization.isValidJSONObject(result) else { return nil }
            return try JSONSerialization.data(withJSONObject: result, options: [])
        }
        return nil
    }
}
