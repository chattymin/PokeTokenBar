import SwiftUI

/// 가방 — **가진 것을 보는 화면**. 상점(사는 곳)에서 떼어 놓은 이유가 그것이다: 도구 106종 중
/// 재화로 살 수 있는 건 7종뿐이고, 나머지 99종은 파트너가 물어 온다. 살 수 없는 것을 상점에
/// 늘어놓으면 "왜 못 사지"가 되고, 산 것과 모은 것이 한 화면에서 섞인다.
///
/// **쓰는 곳은 여기가 아니다.** 사탕도 진화 도구도 폼 도구도 전부 "어떤 개체에게" 쓰는 물건이라
/// 개체 상세에서 쓴다. 가방은 재고를 확인하는 곳이다 — 개체를 안 고르고 쓸 수 있는 물건이 없어서,
/// 여기에 사용 버튼을 두면 누른 뒤 개체를 고르는 두 번째 화면이 또 필요해진다.
struct BagTabView: View {
    let store: PlayerStore

    private var l: L { store.l }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let sections = Self.sections(store)
                if sections.allSatisfy({ $0.rows.isEmpty }) {
                    emptyState
                } else {
                    ForEach(sections, id: \.title) { section in
                        if !section.rows.isEmpty { sectionView(section) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 320)
    }

    /// 빈 가방 — 옛 가방 화면의 관례를 따른다(잠만보 + 안내). 특정 아이템을 지목하지 않는다:
    /// 무엇부터 얻게 될지는 어떤 개체를 파트너로 두느냐에 달렸다.
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 143, size: 84, animated: true)
            Text(l.bagEmptyTitle).font(.system(size: 12, weight: .semibold))
            Text(l.bagEmptyHint)
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(section.title).font(.system(size: 12, weight: .semibold))
                // 모은 개수/전체 — 도구는 수집물이라 남은 양이 곧 진행도다.
                if let total = section.total {
                    Text("\(section.rows.count)/\(total)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(section.rows, id: \.name) { row in
                HStack(spacing: 5) {
                    Text(row.name).font(.system(size: 11, weight: .medium))
                    Spacer()
                    // 안 없어지는 물건에 "×1" 을 붙이면 소모품으로 읽힌다.
                    Text(row.count > 0 ? "×\(row.count)" : l.shopItemOwned)
                        .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    struct Row: Sendable, Equatable {
        let name: String
        /// 소모품이면 남은 개수, 영구 보유형이면 0(개수 대신 "보유 중"을 보여준다).
        let count: Int
    }

    struct Section: Sendable, Equatable {
        let title: String
        let rows: [Row]
        /// 수집물이면 전체 개수(진행도 표시용). 소모품 칸은 nil.
        let total: Int?
    }

    /// 가방에 담기는 것 — **가진 것만**. 안 가진 걸 늘어놓으면 106줄짜리 목록이 되고,
    /// 무엇이 필요한지는 어차피 그 개체의 상세 화면이 훨씬 정확하게 말해 준다
    /// ("마그마부스터 필요 · 파트너로 두면 물어 와요").
    ///
    /// 뷰에서 떼어 둔 건 이 목록이 조용히 줄어드는 걸(새 품목을 더하고 여기 안 넣는 일)
    /// 테스트가 잡게 하기 위해서다.
    static func sections(_ store: PlayerStore) -> [Section] {
        let consumables = ShopItem.allCases
            .filter { !$0.isCharm && store.count(of: $0) > 0 }
            .map { Row(name: $0.label(store.language), count: store.count(of: $0)) }
        let charms = ShopItem.allCases
            .filter { $0.isCharm && store.owns($0) }
            .map { Row(name: $0.label(store.language), count: 0) }
        let evolution = EvolutionItem.allCases
            .filter { store.count(of: $0) > 0 }
            .map { Row(name: $0.label(store.language), count: 0) }
        let forms = FormItem.allCases
            .filter { store.count(of: $0) > 0 }
            .map { Row(name: $0.label(store.language), count: 0) }
        return [
            .init(title: ShopCategory.consumable.title(store.language), rows: consumables, total: nil),
            .init(title: ShopCategory.charm.title(store.language), rows: charms, total: nil),
            .init(title: store.l.shopEvolutionSection, rows: evolution,
                  total: EvolutionItem.allCases.count),
            .init(title: store.l.shopFormItemSection, rows: forms, total: FormItem.allCases.count),
        ]
    }
}
