import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(UpdateChecker.self) private var updater
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginError: String?
    @State private var reportError: String?
    @State private var didCopyDiagnostics = false
    @State private var advancedExpanded = false
    @State private var isCheckingUpdate = false
    @State private var didCheckUpdate = false
    private var l: L { player.l }

    private var isBundledApp: Bool { AppEnv.isBundledApp }

    /// 현재 앱 버전 — 업데이트 적용 여부 확인용으로 설정창 하단에 표기.
    private static var appVersion: String {
        AppEnv.appVersion ?? "—"
    }

    // MARK: 레이아웃 — 헤더 고정 / 본문 스크롤 / 푸터 고정

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    generalGroup(store)
                    boxGroup(store)
                    menuBarGroup(store)
                    floatingPetGroup(store)
                    notificationsGroup(store)
                    updateGroup(store)
                    advancedGroup(store)
                    aboutSupportGroup
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(height: 460)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.backward")
                    Text(l.back)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text(l.settings).font(.headline)
            Spacer()
            // 좌측 뒤로 버튼과 시각적 균형 (제목 중앙 정렬 유지)
            Text(l.back).opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text("v\(Self.appVersion)")
            Text("·")
            footerLink("GitHub", "https://github.com/donky-ey/PokeDexBar")
            Text("·")
            footerLink("Web", "https://donky-ey.github.io/PokeDexBar/")
            Text("·")
            // 개발자 후원 — 기능 잠금·너지 없는 푸터 링크
            footerLink("♥ Sponsor", "https://github.com/sponsors/donky-ey")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 그룹 섹션

    @ViewBuilder
    private func generalGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.generalSectionTitle) {
            groupRow {
                Text(l.language)
                Spacer()
                Picker("", selection: Binding(
                    get: { player.language },
                    set: { player.setLanguage($0); store.localizationLanguage = $0 })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            groupRow {
                Text(l.refreshInterval)
                Spacer()
                Picker("", selection: $store.refreshInterval) {
                    ForEach(UsageStore.intervalPresets, id: \.value) { Text(l.intervalLabel($0.value)).tag($0.value) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.launchAtLogin)
                    if !isBundledApp {
                        Text(l.bundledOnly).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption2).foregroundStyle(.red)
                    }
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!isBundledApp)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)   // KeepAlive 에이전트(로그인 실행+크래시 재실행)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = "\(error.localizedDescription)"
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            }
            Divider()
            // 팝오버 컴패니언·플로팅 펫 스프라이트 공통 설정 — 플로팅 펫이 꺼져 있어도(기본값)
            // 팝오버 컴패니언은 항상 보이므로 조건 없이 여기 둔다.
            // (박스 칸 채우기와 달리 이건 스프라이트가 나오는 모든 화면에 걸린다.)
            toggleRow(l.antialiasLabel, $store.antialiasSprites)
        }
    }

    @ViewBuilder
    private func menuBarGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 6) {
            settingsSection(l.menuBarSectionTitle) {
                toggleRow(l.todayTokensShort, $store.showTokensInMenu)
                Divider()
                toggleRow(l.todayCost, $store.showCostInMenu)
                Divider()
                toggleRow(l.limitPercent, $store.showLimitInMenu)
            }
            Text(l.allOffHint).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func floatingPetGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.floatingPetSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.floatingPetEnableLabel)
                    Text(l.floatingPetHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $store.floatingPetEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if store.floatingPetEnabled {
                Divider()
                groupRow {
                    Text(l.floatingPetSizeLabel).font(.callout)
                    Slider(value: $store.floatingPetSize, in: 48...192, step: 8)
                    Text("\(Int(store.floatingPetSize))px")
                        .font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Divider()
                toggleRow(l.floatingPetBubbleAlertsLabel, $store.floatingPetBubbleAlerts)
                Divider()
                groupRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.floatingPetBurnSpeedLabel)
                        Text(l.floatingPetBurnSpeedHint).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $store.floatingPetBurnSpeed)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func notificationsGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.notificationsSection) {
            toggleRow(l.limitNotificationsLabel, $store.limitNotifications)
            if store.limitNotifications {
                Divider()
                groupRow {
                    Text(l.warning).font(.callout)
                    Slider(value: $store.warnThreshold, in: 50...95, step: 5)
                    Text(TokenFormatter.percent(store.warnThreshold))
                        .font(.caption).monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                Divider()
                groupRow {
                    Text(l.critical).font(.callout)
                    Slider(value: $store.critThreshold, in: 80...100, step: 5)
                    Text(TokenFormatter.percent(store.critThreshold))
                        .font(.caption).monospacedDigit().frame(width: 38, alignment: .trailing)
                }
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.statusChecksLabel)
                    Text(l.statusChecksHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $store.statusChecksEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func updateGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.updateSectionTitle) {
            toggleRow(l.updateNotificationsLabel, $store.updateNotificationsEnabled)
            Divider()
            groupRow {
                Text(l.checkForUpdatesLabel)
                Spacer()
                Button {
                    isCheckingUpdate = true
                    Task {
                        await updater.check(minInterval: 0)   // 수동 확인 — 레이트리밋 우회(강제 조회)
                        isCheckingUpdate = false
                        didCheckUpdate = true
                    }
                } label: {
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.checkNowButton)
                    }
                }
                .disabled(isCheckingUpdate)
            }
            // 확인 결과 — 알림을 꺼둔 사용자도 여기서 새 버전을 알고 바로 적용할 수 있게 업데이트 버튼을 함께 노출.
            if didCheckUpdate, !isCheckingUpdate {
                Divider()
                groupRow {
                    if let version = updater.available?.version {
                        Text(l.updateFound(version)).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(l.updateButton) { updater.applyUpdate() }.controlSize(.small)
                    } else {
                        Text(l.upToDate(Self.appVersion)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func advancedGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.advancedSectionTitle) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { advancedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.forward")
                        .font(.caption).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                    Text(l.advancedDisclosureLabel)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 9)

            if advancedExpanded {
                Divider()
                groupRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.disableKeychain)
                        Text(l.disableKeychainHint).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $store.disableKeychainAccess)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                groupRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.refreshLimitToken)
                        Text(l.onlyOnPress).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshLimitTokenFromKeychain() }
                    } label: {
                        if store.isRefreshingLimitToken {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(l.refreshLimitToken)
                        }
                    }
                    .disabled(store.disableKeychainAccess || store.isRefreshingLimitToken)
                }
                if let limitTokenRefreshError = store.limitTokenRefreshError {
                    Text(limitTokenRefreshError)
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                }
                Divider()
                Text(l.aggregationNote)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    /// 박스 — 보관함 칸을 어떻게 그릴지. 이 설정은 **박스에서만** 의미가 있다: 크기가 같은 칸이
    /// 나란히 놓이는 자리가 거기뿐이라, 작은 종이 유독 작아 보이는 문제도 거기서만 생긴다.
    /// (안티앨리어싱은 스프라이트가 나오는 모든 화면에 걸리므로 일반에 둔다.)
    private func boxGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        return settingsSection(l.boxSectionTitle) {
            toggleRow(l.fillBoxSlotsLabel, $store.fillBoxSlots)
        }
    }

    private var aboutSupportGroup: some View {
        settingsSection(l.aboutSupportSectionTitle) {
            // **버튼을 아랫줄로 내린다.** 설명 옆에 나란히 뒀더니 332pt 안에서 제목이 두 줄로
            // 접히고 설명이 6줄 기둥이 되며 두 번째 버튼 라벨이 잘렸다(렌더로 확인). 설명은
            // 전폭으로 두고 버튼만 오른쪽 아래에 모은다.
            groupRow {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.reportProblem)
                        Text(l.reportAttachHint).font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Spacer()
                        // GitHub 이 주 경로, 복사는 계정이 없거나 이슈가 잘렸을 때의 탈출구다.
                        SupportActionRow(label: l.reportOnGitHub, action: reportProblem)
                        SupportActionRow(
                            label: didCopyDiagnostics ? l.diagnosticsCopied : l.copyDiagnostics,
                            action: copyDiagnostics)
                    }
                }
            }
            Divider()
            // 로그 파일 보기 — 문제 제보 시 바로 첨부할 수 있게 같은 그룹에 둔다(고급 접기 밖).
            groupRow {
                Text(l.showLogFile)
                Spacer()
                Button("Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.logFileURL])
                }
            }
            if let reportError {
                Text(reportError)
                    .font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
    }

    // MARK: 공용 빌더

    /// 섹션 = 소문자 회색 타이틀 + 라운드 카드 (macOS inset grouped 룩).
    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor),
                           in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }

    /// 카드 내부 한 줄 — 좌 라벨 / 우 컨트롤.
    private func groupRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }

    private func toggleRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(label: label, isOn: isOn)
    }

    /// 푸터 링크 — 버전 표기와 동일한 크기·색을 상속하고 밑줄로만 구분.
    private func footerLink(_ title: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        } label: {
            Text(title).underline()
        }
        .buttonStyle(.plain)
        .help(urlString)
    }

    // MARK: 동작

    /// 문제 제보 — 진단이 채워진 GitHub 새 이슈 작성 페이지를 연다.
    /// 브라우저를 못 열면 주소를 안내(복사 가능)한다.
    private func reportProblem() {
        reportError = ProblemReport.openIssue(version: Self.appVersion, player: player, l: l)
    }

    /// 진단 전문을 클립보드에 — 이슈가 잘렸거나 다른 곳에 붙일 때의 탈출구.
    private func copyDiagnostics() {
        ProblemReport.copy(version: Self.appVersion, player: player)
        reportError = nil
        didCopyDiagnostics = true
    }

}

