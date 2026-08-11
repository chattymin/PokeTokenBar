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
/// # `open` 은 호출자의 환경변수를 안 넘긴다 — `--env` 로 하나씩 줘야 한다.
/// open --env PTB_SEED_RIBBON=lifelong --env PTB_SEED_SPECIES=25 -a "PokeDexBar Dev"
/// ```
///
/// 적용 여부는 `~/Library/Logs/PokeDexBarDev.log` 에 남는다 — 조용히 아무것도 안 하면
/// 변수를 못 받은 것인지 조건에 안 걸린 것인지 구분할 수가 없다.
///
/// **앱이 세이브에 개체를 넣는 시드는 두지 않는다.** 메타몽 위장을 만들 때 잠깐 뒀다가 걷어냈다 —
/// 켤 때마다 개체가 하나씩 쌓여 시험용 개체가 일곱 마리까지 늘었고, 봉인된 세이브라 밖에서 지울
/// 수도 없어 앱에 임시 제거 경로를 넣어야 했다. 리본처럼 **이미 있는 개체의 값만 올리는** 시드로
/// 족하다. 개체가 필요하면 테스트에서 `addForTesting` 을 쓴다.
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
        applyExpSeedFromEnvironment()
        guard let seed = DevSeed.parse(ProcessInfo.processInfo.environment) else { return }
        applyDevSeed(seed)
    }

    // MARK: 임시 — 알 발견 화면 확인용. 확인 끝나면 지운다.
    //
    /// `PTB_SEED_EXP` 가 있으면 대상 개체의 경험치를 그 값까지 **끌어올린다**(줄이지는 않는다).
    /// 알 발견은 5천만~4억 경험치가 있어야 보이는데, 그건 실제로는 며칠 치 토큰 사용량이다.
    /// 리본 시드와 같은 부류 — 이미 있는 개체의 값만 올린다.
    ///
    /// ```
    /// open --env PTB_SEED_EXP=500000000 -a "PokeDexBar Dev"
    /// open --env PTB_SEED_EXP=500000000 --env PTB_SEED_SPECIES=663 -a "PokeDexBar Dev"
    /// ```
    func applyExpSeedFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        guard let wanted = environment["PTB_SEED_EXP"].flatMap({ Int($0) }), wanted > 0 else { return }
        let species = environment["PTB_SEED_SPECIES"].flatMap { Int($0) }
        let targets = state.box.indices.filter { index in
            if let species { return state.box[index].speciesID == species }
            return state.box[index].id == state.partnerID
        }
        guard !targets.isEmpty else {
            AppLog.write("DevSeed: PTB_SEED_EXP=\(wanted) 이지만 대상 개체가 없다")
            return
        }
        mutate { state in
            for index in targets where state.box[index].exp < wanted {
                state.box[index].exp = wanted
            }
        }
        AppLog.write("DevSeed: \(targets.count)마리의 경험치를 \(wanted) 로 올렸다")
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
