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

    func testFlappingCooldownSuppression() {
        let baseDate = Date(timeIntervalSince1970: 1000)
        let cooldown: TimeInterval = 5.0

        // 첫 번째 재연결 성공 (lastTriggeredAt = nil) -> 트리거
        XCTAssertTrue(NetworkReachabilityMonitor.shouldTriggerReconnect(
            from: .unsatisfied,
            to: .satisfied,
            lastTriggeredAt: nil,
            now: baseDate,
            cooldown: cooldown
        ))

        // 2초 뒤 flapping으로 다시 unsatisfied -> satisfied 전환 발생 시 쿨다운에 의해 억제
        let flappingDate = baseDate.addingTimeInterval(2.0)
        XCTAssertFalse(NetworkReachabilityMonitor.shouldTriggerReconnect(
            from: .unsatisfied,
            to: .satisfied,
            lastTriggeredAt: baseDate,
            now: flappingDate,
            cooldown: cooldown
        ))

        // 6초 뒤 정상 재연결 -> 쿨다운 경과로 정상 트리거
        let recoveredDate = baseDate.addingTimeInterval(6.0)
        XCTAssertTrue(NetworkReachabilityMonitor.shouldTriggerReconnect(
            from: .unsatisfied,
            to: .satisfied,
            lastTriggeredAt: baseDate,
            now: recoveredDate,
            cooldown: cooldown
        ))
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

    func testConcurrentStartAndStop() {
        let monitor = NetworkReachabilityMonitor()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if i % 2 == 0 {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
        monitor.stop()
    }
}
