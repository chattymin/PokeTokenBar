import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    /// 기존 컬렉션의 도감으로 돌아가 대표 포켓몬을 고르게 한다.
    var onChooseRepresentative: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginError: String?
    @State private var reportError: String?
    @State private var advancedExpanded = false
    @State private var isCheckingUpdate = false
    @State private var didCheckUpdate = false
    @State private var selectedScanProviderID = "claude_code"
    /// Provider the draft currently describes. Picker change updates `selectedScanProviderID`
    /// before the TextField blurs; committing against the selection would write Claude paths
    /// into `customScanRoots.gemini`.
    @State private var customScanDraftOwnerID = "claude_code"
    @State private var customScanDraft = ""
    @State private var customScanMatchCount = 0
    @State private var customScanMatchTask: Task<Void, Never>?
    @State private var customScanMatchGeneration = 0
    @FocusState private var customScanFocused: Bool
    private var l: L { companion.l }

    private var isBundledApp: Bool { AppEnv.isBundledApp }

    private var representativeSelectionText: String {
        guard let selected = companion.representativeSpeciesID,
              let species = companion.dexSpecies.first(where: { $0.id == selected }) else {
            return l.representativeFollowCurrent
        }
        return "#\(species.id) \(species.name)\(species.isShiny ? " ✨" : "")"
    }

    /// 세이브 봉투에 남길 출처 표기 — 어느 Mac에서 내보낸 파일인지 나중에 알아보기 위한 것.
    private static var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// 현재 앱 버전 — 업데이트 적용 여부 확인용으로 설정창 하단에 표기.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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
                    menuBarGroup(store)
                    floatingPetGroup(store)
                    phoneServerGroup(store)
                    notificationsGroup(store)
                    updateGroup(store)
                    transferGroup(store)
                    advancedGroup(store)
                    aboutSupportGroup
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            footerLink("GitHub", "https://github.com/chattymin/PokeTokenBar")
            Text("·")
            footerLink("Web", "https://chattymin.github.io/PokeTokenBar/")
            Text("·")
            // 개발자 후원 — 기능 잠금·너지 없는 푸터 링크
            footerLink("♥ Sponsor", "https://github.com/sponsors/chattymin")
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
                    get: { companion.language },
                    set: { companion.setLanguage($0); store.localizationLanguage = $0 })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            groupRow {
                Text(l.representativePokemonLabel)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button {
                        _ = companion.setRepresentativeSpeciesID(nil)
                    } label: {
                        if companion.representativeSpeciesID == nil {
                            Label(l.representativeFollowCurrent, systemImage: "checkmark")
                        } else {
                            Text(l.representativeFollowCurrent)
                        }
                    }
                    Button(l.representativeChooseFromDex, action: onChooseRepresentative)
                } label: {
                    Text(representativeSelectionText).lineLimit(1).truncationMode(.tail)
                }
                .controlSize(.small)
                .frame(width: 150, alignment: .trailing)
                .layoutPriority(1)
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
                Text(l.limitDisplayModeLabel)
                Spacer()
                Picker("", selection: $store.limitDisplayMode) {
                    Text(l.limitDisplayUsed).tag(UsageStore.LimitDisplayMode.used)
                    Text(l.limitDisplayRemaining).tag(UsageStore.LimitDisplayMode.remaining)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
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

    /// 서버 on/off + 페어링 코드. 코드는 서버가 켜져 있을 때만 — 꺼져 있으면 의미가 없고,
    /// 코드를 읽을 방법이 없으면 폰은 영구히 401 이다.
    @ViewBuilder
    private func phoneServerGroup(_ store: UsageStore) -> some View {
        @Bindable var store = store
        settingsSection(l.phoneServerSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.phoneServerEnableLabel)
                    Text(l.phoneServerHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $store.phoneServerEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if store.phoneServerEnabled {
                Divider()
                groupRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.phonePairingCodeLabel)
                        Text(l.phonePairingCodeHint).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    // 손으로 옮겨 적거나 복사할 수 있어야 한다.
                    Text(store.phoneServerPairingCode)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                Divider()
                groupRow {
                    Text(l.phonePairingRegenerateHint).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button(l.phonePairingRegenerate) { store.regeneratePhoneServerPairingCode() }
                        .controlSize(.small)
                }
            }
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
            toggleRow(l.companionNotificationsLabel, $store.companionNotifications)
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

    /// 백업 & 이전 — 새 Mac으로 옮길 때 쓰는 세이브 파일 내보내기/불러오기.
    /// 사용자가 상태 파일 경로를 직접 찾아다니지 않도록, 저장 위치와 불러올 파일 모두 표준
    /// 파일 선택창으로 고르게 한다.
    @ViewBuilder
    private func transferGroup(_ store: UsageStore) -> some View {
        settingsSection(l.transferSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.exportSaveLabel)
                    Text(l.exportSaveHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.exportSaveButton) { exportSave() }
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.importSaveLabel)
                    Text(l.importSaveHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.importSaveButton) { importSave(store) }
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
            .onChange(of: advancedExpanded) { _, expanded in
                if !expanded {
                    commitCustomScanDraft()
                    customScanMatchTask?.cancel()
                }
            }

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
                groupRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l.customScanRootsLabel)
                        Text(l.customScanRootsHint).font(.caption2).foregroundStyle(.tertiary)
                        HStack {
                            Text(l.customScanProviderLabel).font(.caption)
                            Spacer()
                            Picker("", selection: $selectedScanProviderID) {
                                ForEach(store.registeredProviders, id: \.id) { provider in
                                    Text(provider.displayName).tag(provider.id)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        TextField(l.customScanRootsPlaceholder, text: $customScanDraft, axis: .vertical)
                            .textFieldStyle(.roundedBorder).font(.caption)
                            .focused($customScanFocused)
                            .onSubmit { commitCustomScanDraft() }
                        if !customScanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(l.customScanRootsMatches(customScanMatchCount))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onAppear {
                    customScanDraftOwnerID = selectedScanProviderID
                    customScanDraft = store.customScanRoots(for: selectedScanProviderID)
                    scheduleCustomScanMatchCount()
                }
                .onDisappear {
                    commitCustomScanDraft()
                    customScanMatchTask?.cancel()
                }
                .onChange(of: selectedScanProviderID) { _, newID in
                    store.setCustomScanRoots(customScanDraft, for: customScanDraftOwnerID)
                    customScanDraftOwnerID = newID
                    customScanDraft = store.customScanRoots(for: newID)
                    scheduleCustomScanMatchCount()
                }
                .onChange(of: customScanDraft) { _, _ in
                    scheduleCustomScanMatchCount()
                }
                .onChange(of: customScanFocused) { _, focused in
                    if !focused { commitCustomScanDraft() }
                }
                Divider()
                Text(l.aggregationNote)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    private var aboutSupportGroup: some View {
        settingsSection(l.aboutSupportSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.reportProblem)
                    Text(l.reportAttachHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.reportProblem) { reportProblem() }
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
        groupRow {
            Text(label)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
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

    private func commitCustomScanDraft() {
        store.setCustomScanRoots(customScanDraft, for: customScanDraftOwnerID)
    }

    private func scheduleCustomScanMatchCount() {
        customScanMatchTask?.cancel()
        customScanMatchGeneration += 1
        let generation = customScanMatchGeneration
        let raw = customScanDraft
        let providerID = selectedScanProviderID
        customScanMatchTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let count = CustomScanRoots.survivingExtraCount(
                defaults: CustomScanRoots.curatedRoots(for: providerID),
                extraRaw: raw)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == customScanMatchGeneration else { return }
                customScanMatchCount = count
            }
        }
    }

    // MARK: 동작

    /// 문제점 알리기 — 진단 정보(버전·macOS)가 채워진 리포트 메일을 기본 메일 앱으로 연다.
    /// 메일 앱이 없거나 열기에 실패하면 수신 주소를 안내(복사 가능)한다.
    private func reportProblem() {
        let subject = l.reportMailSubject(Self.appVersion)
        let body = l.reportMailBody(
            version: Self.appVersion,
            os: ProcessInfo.processInfo.operatingSystemVersionString)
        guard let url = SupportMail.mailtoURL(subject: subject, body: body),
              NSWorkspace.shared.open(url) else {
            reportError = l.reportMailFallback(SupportMail.address)
            return
        }
        reportError = nil
    }

    // MARK: 세이브 이전
    //
    // 결과를 인라인 텍스트로 못 보여주는 이유: 팝오버가 `.transient` 라 파일 선택창이 키 윈도우가 되는
    // 순간 닫히고, popoverDidClose 가 호스팅 컨트롤러를 해제해 이 뷰(@State 포함)가 사라진다.
    // → 성공은 Finder 노출(로그 파일 보기와 같은 방식), 그 외는 알림창으로 알린다.
    //
    // 활성화는 `activate(ignoringOtherApps: true)` 여야 한다 — 이 앱은 LSUIElement 라 백그라운드에서
    // `NSApp.activate()`(협조적 활성화)가 무시된다. 실측: activate() 는 isActive=false 로 최전면이 안 바뀌고
    // (패널이 다른 창 뒤에 떠 사용자가 못 찾는다), ignoringOtherApps 만 전면화된다.
    // `NSRunningApplication.current.activate(.activateAllWindows)` 도 같은 이유로 실패한다.
    // 레포의 다른 활성화 지점(PokeTokenBarApp·FloatingPetPanel)도 같은 형태다 — 통일해서 유지할 것.

    private func exportSave() {
        let panel = NSSavePanel()
        panel.title = l.exportSaveLabel
        panel.nameFieldStringValue = companion.suggestedExportFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try companion.exportedSaveData(appVersion: Self.appVersion, deviceName: Self.deviceName)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentAlert(title: l.exportSaveLabel, message: error.localizedDescription, style: .warning)
        }
    }

    private func importSave(_ store: UsageStore) {
        let panel = NSOpenPanel()
        panel.title = l.importSaveLabel
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let envelope: SaveEnvelope
        do {
            envelope = try SaveTransfer.decode(try Data(contentsOf: url))
        } catch {
            presentAlert(title: l.importSaveLabel, message: l.importErrorMessage(error), style: .warning)
            return
        }
        let incoming = SaveSummary(state: envelope.state)

        // 고른 즉시 덮어쓰지 않는다 — 무엇이 대체되는지 수치로 보여주고 한 번 더 확인받는다.
        let current = companion.transferSummary
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = l.importConfirmTitle
        confirm.informativeText = l.importConfirmBody(
            incomingDex: incoming.dexCount,
            incomingTokens: TokenFormatter.compact(incoming.lifetimeTokens),
            exportedAt: Self.exportedAtText(envelope.exportedAt),
            sourceDevice: envelope.sourceDevice,
            currentDex: current.dexCount,
            currentTokens: TokenFormatter.compact(current.lifetimeTokens))
        confirm.addButton(withTitle: l.importConfirmReplace)
        confirm.addButton(withTitle: l.cancel)
        // 파괴적 동작을 기본 버튼으로 두지 않는다(Return 한 번에 진행이 대체되지 않게).
        // 규칙 자체는 ImportConfirmPolicy 에 있고 여기선 적용만 한다 — NSAlert 구성은 테스트 불가라
        // 순서가 뒤바뀌어도 잡을 자동 경로가 없기 때문이다.
        for (index, button) in confirm.buttons.enumerated() {
            button.keyEquivalent = ImportConfirmPolicy.keyEquivalent(forButtonAt: index)
        }
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try companion.applySave(envelope,
                                    todayTokensByProvider: store.todayTokensByProvider,
                                    todayDate: LocalUsageReader.todayKey(),
                                    hasUsageData: store.hasUsageData)
        } catch {
            presentAlert(title: l.importSaveLabel, message: l.importErrorMessage(error), style: .warning)
            return
        }
        presentAlert(title: l.importSaveLabel,
                     message: l.importSaveDone(dex: incoming.dexCount,
                                               tokens: TokenFormatter.compact(incoming.lifetimeTokens)),
                     style: .informational)
    }

    /// 확인창에 보일 내보낸 시각 — 사용자 로케일 기준 짧은 표기.
    private static func exportedAtText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: l.close)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
