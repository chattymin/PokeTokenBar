import Foundation
import Network

/// 네트워크 연결 상태 모니터 — 오프라인에서 온라인으로 복구되는 순간을 감지해 자동 갱신을 트리거한다.
/// periodic timer(1~5분) 대기 없이 Wi-Fi 재연결, 네트워크 복구, 슬립 후 라우트 확립 시 즉각 갱신.
final class NetworkReachabilityMonitor: @unchecked Sendable {
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.poketokenbar.network-monitor", qos: .utility)
    private var lastStatus: NWPath.Status?
    var onReconnected: (@Sendable () -> Void)?

    init() {}

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let prev = self.lastStatus
            self.lastStatus = path.status
            if Self.shouldTriggerReconnect(from: prev, to: path.status) {
                AppLog.write("network reconnected — triggering refresh")
                self.onReconnected?()
            }
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastStatus = nil
    }

    deinit {
        monitor?.cancel()
    }

    /// 상태 전이 판정 — 콜드 스타트(첫 이벤트)는 무시하고, 오프라인이었다가 온라인으로 바뀔 때만 참.
    static func shouldTriggerReconnect(from prev: NWPath.Status?, to current: NWPath.Status) -> Bool {
        guard let prev else { return false }
        return prev != .satisfied && current == .satisfied
    }
}
