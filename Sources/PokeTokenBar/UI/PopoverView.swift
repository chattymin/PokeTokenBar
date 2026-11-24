import AppKit
import SwiftUI

enum PopoverTab { case home, shop, bag, collection, achievements, dungeons }

/// The popover's tab bar: five equal tabs, an icon over a short label, the selected one on a pill in the color of
/// the Pokémon being raised. Achievements ready to claim show as a count on the trophy. Each label must fit its
/// fifth of `PopoverMetrics.contentWidth` in every language (`testTabBarFitsThePopoverInEveryLanguage`).
@MainActor
struct PopoverTabPicker: View {
    @Binding var tab: PopoverTab
    let l: L
    let unclaimedAchievements: Int
    var accent: Color = Design.actionColor

    /// The labels' font, shared with the width test.
    static let labelFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// Smallest scale a long label may shrink to before it no longer fits.
    static let minimumLabelScale: CGFloat = 0.8

    func items() -> [(tab: PopoverTab, title: String, icon: String)] {
        // Five tabs: the Bag and the achievements share the Trainer tab (`BagHubView`), a sixth left no room.
        [(.home, l.home, "house.fill"), (.shop, l.shop, "cart.fill"), (.bag, l.trainerTab, "person.fill"),
         (.collection, l.collection, "books.vertical.fill"), (.dungeons, l.dungeonsTab, "map.fill")]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items(), id: \.tab) { item in
                let selected = tab == item.tab || (item.tab == .bag && tab == .achievements)
                Button { tab = item.tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(height: 16)
                            .overlay(alignment: .topTrailing) {
                                if item.tab == .bag, unclaimedAchievements > 0 {
                                    Text("\(unclaimedAchievements)")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.red))
                                        .offset(x: 10, y: -5)
                                }
                            }
                        Text(item.title)
                            .font(Font(Self.labelFont))
                            .lineLimit(1)
                            .minimumScaleFactor(Self.minimumLabelScale)
                    }
                    .foregroundStyle(selected ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? accent.opacity(0.16) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.tab == .bag && unclaimedAchievements > 0
                                    ? "\(item.title), \(l.achievementsTab(unclaimed: unclaimedAchievements))" : item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
        .animation(.easeOut(duration: 0.15), value: tab)
    }
}

/// 팝오버 치수의 단일 소스. 자식이 쓸 수 있는 폭을 알아야 할 때 이 값을 쓴다 — 넘치는 자식이
/// 부모 폭을 부풀리므로 GeometryReader 로 재면 순환한다.
enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    /// 이 폭을 넘는 자식은 팝오버 창에 좌우로 잘린다.
    static let contentWidth: CGFloat = width - padding * 2
    /// 세로 스크롤 영역 오른쪽에 비워 두는 스크롤러 레인. 얇은 오버레이 스크롤러(휴지 ~6pt, 가장자리
    /// 안쪽)가 우측 정렬 수치·버튼 위에 뜨지 않게 한다. 스크롤이 필요 없어도 항상 비워 탭 간 폭이 같다.
    static let scrollerInset: CGFloat = 12
    /// 세로 스크롤 영역 안의 자식이 쓸 수 있는 폭. 스크롤 안에서 폭을 고정하는 자식(진화 라인 등)은
    /// `contentWidth` 대신 이 값을 써야 한다 — 제안 폭보다 넓은 자식 하나가 열 전체를 다시 넓혀 레인이 사라진다.
    static let scrollContentWidth: CGFloat = contentWidth - scrollerInset
}

extension View {
    /// 팝오버 세로 `ScrollView` 의 콘텐츠에 스크롤러 레인을 비운다. `.contentMargins` 는 쓰지 않는다 —
    /// AppKit 이 오버레이 스크롤러를 콘텐츠 인셋만큼 안쪽으로 옮겨 레인이 생기지 않는다(실측).
    func reservesScrollerLane() -> some View {
        padding(.trailing, PopoverMetrics.scrollerInset)
    }
}

/// 팝오버 내부 내비게이션 상태(현재 탭 / 컬렉션 세그먼트 / 설정 표시 여부).
/// NSHostingController 는 팝오버를 닫아도 재사용되어 @State 가 유지되므로, 화면 상태를 이
/// Observable 로 분리해 AppDelegate 가 팝오버를 열 때마다 reset() 한다 — 닫혔다 열리면 항상 Home.
@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false { didSet { if showSettings { dexDetailCollectionID = nil } } }
    var tab: PopoverTab = .home { didSet { if tab != .collection { dexDetailCollectionID = nil } } }
    /// 일반적인 컬렉션 재진입에는 마지막 세그먼트를 유지하되, 대표 포켓몬 선택 진입점은 도감으로 강제한다.
    var showingCollectionLog = false {
        didSet { if showingCollectionLog != oldValue { dexDetailCollectionID = nil } }
    }
    /// The usage recap takes over the popover like Settings does; closing the popover drops it.
    var showingRecap = false { didSet { if showingRecap { dexDetailCollectionID = nil } } }
    /// The Bonuses page takes over the popover the same way.
    var showingBonuses = false { didSet { if showingBonuses { dexDetailCollectionID = nil } } }
    /// The changelog takes over the popover the same way.
    var showingChangelog = false { didSet { if showingChangelog { dexDetailCollectionID = nil } } }
    /// The Pokédex's view: every species region by region (TokenDex's), the caught ones page by page, or the
    /// missing ones. Kept across openings, like the segment.
    enum DexScope: Hashable, CaseIterable { case all, caught, missing }
    var dexScope: DexScope = .all
    /// The Shop's products tab and the Bag's tab (#183), kept across openings like the Pokédex's segment.
    var shopTab: CompanionStore.ShopTab = .eggs
    var bagSection: BagView.Section = .raising
    /// The ideas page (`IdeasScreen`) too.
    var showingIdeas = false { didSet { if showingIdeas { dexDetailCollectionID = nil } } }
    /// The events' calendar (`EventCalendarScreen`) too.
    var showingCalendar = false { didSet { if showingCalendar { dexDetailCollectionID = nil } } }
    /// Prof. Oak's details page (`OakAdviceScreen`) too.
    var showingOakDetails = false { didSet { if showingOakDetails { dexDetailCollectionID = nil } } }
    /// The team screen of a dungeon (`DungeonTeamScreen`), over the popover.
    var dungeonTeam: DungeonID?
    /// A dungeon's page (`DungeonDetailScreen`): its odds, bosses and past expeditions. Its team screen opens over it.
    var dungeonDetail: DungeonID?
    /// The general team (`MyTeamScreen`) and the type chart (`TypeChartScreen`), from the Dungeons tab.
    var showingMyTeam = false
    var showingTypeChart = false
    /// The Collection's statistics (`CollectionStatsScreen`).
    var showingCollectionStats = false
    /// The costumed Pokémon (`CostumeCollectionScreen`).
    var showingCostumes = false
    /// The battle forms (`BattleFormsScreen`), and its filter of the won ones, kept across openings.
    var showingBattleForms = false
    var battleFormsWonOnly = false
    /// Every expedition that ended (#133), and one of them opened on its journal (`endedAt` names it).
    var showingRunHistory = false
    var pastRun: Date?
    /// A dungeon battle replayed (`BattleReplayScreen`): "Revoir, c'est rejouer".
    var replayBattle: ExpeditionBattle?
    /// Where the replay starts: a battle still being fought opens live, at its present moment.
    var replayStart = 0
    /// The whole journal of the expedition (`ExpeditionLogScreen`).
    var showingExpeditionLog = false
    /// A Capsule being used from the Bag (`CapsuleScreen`).
    var capsule: ItemKind?
    /// The Luck screen (`LuckScreen`) too, on one of its tabs; it reopens on its summary.
    var showingLuck = false { didSet { if showingLuck { dexDetailCollectionID = nil } } }
    enum LuckTab: Hashable, CaseIterable { case summary, curves, hatches }
    var luckTab: LuckTab = .summary
    /// The changelog entries seen before it was opened: the others are marked new on it.
    var changelogSeenBefore: Set<String> = []
    /// The Collection tab's open Pokédex detail page (`DexSpecies.collectionID`); nil = grid or log.
    /// It lives here so Home sprites can open it, but it only lasts while the collection content is
    /// on screen: leaving the tab, switching segment, or covering it with Settings/Recap drops it —
    /// the same lifetime it had as `CollectionView`'s own `@State`.
    var dexDetailCollectionID: String? {
        didSet { if dexDetailCollectionID == nil { dexDetailForm = nil; dexDetailHistory = []; dexDetailFromBattleForms = false } }
    }
    /// Whether the open page came from the Battle Forms screen: Back returns there (`returnToBattleForms`).
    var dexDetailFromBattleForms = false

    /// A won battle form clicked on the Battle Forms screen: its species' page, open in that form.
    func openBattleForm(_ form: BattleForm, collectionID: String) {
        showingBattleForms = false
        showSettings = false
        tab = .collection
        dexDetailHistory = []
        dexDetailCollectionID = collectionID
        dexDetailForm = form.form
        dexDetailFromBattleForms = true
    }

    /// Back from a page the Battle Forms screen opened: that screen again. False for any other page.
    func returnToBattleForms() -> Bool {
        guard dexDetailFromBattleForms else { return false }
        dexDetailCollectionID = nil
        showingBattleForms = true
        return true
    }
    /// The form the open page shows first when another page's evolution family opened it: Alolan Ninetales from
    /// Alolan Vulpix. Nil from the grid, the log and Home.
    var dexDetailForm: PokemonForm?
    /// Pages left for another one through their evolution family, the latest last: Back returns to them first.
    var dexDetailHistory: [DexPage] = []

    /// One Pokédex page in one form.
    struct DexPage: Equatable {
        let collectionID: String
        let form: PokemonForm?
    }

    /// Opens a page from the evolution family of `current`, which Back returns to.
    func openDexPage(_ page: DexPage, from current: DexPage) {
        guard page.collectionID != current.collectionID else { return }
        dexDetailHistory.append(current)
        dexDetailCollectionID = page.collectionID
        dexDetailForm = page.form
    }

    /// Back from a page: the page it was opened from, if any. False when there is none (back to the grid or log).
    func returnToPreviousDexPage() -> Bool {
        guard let previous = dexDetailHistory.popLast() else { return false }
        dexDetailCollectionID = previous.collectionID
        dexDetailForm = previous.form
        return true
    }
    /// 프로바이더 탭 선택 — reset() 대상이 아님(팝오버를 다시 열어도 보던 서비스 유지).
    var providerID: String?
    /// Claude account tab in the limits section. Kept across openings, like `providerID`.
    var claudeAccountID: String?
    /// 설정을 열 때 고급 섹션을 펼친 채로 시작할지. 세션 키 행이 접힌 disclosure 안에 살아서,
    /// 그냥 설정만 열면 "만료됐다"를 보고 들어온 사용자가 고칠 입력란을 못 찾는다.
    var expandAdvancedOnOpen = false

    func reset() {
        showSettings = false
        expandAdvancedOnOpen = false
        showingRecap = false
        showingBonuses = false
        showingChangelog = false
        showingIdeas = false
        showingCalendar = false
        showingOakDetails = false
        dungeonTeam = nil
        dungeonDetail = nil
        showingMyTeam = false
        showingTypeChart = false
        showingCollectionStats = false
        showingCostumes = false
        showingBattleForms = false
        showingRunHistory = false
        pastRun = nil
        replayBattle = nil
        replayStart = 0
        showingExpeditionLog = false
        capsule = nil
        showingLuck = false
        luckTab = .summary
        tab = .home
    }

    /// 세션 키 만료 안내 → 그 키를 고칠 수 있는 유일한 화면으로 바로 보낸다.
    func openSessionKeySettings() {
        showSettings = true
        expandAdvancedOnOpen = true
    }

    /// Clicking a Pokémon sprite on Home opens that species' Pokédex detail page. The segment is left
    /// as it was, so Back lands where the Collection tab would normally reopen.
    func openDexEntry(collectionID: String) {
        showSettings = false
        tab = .collection
        dexDetailCollectionID = collectionID   // last: the didSets above clear it
    }

    /// The achievement the Achievements tab opens on, scrolled to and lit, then cleared.
    var achievementFocus: ItemKind?

    /// Clicking a goal of the Pokémon being raised on Home opens its achievement, in its section.
    func openAchievement(_ kind: ItemKind) {
        showSettings = false
        achievementFocus = kind
        tab = .achievements
    }

    /// 설정의 대표 포켓몬 행에서 기존 도감으로 이동한다. 별도 선택 화면을 만들지 않고
    /// 컬렉션 세그먼트를 도감으로 명시해, 직전에 포획 로그를 봤어도 선택 액션이 있는 화면을 연다.
    func openRepresentativeDex() {
        showSettings = false
        showingCollectionLog = false
        tab = .collection
    }
}

