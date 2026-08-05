import Foundation

/// CLI 바이너리(ccusage, codex 등) 절대경로 탐색.
/// GUI 앱(launchd 실행)은 사용자 셸 PATH 를 상속하지 않아, Homebrew 외 버전매니저
/// (mise/nvm/fnm/asdf/volta/bun)로 설치한 도구를 하드코딩 경로만으로는 못 찾는다.
/// 전략: 수동 지정(UserDefaults "<binary>Path") → 정적 경로(빠름) → 로그인+인터랙티브 셸 PATH 해석.
/// 바이너리별로 1회 캐시(셸 호출 비용 회피).
enum BinaryLocator {
    private static let lock = NSLock()
    private struct Cached { let path: String?; let at: Date }
    private nonisolated(unsafe) static var cache: [String: Cached] = [:]
    /// 미탐지(nil) 캐시 재해석 주기 — 상주 앱이 실행 중 codex 설치 시 반영. 성공 캐시는 영구(경로 소멸 시만 재해석).
    private static let notFoundTTL: TimeInterval = 600

    /// `binary` 의 절대경로(없으면 nil). 스레드 세이프, 1회 해석 후 캐시.
    /// `staticPaths`: 셸 해석 전에 먼저 확인할 알려진 설치 경로.
    static func resolve(_ binary: String, staticPaths: [String]) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[binary] {
            if let path = hit.path {
                // stale 방어 — 해석 후 앱 삭제/교체(Codex.app 업데이트 등)로 경로 소멸 시 재해석.
                if FileManager.default.isExecutableFile(atPath: path) { return path }
                AppLog.write("\(binary) cached path gone, re-resolving: \(path)")
            } else if Date().timeIntervalSince(hit.at) < notFoundTTL {
                return nil   // 최근 미탐지 — TTL 내엔 셸 resolve 비용 회피
            }
            // else: 미탐지 캐시가 TTL 지남 → 재해석(그새 설치됐을 수 있음)
        }
        let result = locate(binary, staticPaths: staticPaths)
        cache[binary] = Cached(path: result, at: Date())
        AppLog.write(result.map { "\(binary) resolved: \($0)" } ?? "\(binary) NOT found on PATH")
        return result
    }

    /// 자식 프로세스용 PATH 보강 — GUI 앱의 최소 PATH 로는 mise/asdf shim 이 내부에서
    /// 버전매니저 본체(mise 등)를 못 찾아 exit 1 로 죽는다(버그 리포트 실측).
    /// 해석된 바이너리의 디렉토리 + 버전매니저/Homebrew 공통 경로를 기존 PATH 앞에 붙인다.
    static func augmentedEnvironment(binaryPath: String,
                                     base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var paths = [URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path]
        paths.append(contentsOf: commonToolDirectories())
        for entry in (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":") {
            paths.append(String(entry))
        }
        var seen = Set<String>()
        let merged = paths.filter { seen.insert($0).inserted }.joined(separator: ":")
        var env = base
        env["PATH"] = merged
        return env
    }

    /// 설정 변경/재탐지 시 캐시 무효화.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    /// 버전매니저/패키지매니저 공통 bin·shim 디렉토리 — 탐색(commonNodeToolPaths)과
    /// 자식 프로세스 PATH 보강(augmentedEnvironment)이 공유하는 단일 소스.
    /// 새 버전매니저 지원 시 여기 한 곳만 추가하면 두 경로 모두에 반영된다.
    static func commonToolDirectories() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",                 // Homebrew (Apple Silicon)
            "/usr/local/bin",                    // Homebrew (Intel) / npm prefix
            "\(home)/.local/share/mise/shims",   // mise (shims 모드)
            "\(home)/.asdf/shims",               // asdf
            "\(home)/.volta/bin",                // Volta
            "\(home)/.bun/bin",                  // Bun
            "\(home)/.npm-global/bin",           // npm prefix=~/.npm-global
            "\(home)/.local/bin",
            "/usr/bin",
        ]
    }

    /// 버전매니저 공통 shim/bin 경로 + 주어진 정적 경로. (절대경로 우선 탐색용)
    static func commonNodeToolPaths(_ binary: String) -> [String] {
        commonToolDirectories().map { "\($0)/\(binary)" }
    }

    private static func locate(_ binary: String, staticPaths: [String]) -> String? {
        let fm = FileManager.default
        // 0) 사용자 수동 지정
        if let override = UserDefaults.standard.string(forKey: "\(binary)Path"),
           !override.isEmpty, fm.isExecutableFile(atPath: override) {
            return override
        }
        // 1) 정적 경로 (서브프로세스 없이 빠르게)
        if let hit = staticPaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // 2) 로그인+인터랙티브 셸 PATH 해석 (mise activate / nvm / fnm 등은 .zshrc 에서 PATH 주입)
        return shellResolve(binary)
    }

    /// 사용자 로그인 셸을 인터랙티브+로그인으로 띄워 `command -v <binary>` 결과를 받는다.
    /// 인터랙티브 프로파일이 stdout 에 noise(neofetch 등)를 찍을 수 있어 마커로 감싸 추출한다.
    private static func shellResolve(_ binary: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // binary 를 위치 인자($1)로 전달 — 문자열 보간 금지(향후 호출자가 외부 입력을 넘겨도 주입 불가).
        process.arguments = ["-ilc", #"printf '<<<BIN:%s:BIN>>>' "$(command -v "$1" 2>/dev/null)""#, "sh", binary]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            AppLog.write("\(binary) shell resolve spawn failed: \(error.localizedDescription)")
            return nil
        }
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            AppLog.write("\(binary) shell resolve timed out")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8),
              let path = parseMarkedPath(raw),
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    /// `<<<BIN:/path/to/tool:BIN>>>` 에서 경로만 추출. 프로파일 noise 무시.
    static func parseMarkedPath(_ s: String) -> String? {
        guard let start = s.range(of: "<<<BIN:"),
              let end = s.range(of: ":BIN>>>", range: start.upperBound..<s.endIndex) else {
            return nil
        }
        let path = s[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
