import XCTest
@testable import PokeTokenBar

/// Additional scan folders (#177). Storage is per provider. Custom roots only *add*
/// to curated defaults — an ancestor custom root must not evict a hidden default
/// (the #162-B failure: `normalizedRoots` + `skipsHiddenFiles` silently zeros usage).
final class CustomScanRootsTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Expand

    /// Comma/newline split, `*` segment expansion, existing directories only, input order
    /// with glob matches sorted. Relative paths and files drop out.
    func testExpandGlobKeepsOnlyExistingDirs() {
        let base = tempDir()
        for name in ["b-inst", "a-inst"] {
            try? FileManager.default.createDirectory(
                at: base.appendingPathComponent("instances/\(name)/projects"),
                withIntermediateDirectories: true)
        }
        try? FileManager.default.createDirectory(
            at: base.appendingPathComponent("instances/empty"),
            withIntermediateDirectories: true)
        let literal = base.appendingPathComponent("literal")
        try? FileManager.default.createDirectory(at: literal, withIntermediateDirectories: true)
        try? "x".write(to: base.appendingPathComponent("file"), atomically: true, encoding: .utf8)

        let raw = "\(base.path)/instances/*/projects, \(literal.path)\n\(base.path)/nope/*, \(base.path)/file, relative/path"
        let roots = CustomScanRoots.expand(raw).map(\.path)

        XCTAssertEqual(roots, [
            base.appendingPathComponent("instances/a-inst/projects").path,
            base.appendingPathComponent("instances/b-inst/projects").path,
            literal.path,
        ], "glob expansion / existence filter / order drifted: \(roots)")
    }

    func testExpandTildeAndBlankFragments() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = CustomScanRoots.expand("  , ~/ , \n\t ").map(\.path)
        XCTAssertEqual(roots, [home.path], "bare ~ should expand to the home directory")
    }

    // MARK: Union — custom only adds

    func testUnionAddsCustomRootWithoutValueUnchanged() {
        let home = URL(fileURLWithPath: "/Users/testhome")
        let extra = tempDir()
        let curated = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        let united = CustomScanRoots.union(defaults: curated, extraRaw: extra.path).map(\.path)
        XCTAssertTrue(united.contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
        XCTAssertTrue(united.contains("/Users/testhome/.claude/projects"))

        let none = CustomScanRoots.union(defaults: curated, extraRaw: nil).map(\.path)
        XCTAssertEqual(none, ["/Users/testhome/.claude/projects", "/Users/testhome/.config/claude/projects"])
        XCTAssertFalse(none.contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
    }

    /// #162-B: a custom root that is an *ancestor* of a curated root must not fold the
    /// curated one away. `jsonlFiles` uses `skipsHiddenFiles`, so scanning `~` never
    /// descends into `~/.claude` and the total goes to zero.
    func testAncestorCustomRootDoesNotEvictCuratedDefault() {
        let home = tempDir()
        let projects = home.appendingPathComponent(".claude/projects/p")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let line = """
        {"type":"assistant","requestId":"R","timestamp":"2026-06-30T10:00:00.000Z","message":{"id":"A","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try? line.write(to: projects.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let curated = [home.appendingPathComponent(".claude/projects")]
        let united = CustomScanRoots.union(defaults: curated, extraRaw: home.path)
        XCTAssertEqual(united.map(\.path), curated.map(\.path),
                       "ancestor custom root evicted the curated default: \(united.map(\.path))")

        var found: [URL] = []
        for root in united {
            found += LocalUsageReader.jsonlFiles(in: root, modifiedSince: .distantPast)
        }
        XCTAssertEqual(found.count, 1, "curated hidden .claude/projects must still be scanned")
    }

    func testNestedCustomRootFoldsIntoDefaultAndCountsAsZeroExtras() {
        let home = tempDir()
        let curatedDir = home.appendingPathComponent(".claude/projects")
        let nested = curatedDir.appendingPathComponent("extra")
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertEqual(CustomScanRoots.survivingExtraCount(defaults: [curatedDir], extraRaw: nested.path), 0,
                       "a path already inside a curated root is not an extra folder")
    }

    func testSurvivingExtraCountIgnoresEvictedAncestor() {
        let home = tempDir()
        let curated = [home.appendingPathComponent(".claude/projects")]
        try? FileManager.default.createDirectory(at: curated[0], withIntermediateDirectories: true)
        XCTAssertEqual(CustomScanRoots.survivingExtraCount(defaults: curated, extraRaw: home.path), 0)
    }

    /// `/` is an ancestor of every curated path, but `extra + "/"` is `"//"` so a naive
    /// prefix check misses it and the refresh would walk the whole disk.
    func testRootFilesystemCustomDoesNotEvictCuratedDefault() {
        let home = tempDir()
        let curated = [home.appendingPathComponent(".claude/projects")]
        try? FileManager.default.createDirectory(at: curated[0], withIntermediateDirectories: true)
        XCTAssertEqual(CustomScanRoots.expand("/").map(\.path), ["/"])
        let united = CustomScanRoots.union(defaults: curated, extraRaw: "/")
        XCTAssertEqual(united.map(\.path), curated.map(\.path),
                       "custom `/` must be dropped, not used as a scan root: \(united.map(\.path))")
        XCTAssertEqual(CustomScanRoots.survivingExtraCount(defaults: curated, extraRaw: "/"), 0)
    }

    func testSiblingCustomRootCountsAsExtra() {
        let home = tempDir()
        let curated = home.appendingPathComponent(".claude/projects")
        let extra = home.appendingPathComponent("elsewhere")
        try? FileManager.default.createDirectory(at: curated, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        XCTAssertEqual(CustomScanRoots.survivingExtraCount(defaults: [curated], extraRaw: extra.path), 1)
    }

    // MARK: Storage keys

    func testDefaultsKeyIsProviderScoped() {
        XCTAssertEqual(CustomScanRoots.defaultsKey(for: "claude_code"), "customScanRoots.claude_code")
        XCTAssertEqual(CustomScanRoots.defaultsKey(for: "codex"), "customScanRoots.codex")
        XCTAssertNotEqual(CustomScanRoots.defaultsKey(for: "claude_code"), "customScanRoots")
    }

    func testStoredValueDoesNotLeakAcrossProviders() {
        let suite = "ptb.scan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("~/claude-extra", forKey: CustomScanRoots.defaultsKey(for: "claude_code"))
        XCTAssertEqual(CustomScanRoots.storedValue(for: "claude_code", defaults: defaults), "~/claude-extra")
        XCTAssertNil(CustomScanRoots.storedValue(for: "codex", defaults: defaults))
        XCTAssertNil(CustomScanRoots.storedValue(for: "claude_code", defaults: UserDefaults(suiteName: "ptb.empty.\(UUID().uuidString)")!))
    }

    func testBlankStoredValueIsNil() {
        let suite = "ptb.scan.blank.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("  \n ", forKey: CustomScanRoots.defaultsKey(for: "gemini"))
        XCTAssertNil(CustomScanRoots.storedValue(for: "gemini", defaults: defaults))
    }

    // MARK: UsageStore persistence

    @MainActor
    func testUsageStorePersistsPerProviderAndLeavesOthersAlone() {
        let suite = "ptb.store.scan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)
        store.setCustomScanRoots("~/codex-extra", for: "codex")
        XCTAssertEqual(store.customScanRoots(for: "codex"), "~/codex-extra")
        XCTAssertEqual(store.customScanRoots(for: "gemini"), "")
        XCTAssertEqual(defaults.string(forKey: "customScanRoots.codex"), "~/codex-extra")
        XCTAssertNil(defaults.string(forKey: "customScanRoots"),
                     "generic customScanRoots key must not be written (#162-C)")
    }

    // MARK: Claude seam

    func testComputeClaudeProjectRootsUnionsCustomWhenInjected() {
        let home = URL(fileURLWithPath: "/Users/testhome")
        let extra = tempDir()
        let roots = LocalUsageReader.computeClaudeProjectRoots(
            configDirValue: nil, customRootsValue: extra.path, home: home).map(\.path)
        XCTAssertTrue(roots.contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
        XCTAssertTrue(roots.contains("/Users/testhome/.claude/projects"))
    }

    func testComputeClaudeProjectRootsDefaultCustomIsNilNotUserDefaults() {
        let home = URL(fileURLWithPath: "/Users/testhome")
        let roots = LocalUsageReader.computeClaudeProjectRoots(configDirValue: nil, home: home).map(\.path)
        XCTAssertEqual(Set(roots).count, roots.count)
        XCTAssertTrue(roots.contains("/Users/testhome/.claude/projects"))
    }

    func testClaudeAncestorCustomDoesNotZeroJsonlScan() {
        let home = tempDir()
        let projects = home.appendingPathComponent(".claude/projects/p")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let line = """
        {"type":"assistant","requestId":"R","timestamp":"2026-06-30T10:00:00.000Z","message":{"id":"A","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try? line.write(to: projects.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let roots = LocalUsageReader.computeClaudeProjectRoots(
            configDirValue: nil, customRootsValue: home.path, home: home)
        let defaultProjects = home.appendingPathComponent(LocalUsageReader.defaultRelativeProjectsPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(roots.map(\.path).contains(defaultProjects),
                      "default .claude/projects missing: \(roots.map(\.path))")

        var files: [URL] = []
        for root in roots {
            files += LocalUsageReader.jsonlFiles(in: root, modifiedSince: .distantPast)
        }
        XCTAssertEqual(files.count, 1, "ancestor custom root zeroed Claude usage")
    }

    // MARK: Other providers pick up an extra root

    func testCodexGeminiGrokScanRootsUnionCustom() {
        let home = URL(fileURLWithPath: "/Users/testhome")
        let extra = tempDir()
        XCTAssertTrue(LocalUsageReader.codexSessionRoots(customRootsValue: extra.path, home: home)
            .map(\.path).contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
        XCTAssertTrue(LocalUsageReader.geminiScanRoots(customRootsValue: extra.path, home: home)
            .map(\.path).contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
        XCTAssertTrue(LocalUsageReader.grokSessionRoots(customRootsValue: extra.path, home: home)
            .map(\.path).contains(extra.resolvingSymlinksInPath().standardizedFileURL.path))
    }

    func testAdditionalProvidersUnionCustomOntoCurated() {
        let extra = tempDir()
        let resolved = extra.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(LocalAdditionalUsageReader.openCodeRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
        XCTAssertTrue(LocalAdditionalUsageReader.hermesRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
        XCTAssertTrue(LocalAdditionalUsageReader.cursorRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
        XCTAssertTrue(LocalAdditionalUsageReader.copilotRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
        XCTAssertTrue(LocalAdditionalUsageReader.kiroRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
        XCTAssertTrue(LocalAntigravityUsageReader.resolvedRoots(customRootsValue: extra.path)
            .map(\.path).contains(resolved))
    }

    func testNilCustomLeavesAdditionalProviderDefaultsUnchanged() {
        let extra = tempDir()
        let resolved = extra.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertFalse(LocalAdditionalUsageReader.openCodeRoots(customRootsValue: nil)
            .map(\.path).contains(resolved))
        XCTAssertFalse(LocalAntigravityUsageReader.resolvedRoots(customRootsValue: nil)
            .map(\.path).contains(resolved))
    }

    func testGeminiCacheScansMultipleRootsAndDedups() async throws {
        let payload = """
        {"type":"session_metadata","sessionId":"s1","startTime":"2026-07-03T01:00:00.000Z"}
        {"type":"gemini","id":"m2","timestamp":"2026-07-03T01:00:10.000Z","model":"gemini-2.5-pro","tokens":{"input":1000,"output":50,"cached":600,"thoughts":30,"tool":20,"total":1100}}
        """
        let a = tempDir(), b = tempDir()
        try FileManager.default.createDirectory(at: a.appendingPathComponent("h/chats"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b.appendingPathComponent("h/chats"), withIntermediateDirectories: true)
        try payload.write(to: a.appendingPathComponent("h/chats/s.jsonl"), atomically: true, encoding: .utf8)
        try payload.write(to: b.appendingPathComponent("h/chats/s.jsonl"), atomically: true, encoding: .utf8)

        let entries = await LocalUsageCache(
            geminiRoots: [a, b], fileURL: tempDir().appendingPathComponent("cache.json")
        ).geminiEntries(modifiedSince: .distantPast)
        XCTAssertEqual(entries.count, 1, "the same Gemini turn copied into a second root must dedup")
        let control = await LocalUsageCache(
            geminiRoot: a, fileURL: tempDir().appendingPathComponent("c.json")
        ).geminiEntries(modifiedSince: .distantPast)
        XCTAssertEqual(control.count, entries.count)
    }

    /// Per-root prune of `codexSessionIDs` would keep only the last root's files and
    /// force a full re-probe of the others on the next refresh.
    func testCodexCacheKeepsSessionIndexAcrossMultipleRoots() async throws {
        func writeRollout(in dir: URL, id: String) throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let meta = """
            {"type":"session_meta","timestamp":"2026-07-29T01:00:00.000Z","payload":{"id":"\(id)","session_id":"\(id)"}}
            """
            let state = """
            {"type":"event_msg","timestamp":"2026-07-29T01:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":11},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":11}}}}
            """
            try (meta + "\n" + state).write(
                to: dir.appendingPathComponent("rollout-\(id).jsonl"), atomically: true, encoding: .utf8)
        }
        let a = tempDir(), b = tempDir()
        try writeRollout(in: a, id: "sess-a")
        try writeRollout(in: b, id: "sess-b")
        let cache = LocalUsageCache(
            codexRoots: [a, b], fileURL: tempDir().appendingPathComponent("cache.json"))
        _ = await cache.codexEntries(modifiedSince: .distantPast)
        let indexed = await cache.codexSessionIndexCount()
        XCTAssertEqual(indexed, 2, "session-id index after a two-root scan must keep both files, got \(indexed)")
    }

    /// Production cache must expand the parent closure over the union of every root,
    /// matching `LocalUsageReader.codexEntries`. A fork in a custom folder whose parent
    /// still lives under the curated sessions dir would otherwise keep replayed turns.
    func testCodexCacheFindsParentInASiblingRoot() async throws {
        func write(_ dir: URL, name: String, lines: [String], mtime: Date) throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
        func sessionMeta(id: String, ts: String) -> String {
            """
            {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","session_id":"\(id)"}}
            """
        }
        func forkMeta(id: String, parentID: String, ts: String) -> String {
            """
            {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","forked_from_id":"\(parentID)","parent_thread_id":"\(parentID)","thread_source":"user"}}
            """
        }
        func state(ts: String, cumulativeInput: Int, cumulativeOutput: Int,
                   lastInput: Int, lastOutput: Int) -> String {
            """
            {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeInput),"cached_input_tokens":0,"output_tokens":\(cumulativeOutput),"reasoning_output_tokens":0,"total_tokens":\(cumulativeInput + cumulativeOutput)},"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":0,"output_tokens":\(lastOutput),"reasoning_output_tokens":0,"total_tokens":\(lastInput + lastOutput)}}}}
            """
        }

        let parentRoot = tempDir()
        let forkRoot = tempDir()
        try write(parentRoot, name: "rollout-real.jsonl", lines: [
            sessionMeta(id: "P-123", ts: "2026-07-29T01:00:00.000Z"),
            state(ts: "2026-07-29T01:00:01.000Z", cumulativeInput: 100, cumulativeOutput: 10,
                  lastInput: 100, lastOutput: 10),
            state(ts: "2026-07-29T01:00:03.000Z", cumulativeInput: 300, cumulativeOutput: 30,
                  lastInput: 200, lastOutput: 20),
        ], mtime: Date(timeIntervalSince1970: 1_000))
        try write(forkRoot, name: "rollout-fork.jsonl", lines: [
            forkMeta(id: "fork", parentID: "P-123", ts: "2026-07-30T01:00:00.000Z"),
            state(ts: "2026-07-30T01:00:05.000Z", cumulativeInput: 100, cumulativeOutput: 10,
                  lastInput: 100, lastOutput: 10),
            state(ts: "2026-07-30T01:00:10.000Z", cumulativeInput: 300, cumulativeOutput: 30,
                  lastInput: 200, lastOutput: 20),
            state(ts: "2026-07-30T01:00:15.000Z", cumulativeInput: 600, cumulativeOutput: 60,
                  lastInput: 300, lastOutput: 30),
        ], mtime: Date(timeIntervalSince1970: 3_000))

        let cache = LocalUsageCache(
            codexRoots: [forkRoot, parentRoot],
            fileURL: tempDir().appendingPathComponent("cache.json"))
        let entries = await cache.codexEntries(modifiedSince: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(entries.map(\.total), [330],
                       "parent in another root was not loaded; replayed turns leaked: \(entries.map(\.total))")
    }

    // MARK: Wiring sweep

    /// Every registered provider must consult its own key. A flat shared list is the
    /// contamination hazard #177 forbids (Gemini `allowJSON` picking up Claude `.meta.json`).
    @MainActor
    func testEveryRegisteredProviderConsultsItsOwnCustomScanRootsKey() throws {
        let suite = "ptb.scan.sweep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        XCTAssertFalse(ids.isEmpty)

        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar")
        var corpus = ""
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            corpus += (try String(contentsOf: url, encoding: .utf8)) + "\n"
        }

        var missing: [String] = []
        for id in ids {
            let needle = "storedValue(for: \"\(id)\")"
            if !corpus.contains(needle) {
                missing.append(id)
            }
        }
        XCTAssertTrue(missing.isEmpty, "provider(s) never read customScanRoots.<id>: \(missing)")
        XCTAssertFalse(corpus.contains("\"customScanRoots\""),
                       "generic customScanRoots key would force a migration (#162-C)")

        var missingCurated: [String] = []
        for id in ids {
            if CustomScanRoots.curatedRoots(for: id).isEmpty {
                missingCurated.append(id)
            }
        }
        XCTAssertTrue(
            missingCurated.isEmpty,
            "curatedRoots(for:) default: [] — Settings match count goes silent for: \(missingCurated)")
    }

    /// #181 archived sessions must survive the custom-root union. Hardcoding
    /// `~/.codex/sessions` alone would drop kept usage the way the CLI-only Antigravity
    /// literal dropped 2.0/IDE stores.
    func testCodexSessionRootsIncludeArchivedSessions() {
        let home = tempDir()
        let roots = LocalUsageReader.codexSessionRoots(customRootsValue: nil, home: home).map(\.path)
        XCTAssertTrue(roots.contains { $0.hasSuffix(".codex/sessions") })
        XCTAssertTrue(
            roots.contains { $0.hasSuffix(".codex/archived_sessions") },
            "codexSessionRoots must union computeCodexScanRoots, not only the active sessions dir")
    }

    func testSettingsUsesProviderPickerAndCommitsOnSubmit() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/SettingsView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("registeredProviders"), "Settings must pick a provider, not grow one field per provider")
        XCTAssertTrue(text.contains(".onSubmit"), "commit on submit, not per keystroke (#162 rec 1)")
        XCTAssertFalse(text.contains("$store.customScanRoots)"),
                       "direct TextField binding to the store writes on every keystroke")
        XCTAssertTrue(text.contains("Task.detached") || text.contains("Task.detached(priority:"),
                      "match count must not run contentsOfDirectory on the main thread in body")
        XCTAssertTrue(text.contains("onDisappear"),
                      "collapsing Advanced without blur must still commit the draft")
        XCTAssertTrue(text.contains("Task.sleep") || text.contains("sleep(for:"),
                      "match count must debounce so Claude desktop walks are not per-keystroke")
        XCTAssertTrue(text.contains(".cancel()") || text.contains("isCancelled"),
                      "a stale glob must not overwrite a newer draft's match count")
        XCTAssertTrue(text.contains("customScanDraftOwnerID"),
                      "focus-loss after a picker change would write provider A's draft into B's key")
        XCTAssertFalse(text.contains("setCustomScanRoots(customScanDraft, for: selectedScanProviderID)"),
                       "commit must use the draft owner, not the picker selection")
    }

    func testSetCustomScanRootsInvalidatesAdditionalProviderCache() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/UsageStore.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("invalidateScanCache"),
                      "OpenCode/Cursor/Copilot/Kiro 30s cache would hide a newly added folder")
        XCTAssertTrue(text.contains("invalidateProjectRootsCache"),
                      "Claude's 300s root cache must still drop on save")
    }

    func testComputeFunctionsDefaultCustomRootsValueToNil() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/LocalUsageReader.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("customRootsValue: String? = nil"),
                      "a UserDefaults.standard default would leak the developer's settings into tests")
    }
}
