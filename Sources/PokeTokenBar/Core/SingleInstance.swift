import AppKit
import Darwin

/// 같은 앱이 두 번 뜨는 것을 막는 가드 — **나중에 뜬 인스턴스가 물러난다**.
///
/// 배경: 로그인 실행을 `SMAppService.agent`(LaunchAgent)로 등록하는데, plist 에 `RunAtLoad` 가 있어
/// **등록하는 순간 launchd 가 실행 파일을 한 번 더 실행한다**. 앱이 떠 있는 상태에서 등록이 일어나는
/// 경로가 둘이라, 둘 다 메뉴바 아이콘이 두 개가 된다:
///   1. 설정에서 "로그인 시 실행"을 켤 때 — `LoginItem.setEnabled(true)`
///   2. 구버전 로그인아이템 사용자의 업데이트 첫 기동 — `LoginItem.migrateFromLegacyLoginItemIfNeeded()`
/// 2번은 사용자가 아무것도 누르지 않아도 일어난다.
///
/// LaunchServices 의 중복 실행 방지는 GUI 로 여는 경로(Finder·`open`)에만 걸린다 — launchd 는
/// `Contents/MacOS/…` 를 직접 exec 하므로 그 경로를 타지 않는다. 그래서 앱이 스스로 막는다.
///
/// 물러나는 쪽을 나중에 뜬 인스턴스로 정한 이유는 사용자가 보고 있던 팝오버·설정 창을 유지하기 위해서다.
/// 그 종료는 정상 종료(exit 0)라 `KeepAlive.SuccessfulExit=false` 인 에이전트가 되살리지 않는다
/// (`UpdateChecker.applyUpdate` 가 이미 같은 성질에 기대고 있다).
///
/// **대가 — 크래시 자동 재실행이 그동안 꺼진다.** 물러나는 쪽이 곧 launchd 가 소유한 프로세스라,
/// 살아남는 인스턴스는 워치독 밖에 있다. 다음 로그인에 에이전트가 단독 실행하면서 복구되지만,
/// 메뉴바 앱은 로그아웃 없이 몇 주씩 도는 일이 흔해 **그 공백은 짧지 않다.** 반대로 먼저 뜬 쪽을
/// 물러나게 하면 워치독은 즉시 지켜진다(어느 쪽이 launchd 소유인지는 `launchDate == nil` 로 알 수 있다).
/// 그 대신 사용자가 토글을 누른 직후 창이 사라졌다 돌아와 크래시처럼 읽히고, 시작 시각을 못 읽거나
/// 같을 때 양쪽이 다 남는 지금과 달리 아무도 안 남는 경우가 생긴다 — 그래서 이쪽을 택했다.
enum SingleInstance {
    /// 나보다 먼저 시작한 같은 앱 인스턴스가 있으면 `true`(= 내가 물러난다).
    ///
    /// 시작 시각을 모르면 물러나지 않는다 — 중복 아이콘은 거슬리는 정도지만, 잘못 물러나면 사용자가
    /// 유일한 인스턴스를 잃는다. 시각이 같을 때도 같은 이유로 남는다(양쪽이 서로를 보고 함께 사라지는 것을
    /// 막는 쪽이 안전하다).
    static func shouldYield(myStartTime: Date?, otherStartTimes: [Date?]) -> Bool {
        guard let mine = myStartTime else { return false }
        return otherStartTimes.compactMap { $0 }.contains { $0 < mine }
    }

    /// 프로세스 시작 시각(커널 `p_starttime`).
    ///
    /// `NSRunningApplication.launchDate` 를 쓰지 않는다 — 그 값은 LaunchServices 가 띄운 프로세스에만
    /// 기록되고 **launchd 가 직접 exec 한 프로세스에선 계속 nil** 이다. 물러나야 할 쪽이 정확히 그
    /// 프로세스라, launchDate 로 판정하면 가드가 통째로 무효가 된다(실측: 로그인 에이전트가 띄운
    /// 인스턴스는 `launchDate == nil`, 같은 pid 의 `p_starttime` 은 정상). 커널 값은 두 경로 모두에
    /// 남고 프로세스 간 비교도 성립한다.
    static func processStartTime(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // `size > 0` 검사가 필수다 — 없는 pid 에 대해 sysctl 은 **실패하지 않고**(rc=0) 길이만 0 으로 둔다.
        // 그대로 두면 zero-init 된 `p_starttime`(=1970)이 "가장 먼저 뜬 인스턴스"로 읽혀 앱이 늘 물러난다.
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }

    /// 위 판정을 실제 실행 중인 인스턴스에 적용한다. 실앱에서만 동작한다 —
    /// `swift test`/로우 바이너리(dev 실행)는 번들이 아니라 항상 `false`(`AppEnv.isBundledApp`).
    @MainActor
    static func shouldYieldToRunningInstance() -> Bool {
        guard AppEnv.isBundledApp, let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)
            .filter { $0 != me }
            .map(processStartTime)
        return shouldYield(myStartTime: processStartTime(me), otherStartTimes: others)
    }
}
