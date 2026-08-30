import XCTest
@testable import PokeTokenBar

final class PhoneServerReconcilerTests: XCTestCase {
    /// 껐을 때 실제로 멈추는 것이 이 토글의 존재 이유다 — 여기가 leaveAsIs 로 새면 사용자는
    /// 껐다고 믿는 채로 LAN 에 계속 서빙된다.
    func testDisablingARunningServerStopsIt() {
        XCTAssertEqual(PhoneServerReconciler.action(enabled: false, isRunning: true), .stop)
    }

    func testEnablingAStoppedServerStartsIt() {
        XCTAssertEqual(PhoneServerReconciler.action(enabled: true, isRunning: false), .start)
    }

    /// 이미 맞는 상태면 아무것도 하지 않는다 — 매 관찰 틱마다 리스너를 재생성하면 폰의 연결이 끊긴다.
    func testAlreadyMatchingStatesAreLeftAlone() {
        XCTAssertEqual(PhoneServerReconciler.action(enabled: true, isRunning: true), .leaveAsIs)
        XCTAssertEqual(PhoneServerReconciler.action(enabled: false, isRunning: false), .leaveAsIs)
    }
}
