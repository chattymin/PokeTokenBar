import XCTest
@testable import PokeTokenBar

final class LinearRewardsTests: XCTestCase {
    private final class StubLinearHTTPClient: LinearHTTPClient, @unchecked Sendable {
        var status: Int
        var data: Data
        var shouldThrow = false
        var lastBody: Data?

        init(status: Int, data: Data) {
            self.status = status
            self.data = data
        }

        func postGraphQL(apiKey: String, body: Data) async throws -> (status: Int, data: Data) {
            lastBody = body
            if shouldThrow { throw URLError(.cannotConnectToHost) }
            return (status, data)
        }
    }

    private final class SequenceLinearHTTPClient: LinearHTTPClient, @unchecked Sendable {
        var responses: [(Int, Data)]
        var bodies: [Data] = []

        init(responses: [(Int, Data)]) {
            self.responses = responses
        }

        func postGraphQL(apiKey: String, body: Data) async throws -> (status: Int, data: Data) {
            bodies.append(body)
            guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
            return responses.removeFirst()
        }
    }

    private func issue(_ id: String, at offset: TimeInterval = 0) -> LinearCompletedIssue {
        LinearCompletedIssue(
            id: id,
            identifier: "ENG-\(id)",
            title: "Done \(id)",
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset))
    }

    func testFirstPollSeedsWithoutXP() {
        let outcome = LinearRewards.evaluate(
            issues: [issue("a"), issue("b")],
            alreadyCredited: [],
            seeded: false)
        XCTAssertEqual(outcome.xp, 0)
        XCTAssertTrue(outcome.seeded)
        XCTAssertEqual(Set(outcome.creditedIDs), ["a", "b"])
        XCTAssertTrue(outcome.newlyCredited.isEmpty)
    }

    func testSubsequentPollAwardsOnlyNewIssues() {
        let seeded = LinearRewards.evaluate(
            issues: [issue("a")], alreadyCredited: [], seeded: false)
        let next = LinearRewards.evaluate(
            issues: [issue("a"), issue("b")],
            alreadyCredited: seeded.creditedIDs,
            seeded: true)
        XCTAssertEqual(next.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(next.newlyCredited.map(\.id), ["b"])
        XCTAssertEqual(Set(next.creditedIDs), ["a", "b"])
    }

    func testDuplicateIDsAcrossPollsDoNotReAward() {
        let first = LinearRewards.evaluate(
            issues: [issue("a")], alreadyCredited: [], seeded: true)
        XCTAssertEqual(first.xp, LinearRewards.xpPerIssue)
        let second = LinearRewards.evaluate(
            issues: [issue("a")], alreadyCredited: first.creditedIDs, seeded: true)
        XCTAssertEqual(second.xp, 0)
    }

    func testMergedCreditedIDsUnionsAndCaps() {
        let a = (0..<300).map(String.init)
        let b = (200..<400).map(String.init)
        let merged = LinearRewards.mergedCreditedIDs(a, b)
        XCTAssertEqual(merged.count, 400)
        XCTAssertTrue(Set(merged).isSubset(of: Set(a + b)))
    }

    func testAppendingXPRecordsStoresFirstCompleteOnly() {
        let first = issue("a")
        let once = LinearRewards.appendingXPRecords(existing: [], newlyCredited: [first])
        XCTAssertEqual(once.map(\.id), ["a"])
        XCTAssertEqual(once.first?.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(once.first?.identifier, "ENG-a")

        let twice = LinearRewards.appendingXPRecords(
            existing: once,
            newlyCredited: [issue("a", at: 99), issue("b")])
        XCTAssertEqual(twice.map(\.id), ["a", "b"])
        XCTAssertEqual(twice.first?.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(twice.first?.awardedAt, first.completedAt)
    }

    func testSeedOutcomeDoesNotCreateXPRecords() {
        let outcome = LinearRewards.evaluate(
            issues: [issue("a"), issue("b")],
            alreadyCredited: [],
            seeded: false)
        let records = LinearRewards.appendingXPRecords(
            existing: [], newlyCredited: outcome.newlyCredited)
        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(LinearRewards.xpRecord(in: records, id: "a"))
    }

    func testXpRecordLookupIgnoresZeroAndMissing() {
        let records = [
            LinearIssueXPRecord(
                id: "zero", identifier: "ENG-0", xp: 0,
                awardedAt: Date(timeIntervalSince1970: 1)),
            LinearIssueXPRecord(
                id: "paid", identifier: "ENG-1", xp: LinearRewards.xpPerIssue,
                awardedAt: Date(timeIntervalSince1970: 2)),
        ]
        XCTAssertNil(LinearRewards.xpRecord(in: records, id: "zero"))
        XCTAssertNil(LinearRewards.xpRecord(in: records, id: "missing"))
        XCTAssertEqual(LinearRewards.xpRecord(in: records, id: "paid")?.xp, LinearRewards.xpPerIssue)
    }

    func testMergingXPRecordsFirstIdWins() {
        let older = LinearIssueXPRecord(
            id: "a", identifier: "ENG-A", xp: LinearRewards.xpPerIssue,
            awardedAt: Date(timeIntervalSince1970: 1))
        let newer = LinearIssueXPRecord(
            id: "a", identifier: "ENG-A", xp: 99,
            awardedAt: Date(timeIntervalSince1970: 2))
        let extra = LinearIssueXPRecord(
            id: "b", identifier: "ENG-B", xp: LinearRewards.xpPerIssue,
            awardedAt: Date(timeIntervalSince1970: 3))
        let merged = LinearRewards.mergingXPRecords([older], [newer, extra])
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
        XCTAssertEqual(merged.first?.xp, LinearRewards.xpPerIssue)
    }

    func testParseCompletedIssuesFromGraphQLFixture() throws {
        let json = """
        {"data":{"issues":{"nodes":[
          {"id":"issue-1","identifier":"ENG-1","title":"Ship it",
           "completedAt":"2026-09-06T12:00:00.000Z"}
        ]}}}
        """.data(using: .utf8)!
        let issues = try LinearClient.parseCompletedIssues(json)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].id, "issue-1")
        XCTAssertEqual(issues[0].identifier, "ENG-1")
    }

    func testParseIssueDashboardSortsByPriority() throws {
        let json = """
        {"data":{
          "completedRecent":{"nodes":[
            {"id":"issue-2","identifier":"ENG-2","title":"Later",
             "priority":3,"updatedAt":"2026-09-06T12:00:00.000Z",
             "completedAt":"2026-09-06T12:00:00.000Z"},
            {"id":"issue-1","identifier":"ENG-1","title":"Urgent",
             "priority":1,"updatedAt":"2026-09-06T11:00:00.000Z",
             "completedAt":"2026-09-06T11:00:00.000Z"}
          ]},
          "inProgress":{"nodes":[
            {"id":"issue-4","identifier":"ENG-4","title":"No priority",
             "priority":0,"updatedAt":"2026-09-06T10:00:00.000Z",
             "state":{"name":"In Progress","type":"started"}},
            {"id":"issue-3","identifier":"ENG-3","title":"High",
             "priority":2,"updatedAt":"2026-09-06T09:00:00.000Z",
             "state":{"name":"In Progress","type":"started"},
             "labels":{"nodes":[{"name":"backend"}]},
             "dueDate":"2026-09-07"}
          ]}
        }}
        """.data(using: .utf8)!

        let dashboard = try LinearClient.parseIssueDashboard(json)
        XCTAssertEqual(dashboard.completedRecent.map(\.id), ["issue-1", "issue-2"])
        XCTAssertEqual(dashboard.inProgress.map(\.id), ["issue-3", "issue-4"])
        XCTAssertEqual(dashboard.inProgress.first?.stateType, "started")
        XCTAssertEqual(dashboard.inProgress.first?.labelNames, ["backend"])
        XCTAssertNotNil(dashboard.inProgress.first?.dueDate)
        XCTAssertTrue(dashboard.projects.isEmpty)
        XCTAssertTrue(dashboard.initiatives.isEmpty)
    }

    func testParseIssueDashboardKeepsInProgressProjectsAndInitiatives() throws {
        let json = """
        {"data":{
          "completedRecent":{"nodes":[]},
          "inProgress":{"nodes":[]},
          "projects":{"nodes":[
            {"id":"p-active","name":"Ship","url":"https://linear.app/p-active",
             "status":{"type":"started","name":"In Progress"},
             "lead":{"name":"Ada"},
             "issues":{"nodes":[
               {"id":"issue-9","identifier":"ENG-9","title":"Nested",
                "state":{"name":"In Progress","type":"started"},
                "team":{"id":"team-1","name":"Eng","key":"ENG",
                  "states":{"nodes":[
                    {"id":"state-start","name":"In Progress","type":"started"},
                    {"id":"state-done","name":"Done","type":"completed"}
                  ]}}}
             ]}},
            {"id":"p-prod","name":"Live","url":"https://linear.app/p-prod",
             "status":{"type":"started","name":"Production"},
             "issues":{"nodes":[]}},
            {"id":"p-planned","name":"Later","status":{"type":"planned","name":"Planned"},
             "issues":{"nodes":[]}},
            {"id":"p-done","name":"Finished","status":{"type":"completed","name":"Completed"},
             "issues":{"nodes":[
               {"id":"issue-old","identifier":"ENG-0","title":"Old",
                "state":{"name":"Done","type":"completed"}}
             ]}}
          ]},
          "initiatives":{"nodes":[
            {"id":"init-active","name":"Q3","status":"Active",
             "url":"https://linear.app/init-active",
             "projects":{"nodes":[
               {"id":"p-active","name":"Ship","issues":{"nodes":[
                 {"id":"issue-8","identifier":"ENG-8","title":"Initiative issue",
                  "state":{"name":"Todo","type":"unstarted"}},
                 {"id":"issue-done","identifier":"ENG-7","title":"Already done",
                  "state":{"name":"Done","type":"completed"}}
               ]}}
             ]}},
            {"id":"init-planned","name":"Roadmap","status":"Planned"},
            {"id":"init-old","name":"Last year","status":"Completed"}
          ]}
        }}
        """.data(using: .utf8)!

        let dashboard = try LinearClient.parseIssueDashboard(json)
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-prod", "p-active"])
        let ship = try XCTUnwrap(dashboard.projects.first { $0.id == "p-active" })
        XCTAssertEqual(ship.leadName, "Ada")
        XCTAssertEqual(ship.issues.map(\.id), ["issue-9"])
        XCTAssertEqual(ship.issues.first?.completedStateId, "state-done")
        XCTAssertEqual(ship.issues.first?.teamStates.map(\.id), ["state-start", "state-done"])
        XCTAssertEqual(ship.issues.first?.teamStates.map(\.type), ["started", "completed"])
        XCTAssertTrue(LinearClient.matchesProjectInProgressTab(name: ship.statusName, type: ship.statusType))
        XCTAssertFalse(LinearClient.matchesProjectProduction(name: ship.statusName, type: ship.statusType))

        let live = try XCTUnwrap(dashboard.projects.first { $0.id == "p-prod" })
        XCTAssertTrue(LinearClient.matchesProjectProduction(name: live.statusName, type: live.statusType))
        XCTAssertFalse(LinearClient.matchesProjectInProgressTab(name: live.statusName, type: live.statusType))

        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active", "init-planned"])
        XCTAssertEqual(dashboard.initiatives.first?.issues.map(\.id), ["issue-8"])
        XCTAssertTrue(LinearClient.matchesInitiativeActive(name: dashboard.initiatives[0].statusName))
        XCTAssertTrue(LinearClient.matchesInitiativePlanned(name: dashboard.initiatives[1].statusName))
        XCTAssertFalse(LinearClient.matchesInitiativePlanned(name: dashboard.initiatives[0].statusName))
    }

    func testCompletedStateIDPrefersDoneName() {
        let team: [String: Any] = [
            "states": [
                "nodes": [
                    ["id": "state-complete", "name": "Completed", "type": "completed"],
                    ["id": "state-done", "name": "Done", "type": "completed"],
                ]
            ]
        ]
        XCTAssertEqual(LinearClient.completedStateID(from: team), "state-done")
    }

    func testSortedWorkflowStatesUsesPositionThenType() {
        let unsorted = [
            LinearWorkflowState(id: "done", name: "Done", type: "completed", position: 3),
            LinearWorkflowState(id: "todo", name: "Todo", type: "unstarted", position: 1),
            LinearWorkflowState(id: "start", name: "In Progress", type: "started", position: 2),
        ]
        XCTAssertEqual(LinearClient.sortedWorkflowStates(unsorted).map(\.id), ["todo", "start", "done"])

        let noPosition = [
            LinearWorkflowState(id: "done", name: "Done", type: "completed", position: nil),
            LinearWorkflowState(id: "todo", name: "Todo", type: "unstarted", position: nil),
            LinearWorkflowState(id: "start", name: "In Progress", type: "started", position: nil),
        ]
        XCTAssertEqual(LinearClient.sortedWorkflowStates(noPosition).map(\.id), ["todo", "start", "done"])
    }

    func testCreditedCompletionOnlyOnTransitionIntoCompleted() {
        let update = LinearIssueStateUpdate(
            id: "issue-1", identifier: "ENG-1", title: "Ship it",
            stateId: "state-done", stateName: "Done", stateType: "completed",
            completedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(LinearClient.creditedCompletion(wasCompleted: false, update: update))
        XCTAssertNil(LinearClient.creditedCompletion(wasCompleted: true, update: update))

        let started = LinearIssueStateUpdate(
            id: "issue-1", identifier: "ENG-1", title: "Ship it",
            stateId: "state-start", stateName: "In Progress", stateType: "started",
            completedAt: nil)
        XCTAssertNil(LinearClient.creditedCompletion(wasCompleted: false, update: started))
        XCTAssertNil(LinearClient.creditedCompletion(wasCompleted: true, update: started))
    }

    func testIsInProgressContainerMatchesStartedAndActive() {
        XCTAssertTrue(LinearClient.isInProgressContainer(name: "In Progress", type: "started"))
        XCTAssertTrue(LinearClient.isInProgressContainer(name: "Active", type: nil))
        XCTAssertFalse(LinearClient.isInProgressContainer(name: "Completed", type: "completed"))
        XCTAssertFalse(LinearClient.isInProgressContainer(name: "Paused", type: "paused"))
        XCTAssertFalse(LinearClient.isInProgressContainer(name: "Planned", type: "planned"))
        XCTAssertFalse(LinearClient.isInProgressContainer(name: nil, type: nil))
    }

    func testProjectAndInitiativeTabClassification() {
        XCTAssertTrue(LinearClient.matchesProjectProduction(name: "Production", type: "started"))
        XCTAssertTrue(LinearClient.matchesProjectProduction(name: "In Production", type: "started"))
        XCTAssertFalse(LinearClient.matchesProjectInProgressTab(name: "Production", type: "started"))
        XCTAssertTrue(LinearClient.matchesProjectInProgressTab(name: "In Progress", type: "started"))
        XCTAssertFalse(LinearClient.shouldKeepProject(name: "Planned", type: "planned"))
        XCTAssertFalse(LinearClient.shouldKeepProject(name: "Completed", type: "completed"))

        XCTAssertTrue(LinearClient.matchesInitiativeActive(name: "Active"))
        XCTAssertTrue(LinearClient.matchesInitiativePlanned(name: "Planned"))
        XCTAssertFalse(LinearClient.matchesInitiativeActive(name: "Planned"))
        XCTAssertFalse(LinearClient.shouldKeepInitiative(name: "Completed"))
    }

    func testParseCompleteIssueFromMutationFixture() throws {
        let json = """
        {"data":{"issueUpdate":{"success":true,"issue":{
          "id":"issue-1","identifier":"ENG-1","title":"Ship it",
          "completedAt":"2026-09-06T12:00:00.000Z",
          "state":{"name":"Done","type":"completed"}
        }}}}
        """.data(using: .utf8)!
        let issue = try LinearClient.parseCompleteIssue(json)
        XCTAssertEqual(issue.id, "issue-1")
        XCTAssertEqual(issue.identifier, "ENG-1")
        XCTAssertEqual(issue.title, "Ship it")
    }

    func testParseCompleteIssueRejectsUnsuccessfulMutation() {
        let json = #"{"data":{"issueUpdate":{"success":false}}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try LinearClient.parseCompleteIssue(json))
    }

    func testParseIssueStateUpdateFromNonCompletedMutation() throws {
        let json = """
        {"data":{"issueUpdate":{"success":true,"issue":{
          "id":"issue-1","identifier":"ENG-1","title":"Ship it",
          "completedAt":null,
          "state":{"id":"state-start","name":"In Progress","type":"started"}
        }}}}
        """.data(using: .utf8)!
        let update = try LinearClient.parseIssueStateUpdate(json)
        XCTAssertEqual(update.stateType, "started")
        XCTAssertNil(update.completedAt)
        XCTAssertNil(LinearClient.creditedCompletion(wasCompleted: false, update: update))
    }

    func testNormalizeRejectsNonLinearKeys() {
        XCTAssertThrowsError(try LinearAPIKeyStore.normalize("sk-ant-not-linear"))
        XCTAssertNoThrow(try LinearAPIKeyStore.normalize("lin_api_" + String(repeating: "x", count: 40)))
    }

    func testValidateAPIKeyUsesViewerProbe() async throws {
        let data = #"{"data":{"viewer":{"id":"user-1"}}}"#.data(using: .utf8)!
        let http = StubLinearHTTPClient(status: 200, data: data)
        let client = LinearClient(http: http)

        try await client.validateAPIKey(
            apiKey: "lin_api_" + String(repeating: "x", count: 40))

        let sentBody = try XCTUnwrap(http.lastBody)
        let bodyText = try XCTUnwrap(String(data: sentBody, encoding: .utf8))
        XCTAssertTrue(bodyText.contains("viewer"))
        XCTAssertFalse(bodyText.contains("completedRecent"))
    }

    func testValidateAPIKeyRejectsUnauthorizedStatus() async {
        let data = #"{"errors":[{"message":"Unauthorized"}]}"#.data(using: .utf8)!
        let client = LinearClient(http: StubLinearHTTPClient(status: 401, data: data))

        do {
            try await client.validateAPIKey(apiKey: "lin_api_" + String(repeating: "x", count: 40))
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? LinearAPIError, .unauthorized)
        }
    }

    func testValidateAPIKeyRejectsUnauthorizedGraphQLError() async {
        let data = #"{"errors":[{"message":"Invalid auth token"}]}"#.data(using: .utf8)!
        let client = LinearClient(http: StubLinearHTTPClient(status: 200, data: data))

        do {
            try await client.validateAPIKey(apiKey: "lin_api_" + String(repeating: "x", count: 40))
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? LinearAPIError, .unauthorized)
        }
    }

    private func issuesDashboardFixture() -> Data {
        """
        {"data":{
          "completedRecent":{"nodes":[]},
          "inProgress":{"nodes":[
            {"id":"issue-2","identifier":"ENG-2","title":"Doing",
             "priority":1,"updatedAt":"2026-09-06T10:00:00.000Z",
             "state":{"name":"In Progress","type":"started"},
             "team":{"id":"team-1","name":"Eng","key":"ENG",
               "states":{"nodes":[
                 {"id":"state-done","name":"Done","type":"completed","position":3},
                 {"id":"state-todo","name":"Todo","type":"unstarted","position":1},
                 {"id":"state-start","name":"In Progress","type":"started","position":2}
               ]}}}
          ]}
        }}
        """.data(using: .utf8)!
    }

    /// Shaped like the live spawn-audio workspace (MCP 2026-09-12):
    /// project status type `started` + name In Progress / Production; initiative status enum scalar.
    private func liveContainersFixture() -> Data {
        """
        {"data":{
          "projects":{"nodes":[
            {"id":"p-sae","name":"Setup: Next SAE Trimester",
             "url":"https://linear.app/p-sae",
             "status":{"type":"started","name":"In Progress"},
             "lead":{"name":"Cody"},
             "issues":{"nodes":[
               {"id":"issue-nested","identifier":"STU-1","title":"Calendar",
                "state":{"name":"In Progress","type":"started"},
                "team":{"id":"team-1","name":"Study","key":"STU"}}
             ]}},
            {"id":"p-prod","name":"PokeTokenBar - Adjustments",
             "status":{"type":"started","name":"Production"},
             "issues":{"nodes":[]}},
            {"id":"p-planned","name":"Habit Pal - App",
             "status":{"type":"planned","name":"Planned"},
             "issues":{"nodes":[]}},
            {"id":"p-done","name":"CIM301.2","status":{"type":"completed","name":"Completed"},
             "issues":{"nodes":[]}}
          ]},
          "initiatives":{"nodes":[
            {"id":"init-active","name":"Build a Credible SPAWN Audio Presence",
             "status":"Active",
             "url":"https://linear.app/init-active",
             "projects":{"nodes":[{"id":"p-sae","name":"Setup: Next SAE Trimester"}]}},
            {"id":"init-planned","name":"Goals & Habits - 2026 Q4","status":"Planned"},
            {"id":"init-old","name":"CIM301","status":"Completed"}
          ]}
        }}
        """.data(using: .utf8)!
    }

    func testFetchIssueDashboardDoesNotUseInvalidPriorityOrderBy() async throws {
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (200, liveContainersFixture()),
        ])
        let client = LinearClient(http: http)

        _ = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(http.bodies.count, 2)
        let issuesQuery = try graphqlQuery(http.bodies[0])
        let containersQuery = try graphqlQuery(http.bodies[1])
        XCTAssertFalse(issuesQuery.contains("orderBy: priority"))
        XCTAssertTrue(issuesQuery.contains("DateTimeOrDuration!"))
        XCTAssertTrue(issuesQuery.contains("states { nodes { id name type position } }"))
        XCTAssertTrue(issuesQuery.contains("state { id name type }"))
        XCTAssertFalse(issuesQuery.contains("projects("))
        XCTAssertTrue(containersQuery.contains("projects"))
        XCTAssertTrue(containersQuery.contains("initiatives"))
        XCTAssertTrue(containersQuery.contains("status { type name }"))
        XCTAssertTrue(containersQuery.contains("filter: { status: { type: { in: [\"started\"] } } }"))
        XCTAssertTrue(containersQuery.contains("filter: { status: { in: [\"Active\", \"Planned\"] } }"))
        XCTAssertFalse(containersQuery.contains("states { nodes"))
    }

    func testFetchIssueDashboardLoadsLiveShapedProjectsAndInitiatives() async throws {
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (200, liveContainersFixture()),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(dashboard.inProgress.map(\.id), ["issue-2"])
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-prod", "p-sae"])
        XCTAssertTrue(LinearClient.matchesProjectInProgressTab(
            name: dashboard.projects.first { $0.id == "p-sae" }?.statusName,
            type: dashboard.projects.first { $0.id == "p-sae" }?.statusType))
        XCTAssertTrue(LinearClient.matchesProjectProduction(
            name: dashboard.projects.first { $0.id == "p-prod" }?.statusName,
            type: dashboard.projects.first { $0.id == "p-prod" }?.statusType))
        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active", "init-planned"])
        let active = try XCTUnwrap(dashboard.initiatives.first { $0.id == "init-active" })
        XCTAssertEqual(active.issues.map(\.id), ["issue-nested"])
        XCTAssertEqual(active.issues.first?.completedStateId, "state-done")
        XCTAssertEqual(active.issues.first?.teamStates.map(\.id), ["state-todo", "state-start", "state-done"])
        XCTAssertEqual(http.bodies.count, 2)
    }

    func testUpdateIssueStatePostsStateIdMutation() async throws {
        let fixture = """
        {"data":{"issueUpdate":{"success":true,"issue":{
          "id":"issue-1","identifier":"ENG-1","title":"Ship it",
          "completedAt":"2026-09-06T12:00:00.000Z",
          "state":{"id":"state-done","name":"Done","type":"completed"}
        }}}}
        """.data(using: .utf8)!
        let http = StubLinearHTTPClient(status: 200, data: fixture)
        let client = LinearClient(http: http)

        let update = try await client.updateIssueState(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            issueID: "issue-1",
            stateID: "state-done")
        XCTAssertEqual(update.id, "issue-1")
        XCTAssertEqual(update.stateType, "completed")
        XCTAssertNotNil(LinearClient.creditedCompletion(wasCompleted: false, update: update))

        let sentBody = try XCTUnwrap(http.lastBody)
        let bodyText = try XCTUnwrap(String(data: sentBody, encoding: .utf8))
        XCTAssertTrue(bodyText.contains("issueUpdate"))
        XCTAssertTrue(bodyText.contains("stateId"))
        XCTAssertTrue(bodyText.contains("issue-1"))
        XCTAssertTrue(bodyText.contains("state-done"))
        XCTAssertFalse(bodyText.contains("CompleteLinearIssue"))
    }

    func testCreateCommentPostsCommentCreateMutation() async throws {
        let fixture = """
        {"data":{"commentCreate":{"success":true,"comment":{"id":"comment-1"}}}}
        """.data(using: .utf8)!
        let http = StubLinearHTTPClient(status: 200, data: fixture)
        let client = LinearClient(http: http)
        let apiKey = "lin_api_" + String(repeating: "x", count: 40)
        let note = "Check-in · No · ENG-142 · 32m\nBlocked on review"

        try await client.createComment(apiKey: apiKey, issueID: "issue-1", body: note)

        let sentBody = try XCTUnwrap(http.lastBody)
        let bodyText = try XCTUnwrap(String(data: sentBody, encoding: .utf8))
        XCTAssertTrue(bodyText.contains("commentCreate"))
        XCTAssertTrue(bodyText.contains("issue-1"))
        XCTAssertTrue(bodyText.contains("Check-in · No · ENG-142"))
        XCTAssertTrue(bodyText.contains("Blocked on review"))
        XCTAssertFalse(bodyText.contains(apiKey))
    }

    func testParseCommentCreateRejectsFailure() {
        let json = #"{"data":{"commentCreate":{"success":false}}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try LinearClient.parseCommentCreate(json))
    }

    func testParseIssueDashboardHydratesNestedTeamStatesFromIssuesQuery() throws {
        let json = """
        {"data":{
          "completedRecent":{"nodes":[]},
          "inProgress":{"nodes":[
            {"id":"issue-2","identifier":"ENG-2","title":"Doing",
             "state":{"id":"state-start","name":"In Progress","type":"started"},
             "team":{"id":"team-1","name":"Eng","key":"ENG",
               "states":{"nodes":[
                 {"id":"state-done","name":"Done","type":"completed","position":3},
                 {"id":"state-todo","name":"Todo","type":"unstarted","position":1},
                 {"id":"state-start","name":"In Progress","type":"started","position":2}
               ]}}}
          ]},
          "projects":{"nodes":[
            {"id":"p-active","name":"Ship",
             "status":{"type":"started","name":"In Progress"},
             "issues":{"nodes":[
               {"id":"issue-9","identifier":"ENG-9","title":"Nested",
                "state":{"id":"state-todo","name":"Todo","type":"unstarted"},
                "team":{"id":"team-1","name":"Eng","key":"ENG"}}
             ]}}
          ]}
        }}
        """.data(using: .utf8)!
        let dashboard = try LinearClient.parseIssueDashboard(json)
        let nested = try XCTUnwrap(dashboard.projects.first?.issues.first)
        XCTAssertEqual(nested.teamStates.map(\.id), ["state-todo", "state-start", "state-done"])
        XCTAssertEqual(nested.completedStateId, "state-done")
        XCTAssertTrue(LinearClient.missingTeamIDs(in: dashboard).isEmpty)
    }

    func testFetchIssueDashboardFetchesMissingTeamStatesOnce() async throws {
        let otherTeamContainers = """
        {"data":{
          "projects":{"nodes":[
            {"id":"p-sae","name":"Setup: Next SAE Trimester",
             "url":"https://linear.app/p-sae",
             "status":{"type":"started","name":"In Progress"},
             "issues":{"nodes":[
               {"id":"issue-other","identifier":"OPS-1","title":"Other team",
                "state":{"id":"ops-start","name":"In Progress","type":"started"},
                "team":{"id":"team-ops","name":"Ops","key":"OPS"}}
             ]}}
          ]},
          "initiatives":{"nodes":[]}
        }}
        """.data(using: .utf8)!
        let teamStates = """
        {"data":{"teams":{"nodes":[
          {"id":"team-ops","states":{"nodes":[
            {"id":"ops-todo","name":"Todo","type":"unstarted","position":1},
            {"id":"ops-start","name":"In Progress","type":"started","position":2},
            {"id":"ops-done","name":"Done","type":"completed","position":3}
          ]}}
        ]}}}
        """.data(using: .utf8)!
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (200, otherTeamContainers),
            (200, teamStates),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        let nested = try XCTUnwrap(dashboard.projects.first { $0.id == "p-sae" }?.issues.first)
        XCTAssertEqual(nested.teamStates.map(\.id), ["ops-todo", "ops-start", "ops-done"])
        XCTAssertEqual(http.bodies.count, 3)
        let lookup = try graphqlQuery(http.bodies[2])
        XCTAssertTrue(lookup.contains("TeamWorkflowStates"))
        XCTAssertTrue(lookup.contains("filter: { id: { in: $ids } }"))
        XCTAssertFalse(lookup.contains("projects("))
        let vars = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: http.bodies[2]) as? [String: Any])
        let variables = try XCTUnwrap(vars["variables"] as? [String: Any])
        XCTAssertEqual(variables["ids"] as? [String], ["team-ops"])
    }

    func testFetchIssueDashboardKeepsContainersWhenTeamStatesLookupFails() async throws {
        let otherTeamContainers = """
        {"data":{
          "projects":{"nodes":[
            {"id":"p-sae","name":"Setup: Next SAE Trimester",
             "status":{"type":"started","name":"In Progress"},
             "issues":{"nodes":[
               {"id":"issue-other","identifier":"OPS-1","title":"Other team",
                "state":{"name":"In Progress","type":"started"},
                "team":{"id":"team-ops","name":"Ops","key":"OPS"}}
             ]}}
          ]},
          "initiatives":{"nodes":[]}
        }}
        """.data(using: .utf8)!
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (200, otherTeamContainers),
            (400, Data("too complex".utf8)),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-sae"])
        XCTAssertTrue(dashboard.projects.first?.issues.first?.teamStates.isEmpty ?? false)
        XCTAssertEqual(http.bodies.count, 3)
    }

    func testFetchIssueDashboardSalvagesContainersWhenFilteredQueryRejected() async throws {
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (400, Data("too complex".utf8)),
            (200, liveContainersFixture()),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(dashboard.inProgress.map(\.id), ["issue-2"])
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-prod", "p-sae"])
        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active", "init-planned"])
        XCTAssertEqual(http.bodies.count, 3)
        let filtered = try graphqlQuery(http.bodies[1])
        let salvage = try graphqlQuery(http.bodies[2])
        XCTAssertTrue(filtered.contains("in: [\"started\"]"))
        XCTAssertFalse(salvage.contains("in: [\"started\"]"))
        XCTAssertTrue(salvage.contains("projects(first: 100)"))
        XCTAssertFalse(salvage.contains("issues("))
    }

    func testFetchIssueDashboardSalvagesContainersWhenGraphQLFieldErrorNullsProjects() async throws {
        let fieldError = """
        {"errors":[{"message":"Cannot query field issues on Project",
          "path":["projects"]}],
         "data":{"projects":null,
          "initiatives":{"nodes":[
            {"id":"init-active","name":"Workflow","status":"Active"}
          ]}}}
        """.data(using: .utf8)!
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (200, fieldError),
            (200, liveContainersFixture()),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-prod", "p-sae"])
        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active", "init-planned"])
        XCTAssertEqual(http.bodies.count, 3)
    }

    func testFetchIssueDashboardBareQueryStillLoadsContainers() async throws {
        let objectStatus = """
        {"data":{
          "projects":{"nodes":[
            {"id":"p-sae","name":"Setup: Next SAE Trimester",
             "status":{"type":"started","name":"In Progress"}}
          ]},
          "initiatives":{"nodes":[
            {"id":"init-active","name":"Workflow",
             "status":{"name":"Active","type":"Active"}}
          ]}
        }}
        """.data(using: .utf8)!
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (400, Data("nope".utf8)),
            (400, Data("nope".utf8)),
            (200, objectStatus),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-sae"])
        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active"])
        XCTAssertEqual(http.bodies.count, 4)
        let bare = try graphqlQuery(http.bodies[3])
        XCTAssertTrue(bare.contains("status { name type }"))
        XCTAssertFalse(bare.contains("lead {"))
    }

    func testFetchIssueDashboardKeepsIssuesWhenEveryContainerQueryFails() async throws {
        let http = SequenceLinearHTTPClient(responses: [
            (200, issuesDashboardFixture()),
            (400, Data("nope".utf8)),
            (400, Data("nope".utf8)),
            (400, Data("nope".utf8)),
        ])
        let client = LinearClient(http: http)

        let dashboard = try await client.fetchIssueDashboard(
            apiKey: "lin_api_" + String(repeating: "x", count: 40),
            completedSince: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(dashboard.inProgress.map(\.id), ["issue-2"])
        XCTAssertTrue(dashboard.projects.isEmpty)
        XCTAssertTrue(dashboard.initiatives.isEmpty)
        XCTAssertEqual(http.bodies.count, 4)
    }

    func testParseLiveLinearWorkspaceStatuses() throws {
        let dashboard = try LinearClient.parseIssueDashboard(
            """
            {"data":{
              "completedRecent":{"nodes":[]},
              "inProgress":{"nodes":[]},
              "projects":{"nodes":[
                {"id":"p-sae","name":"Setup: Next SAE Trimester",
                 "status":{"type":"started","name":"In Progress"}},
                {"id":"p-prod","name":"PokeTokenBar - Adjustments",
                 "status":{"type":"started","name":"Production"}},
                {"id":"p-backlog","name":"CIM310.2",
                 "status":{"type":"backlog","name":"Backlog"}}
              ]},
              "initiatives":{"nodes":[
                {"id":"init-active","name":"Fun Side Projects","status":"Active"},
                {"id":"init-planned","name":"Homelab","status":"Planned"},
                {"id":"init-done","name":"[DASHBOARD]","status":"Completed"}
              ]}
            }}
            """.data(using: .utf8)!)
        XCTAssertEqual(dashboard.projects.map(\.id), ["p-prod", "p-sae"])
        XCTAssertEqual(dashboard.initiatives.map(\.id), ["init-active", "init-planned"])
    }

    func testLinearValidationRejectsOnlyAuthFailures() {
        XCTAssertTrue(UsageStore.shouldRejectLinearAPIKeyValidation(LinearAPIError.unauthorized))
        XCTAssertTrue(UsageStore.shouldRejectLinearAPIKeyValidation(LinearAPIError.httpStatus(403)))
        XCTAssertFalse(UsageStore.shouldRejectLinearAPIKeyValidation(LinearAPIError.transport))
        XCTAssertFalse(UsageStore.shouldRejectLinearAPIKeyValidation(LinearAPIError.httpStatus(500)))
    }

    private func graphqlQuery(_ body: Data) throws -> String {
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(payload["query"] as? String)
    }
}
