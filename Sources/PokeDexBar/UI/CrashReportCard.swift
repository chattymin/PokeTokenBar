import SwiftUI

/// 홈에 뜨는 크래시 알림 — 직전 세션이 예기치 않게 끝났으면 제보를 권한다.
///
/// **이것이 없으면 진단 기능 전체가 아무 일도 안 한다.** 빵부스러기와 마지막 크래시 기록이
/// 아무리 잘 쌓여도, 사용자가 스스로 설정에 들어가 "문제 제보"를 누를 이유가 없다. 메뉴바 앱은
/// 조용히 사라졌다 다시 켜질 뿐이다. 끊긴 자리를 잇는 것이 이 카드의 유일한 일이다.
///
/// **`FoundEggAnnouncementCard`·`DiscoveryCard` 와 같은 자리·같은 패턴을 쓴다** — 이 앱은 이미
/// "알릴 것이 생기면 홈에 카드" 라는 관례를 갖고 있으므로 새 언어를 만들지 않는다. 자기 조건으로
/// 나타났다 사라지고, `#if DEBUG` 레코더로 배선을 잠근다.
///
/// **알림(Notification)은 안 쓴다.** 이 앱은 부화·위장 해제로 이미 알림을 보내고 있어 거기에
/// 크래시까지 얹으면 알림 자체를 꺼 버릴 이유가 된다. 그리고 크래시 제보는 급한 일이 아니다 —
/// 다음에 팝오버를 열 때 보이면 충분하다.
struct CrashReportCard: View {
    let store: PlayerStore
    let version: String

    /// 다시 그리기 위한 방아쇠. 버튼을 누르면 올려서 `LastCrash` 를 다시 읽게 한다 —
    /// 파일이 진실의 원천이고 이 값은 그것을 보러 가라는 신호일 뿐이다.
    @State private var revision = 0

    #if DEBUG
    /// 뜨지 않을 때도 기록된다 — 배열이 비어 있지 않다는 것만으로 "홈이 이 뷰를 만들긴 했다"를
    /// 확인할 수 있다(`FoundEggAnnouncementCard.bodyEvaluations` 와 같은 패턴).
    @MainActor static var bodyEvaluations: [Bool] = []
    /// 실제로 뜬 카드만. **동작까지 들고 있는다** — 뷰만 만들고 안 누르면 배선이 끊겨 있어도
    /// 통과하기 때문이다.
    @MainActor static var constructed: [(report: () -> Void, dismiss: () -> Void)] = []
    @MainActor static func resetConstructed() {
        bodyEvaluations = []
        constructed = []
    }
    #endif

    private var l: L { store.l }

    /// 기록이 있고 아직 확인 전이면 뜬다. 순수 판정이라 테스트로 잠근다.
    nonisolated static func shouldShow(_ record: LastCrashRecord?) -> Bool {
        guard let record else { return false }
        return !record.acknowledged
    }

    var body: some View {
        // `revision` 을 읽어 이 본문이 버튼 누름에 반응하게 한다.
        let record = { _ = revision; return LastCrash.load() }()
        let visible = Self.shouldShow(record)
        #if DEBUG
        let _ = { Self.bodyEvaluations.append(visible) }()
        #endif
        if visible {
            #if DEBUG
            let _ = { Self.constructed.append((report, dismiss)) }()
            #endif
            VStack(alignment: .leading, spacing: 3) {
                Text(l.crashCardTitle).font(.system(size: 11, weight: .semibold))
                Text(l.crashCardBody).font(.system(size: 9)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button(action: report) {
                        Text(l.crashCardReport)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Button(action: dismiss) {
                        Text(l.close)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 5).padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                }
                if let error { Text(error).font(.system(size: 9)).foregroundStyle(.orange)
                    .textSelection(.enabled) }
            }
        }
    }

    @State private var error: String?

    private func report() {
        // 실패해도 확인 처리는 `openIssue` 안에서 이미 됐다 — 브라우저를 못 열었을 뿐이고,
        // 주소를 띄워 줬으므로 같은 카드로 다시 조를 이유가 없다.
        error = ProblemReport.openIssue(version: version, player: store, l: l)
        revision += 1
    }

    private func dismiss() {
        LastCrash.acknowledge()
        revision += 1
    }
}
