import SwiftUI

/// "피카츄가 도구를 3개 물어 왔어요" — 홈에 뜨는 발견 알림.
///
/// **흐름을 막지 않는다.** 도구는 이미 가방에 들어가 있고 이 카드는 알려 주기만 한다. 눌러서
/// 확인하면 사라지고, 확인이 늦어도 잃는 게 없다(`Discovery` 주석 참고 — 채집은 토큰으로 돌기
/// 때문에 확인을 문턱으로 두면 실제로 일한 사람이 손해를 본다).
///
/// 알 부화 카드처럼 `.sheet`/`.alert` 을 쓰지 않는다 — transient 팝오버가 닫힐 때 고아 시트가
/// 남아 이후 클릭을 먹통내는 결함이 있다(`PopoverView` 주석). 펼침은 전부 인라인이다.
struct DiscoveryCard: View {
    let store: PlayerStore
    /// 종 번호 → 이름. 진화 라인에서 오므로 아직 못 받았으면 nil 이고, 그때는 #번호로 적는다.
    let name: (Int) -> String?

    @State private var opened = false

    #if DEBUG
    /// 홈 탭이 이 카드를 **실제로 만드는지** 테스트가 확인할 수 있게 생성 기록을 남긴다.
    /// 카드만 따로 렌더하는 테스트는 홈에서 떼어내도 통과한다(실측).
    @MainActor static var constructed: [Int] = []
    @MainActor static func resetConstructed() { constructed = [] }
    #endif

    private var l: L { store.l }

    var body: some View {
        let finds = store.pendingDiscoveries
        #if DEBUG
        let _ = { Self.constructed.append(finds.count) }()
        #endif
        if !finds.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { opened = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: opened ? "shippingbox" : "shippingbox.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(Self.headline(finds, l: l, name: name))
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        if !opened {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(opened)

                if opened {
                    ForEach(Array(Self.names(finds, l: l).enumerated()), id: \.offset) { index, text in
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle").font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text(text).font(.system(size: 10))
                            Spacer()
                        }
                        // 하나씩 드러난다 — 상자를 열어 보는 느낌을 주되 기다리게 하지는 않는다.
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.08), value: opened)
                    }
                    Button(l.discoveryAcknowledge) {
                        store.acknowledgeDiscoveries()
                        opened = false
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 카드 제목. 물어 온 개체가 하나면 이름을 부르고, 여럿이면 마리 수로 말한다 —
    /// 파트너를 바꿔 가며 며칠 안 열어 본 경우가 그렇다.
    nonisolated static func headline(_ finds: [Discovery], l: L, name: (Int) -> String?) -> String {
        let species = Set(finds.map(\.speciesID))
        guard species.count == 1, let only = species.first else {
            return l.discoveryFoundBySeveral(species.count, finds.count)
        }
        return l.discoveryFoundBy(name(only) ?? "#\(only)", finds.count)
    }

    /// 펼쳤을 때 보여줄 이름들. 못 알아보는 키는 뺀다 — 빈 줄이 남으면 뭘 얻었는지 더 헷갈린다.
    nonisolated static func names(_ finds: [Discovery], l: L) -> [String] {
        finds.compactMap { $0.label(l.lang) }
    }
}
