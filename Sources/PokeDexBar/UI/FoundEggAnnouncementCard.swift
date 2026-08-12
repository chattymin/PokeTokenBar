import SwiftUI

/// 홈에 뜨는 알 발견 알림 — 파트너가 알 임계를 채우면 그 개체가 알을 가져왔다고 알린다.
///
/// **왜 홈인가.** 경험치는 파트너에게만 쌓인다(`PlayerStore.update`) — 그래서 임계를 채우는
/// 개체는 사실상 파트너뿐이고, 예전에 박스 칸에 달았던 배지는 거의 안 일어나는 경우(파트너를
/// 바꾼 옛 개체가 슬쩍 임계를 채운 경우)만 커버하고 있었다. `DiscoveryCard`(파트너가 도구를
/// 물어 왔다는 알림)가 이미 홈의 파트너 카드 바로 아래에 있으므로, 알 발견도 같은 자리에 두면
/// 눌렀을 때 알이 그 아래 부화 슬롯 줄에 떨어지는 걸 그 자리에서 볼 수 있다.
///
/// **상세 화면과 문구가 다른 이유.** `L.eggFound` (상세)는 "~의 알이 발견되었어요" — 그 개체
/// 자신의 진행을 말한다. 여기 `L.partnerFoundEgg` 는 "~의 알을 가져왔어요" — 파트너가 지금
/// 이 화면에 서서 건네주는 장면이다. 둘 다 자기 자리에서는 자연스럽고, 뜻이 겹친다고 하나로
/// 합치지 않는다.
///
/// **`DiscoveryCard` 와 같은 패턴을 쓴다:** 자기 자신의 조건으로 나타났다 사라지고(빈 카드가
/// 상주하지 않는다), `#if DEBUG` 레코더로 "홈이 실제로 이 뷰를 만드는지"를 테스트가 확인한다.
struct FoundEggAnnouncementCard: View {
    let store: PlayerStore
    /// 지금 데리고 다니는 개체. 없으면(이론상 스타터를 고르면 항상 있다) 카드도 없다.
    let partner: Individual?
    /// 파트너의 진화 라인. 발견되는 알의 종 이름(`speciesName`)을 읽는 데 필요한데 네트워크에서
    /// 비동기로 온다 — 아직 없으면 판단 자체를 보류한다(`PopoverView.showsEvolutionBadge` 와
    /// 같은 원칙: 모르면 아무것도 보여주지 않는다).
    let line: EvoLine?

    #if DEBUG
    /// 매 렌더마다 "지금 뜨나"를 기록한다 — `DiscoveryCard.constructed` 와 같은 패턴.
    /// 뜨지 않을 때도 기록되므로, 이 배열이 비어 있지 않다는 것만으로 "홈이 이 뷰를 만들긴
    /// 했다"(도달성)를 확인할 수 있다. 실제로 보이는지는 값(`true`/`false`)으로 잰다.
    @MainActor static var bodyEvaluations: [Bool] = []
    /// 실제로 뜬 버튼만 기록한다 — `DetailActionButton`/`CandyButton` 과 같은 패턴. 제목·활성
    /// 여부·눌렀을 때의 동작까지 담아 두어야 "버튼이 있다"를 넘어 "눌렀을 때 실제로 알을
    /// 받는다"까지 테스트가 잠글 수 있다.
    @MainActor static var constructed: [(name: String, canTake: Bool, action: () -> Void)] = []
    @MainActor static func resetConstructed() {
        bodyEvaluations = []
        constructed = []
    }
    #endif

    private var l: L { store.l }

    /// 위장 중이 아니고 라인이 있으면 후보다. **더 이상 최종형일 필요가 없다** — `eggProgress`
    /// 가 `exp` 와 분리된 뒤로는 진화 중인 개체도 알을 부를 수 있다(`canTakeFoundEgg` 와 같은
    /// 판단). 상세 화면의 `IndividualDetailView.isFoundEggCandidate` 도 지금은 같은 조건이지만,
    /// 그쪽은 `individual: Individual`(항상 있음)을, 이 카드는 `partner: Individual?`(옵셔널 —
    /// 파트너가 없을 수 있다)을 다뤄야 해서 술어를 각자 둔다.
    private var isCandidate: Bool {
        guard let partner, line != nil else { return false }
        return partner.disguisedAs == nil
    }

    /// 후보이고 알 계량기가 알 임계를 채웠으면 카드가 뜬다. **빈 슬롯 여부는 안 본다** —
    /// 그건 카드가 뜨느냐가 아니라 버튼이 활성이냐만 가른다(상세 화면과 같은 구분).
    private var isReady: Bool {
        guard let partner else { return false }
        return isCandidate && partner.eggProgress >= ExpBalance.eggThreshold(grade: partner.grade)
    }

    /// 발견되는 알의 종 이름 — **baseID**(원종) 기준. 리자몽 파트너가 알리는 건 파이리 알이다.
    private var speciesName: String {
        guard let partner, let line else { return "" }
        return line.localizedName(partner.baseID, store.language)
    }

    var body: some View {
        #if DEBUG
        let _ = { Self.bodyEvaluations.append(isReady) }()
        #endif
        if isReady, let partner, let line {
            let canTake = store.canTakeFoundEgg(partner, line: line)
            #if DEBUG
            let _ = { Self.constructed.append(
                (speciesName, canTake, { store.takeFoundEgg(individualID: partner.id, line: line) })) }()
            #endif
            VStack(alignment: .leading, spacing: 3) {
                // **누를 곳에 배경이 있어야 버튼으로 읽힌다.** 처음엔 바깥 상자에만 옅은 색을
                // 깔고 버튼은 투명하게 뒀는데, 그러면 알림 카드로 보이고 눌러 볼 생각이 안 든다
                // (사용자 지적). 이 앱의 "누르는 것" 관례는 `DetailActionButton(prominent:)` —
                // accent 로 꽉 찬 배경 · 흰 굵은 글씨 · 전폭 — 이라 그쪽에 맞춘다.
                Button {
                    store.takeFoundEgg(individualID: partner.id, line: line)
                } label: {
                    // 기호는 안 붙인다 — SF Symbols 에 알이 없어 `oval.fill` 을 썼더니 알이
                    // 아니라 글머리 점으로 읽혔다. 문장이 이미 "알" 이라고 말한다.
                    Text(l.partnerFoundEgg(speciesName))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                // 빈 슬롯이 없으면 숨기지 않고 비활성으로 둔다(상세 화면과 같은 규칙) —
                // `.disabled` 만으로는 안 보여서 `.opacity` 를 더한다(이 파일들의 공통 관례).
                .disabled(!canTake)
                .opacity(canTake ? 1 : 0.55)
                if !canTake {
                    Text(l.eggFoundNoFreeSlot).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
