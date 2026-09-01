import Foundation

/// 사용량 로그 위치를 가리키는, **사용자가 셸에 export 하는** 환경변수의 단일 조회 지점.
///
/// Finder/launchd 로 뜬 `.app` 은 로그인 셸 환경을 상속하지 않는다. 그래서 `~/.zshrc` 에
/// `export COPILOT_HOME=...` 를 써 둔 사용자는 CLI 에서는 정상인데 앱에서만 사용량이 비거나
/// 적게 나오고, 앱 안에는 그 사실을 알 방법도 고칠 방법도 없다. 프로바이더가 프로세스 환경만
/// 읽으면 그 상태가 조용히 유지된다.
///
/// 새 프로바이더가 위치 override 환경변수를 쓰면 **이름만 `names` 에 추가한다** — 조회는
/// 한 번의 셸 spawn 으로 묶이므로 프로바이더가 늘어도 기동 비용은 그대로다.
///
/// 여기 넣지 않는 것: 앱이 스스로 쓰는 값(`SHELL`, `PATH`)과 개발/QA 전용 override(`PTB_STATE_DIR`).
/// 그것들은 사용자가 셸에 export 해 두고 앱이 못 봐서 생기는 문제가 아니다.
enum UsageEnvironment {

    /// 셸 조회 대상. 프로바이더별 override 이름의 정본이다.
    static let names = [
        "CLAUDE_CONFIG_DIR",   // Claude CLI 설정 디렉터리(콤마로 다중)
        "OPENCODE_DATA_DIR",   // OpenCode 데이터 디렉터리
        "HERMES_HOME",         // Hermes 홈
        "COPILOT_HOME",        // Copilot CLI 홈
        "GROK_HOME",           // Grok CLI 홈
        "CLOUD_CODE_URL",      // Google CloudCode Quota API 엔드포인트 override
        "PI_CODING_AGENT_DIR", // pi config/session base directory
        "PI_CODING_AGENT_SESSION_DIR", // pi session directory override
        "CURSOR_SESSION_TOKEN", // Cursor dashboard API session override
        "CURSOR_USAGE_API",    // Cursor dashboard API disable switch (`0` = off)
        "KIRO_CLI_HOME",       // pre-2.20 Kiro SQLite home (kiro-cli)
        "KIRO_HOME",           // ~/.kiro — JSONL sessions live under <this>/sessions
        "CURSOR_DATA_DIR",     // Cursor user-data dir override
        "OMP_CODING_AGENT_DIR", // omp (oh-my-pi) config/session base directory
    ]

    /// `name` 의 값. 프로세스 환경이 우선이고, 없으면 로그인 셸에서 읽은 값을 쓴다.
    /// 빈 문자열은 미설정과 같게 취급한다(`export FOO=` 는 "여기 있다"가 아니다).
    static func value(_ name: String) -> String? { resolved[name] }

    /// 프로세스 생애 1회 조회. 환경변수는 앱이 도는 동안 바뀌지 않으므로 TTL 이 필요 없고,
    /// 못 찾은 결과도 캐시된다(`resolved` 에 키가 없는 것이 곧 negative 캐시) — 재시도하면
    /// 값을 안 쓰는 대다수 사용자가 갱신마다 셸 spawn 비용을 문다.
    /// `static let` 은 lazy + once 라 이 자체가 캐시이자 동기화다.
    private static let resolved: [String: String] = resolve(
        names: names,
        processEnvironment: ProcessInfo.processInfo.environment,
        shellLookup: BinaryLocator.shellEnvironmentValues)

    /// 조회 정책 본체 — 주입 가능하게 분리해 두 갈래를 테스트가 각각 밟는다:
    /// 프로세스 환경에 다 있으면 셸을 **안 띄운다**, 하나라도 없으면 없는 것만 모아 **한 번** 띄운다.
    /// 실제 셸 spawn 은 테스트에서 재현할 수 없으므로 이 분기를 검증하지 않으면
    /// "그냥 프로세스 환경만 읽던" 회귀가 전부 통과한다.
    static func resolve(
        names: [String],
        processEnvironment: [String: String],
        shellLookup: ([String]) -> [String: String]) -> [String: String]
    {
        var out: [String: String] = [:]
        var missing: [String] = []
        for name in names {
            // 빈 값(`export FOO=`)은 미설정과 같게 본다 — 있다고 보면 그 사용자는 존재하지 않는
            // 경로를 스캔하고 조용히 0 을 받는다.
            if let v = processEnvironment[name],
               !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out[name] = v
            } else {
                missing.append(name)
            }
        }
        // 대다수 사용자(터미널 실행·override 없음)는 여기서 끝난다 — 셸을 띄우지 않는다.
        guard !missing.isEmpty else { return out }

        for (name, value) in shellLookup(missing)
        where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out[name] = value
        }
        return out
    }
}
