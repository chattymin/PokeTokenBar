import AppKit
import Observation

/// GitHub 릴리스 최신 버전을 확인해 새 버전이 있으면 팝오버에 알린다.
/// 실제 설치는 brew 사용자면 `brew upgrade`, 그 외엔 릴리스 페이지 열기(저위험·인프라 0).
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable { let version: String; let url: String }

    private(set) var available: Available?
    private(set) var isUpdating = false

    let currentVersion: String
    private let repo = "chattymin/PokeTokenBar"
    private let clock: () -> Date
    private var lastChecked: Date?

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
    }

    /// 최신 릴리스 조회 → 새 버전이고 사용자가 그 버전을 'skip' 하지 않았으면 available 설정.
    /// minInterval 보다 자주 호출되면 무시(레이트리밋 보호).
    func check(minInterval: TimeInterval = 1800) async {
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        lastChecked = clock()
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              // 응답 필드가 NSWorkspace.open 으로 가므로 https + github.com 만 허용(스킴 하이재킹 방지)
              let htmlURL = URL(string: html), htmlURL.scheme == "https", htmlURL.host == "github.com"
        else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        if Self.isNewer(latest, than: currentVersion), latest != skipped {
            available = Available(version: latest, url: html)
        } else {
            available = nil
        }
    }

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: "skippedUpdateVersion") }
        available = nil
    }

    /// 업데이트 적용: brew cask 설치본이면 `brew upgrade` 후 재시작, 아니면 릴리스 페이지.
    func applyUpdate() {
        guard let update = available, !isUpdating else { return }
        isUpdating = true
        Task { @MainActor in
            // brew cask 설치본이면 분리(detached) 스크립트가 앱 종료 후 tap 갱신→업그레이드→재오픈.
            // 그 외(brew 미설치/비-cask 설치)면 릴리스 페이지를 연다.
            let brew = await Task.detached { Self.brewCaskPath() }.value
            if let brew {
                Self.launchDetachedUpgrade(brew: brew)
                NSApp.terminate(nil)
            } else {
                isUpdating = false
                AppLog.write("update: brew cask 아님/brew 미설치 → 릴리스 페이지 열기")
                if let u = URL(string: update.url) { NSWorkspace.shared.open(u) }
            }
        }
    }

    // MARK: 버전 비교

    /// a 가 b 보다 높은 semver 인가. ("2.0.10" > "2.0.9" 등 숫자 비교)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: brew 적용 (nonisolated — 블로킹 Process 는 detached 에서)

    /// poke-token-bar 가 brew cask 로 설치돼 있으면 brew 경로 반환, 아니면 nil(→ 릴리스 페이지 폴백).
    private nonisolated static func brewCaskPath() -> String? {
        guard let brew = BinaryLocator.resolve("brew", staticPaths: [
            "/opt/homebrew/bin/brew", "/usr/local/bin/brew",
        ]) else { return nil }
        return run(brew, ["list", "--cask", "poke-token-bar"], timeout: 20) ? brew : nil
    }

    private nonisolated static func run(_ binary: String, _ args: [String], timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }

    /// 앱이 완전히 종료된 뒤 tap 갱신 + cask 업그레이드 + 재오픈을 수행하는 분리(detached) 스크립트 본문.
    /// - `brew update` 선행: auto-update 빈도 제한(기본 24h)으로 stale 한 로컬 tap 때문에 `brew upgrade`
    ///   가 no-op(exit 0) 되어 "업데이트 안 됨 + 앱만 종료"가 나던 문제를 막는다.
    /// - 앱 종료를 기다림(`kill -0 $3`): 실행 중 번들 교체 레이스 + 재오픈 LaunchServices(-600) 레이스 회피.
    ///   `pgrep -x` 대신 특정 PID를 감시하여 중복 인스턴스가 실행 중일 때도 20s 타임아웃 없이 즉시 진행 (#175).
    /// - brew 를 백그라운드+워치독(≤300s)으로 감싸 hang 시에도 reopen 이 반드시 실행되게 함
    ///   (앱이 종료된 채 영영 안 돌아오는 것 방지). 종료 직후 재오픈 실패 대비 `open` 재시도.
    /// 인자는 positional($1=brew, $2=bundlePath, $3=pid)로 전달 — 셸 인젝션 차단.
    nonisolated static let detachedUpgradeScript = """
    for i in $(seq 1 40); do kill -0 "$3" 2>/dev/null || break; sleep 0.5; done
    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    ( "$1" update; "$1" upgrade --cask poke-token-bar ) &
    brew_pid=$!
    for i in $(seq 1 300); do kill -0 "$brew_pid" 2>/dev/null || break; sleep 1; done
    kill "$brew_pid" 2>/dev/null
    for i in $(seq 1 15); do
      launchctl kickstart -k "gui/$(id -u)/io.github.chattymin.poketokenbar.login" 2>/dev/null && break
      open "$2" 2>/dev/null && break
      sleep 1
    done
    """

    nonisolated static func launchDetachedUpgrade(
        brew: String,
        pid: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundlePath: String = Bundle.main.bundlePath
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", detachedUpgradeScript, "sh", brew, bundlePath, String(pid)]
        try? task.run()
    }
}
