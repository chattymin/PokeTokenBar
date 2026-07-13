import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginError: String?
    @State private var reportError: String?
    @State private var advancedExpanded = false

    private var l: L { companion.l }

    private var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
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
                    notificationsGroup(store)
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
}
