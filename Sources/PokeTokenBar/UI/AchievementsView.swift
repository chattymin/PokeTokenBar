import SwiftUI

/// 업적 화면 (체육관 배지 및 전설의 유물) — 도감 수집 조건을 달성하면 아이템을 무료로 획득.
/// 획득한 아이템은 가방(인벤토리)으로 들어가 상시 패시브 효과를 발휘한다.
@MainActor
struct AchievementsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    enum AchievementCategory: Hashable, CaseIterable {
        case gymBadges
        case legendaryArtifacts

        var collectorGroup: CollectorGroup {
            switch self {
            case .gymBadges: return .gymBadges
            case .legendaryArtifacts: return .legendaryArtifacts
            }
        }
    }

    @State private var selectedCategory: AchievementCategory = .gymBadges

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 10) {
            header

            Picker("", selection: $selectedCategory) {
                ForEach(AchievementCategory.allCases, id: \.self) { cat in
                    Text(categoryTitle(cat, l)).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let items = store.achievementItems(in: selectedCategory.collectorGroup)
                    ForEach(items, id: \.self) { kind in
                        AchievementCard(store: store, nav: nav, kind: kind)
                    }
                }
                .reservesScrollerLane()
            }
            .frame(height: 460)
        }
        .frame(height: 520)
    }

    private func categoryTitle(_ category: AchievementCategory, _ l: L) -> String {
        let items = store.achievementItems(in: category.collectorGroup)
        let claimed = items.filter { store.itemCount($0) > 0 }.count
        return "\(l.collectorGroupTitle(category.collectorGroup)) (\(claimed)/\(items.count))"
    }

    private var header: some View {
        let l = store.l
        let claimed = store.claimedAchievementsCount
        let total = store.totalAchievementsCount
        let unclaimed = store.unclaimedAchievementsCount

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.achievementsTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(l.achievementsProgress(claimed, total))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if unclaimed > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Text(l.readyToClaimNotice(unclaimed))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// 개별 업적 카드 — 아이콘, 이름, 패시브 효과 설명, 도감 달성 조건 및 [받기 / 획득함] 버튼.
@MainActor
private struct AchievementCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind

    private var isClaimed: Bool {
        store.itemCount(kind) > 0
    }

    private var canClaim: Bool {
        !isClaimed && store.isUnlocked(kind)
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                    .grayscale(isClaimed || canClaim ? 0 : 1)
                    .opacity(isClaimed || canClaim ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind))
                            .font(.callout.weight(.semibold))

                        if let badgeType = kind.badgeType {
                            Badge(l.typeName(badgeType).uppercased(), tint: .type(badgeType))
                        }

                        Spacer(minLength: 4)

                        statusAction(l)
                    }

                    Text(l.itemDescription(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            UnlockRequirementView(store: store, kind: kind, compact: isClaimed)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusAction(_ l: L) -> some View {
        if isClaimed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(l.claimed)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        } else if canClaim {
            Button(l.claim) {
                store.claimAchievement(kind)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Label(l.lockedLabel, systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
