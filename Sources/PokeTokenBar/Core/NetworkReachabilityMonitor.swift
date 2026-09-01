import Foundation
import Network

/// 네트워크 연결 상태 모니터 — 오프라인에서 온라인으로 복구되는 순간을 감지해 자동 갱신을 트리거한다.
/// periodic timer(1~5분) 대기 없이 Wi-Fi 재연결, 네트워크 복구, 슬립 후 라우트 확립 시 즉각 갱신.
final class NetworkReachabilityMonitor: @unchecked Sendable {
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.poketokenbar.network-monitor", qos: .utility)
    private let lock = NSLock()
    private var lastStatus: NWPath.Status?
    private var lastTriggeredAt: Date?
    private let cooldown: TimeInterval
    private let clock: @Sendable () -> Date

    var onReconnected: (@Sendable () -> Void)?

    init(cooldown: TimeInterval = 5.0, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.cooldown = cooldown
        self.clock = clock
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path.status)
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
        lastStatus = nil
    }

    deinit {
        stop()
    }

    private func handlePathUpdate(_ status: NWPath.Status) {
        lock.lock()
        let prev = lastStatus
        lastStatus = status
        let now = clock()
        let shouldTrigger = Self.shouldTriggerReconnect(
            from: prev,
            to: status,
            lastTriggeredAt: lastTriggeredAt,
            now: now,
            cooldown: cooldown
        )
        if shouldTrigger {
            lastTriggeredAt = now
        }
        let callback = onReconnected
        lock.unlock()

        if shouldTrigger {
            AppLog.write("network reconnected — triggering refresh")
            callback?()
        }
    }

    /// 상태 전이 판정 — 콜드 스타트(첫 이벤트)는 무시하고, 오프라인이었다가 온라인으로 바뀔 때만 참.
    /// 네트워크 인터페이스 flapping(단시간 반복 토글) 방지를 위해 cooldown 체크 적용.
    static func shouldTriggerReconnect(
        from prev: NWPath.Status?,
        to current: NWPath.Status,
        lastTriggeredAt: Date? = nil,
        now: Date = Date(),
        cooldown: TimeInterval = 5.0
    ) -> Bool {
        guard let prev else { return false }
        guard prev != .satisfied && current == .satisfied else { return false }
        if let lastTriggeredAt, now.timeIntervalSince(lastTriggeredAt) < cooldown {
            return false
        }
        return true
    }
}
