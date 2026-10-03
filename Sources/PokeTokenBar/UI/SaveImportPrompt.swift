import AppKit

/// Confirm-then-apply for an incoming save. Settings → Import, Load from sync folder, and the
/// launch/wake handoff offer all go through here, so each shows the same "what gets replaced"
/// summary, keeps Cancel as the Return-key default, and keeps the pre-import backup.
@MainActor
enum SaveImportPrompt {
    enum Outcome { case applied, declined, failed }

    static func confirmAndApply(_ envelope: SaveEnvelope, title: String, cancelTitle: String? = nil,
                                companion: CompanionStore, store: UsageStore) -> Outcome {
        let l = companion.l
        let incoming = SaveSummary(state: envelope.state)
        let current = companion.transferSummary
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = title
        confirm.informativeText = l.importConfirmBody(
            incomingDex: incoming.dexCount,
            incomingTokens: TokenFormatter.compact(incoming.lifetimeTokens),
            exportedAt: SettingsView.exportedAtText(envelope.exportedAt, language: companion.language),
            sourceDevice: envelope.sourceDevice,
            currentDex: current.dexCount,
            currentTokens: TokenFormatter.compact(current.lifetimeTokens))
        confirm.addButton(withTitle: l.importConfirmReplace)
        confirm.addButton(withTitle: cancelTitle ?? l.cancel)
        // 파괴적 동작을 기본 버튼으로 두지 않는다(Return 한 번에 진행이 대체되지 않게).
        // 규칙 자체는 ImportConfirmPolicy 에 있고 여기선 적용만 한다 — NSAlert 구성은 테스트 불가라
        // 순서가 뒤바뀌어도 잡을 자동 경로가 없기 때문이다.
        for (index, button) in confirm.buttons.enumerated() {
            button.keyEquivalent = ImportConfirmPolicy.keyEquivalent(forButtonAt: index)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return .declined }

        do {
            try companion.applySave(envelope,
                                    todayTokensByProvider: store.todayTokensByProvider,
                                    todayDate: LocalUsageReader.todayKey(),
                                    hasUsageData: store.hasUsageData)
        } catch {
            AppLog.write("save import apply failed: \(error)")
            present(title: l.importSaveLabel, message: l.importErrorMessage(error), style: .warning, l: l)
            return .failed
        }
        present(title: l.importSaveLabel,
                message: l.importSaveDone(dex: incoming.dexCount,
                                          tokens: TokenFormatter.compact(incoming.lifetimeTokens)),
                style: .informational, l: l)
        return .applied
    }

    static func present(title: String, message: String, style: NSAlert.Style, l: L) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: l.close)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
