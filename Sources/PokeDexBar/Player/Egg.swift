import Foundation

/// 부화 중인 알. 종과 이로치 여부는 **뽑는 순간** 정해 두고(스프라이트를 미리 받으려고)
/// 부화 때 공개한다.
struct Egg: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var grade: Grade
    var speciesID: Int
    var shiny: Bool
    var startedAt: Date
    var hatchesAt: Date

    func isReady(at now: Date) -> Bool { now >= hatchesAt }

    /// 남은 시간. 이미 지났으면 0 — 음수가 화면에 새지 않게.
    func remaining(at now: Date) -> TimeInterval {
        max(0, hatchesAt.timeIntervalSince(now))
    }

    /// 신뢰경계(디코드)의 값 범위 검증 — 관대 디코딩과 반드시 짝으로 온다(CLAUDE.md 결함 대응 프로토콜).
    /// 관대 디코딩은 한 필드가 깨져도 나머지를 지키는 대신 **말이 안 되는 값도 통과시킨다**:
    /// `hatchesAt: 1e300` 은 디코드에 *성공*하므로 `load()` 의 손상 복구가 발동하지 않고, 그 뒤
    /// 카운트다운의 `Int(remaining.rounded(.up))` 이 변환 트랩으로 프로세스를 죽인다 — 재기동해도
    /// 같은 파일을 다시 읽어 또 죽어서, 파일을 손으로 지우기 전엔 앱을 쓸 수 없다.
    /// 방어는 다운스트림 산술 지점마다가 아니라 값이 들어오는 이 한 곳에서 한다.
    /// 알 자체는 버리지 않는다(데이터 손실) — 산술에 쓰이는 시각만 자른다.
    func sanitized() -> Egg {
        var egg = self
        egg.startedAt = Self.clampDate(startedAt)
        // 부화는 시작보다 이를 수 없고, 아무리 늦어도 시작 + 최장 등급 시간이다.
        let longest = Grade.allCases.map(EggBalance.duration).max() ?? 0
        egg.hatchesAt = min(max(Self.clampDate(hatchesAt), egg.startedAt),
                            egg.startedAt.addingTimeInterval(longest))
        return egg
    }

    /// 저장분에서 받아들일 시각 범위의 상한(2200-01-01). 하한은 유닉스 원년.
    /// 실사용 값은 늘 이 안이고 밖은 손상·조작이다.
    private static let latestValidSeconds: TimeInterval = 7_258_118_400

    private static func clampDate(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        // NaN·무한대는 비교가 전부 false 라 min/max 로는 못 거른다 — 먼저 걸러낸다.
        guard seconds.isFinite else { return Date(timeIntervalSince1970: 0) }
        return Date(timeIntervalSince1970: min(max(seconds, 0), latestValidSeconds))
    }
}
