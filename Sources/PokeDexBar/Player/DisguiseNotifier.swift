import Foundation
import UserNotifications

/// 위장이 풀렸다는 알림. `HatchNotifier` 와 같은 모양이다 — 문구 조립은 순수 함수로 떼어
/// 테스트하고, 실제 발송은 번들 앱에서만 동작한다(xctest 로는 확인할 수 없다).
struct DisguiseNotifier: Sendable {
    /// 공개된 개체 → 알림 문구. 없으면 nil. 여럿이면 하나로 묶는다(알림 폭탄 방지).
    ///
    /// **개체를 받는다** — 부화 알림과 달리 확인 버튼이 없고, 공개는 이미 일어난 뒤라
    /// 무엇이었는지를 그대로 말해도 스포일러가 되지 않는다.
    static func message(for revealed: [Individual], language: AppLanguage) -> (title: String, body: String)? {
        guard !revealed.isEmpty else { return nil }
        let l = L(language)
        if revealed.count == 1, let one = revealed.first {
            return (l.notifDisguiseTitle, l.notifDisguiseBody(one.speciesID, shiny: one.shiny))
        }
        return (l.notifDisguiseTitle, l.notifDisguiseMultipleBody(revealed.count))
    }

    func notify(revealed: [Individual], language: AppLanguage) {
        guard AppEnv.isBundledApp,
              let message = Self.message(for: revealed, language: language) else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
