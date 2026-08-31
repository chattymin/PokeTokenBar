import Foundation

/// 반복 상태 줄의 억제 판정 — 순수 상태 머신이라 픽스처로 테스트한다
/// (`AppLog.write` 는 `swift test` 에서 no-op 이라 파일로는 검증할 수 없다).
///
/// 왜 필요한가: 미설치 프로바이더는 폴마다 **같은 줄**을 남긴다. 실측(2026-08-30) 로그 9,093줄 중
/// `phase1 recv id=<미설치> today=nil err=none` 류가 507회씩 반복돼 60% 가량을 차지했다.
/// `AppLog` 는 2MB 에서 회전하므로 이 잡음이 실제 진단 이력을 밀어낸다 — 회전 주기가 짧아
/// "장애 직전 컨텍스트"가 사라지던 것이 이미 알려진 문제였다(AppLog.maxBytes 주석).
///
/// 억제하되 **상태 전이는 절대 놓치지 않는다**: 메시지가 달라지면 즉시 기록한다. 같은 상태가
/// 길게 이어져도 `repeatAfter` 마다 한 번은 남긴다 — 로그만 보고 "언제부터 이랬나"와
/// "지금도 그런가"를 구분할 수 있어야 한다.
struct LogRepeatSuppressor {
    private var lastWritten: [String: (message: String, at: Date)] = [:]

    /// 기록해야 하면 true 를 돌려주고 내부 상태를 갱신한다.
    /// - key: 같은 슬롯으로 볼 줄들의 식별자(예: `"phase1-recv-codex"`). 프로바이더별로 나눠야
    ///   한 프로바이더의 변화가 다른 프로바이더의 억제를 풀지 않는다.
    mutating func shouldWrite(key: String,
                              message: String,
                              now: Date = Date(),
                              repeatAfter: TimeInterval) -> Bool
    {
        guard let previous = lastWritten[key] else {
            lastWritten[key] = (message, now)
            return true                                  // 첫 관측은 항상 남긴다
        }
        if previous.message != message {
            lastWritten[key] = (message, now)
            return true                                  // 상태 전이 — 즉시 기록
        }
        if now.timeIntervalSince(previous.at) >= repeatAfter {
            lastWritten[key] = (message, now)
            return true                                  // 같은 상태의 주기적 확인
        }
        return false
    }
}
