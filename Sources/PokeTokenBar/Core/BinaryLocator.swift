import Foundation

/// CLI 바이너리(codex, brew 등) 절대경로 탐색.
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
        // binary 를 위치 인자($1)로 전달 — 문자열 보간 금지(향후 호출자가 외부 입력을 넘겨도 주입 불가).
        guard let path = shellMarkedValue(
            script: #"printf '<<<BIN:%s:BIN>>>' "$(command -v "$1" 2>/dev/null)""#,
            argument: binary, label: "\(binary) shell resolve"),
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }

    /// 로그인+인터랙티브 셸을 띄워 마커로 감싼 값 하나를 받는다(`shellResolve`·`shellEnvironmentValue` 공용).
    ///
    /// stdout 은 프로세스 종료를 기다리기 **전에** 백그라운드로 드레인한다. 인터랙티브 프로파일이
    /// 파이프 버퍼(64KB)를 넘게 찍으면 자식이 write 에서 막혀 영영 종료하지 않고, 종료를 먼저 기다리는
    /// 구조에서는 타임아웃까지 통째로 날린 뒤 nil 을 돌려준다.
    private static func shellMarkedValue(script: String, argument: String, label: String) -> String? {
        shellMarkedOutput(script: script, arguments: [argument], label: label).flatMap(parseMarkedPath)
    }

    /// 셸을 띄워 stdout 을 통째로 돌려준다(마커 추출은 호출자 몫). 값을 **여러 개** 받는 스크립트는
    /// 마커가 여러 쌍이라 `parseMarkedPath`(첫 쌍만) 로는 못 읽으므로 원문이 필요하다.
    private static func shellMarkedOutput(script: String, arguments: [String], label: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", script, "sh"] + arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            AppLog.write("\(label) spawn failed: \(error.localizedDescription)")
            return nil
        }

        final class DataBox: @unchecked Sendable { var data = Data() }
        let box = DataBox()
        let drained = DispatchSemaphore(value: 0)
        let handle = output.fileHandleForReading
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()
            drained.signal()
        }

        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            try? handle.close()            // 리더 스레드 해제 — 안 닫으면 영구 블록된 채 남는다.
            AppLog.write("\(label) timed out")
            return nil
        }
        // 드레인은 **남은 예산 전체**를 준다. 셸이 종료해도 rc 가 띄운 백그라운드 잡(zsh-async·zinit turbo
        // 등)이 stdout write end 를 계속 쥐고 있으면 EOF 가 늦게 온다 — 여기에 짧은 별도 상한을 두면
        // 종료를 무한정 기다리던 이전 동작에서 값을 얻던 사용자가 nil 을 받는다(실측 회귀).
        let remaining = max(0, deadline.timeIntervalSinceNow)
        guard drained.wait(timeout: .now() + remaining) == .success else {
            try? handle.close()
            AppLog.write("\(label) output drain timed out")
            return nil
        }
        return String(data: box.data, encoding: .utf8)
    }

    /// 로그인 셸에서 환경변수 하나를 읽는다. Finder/launchd 로 뜬 `.app` 은 셸 환경(`~/.zshrc` 의
    /// export)을 상속하지 않아, 프로세스 환경만 보면 사용자가 설정한 값이 앱에서만 안 보인다.
    /// PATH 해석(`shellResolve`)과 같은 수법이며, 셸을 띄우는 비용이 있으므로 호출자가 결과를 캐시해야 한다.
    static func shellEnvironmentValue(_ name: String) -> String? {
        // 변수명은 ASCII 대문자·숫자·밑줄만 허용 — 셸 주입 방지.
        // `isUppercase`/`isNumber` 는 유니코드 기준이라 `Σ`·키릴 `А`·`٣` 도 통과한다. 셸 메타문자는
        // 아니라 실제 주입은 안 되지만, 가드가 선언한 범위와 실제 허용 범위를 일치시킨다.
        guard isShellSafeEnvironmentName(name) else { return nil }
        // 변수명은 위치 인자($1)로 넘기고 `eval` 은 그 이름의 값만 전개한다. 전개 결과는 재파싱되지
        // 않으므로 값에 셸 메타문자가 있어도 그대로 돌아온다(실측 확인).
        return shellMarkedValue(
            script: #"printf '<<<BIN:%s:BIN>>>' "$(eval printf '%s' \"\$$1\" 2>/dev/null)""#,
            argument: name, label: "\(name) shell env lookup")
    }

    /// 환경변수 **여러 개**를 셸 spawn **한 번**으로 읽는다. 이름마다 부르면 프로바이더가 늘수록
    /// 기동이 그만큼 느려진다(셸 조회 실측 ~0.44s × 이름 수). 미설정·빈 값은 결과에서 빠지므로
    /// 반환 딕셔너리에 키가 없는 것이 곧 "그 사용자는 이 변수를 안 쓴다"이다.
    static func shellEnvironmentValues(_ names: [String]) -> [String: String] {
        let safe = names.filter(isShellSafeEnvironmentName)
        guard !safe.isEmpty else { return [:] }
        // 이름은 전부 위치 인자로 넘기고 `$@` 로 순회한다 — 스크립트에 이름을 보간하지 않으므로
        // 단일 조회와 같은 주입 안전성을 유지한다. 마커에 이름을 함께 실어 값과 짝을 잃지 않게 한다.
        guard let raw = shellMarkedOutput(
            script: #"for n in "$@"; do printf '<<<BIN:%s:%s:BIN>>>' "$n" "$(eval printf '%s' \"\$$n\" 2>/dev/null)"; done"#,
            arguments: safe, label: "env batch lookup(\(safe.count))")
        else { return [:] }

        var out: [String: String] = [:]
        for name in safe {
            guard let value = parseMarkedValue(raw, name: name) else { continue }
            out[name] = value
        }
        return out
    }

    /// 셸 주입 방지 — ASCII 대문자·숫자·밑줄만.
    /// `isUppercase`/`isNumber` 는 유니코드 기준이라 `Σ`·키릴 `А`·`٣` 도 통과한다. 셸 메타문자는
    /// 아니라 실제 주입은 안 되지만, 가드가 선언한 범위와 실제 허용 범위를 일치시킨다.
    static func isShellSafeEnvironmentName(_ name: String) -> Bool {
        !name.isEmpty
            && name.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }
    }

    /// `<<<BIN:NAME:value:BIN>>>` 에서 `NAME` 의 값만 추출. 프로파일 noise 와 다른 이름의 쌍은 무시.
    /// 이름을 마커에 실어야 하는 이유: 인터랙티브 프로파일이 stdout 에 찍는 noise 가 쌍 사이에
    /// 섞여도 순서가 아니라 이름으로 짝을 찾을 수 있다.
    static func parseMarkedValue(_ s: String, name: String) -> String? {
        guard let start = s.range(of: "<<<BIN:\(name):"),
              let end = s.range(of: ":BIN>>>", range: start.upperBound..<s.endIndex)
        else { return nil }
        let value = s[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