/// 제보 버튼 한 개. `SettingsToggleRow` 와 **같은 이유로** 별도 타입이다 — 버튼이 화면에서
/// 사라져도 로직 테스트는 전부 통과하므로, 화면에 실제로 붙어 있고 눌리는지를 여기서 잠근다.
struct SupportActionRow: View {
    let label: String
    let action: () -> Void

    #if DEBUG
    /// 테스트 전용 — 라벨과 **동작까지** 들고 있는다. 뷰만 만들고 안 누르면 배선이 끊겨
    /// 있어도 통과하기 때문이다.
    @MainActor static var constructed: [(label: String, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((label, action)) }
        #endif
    }

    var body: some View {
        Button(label, action: action)
    }
}

/// 설정 토글 한 줄. 별도 타입으로 뽑은 이유는 **설정이 화면에 실제로 붙어 있는지 잠그기 위해서**다 —
/// 스프라이트 부드럽게가 섹션을 옮기다 통째로 사라져 어느 화면에서도 못 켜는 상태로 남았던 적이 있다
/// (`UsageStore` 에는 값이 그대로 있어 저장·로드 테스트는 전부 통과했다). 사탕이 상점에서 팔리는데
/// 쓸 화면이 없던 결함과 같은 부류다.
struct SettingsToggleRow: View {
    let label: String
    let isOn: Binding<Bool>

    #if DEBUG
    /// 테스트 전용 — 이번 렌더에서 만들어진 토글 줄의 라벨.
    @MainActor static var constructed: [String] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(label: String, isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
        #if DEBUG
        if Self.isRecording { Self.constructed.append(label) }
        #endif
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