@MainActor
struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    @Environment(PopoverNavigation.self) private var nav

    private var l: L { companion.l }
    @State private var showingClaudeKeychainHelp = false
    /// The birthday gift was just opened: the banner says where the egg went until it is dismissed.
    @State private var birthdayGiftOpened = false
    /// The event egg just taken: the banner says where it went until it is dismissed.
    @State private var eventEggTaken: EventEgg?
    /// The news shown in the strip above the tabs (`newsPages`), by its place.
    /// The news shown, by what it is rather than its place: claiming an egg, then opening the Bag (which sees the
    /// treasures), moved the pages under an index and showed another.
    @State private var newsSelection: NewsPage?

    var body: some View {
        // NOTE: 설정을 .sheet 로 띄우면 transient 팝오버가 닫힐 때 시트가 고아로 남아
        // 이후 팝오버의 모든 버튼 클릭을 차단할 수 있음 — 팝오버 내부 화면 전환으로 처리
        @Bindable var nav = nav
        Group {
            if nav.showSettings {
                SettingsView(
                    onClose: {
                        nav.showSettings = false
                        nav.expandAdvancedOnOpen = false
                    },
                    onChooseRepresentative: { nav.openRepresentativeDex() },
                    startExpanded: nav.expandAdvancedOnOpen
                )
                    .environment(store)
                    .environment(companion)
                    .environment(updater)
            } else if nav.showingRecap {
                StatsScreen(store: store, companion: companion) { nav.showingRecap = false }
            } else if nav.showingBonuses {
                BonusScreen(store: companion) { nav.showingBonuses = false }
            } else if nav.showingChangelog {
                ChangelogScreen(l: l, language: companion.language, seenBefore: nav.changelogSeenBefore) {
                    nav.showingChangelog = false
                }
            } else if nav.showingIdeas {
                IdeasScreen(l: l) { nav.showingIdeas = false }
            } else if nav.showingCalendar {
                EventCalendarScreen(store: companion) { nav.showingCalendar = false }
            } else if nav.showingOakDetails {
                OakAdviceScreen(store: companion) { nav.showingOakDetails = false }
            } else if let battle = nav.replayBattle {
                BattleReplayScreen(store: companion, battle: battle, startAt: nav.replayStart) {
                    nav.replayBattle = nil
                    nav.replayStart = 0
                }
            } else if let ended = nav.pastRun, let run = companion.allRuns.first(where: { $0.endedAt == ended }) {
                PastRunScreen(store: companion, nav: nav, run: run) { nav.pastRun = nil }
            } else if nav.showingRunHistory {
                RunHistoryScreen(store: companion, nav: nav) { nav.showingRunHistory = false }
            } else if nav.showingExpeditionLog {
                ExpeditionLogScreen(store: companion, nav: nav)
            } else if let capsule = nav.capsule {
                CapsuleScreen(store: companion, kind: capsule) { nav.capsule = nil }
            } else if let dungeon = nav.dungeonTeam {
                DungeonTeamScreen(store: companion, dungeon: dungeon) { nav.dungeonTeam = nil } onDepart: {
                    nav.dungeonTeam = nil
                    nav.dungeonDetail = nil
                    nav.tab = .home
                }
            } else if let dungeon = nav.dungeonDetail {
                DungeonDetailScreen(store: companion, nav: nav, id: dungeon) { nav.dungeonDetail = nil } onPrepare: {
                    nav.dungeonTeam = dungeon
                }
            } else if nav.showingMyTeam {
                MyTeamScreen(store: companion) { nav.showingMyTeam = false }
            } else if nav.showingTypeChart {
                TypeChartScreen(store: companion) { nav.showingTypeChart = false }
            } else if nav.showingCollectionStats {
                CollectionStatsScreen(store: companion) { nav.showingCollectionStats = false }
            } else if nav.showingCostumes {
                CostumeCollectionScreen(store: companion) { nav.showingCostumes = false }
            } else if nav.showingBattleForms {
                BattleFormsScreen(store: companion, wonOnly: $nav.battleFormsWonOnly) { nav.showingBattleForms = false }
                    onOpen: { form, collectionID in nav.openBattleForm(form, collectionID: collectionID) }
            } else if nav.showingLuck {
                LuckScreen(store: companion, nav: nav) { nav.showingLuck = false }
            } else {
                mainContent
            }
        }
        .frame(width: PopoverMetrics.width)
        // Above the scroll views and cards, which clip: the Pokémon names shown on hover.
        .hoverTipHost()
        .overlay(alignment: .top) {
            if !companion.formUnlockNews.isEmpty {
                FormUnlockToast(store: companion)
                    .padding(.horizontal, 10).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: companion.formUnlockNews)
        .environment(\.locale, companion.language.displayLocale)
    }

    @ViewBuilder
    private var updateBanner: some View {
        if updater.isUpdating {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.updating).font(.caption).fontWeight(.medium)
                    Spacer()
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let error = updater.updateError {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.updateFailed).font(.caption).fixedSize(horizontal: false, vertical: true)
                Text(error).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 8) {
                    Spacer()
                    Button(l.close) { updater.dismissUpdateError() }
                        .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    if updater.updateTarget != nil {
                        Button(l.retry) { updater.applyUpdate() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
            .padding(8)
            .background(Color.readableOrange.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let update = updater.available, store.updateNotificationsEnabled {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.updateAvailable(update.version, current: updater.currentVersion))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button(l.skipThisVersion) { updater.skipCurrent() }
                        .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    Button(l.updateButton) { updater.applyUpdate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// The birthday gift waiting, above the tabs whatever the tab, until it is opened; then where it went. It never
    /// tells what hatches.
    @ViewBuilder
    private var birthdayBanner: some View {
        if let gift = companion.birthdayGift {
            HStack(spacing: 10) {
                SpriteView(speciesID: nil, size: 40, animated: true, egg: .birthday)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gift.occasion == .birthday ? l.birthdayBannerTitle : l.birthdayBelatedTitle)
                        .font(.callout.weight(.bold))
                    Text(l.birthdayBannerBody).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(l.birthdayClaim) {
                    guard companion.claimBirthdayGift() else { return }
                    birthdayGiftOpened = true
                    newsSelection = .birthday
                    nav.tab = .bag
                }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(.pink)
            }
            .padding(8)
            .background(LinearGradient(colors: [Color.pink.opacity(0.22), Color.purple.opacity(0.14)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if birthdayGiftOpened {
            HStack(spacing: 8) {
                Text("🎁").font(.callout)
                Text(l.birthdayClaimed).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { birthdayGiftOpened = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    .accessibilityLabel(l.close)
            }
            .padding(8)
            .background(Color.pink.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// One event egg waiting, on its page of the news strip: the event's wish while it
    /// is on, then that it still waits, two weeks more. Then where it went. It never tells what hatches.
    @ViewBuilder
    private func eventEggBanner(_ pending: (egg: EventEgg, year: Int)) -> some View {
        let egg = pending.egg
        let colors = egg.bannerColors
        HStack(spacing: 10) {
            SpriteView(speciesID: nil, size: 40, animated: true, egg: .event(egg))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(companion.isEventOn(egg, year: pending.year) ? l.eventEggWish(egg) : l.eventEggStillWaiting(egg))
                    .font(.callout.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(l.eventEggBody(egg)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(l.eventEggClaim) {
                guard companion.claimEventEgg(egg) else { return }
                eventEggTaken = egg
                // The note saying where this one went, not the next egg that took its place.
                newsSelection = .eventEggTaken
                nav.tab = .bag
            }
            .buttonStyle(.borderedProminent).controlSize(.small).tint(colors.0)
        }
        .padding(8)
        .background(LinearGradient(colors: [colors.0.opacity(0.22), colors.1.opacity(0.14)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// What the Explorer Kit dug up, until the Bag is opened or the page closed. A Legendary Egg is the jackpot, in its
    /// own color and title.
    @ViewBuilder
    private var treasureBanner: some View {
        let treasures = companion.unseenTreasures
        if let first = treasures.first {
            let jackpot = first.kind == .legendaryEgg
            let tint: Color = jackpot ? .purple : .orange
            HStack(spacing: 8) {
                ItemIconView(kind: first.kind, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(jackpot ? l.treasureJackpotTitle : l.treasureTitle).font(.callout.weight(.bold))
                    Text(l.treasureBody(treasures)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(l.treasureOpenBag) {
                    companion.markTreasuresSeen()
                    nav.tab = .bag
                }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(tint)
                Button { companion.markTreasuresSeen() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    .accessibilityLabel(l.close)
            }
            .padding(8)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Where the egg just taken went, until closed.
    @ViewBuilder
    private var eventEggTakenBanner: some View {
        if let egg = eventEggTaken {
            HStack(spacing: 8) {
                Text("🥚").font(.callout)
                Text(l.eventEggClaimed(egg)).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { eventEggTaken = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    .accessibilityLabel(l.close)
            }
            .padding(8)
            .background(egg.bannerColors.0.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Opens the changelog, the days not seen yet marked new on it, and counts them seen.
    private func openChangelog() {
        nav.changelogSeenBefore = store.changelogSeen
        store.markChangelogSeen()
        nav.showingChangelog = true
    }

    /// What changed since the player last looked, above the tabs, until they open it or close the banner.
    @ViewBuilder
    private var changelogBanner: some View {
        let unseen = store.unseenChangelogEntries
        if !unseen.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "newspaper.fill").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.changelogTitle).font(.callout.weight(.semibold))
                    Text(l.changelogBannerBody(unseen.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(l.changelogOpen) { openChangelog() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button { store.markChangelogSeen() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                    .accessibilityLabel(l.close)
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// One of the news above the tabs.
    private enum NewsPage: Hashable {
        case treasure, update, birthday, eventEgg(EventEgg), eventEggTaken, changelog
    }

    /// The news waiting, the eggs to take first: every event egg waiting has its page (autumn and Halloween together;
    /// only the first showed until it was taken).
    private var newsPages: [NewsPage] {
        var pages: [NewsPage] = []
        // The Explorer Kit's treasures first: what just came, which the other news does not hide.
        if !companion.unseenTreasures.isEmpty { pages.append(.treasure) }
        if updater.isUpdating || updater.updateError != nil
            || (updater.available != nil && store.updateNotificationsEnabled) { pages.append(.update) }
        pages += companion.eventEggs.map { .eventEgg($0.egg) }
        if eventEggTaken != nil { pages.append(.eventEggTaken) }
        if companion.birthdayGift != nil || birthdayGiftOpened { pages.append(.birthday) }
        if store.hasUnseenChangelog { pages.append(.changelog) }
        return pages
    }

    /// The news in one strip of one height, one at a time with arrows between them: stacked, four of them pushed Home
    /// down by some 170 points.
    @ViewBuilder
    private var newsStrip: some View {
        let pages = newsPages
        if !pages.isEmpty {
            let index = newsSelection.flatMap(pages.firstIndex(of:)) ?? 0
            VStack(alignment: .leading, spacing: 4) {
                if pages.count > 1 {
                    HStack(spacing: 6) {
                        Text(l.newsCount(pages.count)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button { newsSelection = pages[(index + pages.count - 1) % pages.count] } label: {
                            Image(systemName: "chevron.left").frame(width: 18, height: 14)
                        }
                        .accessibilityLabel(l.recapPrevious)
                        Text(l.newsPosition(index + 1, pages.count))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        Button { newsSelection = pages[(index + 1) % pages.count] } label: {
                            Image(systemName: "chevron.right").frame(width: 18, height: 14)
                        }
                        .accessibilityLabel(l.recapNext)
                    }
                    .buttonStyle(.borderless)
                }
                newsPage(pages[index])
            }
        }
    }

    @ViewBuilder
    private func newsPage(_ page: NewsPage) -> some View {
        switch page {
        case .treasure: treasureBanner
        case .update: updateBanner
        case .birthday: birthdayBanner
        case .eventEgg(let egg):
            if let pending = companion.eventEggs.first(where: { $0.egg == egg }) { eventEggBanner(pending) }
        case .eventEggTaken: eventEggTakenBanner
        case .changelog: changelogBanner
        }
    }

    /// Why the save is not written (`CompanionStore.SaveLock`): stays until the cause is gone.
    @ViewBuilder
    private var saveLockBanner: some View {
        if let lock = companion.saveLock {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.readableOrange)
                Text(saveLockText(lock))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func saveLockText(_ lock: CompanionStore.SaveLock) -> String {
        switch lock {
        case .unreadable: return l.saveLockUnreadable
        case .newerBuild(let commit): return l.saveLockNewerBuild(commit)
        }
    }

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            saveLockBanner
            newsStrip
            PopoverTabPicker(tab: $nav.tab, l: l, unclaimedAchievements: companion.unclaimedAchievementsCount)

            if nav.tab == .dungeons {
                DungeonsView(store: companion, nav: nav)
            } else if nav.tab == .collection {
                CollectionView(store: companion, navigation: nav)
            } else if nav.tab == .bag || nav.tab == .achievements {
                BagHubView(store: companion, nav: nav)
            } else if nav.tab == .shop {
                ShopView(store: companion, nav: nav)
            } else {
                // 고정 높이 — 상점/가방/컬렉션과 동일(팝오버가 화면을 넘어가는 것을 방지).
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                        VillainAmbushCards(store: companion, nav: nav)
                        ExpeditionResultCard(store: companion, nav: nav)
                        ExpeditionCard(store: companion, nav: nav)
                        // While a team explores, the Pokémon raised waits as one small line; the card comes back
                        // with its growth.
                        if companion.growthPaused {
                            PausedCompanionStrip(store: companion)
                        } else {
                            CompanionHeader(store: companion, onOpenDexEntry: { nav.openDexEntry(collectionID: $0) },
                                            onOpenBonuses: { nav.showingBonuses = true },
                                            onOpenAchievement: { nav.openAchievement($0) })
                        }
                        header
                        providerStatusBanner   // 인시던트 있을 때만 — 한도 가용 여부와 무관(API 다운=한도 nil 케이스에도)
                        if selectedProviderHasLimits {
                            limitsSection.designCard()
                        }
                        if let id = selectedSnapshot?.providerID, companion.paysCandiesByTokens(id) {
                            TokenCandiesCard(store: companion).designCard()
                        }
                    }
                    .reservesScrollerLane()
                }
                .frame(height: 520)
                // The day's villains come at their hour, seen as Home opens (issue #180).
                .task { companion.settleVillainAmbush() }
            }
            footer
        }
        .padding(PopoverMetrics.padding)
    }

    // MARK: 헤더 — 오늘 합계 + provider/토큰타입 분해

    /// Today's usage, then the selected tool's detail: one card each. The month's daily chart is on the Stats page,
    /// with every other number.
    private var header: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            todayCard
            providerCard
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionTitle(text: l.todayTokens, systemImage: "bolt.fill")
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                CircleIconButton(systemImage: "wand.and.stars", help: l.bonusOpen) { nav.showingBonuses = true }
                CircleIconButton(systemImage: "chart.bar.xaxis", help: l.statsTitle) { nav.showingRecap = true }
                CircleIconButton(systemImage: "suit.club.fill", help: l.luckTitle) { nav.showingLuck = true }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TokenFormatter.compact(store.todayTotalTokens))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if store.todayTotalTokens >= 1_000 {
                    Text(TokenFormatter.grouped(store.todayTotalTokens))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if store.showsCost {
                    UsageCostText(cost: store.todayUsageCost, l: l)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.readableGreen)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                }
            }
            // Keep period totals visible on quiet days too.
            HStack(spacing: 8) {
                periodTile(l.thisWeek, tokens: store.weekTotalTokens, cost: store.showsCost ? store.weekUsageCost : nil)
                periodTile(l.thisMonth, tokens: store.monthTotalTokens, cost: store.showsCost ? store.monthUsageCost : nil)
            }
        }
        .designCard()
    }

    @ViewBuilder
    private var providerCard: some View {
        // 연결된 서비스가 2개 이상이면 작은 탭으로 서비스별 상세를 넘나든다
        // (합계는 위에 유지 — 상세·한도만 탭 스코프).
        let today = selectedSnapshot.flatMap { snap in snap.today.map { (snap, $0) } }
        if store.snapshots.count > 1 || today != nil {
            VStack(alignment: .leading, spacing: 8) {
                if store.snapshots.count > 1 {
                    providerTabBar
                }
                if let (snap, today) = today {
                    providerRow(snapshot: snap, today: today)
                }
            }
            .designCard()
        }
    }

    /// 현재 선택된 프로바이더 스냅샷 — 선택이 없거나 연결 해제됐으면 첫 번째로 폴백.
    private var selectedSnapshot: ProviderSnapshot? {
        store.snapshot(preferring: nav.providerID)
    }

    private var providerTabBar: some View {
        ProviderTabBar(
            snapshots: store.snapshots,
            selectedID: selectedSnapshot?.providerID,
            onSelect: { nav.providerID = $0 })
    }

    private func periodLabel(_ name: String, tokens: Int, cost: UsageCost?) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(tokens))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let cost {
                UsageCostText(cost: cost, l: l)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func periodTile(_ name: String, tokens: Int, cost: UsageCost?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Small and grey, "이번 달" read as "미번 달" (Vision on CI): 11 pt semibold reads at a glance.
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(TokenFormatter.compact(tokens))
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .monospacedDigit()
                if let cost {
                    UsageCostText(cost: cost, l: l)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func providerRow(snapshot: ProviderSnapshot, today: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snapshot.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(TokenFormatter.compact(today.totalTokens))
                    .font(.callout)
                    .monospacedDigit()
                if snapshot.reportsCost {
                    UsageCostText(cost: today.usageCost, l: l)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    tokenTypeLabel(l.tokenInput, today.inputTokens)
                    tokenTypeLabel(l.tokenOutput, today.outputTokens)
                }
                HStack(spacing: 10) {
                    tokenTypeLabel(l.tokenCacheWrite, today.cacheCreationTokens)
                    tokenTypeLabel(l.tokenCacheRead, today.cacheReadTokens)
                }
            }
            if let models = today.models, models.count > 1 {
                ForEach(models.sorted(by: { $0.value > $1.value }), id: \.key) { model, tokens in
                    HStack(spacing: 6) {
                        Text(model.split(separator: "/").last.map(String.init) ?? model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(TokenFormatter.compact(tokens))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func tokenTypeLabel(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: 한도 섹션 — 공식 5h/주간 % + 리셋 카운트다운

    /// 선택된 프로바이더에 표시할 공식 한도가 있는가 (Gemini 는 공식 한도 API 없음 → 섹션 생략).
    private var selectedProviderHasLimits: Bool {
        switch selectedSnapshot?.providerID {
        // Keychain 이 꺼져있지 않으면 한도가 아직 없어도 섹션을 노출한다 — 그래야 최초 실행에
        // claudeLimitsRefreshRow("탭해서 로드")가 보여, 설정까지 안 들어가도 원탭으로 켤 수 있다.
        // (자동 Keychain 읽기는 팝업 방지로 여전히 안 함 — 발견성만 살린다.)
        case "claude_code": return !store.disableKeychainAccess || store.limits != nil || store.limitsAuthExpired
            || !store.additionalLimits.isEmpty
        case "codex": return store.codexLimits?.hasVisibleLimit == true
        case "antigravity": return !store.disableKeychainAccess || store.antigravityHasTokenFile || store.antigravityLimits?.hasVisibleLimit == true || store.antigravityLimitsAuthExpired
        case "cursor": return store.cursorLimits?.hasVisibleLimit == true || store.cursorLimitsAuthExpired
        case "opencode": return store.openCodeGoLimits?.hasVisibleLimit == true || store.openCodeGoLimitsAuthExpired
        case "grok": return store.grokLimits?.hasVisibleLimit == true || store.grokLimitsAuthExpired
        default: return false
        }
    }

    /// 선택 프로바이더의 상태 페이지 인시던트(있을 때만) — Claude/OpenAI API 장애를 앱 고장으로
    /// 오인하지 않게. 표시 전용(알림 아님). 인시던트 없거나 상태조회 꺼짐이면 아무것도 안 그림.
    /// 범위(v1): 선택된 provider 탭 한정. 오늘 안 쓴 provider 는 탭/스냅샷이 없어 배너도 안 뜬다 —
    /// 오인이 실제로 생기는 케이스(오늘 써서 이상 수치를 보는데 한도는 nil)는 로컬 사용 스냅샷이 있어
    /// 탭이 존재하므로 커버된다. 전 provider 전역 인시던트 행은 추후.
    @ViewBuilder
    private var providerStatusBanner: some View {
        if let id = selectedSnapshot?.providerID,
           let status = store.providerStatus(for: id), status.indicator.hasIssue {
            HStack(spacing: 6) {
                Circle().fill(statusColor(status.indicator)).frame(width: 7, height: 7)
                Text(l.providerStatusLabel(status.indicator))
                    .font(.caption).fontWeight(.medium)
                if !status.description.isEmpty {
                    Text(status.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private func statusColor(_ indicator: ProviderStatusIndicator) -> Color {
        switch indicator {
        case .operational:         return .green
        case .minor, .maintenance: return .yellow
        case .major:               return .orange
        case .critical:            return .red
        case .unknown:             return .gray
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                SectionTitle(text: l.limitsOfficial, systemImage: "gauge.with.dots.needle.33percent")
                if selectedSnapshot?.providerID == "claude_code", !store.sessionKeyConfigured {
                    claudeKeychainHelpButton
                }
            }
            if showingClaudeKeychainHelp, selectedSnapshot?.providerID == "claude_code", !store.sessionKeyConfigured {
                claudeKeychainHelp
            }
            if selectedSnapshot?.providerID == "claude_code", store.limitsAuthExpiry == .sessionKey {
                sessionKeyExpiredNotice
            } else if selectedSnapshot?.providerID == "claude_code", store.limitsAuthExpired {
                claudeAuthExpiredNotice
            } else if selectedSnapshot?.providerID == "claude_code",
                      !store.disableKeychainAccess,
                      store.claudeLimitsMissing || store.claudeLimitsStale || store.additionalLimitsPending
                        || store.additionalLimitsStale {
                // 자동 폴링은 Keychain 을 안 읽으므로(팝업 방지), 최초/만료 후 공식 한도는 이 원탭으로
                // 사용자가 직접 갱신한다. 프롬프트가 뜨더라도 사용자 행동에 의한 것이라 예상 가능하다.
                claudeLimitsRefreshRow
            }
            if selectedSnapshot?.providerID == "claude_code" {
                claudeAccountsContent
            }
            if selectedSnapshot?.providerID == "codex",
               let codexStatus = store.codexLimits, codexStatus.hasVisibleLimit {
                let buckets = codexStatus.visibleSnapshots
                codexMetaRow(codexStatus)
                // id 는 offset — limitId 가 nil 인 bucket 이 2개 이상이면 \.limitId 는 충돌(행 누락)한다.
                // snapshots 순서는 결정적(sorted)이라 offset 안정. (scopedLimitEntries 와 동일 방식)
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    // bucket 이 여럿일 때만 구분 라벨 (단일 bucket 사용자는 기존 UI 그대로)
                    if buckets.count > 1 {
                        Text(bucket.bucketDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    codexLimitRow(name: l.codexWindow(bucket.primary?.windowDurationMins), window: bucket.primary,
                                  candyKey: UsageStore.codexCandyKey(bucket, secondary: false))
                    codexLimitRow(name: l.codexWindow(bucket.secondary?.windowDurationMins), window: bucket.secondary,
                                  candyKey: UsageStore.codexCandyKey(bucket, secondary: true))
                    codexSpendLimitRow(bucket.individualLimit)
                }
            }
            if selectedSnapshot?.providerID == "antigravity" {
                antigravityLimitsContent
            }
            if selectedSnapshot?.providerID == "cursor" {
                cursorLimitsContent
            }
            if selectedSnapshot?.providerID == "opencode" {
                openCodeGoLimitsContent
            }
            if selectedSnapshot?.providerID == "grok" {
                grokLimitsContent
            }
        }
    }

    @ViewBuilder
    private var cursorLimitsContent: some View {
        if store.cursorLimitsAuthExpired {
            cursorAuthExpiredNotice
        }
        if let status = store.cursorLimits, status.hasVisibleLimit {
            if store.cursorLimitsStale {
                staleBadge(updatedAt: store.cursorLimitsUpdatedAt)
            }
            if let message = status.displayMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let usage = status.planUsage, let used = usage.usedPercent {
                    cursorLimitRow(name: l.cursorMonthlyIncluded, utilization: used, reset: status.billingCycleEndDate)
                    if let remaining = usage.remainingDollars {
                        Text(l.cursorRemainingSpend(TokenFormatter.cost(remaining)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let auto = status.planUsage?.autoPercentUsed {
                    cursorLimitRow(name: l.cursorAutoUsage, utilization: auto, reset: nil)
                }
                if let api = status.planUsage?.apiPercentUsed {
                    cursorLimitRow(name: l.cursorApiUsage, utilization: api, reset: nil)
                }
            }
            .opacity(store.cursorLimitsAuthExpired ? 0.5 : 1)
        }
    }

    /// Same row as every other limit, so the bar follows the used/remaining display mode and
    /// the colors follow the pace gauge. The billing cycle has no fixed span, so no pace marker.
    private func cursorLimitRow(name: String, utilization: Double, reset: Date?) -> some View {
        quotaRow(name: name, utilization: utilization, reset: reset)
    }

    @ViewBuilder
    private var openCodeGoLimitsContent: some View {
        if store.openCodeGoLimitsAuthExpired {
            authExpiredNotice(title: l.openCodeGoAuthExpiredTitle, hint: l.openCodeGoAuthExpiredHint)
        }
        if let status = store.openCodeGoLimits, status.hasVisibleLimit {
            if store.openCodeGoLimitsStale {
                staleBadge(updatedAt: store.openCodeGoLimitsUpdatedAt)
            }
            VStack(alignment: .leading, spacing: 8) {
                openCodeGoLimitRow(name: l.fiveHourSession, window: status.rolling,
                                   span: LimitWindowSpan.fiveHour, notStartedHint: l.fiveHourNotStarted)
                openCodeGoLimitRow(name: l.weekly, window: status.weekly, span: LimitWindowSpan.sevenDay)
                // The monthly window follows the subscription date, not a fixed span: no pace marker.
                openCodeGoLimitRow(name: l.openCodeGoMonthly, window: status.monthly, span: nil)
            }
            .opacity(store.openCodeGoLimitsAuthExpired ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func openCodeGoLimitRow(name: String, window: OpenCodeGoWindow?, span: TimeInterval?,
                                    notStartedHint: String? = nil) -> some View {
        let now = Date()
        if let window, let utilization = window.utilization(now: now) {
            quotaRow(name: name, utilization: utilization, reset: window.activeReset(now: now), span: span,
                     idleHint: window.hasEnded(now: now) ? notStartedHint : nil)
        }
    }

    @ViewBuilder
    private var grokLimitsContent: some View {
        if store.grokLimitsAuthExpired {
            authExpiredNotice(title: l.grokAuthExpiredTitle, hint: l.grokAuthExpiredHint)
        }
        if let status = store.grokLimits, status.hasVisibleLimit {
            if store.grokLimitsStale {
                staleBadge(updatedAt: store.grokLimitsUpdatedAt)
            }
            let now = Date()
            VStack(alignment: .leading, spacing: 4) {
                if let utilization = status.utilization(now: now) {
                    quotaRow(name: l.grokCreditPeriod(weekly: status.isWeekly, monthly: status.isMonthly),
                             utilization: utilization, reset: status.activeReset(now: now), span: status.periodSpan)
                }
                let products = status.usedProducts(now: now)
                if !products.isEmpty {
                    Text(products.map { "\(grokProductName($0.product)) \(TokenFormatter.percent($0.usagePercent ?? 0))" }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(store.grokLimitsAuthExpired ? 0.5 : 1)
        }
    }

    /// Billing product ids → the names grok.com shows.
    private func grokProductName(_ product: String?) -> String {
        switch product {
        case "GrokBot": return "Grok"
        case "GrokBuild": return "Grok Build"
        case "Api": return "API"
        default: return product ?? ""
        }
    }

    private func authExpiredNotice(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.readableOrange)
                Text(title)
                    .font(.caption).fontWeight(.medium)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var cursorAuthExpiredNotice: some View {
        authExpiredNotice(title: l.cursorAuthExpiredTitle, hint: l.cursorAuthExpiredHint)
    }

    @ViewBuilder
    private var antigravityLimitsContent: some View {
        if store.antigravityLimitsAuthExpired {
            antigravityAuthExpiredNotice
        } else if !store.disableKeychainAccess && (store.antigravityLimits == nil || store.antigravityLimitsStale) {
            antigravityRefreshRow
        }
        if let status = store.antigravityLimits, status.hasVisibleLimit {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(status.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l.antigravityGroupTitle(group.displayName))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.buckets, id: \.bucketId) { bucket in
                            antigravityBucketRow(bucket, group: group)
                        }
                    }
                }
            }
            .opacity(store.antigravityLimitsAuthExpired ? 0.5 : 1)
        }
    }

    private func antigravityBucketRow(_ bucket: AntigravityQuotaBucket, group: AntigravityQuotaGroup) -> some View {
        let weekly = bucket.isWeeklyWindow
        let paysCandies = weekly || bucket.is5HourWindow
        return quotaRow(name: l.antigravityWindow(window: bucket.window, bucketId: bucket.bucketId),
                        utilization: bucket.usedPercent, reset: bucket.resetDate,
                        span: bucket.windowSpan,
                        candyKey: paysCandies ? UsageStore.antigravityCandyKey(group, weekly: weekly) : nil)
    }

    @ViewBuilder
    private var antigravityRefreshRow: some View {
        HStack(spacing: 6) {
            if store.antigravityLimits == nil {
                Text(l.limitsTapToLoad)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                (Text(l.staleLimits) + Text(" · ") + Text(store.antigravityLimitsUpdatedAt ?? Date(), style: .relative))
                    .font(.caption).foregroundStyle(Color.readableOrange)
            }
            Spacer()
            Button {
                Task { await store.refreshAntigravityLimitsFromKeychain() }
            } label: {
                if store.isRefreshingAntigravityLimits {
                    ProgressView().controlSize(.small)
                } else {
                    Text(l.refresh)
                }
            }
            .controlSize(.small)
            .disabled(store.isRefreshingAntigravityLimits)
        }
    }

    @ViewBuilder
    private var antigravityAuthExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.readableOrange)
                Text(l.antigravityAuthExpiredTitle)
                    .font(.caption).fontWeight(.medium)
            }
            Text(l.antigravityAuthExpiredHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(l.retry) {
                Task { await store.refreshAntigravityLimitsFromKeychain() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .padding(.top, 2)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }


    /// 한도 % 표시 문자열 — remaining 모드면 남은 %에 자기설명 접미사("남음/left/残り").
    /// 게이지 채움도 같은 표시 모드를 따르며, 경고색은 실제 사용률로 판단한다.
    private func limitPercentText(_ utilization: Double) -> String {
        let text = TokenFormatter.percent(store.limitDisplayPercent(utilization))
        return store.limitDisplayMode == .remaining ? l.percentRemaining(text) : text
    }

    /// 리셋이 이 창 안(≤ 6h)이거나 오늘이면 벽시계 접미사를 "HH:mm" 만으로 짧게 낸다.
    /// 그 밖(주간 한도 등 며칠 뒤)이면 요일·일자를 붙여 "HH:mm" 만으로 생기는 오해를 막는다.
    /// 어느 쪽이든 접미사는 항상 붙는다 — 프로바이더 리터럴 분기 없이 리셋 근접도만 본다
    /// (확장 규약: 플랫폼 종속 분기 금지).
    private static let resetClockWindow: TimeInterval = 6 * 3600

    /// 카운트다운 뒤에 붙는 절대 리셋 시각 " (…)". 오늘 안이거나 ≤ 6h 면 시:분만,
    /// 며칠 뒤(주간 한도 등)면 요일·일자까지 — "in 2 days, 9 hr" 만으론 언제 풀리는지 감이 안 와서다.
    /// 요일명은 팝오버 로케일(companion.language)로 현지화하고, 시각은 항상 24시간 표기.
    private func resetClockSuffix(_ reset: Date) -> Text {
        let f = DateFormatter()
        f.locale = companion.language.displayLocale
        let nearby = Calendar.current.isDateInToday(reset)
            || reset.timeIntervalSinceNow <= Self.resetClockWindow
        f.setLocalizedDateFormatFromTemplate(nearby ? "HHmm" : "EEEEdHHmm")
        return Text(" (\(f.string(from: reset)))")
    }
    private func resetLabel(_ reset: Date) -> Text {
        Text("\(reset, style: .relative)") + resetClockSuffix(reset)
    }

    /// 페이스 기준선 — 리셋 시각과 창 길이가 **둘 다** 있어야 그린다. 창 길이를 모르는 행
    /// (Codex 개인 지출 한도)은 자연히 nil 이 되어 마커가 빠진다.
    /// `Date()` 를 body 평가 시점에 읽으므로 갱신 주기·팝오버 재오픈마다 눈금이 이동한다.
    private func paceFraction(reset: Date?, span: TimeInterval?) -> Double? {
        guard let reset, let span else { return nil }
        return UsageStore.paceFraction(resetsAt: reset, span: span, now: Date())
    }

    /// 툴팁 문구. 숫자도 `limitDisplayPercent` 를 거쳐 눈금 위치와 같은 방향을 말한다.
    /// 단계가 있으면 이름과 차이를 첫 줄에 둔다 — 행에는 색만 있으므로 글로 된 단계는 여기서 준다.
    private func paceHelp(_ pace: Double?, tier: PaceTier?, utilization: Double) -> String? {
        guard let pace else { return nil }
        let hint = l.paceHint(TokenFormatter.percent(store.limitDisplayPercent(pace * 100)))
        guard let tier else { return hint }
        var head = l.paceTier(tier)
        if let delta = l.paceDelta(PaceTier.roundedDelta(utilization: utilization, pace: pace)) {
            head += " · " + delta
        }
        return head + "\n" + hint
    }

    @ViewBuilder
    private func limitRow(name: String, window: LimitWindow?, span: TimeInterval?,
                          notStartedHint: String? = nil, candyKey: String? = nil) -> some View {
        if let window, let utilization = window.utilization {
            quotaRow(name: name, utilization: utilization, reset: window.resetDate, span: span,
                     idleHint: window.hasNotStarted ? notStartedHint : nil, candyKey: candyKey)
        }
    }

    /// The Rare Candies a limit window paid in its epoch, of those a whole window pays (`RareCandy.windowCandies`).
    /// Nil for a window that pays none (another account not armed yet, a window the candies do not read).
    private func candyTally(_ key: String) -> (paid: Int, whole: Int)? {
        guard let window = store.candyEligibleWindows.first(where: { $0.key == key }) else { return nil }
        let whole = RareCandy.windowCandies(kind: window.kind, planMultiplier: window.planMultiplier)
        return (min(whole, companion.state.candyGrantTier[key] ?? 0), whole)
    }

    /// "2 of 5 · next at 60%": what the window paid, and the usage that pays the next candy.
    private func candyLine(_ tally: (paid: Int, whole: Int)) -> some View {
        let next = tally.paid < tally.whole
            ? l.candyNext(limitPercentText(Double(tally.paid + 1) * 100 / Double(tally.whole)))
            : l.candyWindowComplete
        return HStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.readableOrange)
                Text(l.candyTally(tally.paid, of: tally.whole)).fontWeight(.semibold)
            }
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.readableOrange.opacity(0.16)))
            Text(next).foregroundStyle(.secondary)
        }
        .font(.caption2).monospacedDigit()
        .hoverTip(l.candyTallyHelp(l.itemName(.rareCandy)))
    }

    /// All quota types share the same trailing percentage alignment.
    /// `span` 은 창 길이 — 리셋 시각과 함께 주어질 때만 페이스 눈금을 그린다. 기본 nil 이라
    /// 창 길이를 모르는 행(Codex 개인 지출 한도)은 호출을 바꾸지 않아도 눈금 없이 남는다.
    private func quotaRow(name: String, utilization: Double, reset: Date?,
                          span: TimeInterval? = nil, detail: String? = nil,
                          idleHint: String? = nil, candyKey: String? = nil) -> some View {
        let tally = candyKey.flatMap(candyTally)
        let pace = paceFraction(reset: reset, span: span)
        // 페이스가 있으면 페이스 대비 단계색, 없거나 창 초반 보류 중이면 기존 절대 임계색.
        let tier = PaceTier.tier(utilization: utilization, pace: pace, critThreshold: store.critThreshold)
        // Same rule as the menu bar items (`UsageStore.menuLimitColorRuns`).
        let gauge = PaceTier.gauge(utilization: utilization, pace: pace,
                                   warnThreshold: store.warnThreshold, critThreshold: store.critThreshold)
        let tint = gauge.color
        let percentTint = gauge.percentColor
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.callout)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let reset {
                    resetLabel(reset)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let idleHint {
                    Text(idleHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(limitPercentText(utilization))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(percentTint)
            }
            // Notches only while they stay apart: five a window at most (a Pro week, a Max 5x session).
            LimitProgressBar(usedPercent: utilization, tint: tint, pace: pace,
                             candies: tally.flatMap { $0.whole <= 5 ? $0 : nil })
            if let tally { candyLine(tally) }
        }
        // `hoverTip` shows nothing for a nil text; an `if` around it rebuilt the row each time the help came or went.
        .hoverTip(paceHelp(pace, tier: tier, utilization: utilization))
    }

    @ViewBuilder
    private func codexMetaRow(_ status: CodexRateLimitStatus) -> some View {
        // plan 은 계정 속성 — bucket 필터와 무관하게 top-level 에서 읽는다 (로그와 동일 소스)
        let planType = status.rateLimits.planType ?? status.visibleSnapshots.first?.planType
        let reached = status.visibleSnapshots.contains { $0.rateLimitReachedType != nil }
        if planType != nil || reached || store.codexLimitsStale {
            HStack(spacing: 8) {
                if let plan = planType {
                    Text(l.plan(plan))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if reached {
                    Text(l.limitReached)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                // 갱신 실패가 15분+ 이어지면 이전 스냅샷임을 노출 (codex TUI stale 임계와 동일)
                if store.codexLimitsStale {
                    staleBadge(updatedAt: store.codexLimitsUpdatedAt)
                }
            }
        }
    }

    /// Claude 세션 만료(401) 안내 — 자동 폴링은 만료 토큰을 스스로 못 고치므로,
    /// "왜 어제 값에 멈췄는지 + 원탭 재시도 + Claude Code 실행 시 자동 갱신" 을 눈에 띄게 노출.
    @ViewBuilder
    /// 세션 키 만료 — OAuth 안내와 달리 재시도가 의미 없다(죽은 쿠키는 재조회로 안 살아난다).
    /// 그래서 버튼이 Keychain 을 읽지 않고, 키를 다시 넣을 수 있는 화면으로 보낸다.
    private var sessionKeyExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "key.slash.fill")
                    .foregroundStyle(Color.readableOrange)
                Text(l.sessionKeyExpiredTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Button(l.settings) { nav.openSessionKeySettings() }
                    .controlSize(.small)
            }
            Text(l.sessionKeyExpiredNoticeHint)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var claudeAuthExpiredNotice: some View {
        authExpiredNotice(hint: l.claudeAuthExpiredHint)
    }

    /// Expired session banner with a retry: the default account above the tabs, an additional
    /// account inside its tab (retry reads its renewed token once Claude Code ran on that folder).
    private func authExpiredNotice(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.readableOrange)
                Text(l.claudeAuthExpiredTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await store.refreshLimitTokenFromKeychain() }
                } label: {
                    if store.isRefreshingLimitToken {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.retry)
                    }
                }
                .controlSize(.small)
                .disabled(store.isRefreshingLimitToken)
            }
            Text(hint)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Claude 공식 한도 — 최초 로드/만료(stale) 시 사용자가 원탭으로 Keychain 을 읽어 갱신.
    /// 자동 폴링이 Keychain 을 안 읽는 대신 여기서 명시적 사용자 동작으로만 재취득한다.
    private var claudeKeychainHelpButton: some View {
        Button {
            showingClaudeKeychainHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .hoverTip(l.claudeKeychainHelpTooltip)
        .accessibilityLabel(l.claudeKeychainHelpTooltip)
    }

    /// The help the button opens, under the section title. Inline rather than a SwiftUI `.popover`: a popover inside
    /// the menu bar popover can outlive it as an orphan window.
    private var claudeKeychainHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.claudeKeychainHelpTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer(minLength: 4)
                Button {
                    showingClaudeKeychainHelp = false
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l.close)
            }
            Text(l.claudeKeychainHelpBody)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(l.registerSessionKey) {
                    showingClaudeKeychainHelp = false
                    nav.openSessionKeySettings()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Claude official limits, one tab per account when there are several (default login first).
    @ViewBuilder
    private var claudeAccountsContent: some View {
        let accounts = store.claudeAccounts
        if accounts.count > 1 {
            let trackedID = store.trackedClaudeAccount?.id
            CapsuleTabBar(
                items: accounts.map {
                    CapsuleTabBar.Item(id: $0.id, title: $0.title, help: $0.status.accountDisplay,
                                       marked: $0.id == trackedID)
                },
                selectedID: selectedClaudeAccount(in: accounts)?.id,
                onSelect: { nav.claudeAccountID = $0 })
        }
        if let account = selectedClaudeAccount(in: accounts) {
            claudeAccountLimits(account, showsUsage: accounts.count > 1)
        }
        // Tab totals do not add up to the header when some sessions belong to no login's history.
        if accounts.count > 1, store.unattributedClaudeUsage.monthTokens > 0 {
            Text(l.unattributedClaudeUsage(TokenFormatter.compact(store.unattributedClaudeUsage.monthTokens)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func selectedClaudeAccount(in accounts: [ClaudeAccountLimits]) -> ClaudeAccountLimits? {
        accounts.first { $0.id == nav.claudeAccountID } ?? accounts.first
    }

    @ViewBuilder
    private func claudeAccountLimits(_ account: ClaudeAccountLimits, showsUsage: Bool) -> some View {
        let limits = account.status
        if account.isExpired, !account.isDefault {
            // A dead session key is fixed in Settings; the retry banner would only read the Keychain.
            if account.sessionKeyExpired {
                sessionKeyExpiredNotice
            } else {
                authExpiredNotice(hint: l.additionalAccountExpiredHint(account.fallbackTitle))
            }
        } else if !account.isDefault, account.isStale() {
            // The default account's stale label lives in the refresh row above the tabs.
            staleBadge(updatedAt: account.updatedAt)
        }
        // 플랜(계정 속성) — Codex codexMetaRow 와 동일 스타일. 구독 정보 있을 때만 노출.
        if let plan = limits.planDisplay {
            Text(l.plan(plan))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        // 계정 라벨 — 두 계정이 한 Keychain 항목을 번갈아 쓰는 기기에서 이 한도가
        // 어느 계정 것인지 알려준다 (없으면 라벨 없이 종전과 동일).
        if let accountLabel = limits.accountDisplay {
            Text(l.limitsAccount(accountLabel))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        // This account's share of the local usage (the header keeps the machine-wide totals).
        if showsUsage, let usage = store.claudeAccountUsage[account.id], !usage.isEmpty {
            HStack(spacing: 14) {
                periodLabel(l.today, tokens: usage.todayTokens, cost: store.showsCost ? usage.todayCost : nil)
                periodLabel(l.thisMonth, tokens: usage.monthTokens, cost: store.showsCost ? usage.monthCost : nil)
                Spacer()
            }
        }
        // 세션 만료 시 표시값은 만료 전 기준 → 흐리게 처리해 "현재 값 아님"을 시각적으로 전달
        VStack(alignment: .leading, spacing: 8) {
            limitRow(name: l.fiveHourSession, window: limits.fiveHour,
                     span: LimitWindowSpan.fiveHour, notStartedHint: l.fiveHourNotStarted,
                     candyKey: UsageStore.claudeCandyKey(account, weekly: false))
            // The forecast follows the tracked account (it combines that account's utilization with local usage).
            if account.id == store.trackedClaudeAccount?.id { forecastRow }
            limitRow(name: l.weekly, window: limits.sevenDay,
                     span: LimitWindowSpan.sevenDay, candyKey: UsageStore.claudeCandyKey(account, weekly: true))
            limitRow(name: l.weeklyOpus, window: limits.sevenDayOpus,
                     span: LimitWindowSpan.sevenDay)
            limitRow(name: l.weeklySonnet, window: limits.sevenDaySonnet,
                     span: LimitWindowSpan.sevenDay)
            // 신형 limits[] — 모델별 주간(weekly_scoped) 등 레거시 필드 밖 윈도우
            ForEach(Array(limits.scopedLimitEntries.enumerated()), id: \.offset) { _, entry in
                limitRow(
                    name: l.claudeLimitEntry(kind: entry.kind, model: entry.scope?.model?.displayName),
                    window: LimitWindow(utilization: entry.percent, resetsAt: entry.resetsAt),
                    span: entry.windowSpan)
            }
            // 전 프로바이더가 블록을 갖게 됨 — "Claude 현재 5h 블록" 행은 명시 조회
            if let block = store.claudeCurrentBlock(for: account), let end = block.endDate {
                HStack {
                    Text(l.claudeCurrentBlock)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TokenFormatter.compact(block.totalTokens))
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    (Text("\(l.reset) ") + Text(end, style: .relative) + resetClockSuffix(end))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(account.isExpired ? 0.5 : 1)
    }

    /// 자동 폴링이 Keychain 을 안 읽는 대신 여기서 명시적 사용자 동작으로만 재취득한다.
    @ViewBuilder
    private var claudeLimitsRefreshRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // The row also shows for another account's pending refresh: only call the values
                // stale when the default account's own values are.
                if store.limits != nil, store.claudeLimitsStale {
                    (Text(l.staleLimits) + Text(" · ") + Text(store.limitsUpdatedAt ?? Date(), style: .relative))
                        .font(.caption).foregroundStyle(Color.readableOrange)
                } else {
                    Text(l.limitsTapToLoad)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refreshLimitTokenFromKeychain() }
                } label: {
                    if store.isRefreshingLimitToken {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.refresh)
                    }
                }
                .controlSize(.small)
                .disabled(store.isRefreshingLimitToken)
            }
            // Without this the button looks inert when the refresh fails (e.g. rate limited):
            // the reason was only shown in Settings.
            if let error = store.limitTokenRefreshMessage, !store.isRefreshingLimitToken {
                Text(error)
                    .font(.caption2).foregroundStyle(Color.readableOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 한도 스냅샷 갱신 지연 배지 — Claude/Codex 공용 (마지막 성공 시각 상대 표시).
    @ViewBuilder
    private func staleBadge(updatedAt: Date?) -> some View {
        if let updatedAt {
            (Text(l.staleLimits) + Text(" · ") + Text(updatedAt, style: .relative))
                .font(.caption)
                .foregroundStyle(Color.readableOrange)
        }
    }

    @ViewBuilder
    private func codexLimitRow(name: String, window: CodexRateLimitWindow?, candyKey: String? = nil) -> some View {
        if let window {
            quotaRow(name: name, utilization: Double(window.usedPercent), reset: window.resetDate,
                     span: window.windowSpan, candyKey: candyKey)
        }
    }

    @ViewBuilder
    private func codexSpendLimitRow(_ limit: CodexSpendControlLimit?) -> some View {
        if let limit {
            quotaRow(name: l.personalSpendLimit, utilization: Double(limit.usedPercent),
                     reset: limit.resetDate, detail: "\(limit.used) / \(limit.limit)")
        }
    }

    /// 한도 소진 예측 — 현재 burn rate 로 5h 한도 100% 도달 시각 외삽
    @ViewBuilder
    private var forecastRow: some View {
        if let forecast = store.fiveHourForecast {
            HStack(spacing: 4) {
                Image(systemName: forecast.beforeReset
                    ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption2)
                Text(forecast.beforeReset
                    ? l.forecastReach(Self.timeFormatter.string(from: forecast.depletionDate))
                    : l.forecastNoReach)
                    .font(.caption)
            }
            .foregroundStyle(forecast.beforeReset ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .padding(.leading, 2)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: 푸터

    private var footer: some View {
        HStack(spacing: 10) {
            // 갱신·"Updated" 시각·에러 삼각형은 사용량 신선도 UI — 사용량을 표시하지 않는 탭(도감/가방/상점)에선
            // "뭘 갱신하라는 건지" 혼란만 줘서 홈 탭에서만 노출한다. 설정/종료는 전역이라 아래에 그대로 둔다.
            if nav.tab == .home {
                // 스피너 스왑을 두지 않는다 — 로컬 파싱이 보이는 오늘 숫자를 즉시 갱신하는데
                // enrichment/한도(네트워크)까지 기다리는 스피너가 데이터보다 오래 돌아 불필요해 보였다.
                // 중복 클릭은 refresh() 의 재진입 guard 가 무시하고, 피드백은 아래 "Updated" 시각이 준다.
                CircleIconButton(systemImage: "arrow.clockwise", help: l.refreshNow) {
                    Task { await store.refresh() }
                }
                if let updated = store.lastUpdated {
                    // One line: with the calendar's button the six icons left it some 70 points, and "Mis à jour 3 s"
                    // broke in two.
                    (Text("\(l.updated) ") + Text(updated, style: .relative))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if store.lastErrorDescription != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.readableOrange)
                        .hoverTip(store.lastErrorMessage(l) ?? "")
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                // The menu bar's Pokémon, hidden in one click, its token lines staying (a meeting, a shared screen). The
                // floating pet it used to switch is in Settings and in the status item's menu (#301: not lost once
                // hidden). Without any token line the menu bar keeps the Pokémon, or nothing would be left to click.
                let spriteHidden = store.menuSpriteMode == .hidden
                CircleIconButton(systemImage: spriteHidden ? "eye.slash" : "eye",
                                 help: spriteHidden ? l.menuSpriteShowLabel : l.menuSpriteHideLabel) {
                    store.toggleMenuSprite()
                }
                CircleIconButton(systemImage: "lightbulb", help: l.ideasTitle) { nav.showingIdeas = true }
                CircleIconButton(systemImage: "calendar", help: l.calendarTitle) { nav.showingCalendar = true }
                CircleIconButton(systemImage: "newspaper", help: l.changelogTitle) { openChangelog() }
                    .overlay(alignment: .topTrailing) {
                        if store.hasUnseenChangelog {
                            Circle().fill(Color.red).frame(width: 7, height: 7).offset(x: 1, y: -1)
                        }
                    }
                CircleIconButton(systemImage: "gearshape", help: l.settings) { nav.showSettings = true }
                CircleIconButton(systemImage: "power", help: l.quit) { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

/// Per-provider stacking of the daily bars (the Stats page), pure so the ordering and the height split can be
/// checked headlessly. The split is where a view-local version goes quietly wrong: independently scaled segments do
/// not sum to the bar, and the stacked bar then disagrees with the single-color bar's height for the same day.
enum DailyTrendStack {
    /// Segment colors, indexed by `colorIndices`. At least one per registered provider, so no two of them share a
    /// color (a test pins this). A provider registered past the palette wraps around; the legend names it.
    static let palette: [Color] = [
        Color(red: 0.85, green: 0.47, blue: 0.34),
        Color(red: 0.36, green: 0.62, blue: 0.95),
        Color(red: 0.45, green: 0.78, blue: 0.52),
        Color(red: 0.78, green: 0.55, blue: 0.92),
        Color(red: 0.95, green: 0.76, blue: 0.32),
        Color(red: 0.35, green: 0.78, blue: 0.80),
        Color(red: 0.93, green: 0.51, blue: 0.68),
        Color(red: 0.62, green: 0.64, blue: 0.70),
        Color(red: 0.88, green: 0.80, blue: 0.60),
        Color(red: 0.70, green: 0.82, blue: 0.38),
        Color(red: 0.60, green: 0.42, blue: 0.30),
        Color(red: 0.30, green: 0.60, blue: 0.55),
        Color(red: 0.80, green: 0.35, blue: 0.40),
        Color(red: 0.40, green: 0.48, blue: 0.80),
        Color(red: 0.96, green: 0.58, blue: 0.22),
        Color(red: 0.76, green: 0.58, blue: 0.38),
    ]

    struct ProviderSeries {
        var id: String
        var name: String
        var days: [DailyUsage]
        var reportsCost: Bool
    }

    struct Segment: Equatable {
        var providerID: String
        var tokens: Int
        var height: CGFloat
    }

    /// Providers that used anything this month, largest month total first (bottom of the stack).
    /// Ties break on id so the order cannot flip between refreshes.
    static func ordered(_ providers: [ProviderSeries]) -> [ProviderSeries] {
        let totals: [(provider: ProviderSeries, tokens: Int)] = providers.map { provider in
            (provider, provider.days.reduce(0) { $0 + $1.totalTokens })
        }
        return totals
            .filter { $0.tokens > 0 }
            .sorted { lhs, rhs in
                lhs.tokens != rhs.tokens ? lhs.tokens > rhs.tokens : lhs.provider.id < rhs.provider.id
            }
            .map(\.provider)
    }

    /// Whether the row stacks at all. With one provider (or none) the row stays the plain
    /// single-color bar with today in the accent color.
    static func isStacked(_ ordered: [ProviderSeries]) -> Bool { ordered.count > 1 }

    /// Segments of `date`'s bar, bottom → top in `ordered` order. Zero-token providers are left
    /// out. Heights come from cumulative shares, so they add up to exactly `barHeight` with no
    /// rounding drift. Empty when nobody used anything that day.
    static func segments(on date: String, stack ordered: [ProviderSeries],
                         barHeight: CGFloat) -> [Segment] {
        let parts = ordered.compactMap { provider -> (String, Int)? in
            let tokens = provider.days.first { $0.date == date }?.totalTokens ?? 0
            return tokens > 0 ? (provider.id, tokens) : nil
        }
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }

        var segments: [Segment] = []
        var running = 0
        var placed: CGFloat = 0
        for (index, part) in parts.enumerated() {
            running += part.1
            let top = index == parts.count - 1
                ? barHeight
                : barHeight * CGFloat(running) / CGFloat(total)
            segments.append(Segment(providerID: part.0, tokens: part.1, height: top - placed))
            placed = top
        }
        return segments
    }

    /// Palette slot per provider id: its registration index (`UsageStore.registeredProviderIDs`) modulo the
    /// palette. It depends on nothing but that index, so a provider keeps its color as others become
    /// active or idle and as usage rank shifts during the month. Past the palette size colors repeat;
    /// the legend and tooltip name the providers, so a shared color stays readable.
    static func colorIndices(for ids: [String], registry: [String],
                             paletteCount: Int) -> [String: Int] {
        var slots: [String: Int] = [:]
        for id in ids {
            slots[id] = (registry.firstIndex(of: id) ?? 0) % paletteCount
        }
        return slots
    }
}

/// Lays children left to right, starting a new line when the next one would not fit the width.
struct WrappingHStack: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}

/// 서비스 전환 탭. 프로바이더가 늘면 캡슐 합계 폭이 `PopoverMetrics.contentWidth` 를 넘는다
/// (6개 기준 439pt vs 332pt). 폭 제한만 있고 줄바꿈을 막지 않으면 SwiftUI 가 캡슐 텍스트를 눌러
/// "Curso/r"·"Code/x" 처럼 **단어 중간에서** 접고 탭 바가 2~3줄이 된다.
/// 가로 스크롤 + `lineLimit(1)`/`fixedSize` 로 각 탭이 항상 자연 폭 한 줄을 유지한다.
/// (`Spacer()` 는 가로 ScrollView 안에서 무한 확장하므로 쓰지 않는다.)
@MainActor
struct ProviderTabBar: View {
    let snapshots: [ProviderSnapshot]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        CapsuleTabBar(
            items: snapshots.map { CapsuleTabBar.Item(id: $0.providerID, title: $0.displayName) },
            selectedID: selectedID,
            onSelect: onSelect)
    }
}

/// Capsule tabs shared by the service tabs and the Claude account tabs (layout notes on `ProviderTabBar`).
@MainActor
struct CapsuleTabBar: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var help: String? = nil
        /// A small dot before the title (the Claude account the menu bar follows).
        var marked = false
    }

    let items: [Item]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    let isSelected = item.id == selectedID
                    Button { onSelect(item.id) } label: {
                        HStack(spacing: 4) {
                            if item.marked {
                                Circle().frame(width: 5, height: 5)
                            }
                            Text(item.title)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverTip(item.help ?? "")
                }
            }
        }
        // 탭이 적으면(대부분의 사용자) 스크롤·바운스가 생기지 않아 기존과 동일하게 보인다.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// Text and fill describe the same quantity; warning colors still represent actual usage.
@MainActor
struct LimitProgressBar: View {
    let usedPercent: Double
    let tint: Color
    /// 창이 지난 비율(0…1) — 균등하게 썼다면 채움이 여기 있어야 한다. nil 이면 마커 없음.
    var pace: Double?
    /// The window's Rare Candies: a notch at each one's usage, in candy orange once paid.
    var candies: (paid: Int, whole: Int)?
    @Environment(UsageStore.self) private var store

    /// 마커 가로 위치(0…1). 채움과 **같은 변환**(`displayPercent`)을 거치게 해서, 잔량 모드에서
    /// 채움만 뒤집히고 마커는 그대로 남는 어긋남(#286 부류)이 구조적으로 생길 수 없게 한다.
    nonisolated static func markerFraction(pace: Double?, mode: UsageStore.LimitDisplayMode) -> Double? {
        guard let pace else { return nil }
        return UsageStore.displayPercent(pace * 100, mode: mode) / 100
    }

    var body: some View {
        ProgressView(value: min(100, max(0, store.limitDisplayPercent(usedPercent))), total: 100)
            .tint(tint)
            .controlSize(.small)
            .overlay { candyNotches }
            .overlay { paceMarker }
    }

    /// The candies' notches, through the same transform as the fill (`displayPercent`), so the remaining mode
    /// mirrors them with it. None at the bar's end: the last candy is the window's full.
    @ViewBuilder
    private var candyNotches: some View {
        if let candies, candies.whole > 1 {
            GeometryReader { geo in
                ForEach(1..<candies.whole, id: \.self) { i in
                    let fraction = UsageStore.displayPercent(Double(i) * 100 / Double(candies.whole),
                                                             mode: store.limitDisplayMode) / 100
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        // Candy orange, pale until paid: never the pace marker's grey.
                        .fill(Color.readableOrange.opacity(i <= candies.paid ? 1 : 0.35))
                        .frame(width: 2, height: Self.markerHeight)
                        .offset(x: (geo.size.width - 2) * fraction, y: (geo.size.height - Self.markerHeight) / 2)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 짧고 통통한 세로 눈금. 새 타이머를 두지 않는다 — 5시간 창에서 분당 0.33%p 라 갱신 주기
    /// (refreshInterval, 기본 120초)와 팝오버 재오픈만으로 충분히 "시간 따라 이동"한다.
    @ViewBuilder
    private var paceMarker: some View {
        if let fraction = Self.markerFraction(pace: pace, mode: store.limitDisplayMode) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Self.markerWidth / 2, style: .continuous)
                    .fill(.primary.opacity(0.55))
                    .frame(width: Self.markerWidth, height: Self.markerHeight)
                    // 양 끝에서도 선이 막대 밖으로 반쯤 걸치지 않도록 폭을 빼고 배분한다.
                    .offset(x: (geo.size.width - Self.markerWidth) * fraction,
                            y: (geo.size.height - Self.markerHeight) / 2)
            }
            .allowsHitTesting(false)
        }
    }

    /// 2.5pt = 2배 화면에서 딱 5px — 반픽셀에 걸려 흐려지지 않는 가장 얇은 "선 아닌 눈금" 굵기.
    private static let markerWidth: CGFloat = 2.5
    /// 눈금 길이는 `geo.size.height`(=12pt 레이아웃 칸)가 아니라 **실제로 칠해지는 트랙**에
    /// 맞춘다. 칸 기준으로 잡았더니 6pt 막대에 16pt 눈금이 붙어 막대보다 눈금이 커 보였다.
    /// 위아래 2pt 씩만 물려 막대 위에 얹힌 눈금으로 읽히게 한다.
    /// The small linear `ProgressView` is 6 pt tall when built with the macOS 15 SDK (Xcode 16) and 3 pt with the
    /// macOS 26 SDK (Xcode 26, Swift 6.2), whatever macOS it runs on: the marker follows the SDK the app is built with.
    #if compiler(>=6.2)
    private static let trackHeight: CGFloat = 3
    #else
    private static let trackHeight: CGFloat = 6
    #endif
    private static let markerOverhang: CGFloat = 2
    private static let markerHeight: CGFloat = trackHeight + markerOverhang * 2
}

/// 단계색은 시스템 색 — 라이트/다크에서 각각 조정된 값으로 바뀌고, 최상위(.red)는
/// `limitColor` 의 crit 색과 같아 "crit 이면 항상 빨강"이 두 경로에서 같은 색으로 보인다.
extension PaceTier {
    var color: Color {
        switch self {
        case .wayUnder: return .blue
        case .under: return .teal
        case .onPace: return .green
        case .slightlyOver: return .yellow
        case .over: return .orange
        case .wayOver: return .red
        }
    }

    /// % 숫자색. 노랑 글자는 라이트 모드 배경에서 거의 안 읽혀 그 단계만 기본 글자색으로 둔다 —
    /// 단계는 채움 색과 툴팁이 여전히 말해 준다.
    var percentColor: Color { self == .slightlyOver ? .primary : color }
}

/// A horizontal line across its frame, for dashed guides.
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

private extension EventEgg {
    /// The banner's two colors: the button's, then the gradient's end.
    var bannerColors: (Color, Color) {
        switch self {
        case .newYear: return (.indigo, .yellow)
        case .valentine: return (.pink, .red)
        case .pokemonDay: return (.red, .blue)
        case .easter: return (.green, .yellow)
        case .halloween: return (.orange, .purple)
        case .christmas: return (.red, .green)
        case .companion: return (.teal, .pink)
        case .spring: return (.pink, .green)
        case .summer: return (.orange, .yellow)
        case .autumn: return (.brown, .orange)
        case .winter: return (.blue, .cyan)
        }
    }
}
