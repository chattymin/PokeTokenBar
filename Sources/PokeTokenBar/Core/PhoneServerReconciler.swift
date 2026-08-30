import Foundation

/// 설정(`phoneServerEnabled`)과 실제 리스너 상태를 맞추는 전이 판정.
///
/// 토글은 즉시 반영돼야 한다 — "껐는데 다음 실행까지 계속 서빙"은 보안 설정에서 최악의 형태다
/// (사용자는 껐다고 믿는다). 반대로 이미 맞는 상태에서 start/stop 을 다시 부르면 리스너를
/// 불필요하게 재생성하므로, 두 방향 모두 판정해서 필요한 전이만 수행한다.
enum PhoneServerReconciler {
    enum Action: Equatable {
        case start
        case stop
        case leaveAsIs
    }

    static func action(enabled: Bool, isRunning: Bool) -> Action {
        switch (enabled, isRunning) {
        case (true, false): return .start
        case (false, true): return .stop
        case (true, true), (false, false): return .leaveAsIs
        }
    }
}
