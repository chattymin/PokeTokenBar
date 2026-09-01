import XCTest
import Network
@testable import PokeTokenBar

final class NetworkReachabilityTests: XCTestCase {

    func testColdStartDoesNotTriggerReconnect() {
        // 앱 첫 기동 시 initial satisfied 이벤트는 재연결이 아니므로 트리거하지 않아야 함
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: nil, to: .satisfied))
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: nil, to: .unsatisfied))
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: nil, to: .requiresConnection))
    }

    func testAlreadySatisfiedDoesNotTriggerReconnect() {
        // 이미 온라인 상태에서 추가 satisfied 이벤트 수신 시 중복 발화 방지
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .satisfied, to: .satisfied))
    }

    func testOfflineTransitions() {
        // 오프라인 유지 상태
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .unsatisfied, to: .unsatisfied))
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .requiresConnection, to: .requiresConnection))
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .satisfied, to: .unsatisfied))

        // 오프라인/연결필요 상태에서 온라인(satisfied)으로 복구된 순간 -> 참
        XCTAssertTrue(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .unsatisfied, to: .satisfied))
        XCTAssertTrue(NetworkReachabilityMonitor.shouldTriggerReconnect(from: .requiresConnection, to: .satisfied))
    }

    func testMonitorLifecycleAndCallback() {
        final class Box: @unchecked Sendable {
            var value = false
        }
        let box = Box()
        let monitor = NetworkReachabilityMonitor()
        monitor.onReconnected = {
            box.value = true
        }

        // 콜백 설정 확인
        monitor.onReconnected?()
        XCTAssertTrue(box.value)

        // start & stop 라이프사이클
        monitor.start()
        monitor.start() // 중복 start 방어
        monitor.stop()
        monitor.stop() // 중복 stop 방어
    }
}
