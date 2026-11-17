import AppKit
import Darwin

/// Keeps the earlier instance so an open popover or settings view survives a duplicate launch.
/// A legacy LaunchAgent can exec the binary directly during migration, bypassing LaunchServices.
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
