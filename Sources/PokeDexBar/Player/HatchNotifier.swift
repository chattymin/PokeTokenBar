import Foundation
import UserNotifications

/// 부화 알림. 문구 조립은 순수 함수로 떼어 테스트한다(실제 발송은 번들 앱에서만 동작해
/// xctest 로는 확인할 수 없다 — UsageStore 의 한도 알림과 같은 분리 패턴).
struct HatchNotifier: Sendable {
    /// 부화 결과 → 알림 문구. 아무것도 안 깼으면 nil. 여러 개면 하나로 묶는다(알림 폭탄 방지).
    /// 이로치는 놓치면 아까운 정보라 문구에서 티가 나야 한다.
    static func message(for hatched: [Individual], language: AppLanguage) -> (title: String, body: String)? {
        guard !hatched.isEmpty else { return nil }
        let l = L(language)
        if hatched.count == 1, let one = hatched.first {
            return (l.notifHatchTitle, l.notifHatchSingleBody(one.speciesID, shiny: one.shiny))
        }
        let shinyCount = hatched.count { $0.shiny }
        return (l.notifHatchTitle, l.notifHatchMultipleBody(hatched.count, shinyCount: shinyCount))
    }

    /// 실제 발송 — 번들 앱에서만 동작(AppEnv.isBundledApp). 알림 권한은 UsageStore 가 팝오버 첫 오픈
    /// 시점에 이미 요청한다(한도 알림과 같은 OS 권한을 공유하므로) — 여기서 별도 요청 플로우를 새로
    /// 만들지 않는다.
    func notify(hatched: [Individual], language: AppLanguage) {
        guard AppEnv.isBundledApp, let message = Self.message(for: hatched, language: language) else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
