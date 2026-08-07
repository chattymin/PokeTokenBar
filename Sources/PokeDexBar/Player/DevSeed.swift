import Foundation

/// 개발 빌드 전용 시드 — 시험용 상태를 만들 때 **세이브를 손으로 고치지 않기 위해** 있다.
///
/// 세이브는 봉인돼 있어(`SaveSeal`) 밖에서 고치면 앱이 영구히 `tampered` 로 표시하고 모든
/// 스프라이트를 뒤집는다. 그건 의도된 장치라 우회하면 안 되지만, 리본처럼 **시간으로만 열리는
/// 상태**는 확인하려면 며칠을 기다려야 한다. 그래서 앱이 *스스로* 쓰게 한다 — 저장은 정상
/// 봉인되고, 표시도 안 붙는다.
///
/// 이 경로는 `#if DEBUG` 안에만 있고, 개발 빌드(`PTB_DEV=1`)만 디버그 구성으로 짓는다
/// (`scripts/build-app.sh`). 정식 배포본에는 코드 자체가 없다.
///
/// ```
/// PTB_SEED_RIBBON=lifelong PTB_SEED_SPECIES=25 open -a "PokeDexBar Dev"
/// ```
struct DevSeed: Equatable, Sendable {
    let ribbon: Ribbon
    /// 대상 종. 비우면 지금 파트너에게 적용한다.
    let speciesID: Int?

    /// 환경변수 → 시드. 값이 없거나 못 알아들으면 nil(= 아무것도 안 한다).
    /// 순수 함수라 파싱을 테스트로 잠근다 — 앱 기동 경로는 xctest 로 못 밟는다.
    static func parse(_ environment: [String: String]) -> DevSeed? {
        guard let raw = environment["PTB_SEED_RIBBON"]?
            .trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let names: [String: Ribbon] = ["bond": .bond, "trust": .trust,
                                       "kinship": .kinship, "lifelong": .lifelong]
        guard let ribbon = names[raw] else { return nil }
        // 종 번호가 있으면 그 종에만. 숫자가 아니면 지정이 없는 것으로 본다(조용히 전부 바꾸는
        // 것보다 아무것도 안 하는 편이 낫지만, 리본 지정은 이미 명시적이므로 파트너로 떨어뜨린다).
        let species = environment["PTB_SEED_SPECIES"].flatMap { Int($0) }
        return DevSeed(ribbon: ribbon, speciesID: species)
    }
}

extension PlayerStore {
    #if DEBUG
    /// 환경변수에 시드가 있으면 적용한다. 기동 때 한 번 부른다.
    func applyDevSeedFromEnvironment() {
        guard let seed = DevSeed.parse(ProcessInfo.processInfo.environment) else { return }
        applyDevSeed(seed)
    }

    /// 대상 개체의 누적 파트너 시간을 그 리본의 문턱으로 끌어올린다. **줄이지는 않는다** —
    /// 이미 더 오래 함께한 개체의 기록을 시험 때문에 깎으면 안 된다.
    func applyDevSeed(_ seed: DevSeed) {
        let targets: [Int] = state.box.indices.filter { index in
            if let species = seed.speciesID { return state.box[index].speciesID == species }
            return state.box[index].id == state.partnerID
        }
        guard !targets.isEmpty else { return }
        let now = currentDate()
        mutate { state in
            for index in targets {
                let current = state.box[index].partnerDuration(at: now)
                let wanted = seed.ribbon.requiredPartnerSeconds
                guard current < wanted else { continue }
                state.box[index].partnerSeconds += wanted - current
            }
        }
    }
    #endif
}
