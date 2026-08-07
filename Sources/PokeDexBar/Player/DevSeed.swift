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
/// PTB_SEED_DITTO=1        open -a "PokeDexBar Dev"   # 위장한 메타몽을 파트너로
/// PTB_SEED_DITTO=570      open -a "PokeDexBar Dev"   # 이미 570초 함께한 상태로(30초 뒤 풀림)
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
        seedDisguisedDittoIfRequested(ProcessInfo.processInfo.environment)
        guard let seed = DevSeed.parse(ProcessInfo.processInfo.environment) else { return }
        applyDevSeed(seed)
    }

    /// 위장한 메타몽을 파트너로 넣는다 — `PTB_SEED_DITTO` 가 있을 때만.
    ///
    /// 이게 없으면 이 이스터에그를 눈으로 확인하는 데 커먼 알 1/128 과 파트너 10분이 필요하다.
    /// 값에 숫자를 주면 그만큼 이미 함께한 것으로 시작한다(`PTB_SEED_DITTO=570` → 30초 뒤 풀림).
    /// 이미 위장한 개체를 데리고 있으면 아무것도 하지 않는다 — 켤 때마다 늘어나면 박스가 찬다.
    func seedDisguisedDittoIfRequested(_ environment: [String: String]) {
        guard let raw = environment["PTB_SEED_DITTO"]?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw != "0" else { return }
        guard !state.box.contains(where: { $0.disguisedAs != nil }) else { return }
        let now = currentDate()
        var ditto = Individual(baseID: DittoDisguise.speciesID, speciesID: DittoDisguise.speciesID,
                               pathIDs: [DittoDisguise.speciesID], nature: .naughty,
                               obtainedAt: now, grade: .common)
        ditto.disguisedAs = DittoDisguise.disguisedAs
        // 숫자를 줬으면 그만큼 이미 함께한 상태로 시작한다. 문턱을 넘겨 주지는 않는다 —
        // 기동하자마자 풀려 버리면 정작 위장한 모습을 못 본다.
        ditto.partnerSeconds = min(Int(raw) ?? 0, DittoDisguise.revealSeconds - 1)
        mutate { state in state.box.append(ditto) }
        // **`partnerID` 를 직접 넣으면 안 된다.** `setPartner` 는 같은 개체를 다시 지정하면
        // 조기 반환하므로 `partnerSince` 가 안 잡히고, 그러면 함께한 시간이 영영 안 흘러
        // 위장이 절대 안 풀린다. 정상 경로로만 지정한다.
        setPartner(ditto.id)
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
