import SwiftUI

@MainActor
struct QuestsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    @State private var selectedSegment = 0
    @State private var selectedCategoryFilter: AchievementCategory? = nil
    @State private var collapsedCategories: Set<AchievementCategory> = []

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            streakBanner

            Picker("", selection: $selectedSegment) {
                Text(store.unclaimedQuestsTabCount > 0 ? "\(l.quests) (\(store.unclaimedQuestsTabCount))" : l.quests).tag(0)
                Text(store.unclaimedAchievementsCount > 0 ? "\(l.achievements) (\(store.unclaimedAchievementsCount))" : l.achievements).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            actionBar

            if selectedSegment == 1 {
                categoryFilterBar
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                    if selectedSegment == 0 {
                        questsContent
                    } else {
                        achievementsList
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(height: selectedSegment == 1 ? 405 : 440)
        }
    }

    private var streakBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        store.isStreakActiveToday
                            ? LinearGradient(
                                colors: [Color.orange.opacity(0.28), Color.red.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        store.isStreakActiveToday
                            ? LinearGradient(colors: [Color.orange, Color.red], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.secondary, Color.secondary.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(l.streakTitle(days: store.currentStreak))
                        .font(.callout.weight(.bold))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow)
                        Text(l.bestStreakTitle(days: store.bestStreak))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isStreakActiveToday ? Color.orange : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(store.isStreakActiveToday ? l.streakActiveToday : l.streakInactiveToday)
                        .font(.caption2.weight(store.isStreakActiveToday ? .semibold : .regular))
                        .foregroundStyle(store.isStreakActiveToday ? Color.orange : Color.secondary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    store.isStreakActiveToday
                        ? LinearGradient(
                            colors: [Color.orange.opacity(0.09), Color.accentColor.opacity(0.03)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [Color.secondary.opacity(0.06), Color.secondary.opacity(0.02)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    store.isStreakActiveToday
                        ? Color.orange.opacity(0.24)
                        : Color.secondary.opacity(0.14),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            if selectedSegment == 0 {
                Text(l.quests)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.unclaimedQuestsTabCount > 0 {
                    Button("\(l.claimAll) (\(store.unclaimedQuestsTabCount))") {
                        _ = store.claimAllQuests()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Text(l.achievements)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.unclaimedAchievementsCount > 0 {
                    Button("\(l.claimAll) (\(store.unclaimedAchievementsCount))") {
                        _ = store.claimAllAchievements()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                }
            }
        }
    }

    private var questsContent: some View {
        let activeDaily = store.dailyQuests.filter { !$0.isClaimed }
            .sorted { ($0.isCompleted && !$1.isCompleted) }
        let claimedDaily = store.dailyQuests.filter { $0.isClaimed }
        let activeWeekly = store.weeklyQuests.filter { !$0.isClaimed }
            .sorted { ($0.isCompleted && !$1.isCompleted) }
        let claimedWeekly = store.weeklyQuests.filter { $0.isClaimed }
        let totalClaimedCount = claimedDaily.count + claimedWeekly.count

        return VStack(alignment: .leading, spacing: 10) {
            Text(l.dailyQuests)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            if activeDaily.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(l.allDailyQuestsCompleted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(activeDaily) { quest in
                    DailyQuestRow(store: store, quest: quest)
                }
            }

            Text(l.weeklyQuests)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            if activeWeekly.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(l.allWeeklyQuestsCompleted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(activeWeekly) { quest in
                    WeeklyQuestRow(store: store, quest: quest)
                }
            }

            if totalClaimedCount > 0 {
                Divider().padding(.vertical, 4)
                HStack {
                    Text("\(l.completedQuests) (\(totalClaimedCount))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(claimedDaily) { quest in
                    DailyQuestRow(store: store, quest: quest)
                        .opacity(0.75)
                }

                ForEach(claimedWeekly) { quest in
                    WeeklyQuestRow(store: store, quest: quest)
                        .opacity(0.75)
                }
            }
        }
    }

    private var categoryFilterBar: some View {
        let allAchievements = store.achievements
        let byCategory = Dictionary(grouping: allAchievements, by: \.category)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let isAllSelected = selectedCategoryFilter == nil
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategoryFilter = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l.allCategories)
                        Text("(\(allAchievements.count))")
                            .font(.caption2)
                            .foregroundStyle(isAllSelected ? Color.accentColor : Color.secondary)
                    }
                    .font(.caption.weight(isAllSelected ? .semibold : .regular))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(isAllSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    .foregroundStyle(isAllSelected ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(AchievementCategory.allCases) { category in
                    let isSelected = selectedCategoryFilter == category
                    let categoryAchievements = byCategory[category] ?? []
                    let count = categoryAchievements.count
                    let unclaimed = categoryAchievements.filter { $0.isCompleted && !$0.isClaimed }.count

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategoryFilter = (selectedCategoryFilter == category ? nil : category)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(l.achievementCategoryTitle(category))
                            if unclaimed > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                            } else {
                                Text("(\(count))")
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            }
                        }
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private var achievementsList: some View {
        let displayedCategories: [AchievementCategory] = {
            if let filter = selectedCategoryFilter {
                return [filter]
            }
            return AchievementCategory.allCases
        }()

        let allAchievements = store.achievements
        let byCategory = Dictionary(grouping: allAchievements, by: \.category)
        let allClaimed = allAchievements.allSatisfy(\.isClaimed)

        if allClaimed {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text(l.allAchievementsCompleted)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }

        ForEach(displayedCategories) { category in
            let categoryAchievements = byCategory[category] ?? []
            let totalCount = categoryAchievements.count
            let completedCount = categoryAchievements.filter { $0.isCompleted }.count
            let unclaimedCount = categoryAchievements.filter { $0.isCompleted && !$0.isClaimed }.count
            let isExpanded = !collapsedCategories.contains(category)

            Section {
                if isExpanded {
                    let readyToClaim = categoryAchievements.filter { $0.isCompleted && !$0.isClaimed }
                    let inProgress = categoryAchievements.filter { !$0.isCompleted }
                    let claimed = categoryAchievements.filter { $0.isClaimed }

                    ForEach(readyToClaim) { achievement in
                        AchievementRow(store: store, achievement: achievement)
                    }
                    ForEach(inProgress) { achievement in
                        AchievementRow(store: store, achievement: achievement)
                    }
                    ForEach(claimed) { achievement in
                        AchievementRow(store: store, achievement: achievement)
                    }
                }
            } header: {
                AchievementCategoryBanner(
                    category: category,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    unclaimedCount: unclaimedCount,
                    isExpanded: isExpanded,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if collapsedCategories.contains(category) {
                                collapsedCategories.remove(category)
                            } else {
                                collapsedCategories.insert(category)
                            }
                        }
                    },
                    l: l
                )
                .padding(.top, 4)
                .padding(.bottom, 2)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

@MainActor
private struct DailyQuestRow: View {
    let store: CompanionStore
    let quest: DailyQuestItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: quest.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.dailyQuestTitle(quest.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(quest.type.reward)
                    }
                    Text(l.dailyQuestDescription(quest.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(quest.progress), total: Double(quest.target))
                    .tint(.accentColor)
                Text("\(formatNumber(quest.progress)) / \(formatNumber(quest.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if quest.isClaimed {
            Text("✓ " + l.rewardClaimed)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else if quest.isCompleted {
            Button(l.claimReward) {
                store.claimDailyQuest(quest.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
private struct WeeklyQuestRow: View {
    let store: CompanionStore
    let quest: WeeklyQuestItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: quest.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.weeklyQuestTitle(quest.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(quest.type.reward)
                    }
                    Text(l.weeklyQuestDescription(quest.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(quest.progress), total: Double(quest.target))
                    .tint(.indigo)
                Text("\(formatNumber(quest.progress)) / \(formatNumber(quest.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if quest.isClaimed {
            Text("✓ " + l.rewardClaimed)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else if quest.isCompleted {
            Button(l.claimReward) {
                store.claimWeeklyQuest(quest.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.indigo)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
private struct AchievementRow: View {
    let store: CompanionStore
    let achievement: AchievementItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: achievement.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.achievementTitle(achievement.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(achievement.type.reward)
                    }
                    Text(l.achievementDescription(achievement.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(achievement.progress), total: Double(achievement.target))
                    .tint(achievement.isClaimed ? Color.green.opacity(0.65) : Color.orange)
                Text("\(formatNumber(achievement.progress)) / \(formatNumber(achievement.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(
            achievement.isClaimed
                ? Color.green.opacity(0.08)
                : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    achievement.isClaimed ? Color.green.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(achievement.isClaimed ? 0.70 : 1.0)
    }

    @ViewBuilder
    private var actionButton: some View {
        if achievement.isClaimed {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                Text(l.rewardClaimed)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.green.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else if achievement.isCompleted {
            Button(l.claimReward) {
                store.claimAchievement(achievement.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
private struct AchievementCategoryBanner: View {
    let category: AchievementCategory
    let completedCount: Int
    let totalCount: Int
    let unclaimedCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let l: L

    private var colors: (Color, Color) {
        switch category {
        case .starters:
            return (Color(red: 0.12, green: 0.68, blue: 0.45), Color.teal)
        case .legendaries:
            return (Color.purple, Color(red: 0.90, green: 0.40, blue: 0.65))
        case .gymBadges:
            return (Color.orange, Color.yellow)
        case .productivity:
            return (Color.red, Color.orange)
        case .adventure:
            return (Color.accentColor, Color.indigo)
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [colors.0.opacity(0.24), colors.1.opacity(0.08)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(colors.0.opacity(0.22))
                        .frame(width: 34, height: 34)
                    QuestIconView(icon: category.icon, size: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.achievementCategoryTitle(category))
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.primary)

                        if unclaimedCount > 0 {
                            Text("+\(unclaimedCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.orange, in: Capsule())
                        }
                    }

                    Text(l.achievementCategorySubtitle(category))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    if completedCount == totalCount && totalCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.yellow)
                            Text("\(completedCount)/\(totalCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.yellow)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(Color.yellow.opacity(0.4), lineWidth: 1))
                    } else {
                        Text("\(completedCount)/\(totalCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .background(gradient, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colors.0.opacity(0.32), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct QuestIconView: View {
    let icon: QuestIcon
    var size: CGFloat = 30
    @State private var img: NSImage?

    init(icon: QuestIcon, size: CGFloat = 30) {
        self.icon = icon
        self.size = size
        if icon == .egg {
            _img = State(initialValue: SpriteLoader.cachedEggImage())
        } else if icon != .rareCandy {
            _img = State(initialValue: SpriteLoader.cachedItemImage(name: icon.rawValue))
        }
    }

    var body: some View {
        Group {
            if icon == .rareCandy {
                ItemIconView(kind: .rareCandy, size: size)
            } else if let img {
                let fit = SpriteFit.size(for: img.size, box: size)
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
                    .frame(width: size, height: size)
            } else {
                Text(icon.fallbackEmoji).font(.system(size: size * 0.8))
                    .frame(width: size, height: size)
            }
        }
        .task(id: icon.rawValue) {
            guard img == nil, icon != .rareCandy else { return }
            if icon == .egg {
                if let loaded = await SpriteLoader.eggImage() {
                    if img != loaded { img = loaded }
                }
            } else {
                if let loaded = await SpriteLoader.itemImage(name: icon.rawValue) {
                    if img != loaded { img = loaded }
                }
            }
        }
    }
}
