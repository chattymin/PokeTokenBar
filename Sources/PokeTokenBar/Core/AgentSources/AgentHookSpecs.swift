import Foundation

/// The hooks the app can add for agents whose logs miss a state: a reliable done (Gemini CLI,
/// Copilot CLI, Cursor), a permission prompt (Codex, Grok CLI, Gemini CLI, Copilot CLI), or the
/// whole turn (Antigravity, whose transcript is written after the turn). Facts checked against each
/// agent's source or docs on 2026-11-06; the citation sits next to each choice.
extension AgentHookFile {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path)
    }

    /// Codex reads `hooks.json` next to its user `config.toml` (`config/src/state.rs`), strict JSON
    /// with only `description` and `hooks` at the top (`hook_config.rs`, `deny_unknown_fields`), so
    /// no `version` key. Each new or changed hook runs only after the person trusts it in `/hooks`
    /// (`hooks/src/engine/discovery.rs`); the app's groups go last so the person's own keep their
    /// trusted indices. The command runs in the session folder, and `PermissionRequest`'s `cwd` can
    /// be the tool's folder instead, so `PWD` names the folder first.
    static var codex: AgentHookFile {
        AgentHookFile(
            agentID: "codex", agentName: "Codex",
            files: {
                let codexHome = UsageEnvironment.value("CODEX_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = codexHome.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                    ?? home.appendingPathComponent(".codex")
                return [base.appendingPathComponent("hooks.json")]
            },
            ownsFile: false,
            layout: .groups(root: "hooks"),
            entries: [
                AgentHookEntry("UserPromptSubmit", "working"),
                AgentHookEntry("PostToolUse", "working"),
                // Runs before the approval UI; a guardian may still approve on its own.
                AgentHookEntry("PermissionRequest", "waiting"),
                AgentHookEntry("Stop", "done"),
                AgentHookEntry("Interrupt", "idle"),
            ],
            labelKeys: ["env:PWD", "cwd"],
            skipEnv: [],
            isAvailable: { exists(".codex") },
            approval: "/hooks")
    }

    /// Gemini CLI: user hooks in `~/.gemini/settings.json` `"hooks"`, matcher groups; `""` matches
    /// every event (docs/hooks/index.md). `AfterAgent` fires once per finished turn; nothing fires
    /// on cancel (`core/src/core/client.ts`), which the log reports as idle. The only notification
    /// type is `ToolPermission` (`core/src/hooks/types.ts`). The file may hold comments (JSONC);
    /// the app then refuses to edit it rather than drop them. Hooks do not run in a folder the
    /// person has not trusted (`hookRegistry.ts`).
    static var geminiCLI: AgentHookFile {
        AgentHookFile(
            agentID: "gemini", agentName: "Gemini CLI",
            files: { [home.appendingPathComponent(".gemini/settings.json")] },
            ownsFile: false,
            layout: .groups(root: "hooks"),
            entries: [
                AgentHookEntry("BeforeAgent", matcher: "", "working"),
                AgentHookEntry("AfterTool", matcher: "", "working"),
                AgentHookEntry("Notification", matcher: "", "notification_type:ToolPermission=waiting,*=skip"),
                AgentHookEntry("AfterAgent", matcher: "", "done"),
            ],
            labelKeys: ["cwd", "env:GEMINI_PROJECT_DIR"],
            skipEnv: [],
            isAvailable: { exists(".gemini/tmp") || exists(".gemini/settings.json") },
            approval: nil,
            gain: .finishAndPermissionPrompts)
    }

    /// Grok CLI: personal hook files `~/.grok/hooks/*.json` are always trusted, so the app owns one
    /// (strict JSON, Claude-style groups; `xai-grok-hooks/src/config.rs`). Payload keys are
    /// camelCase (`event.rs`): `notificationType`, `subagentType`, `reason`. Subagent turns are
    /// skipped, and only a `Stop` that ended the turn (`end_turn`) is a done; a session closing
    /// also sends `Stop` (user-guide/10-hooks.md).
    static var grok: AgentHookFile {
        AgentHookFile(
            agentID: "grok", agentName: "Grok CLI",
            files: {
                let grokHome = UsageEnvironment.value("GROK_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = grokHome.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                    ?? home.appendingPathComponent(".grok")
                return [base.appendingPathComponent("hooks/poketokenbar.json")]
            },
            ownsFile: true,
            layout: .groups(root: "hooks"),
            entries: [
                AgentHookEntry("UserPromptSubmit", "subagentType:+=skip;working"),
                AgentHookEntry("PostToolUse", "subagentType:+=skip;working"),
                AgentHookEntry("Notification", matcher: "permission_prompt", "subagentType:+=skip;waiting"),
                AgentHookEntry("Stop", "subagentType:+=skip;reason:end_turn=done,*=skip"),
                AgentHookEntry("StopFailure", "subagentType:+=skip;idle"),
                AgentHookEntry("StopCancelled", "subagentType:+=skip;idle"),
            ],
            labelKeys: ["cwd", "workspaceRoot"],
            skipEnv: [],
            isAvailable: { exists(".grok") },
            approval: nil)
    }

    /// Copilot CLI: personal hook files `~/.copilot/hooks/*.json`, flat entries with a `bash` key
    /// and `"version": 1` (docs.github.com, cli-hooks-reference). `agentStop` is the main turn's
    /// end; `agent_idle` / `agent_completed` notifications are background agents, so only
    /// `permission_prompt` and `elicitation_dialog` mean waiting. `notification_type` stays
    /// snake_case even in camelCase payloads.
    static var copilotCLI: AgentHookFile {
        AgentHookFile(
            agentID: "copilot", agentName: "Copilot CLI",
            files: {
                let copilotHome = UsageEnvironment.value("COPILOT_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = copilotHome.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                    ?? home.appendingPathComponent(".copilot")
                return [base.appendingPathComponent("hooks/poketokenbar.json")]
            },
            ownsFile: true,
            layout: .flat(root: "hooks", commandKey: "bash",
                          extra: ["type": .string("command"), "timeoutSec": .number("10")],
                          header: ["version": .number("1")]),
            entries: [
                AgentHookEntry("userPromptSubmitted", "working"),
                AgentHookEntry("postToolUse", "working"),
                AgentHookEntry("notification", "notification_type:permission_prompt=waiting,elicitation_dialog=waiting,*=skip"),
                AgentHookEntry("agentStop", "done"),
            ],
            labelKeys: ["cwd"],
            skipEnv: [],
            isAvailable: { exists(".copilot") },
            approval: nil,
            gain: .finish)
    }

    /// Cursor: one shared `~/.cursor/hooks.json`, flat entries, `"version": 1`
    /// (cursor.com/docs/agent/hooks). Permission-type hooks block on unexpected output, so none are
    /// used. `stop` carries `status` (completed / aborted / error) and must not print a
    /// `followup_message`; `beforeSubmitPrompt` answers `{"continue":true}`, the documented reply.
    /// Grok CLI also runs this file, so the command does nothing under `GROK_HOOK_EVENT`.
    static var cursor: AgentHookFile {
        AgentHookFile(
            agentID: "cursor", agentName: "Cursor",
            files: { [home.appendingPathComponent(".cursor/hooks.json")] },
            ownsFile: false,
            layout: .flat(root: "hooks", commandKey: "command",
                          extra: ["type": .string("command"), "timeout": .number("5")],
                          header: ["version": .number("1")]),
            entries: [
                AgentHookEntry("beforeSubmitPrompt", "working", stdout: #"{"continue":true}"#),
                AgentHookEntry("afterShellExecution", "working"),
                AgentHookEntry("afterFileEdit", "working"),
                AgentHookEntry("stop", "status:completed=done,*=idle", stdout: "{}"),
            ],
            labelKeys: ["workspace_roots", "env:CURSOR_PROJECT_DIR"],
            skipEnv: ["GROK_HOOK_EVENT"],
            isAvailable: { exists(".cursor") },
            approval: nil,
            gain: .finish)
    }

    /// Antigravity: a named entry in the shared `~/.gemini/config/hooks.json`, loaded by the app,
    /// CLI and IDE alike (antigravity.google/docs/hooks). `PreInvocation` and `Stop` take handler
    /// lists directly; `Stop` with `fullyIdle` false means more work follows. There is no prompt or
    /// waiting event and no `cwd`: the folder is `workspacePaths[0]`. Replies are JSON, so `{}`.
    static var antigravity: AgentHookFile {
        AgentHookFile(
            agentID: "antigravity", agentName: "Antigravity",
            files: { [home.appendingPathComponent(".gemini/config/hooks.json")] },
            ownsFile: false,
            layout: .flat(root: "poketokenbar", commandKey: "command",
                          extra: ["type": .string("command"), "timeout": .number("5")],
                          header: [:], rootFields: ["enabled": .bool(true)]),
            entries: [
                AgentHookEntry("PreInvocation", "working", stdout: "{}"),
                AgentHookEntry("Stop", "fullyIdle:0=working;terminationReason:model_stop=done,*=idle", stdout: "{}"),
            ],
            labelKeys: ["workspacePaths"],
            skipEnv: [],
            isAvailable: { ["antigravity", "antigravity-cli", "antigravity-ide"].contains { exists(".gemini/" + $0) } },
            approval: nil,
            gain: .everything)
    }
}

extension AgentLogSource {
    /// Antigravity writes its transcript only after a turn ends, so it has no log to follow: it
    /// reaches the pet through its hooks alone.
    static func antigravity() -> AgentLogSource {
        AgentLogSource(id: "antigravity", roots: { [] }, accepts: { _ in false }, interpret: { _ in nil },
                       hooks: AgentHookFile.antigravity.integration)
    }
}
