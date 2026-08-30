import Foundation

/// 원격 한도 endpoint 의 최소 조회 간격.
///
/// 사용량 스캔 주기(`refreshInterval`, 1~15분)는 **로컬 파일 읽기**를 위한 값인데, 한도 조회가 같은
/// 틱에 묶여 있어서 그 설정이 그대로 외부 endpoint 호출 빈도가 됐다. 2분으로 두자 실측으로 429 가
/// 반복됐다(`claude limits rate-limited: backing off 300s`, 2026-08-30). 사용자는 "사용량을 자주
/// 갱신"을 고른 것이지 "비공식 endpoint 를 자주 두드림"을 고른 게 아니다.
///
/// 429 백오프(`applyLimitsBackoffIfRateLimited`)와는 역할이 다르다 — 백오프는 이미 맞고 나서
/// 물러나는 사후 대응이고, 이 게이트는 애초에 그 빈도로 두드리지 않게 하는 사전 조건이다. 둘은 겹쳐서 쓴다.
enum LimitsPollCadence {
    /// 5분. 한도 창(5시간·주간)은 이보다 훨씬 느리게 움직이고, UI 의 stale 기준(`claudeLimitsStale`,
    /// 15분)보다 넉넉히 짧아 "오래된 값" 표시를 유발하지 않는다.
    ///
    /// 값의 출처는 OpenCode Go 가 먼저 쓰던 `opencodeGoPollInterval` 이다 — 그 엔드포인트는 3-table
    /// join 이고 공식 캐시 헤더/폴링 가이드가 없어(anomalyco/opencode#16513 리뷰 지적) 실패 사용자도
    /// 최대 12 req/h 로 묶으려고 5분을 골랐다. 같은 근거가 나머지 원격 한도에도 그대로 적용된다.
    static let minimumInterval: TimeInterval = 300

    /// 마지막 **시도** 기준이다(성공 아님). rate limit 은 요청 수를 세지 성공 수를 세지 않으므로,
    /// 실패한 요청도 간격에 포함해야 게이트가 의미를 갖는다.
    static func shouldFetch(lastAttemptAt: Date?,
                            now: Date = Date(),
                            minimumInterval: TimeInterval = minimumInterval) -> Bool
    {
        guard let lastAttemptAt else { return true }   // 첫 조회는 항상 통과(기동 직후 빈 화면 방지)
        return now.timeIntervalSince(lastAttemptAt) >= minimumInterval
    }
}
