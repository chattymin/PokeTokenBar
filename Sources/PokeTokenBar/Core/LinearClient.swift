import Foundation

/// Completed Linear issue eligible for companion XP.
struct LinearCompletedIssue: Equatable, Sendable, Identifiable {
    var id: String
    var identifier: String
    var title: String
    var completedAt: Date
}

/// Per-issue Linear Done XP. First completion only — re-completing does not rewrite this.
struct LinearIssueXPRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var identifier: String
    var xp: Int
    var awardedAt: Date
}

/// One workflow state on a Linear team (Todo, In Progress, Done, …).
struct LinearWorkflowState: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var type: String
    var position: Double?
}

/// Result of `issueUpdate` when changing an issue's workflow state.
struct LinearIssueStateUpdate: Equatable, Sendable {
    var id: String
    var identifier: String
    var title: String
    var stateId: String?
    var stateName: String?
    var stateType: String?
    var completedAt: Date?
}

/// Rich Linear issue metadata for UI surfaces.
struct LinearIssueSummary: Equatable, Sendable, Identifiable {
    var id: String
    var identifier: String
    var title: String
    var issueURL: URL?
    var priority: Int?
    var estimate: Int?
    var stateId: String?
    var stateName: String?
    var stateType: String?
    var assigneeName: String?
    var assigneeEmail: String?
    var projectName: String?
    var teamName: String?
    var teamKey: String?
    var teamID: String?
    var teamStates: [LinearWorkflowState]
    var completedStateId: String?
    var labelNames: [String]
    var createdAt: Date?
    var updatedAt: Date?
    var dueDate: Date?
    var completedAt: Date?
    var descriptionText: String?
}

struct LinearProjectSummary: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var url: URL?
    var statusName: String?
    var statusType: String?
    var leadName: String?
    var targetDate: Date?
    var descriptionText: String?
    var issues: [LinearIssueSummary]
}

struct LinearInitiativeSummary: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var url: URL?
    var statusName: String?
    var ownerName: String?
    var targetDate: Date?
    var descriptionText: String?
    var issues: [LinearIssueSummary]
}

struct LinearIssueDashboard: Equatable, Sendable {
    var completedRecent: [LinearIssueSummary]
    var inProgress: [LinearIssueSummary]
    var projects: [LinearProjectSummary]
    var initiatives: [LinearInitiativeSummary]
}

protocol LinearHTTPClient: Sendable {
    func postGraphQL(apiKey: String, body: Data) async throws -> (status: Int, data: Data)
}

struct URLSessionLinearClient: LinearHTTPClient {
    func postGraphQL(apiKey: String, body: Data) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}

/// Fetches recently completed Linear issues. Injectable HTTP for tests.
struct LinearClient: Sendable {
    var http: any LinearHTTPClient = URLSessionLinearClient()

    /// Issues completed at or after `since` (ISO8601).
    func fetchCompletedIssues(apiKey: String, since: Date) async throws -> [LinearCompletedIssue] {
        let dashboard = try await fetchIssueDashboard(apiKey: apiKey, completedSince: since)
        return dashboard.completedRecent.compactMap { issue in
            guard let completedAt = issue.completedAt else { return nil }
            return LinearCompletedIssue(
                id: issue.id,
                identifier: issue.identifier,
                title: issue.title,
                completedAt: completedAt)
        }
    }

    /// Lightweight auth probe used by Settings key validation.
    /// We intentionally avoid the dashboard query here because large workspaces can
    /// hit transient timeouts/rate limits and look like false "invalid key" failures.
    func validateAPIKey(apiKey: String) async throws {
        let query = """
        query ValidateLinearAPIKey {
          viewer { id }
        }
        """
        let payload: [String: Any] = ["query": query]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (status, data): (Int, Data)
        do {
            (status, data) = try await http.postGraphQL(apiKey: apiKey, body: body)
        } catch {
            throw LinearAPIError.transport
        }
        if status == 401 || status == 403 { throw LinearAPIError.unauthorized }
        guard (200..<300).contains(status) else { throw LinearAPIError.httpStatus(status) }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if Self.containsUnauthorizedGraphQLError(errors) {
                throw LinearAPIError.unauthorized
            }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any],
              let viewer = dataObj["viewer"] as? [String: Any],
              let viewerID = viewer["id"] as? String,
              !viewerID.isEmpty
        else { throw LinearAPIError.decoding }
    }

    /// Moves an issue to any workflow state via `issueUpdate` (two-way sync).
    func updateIssueState(
        apiKey: String, issueID: String, stateID: String
    ) async throws -> LinearIssueStateUpdate {
        let query = """
        mutation UpdateLinearIssueState($id: String!, $stateId: String!) {
          issueUpdate(id: $id, input: { stateId: $stateId }) {
            success
            issue {
              id
              identifier
              title
              completedAt
              state { id name type }
            }
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": issueID, "stateId": stateID]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (status, data): (Int, Data)
        do {
            (status, data) = try await http.postGraphQL(apiKey: apiKey, body: body)
        } catch {
            throw LinearAPIError.transport
        }
        if status == 401 || status == 403 { throw LinearAPIError.unauthorized }
        guard (200..<300).contains(status) else { throw LinearAPIError.httpStatus(status) }
        return try Self.parseIssueStateUpdate(data)
    }

    /// Posts a new comment on an issue via `commentCreate`.
    func createComment(apiKey: String, issueID: String, body: String) async throws {
        let query = """
        mutation CreateLinearComment($issueId: String!, $body: String!) {
          commentCreate(input: { issueId: $issueId, body: $body }) {
            success
            comment { id }
          }
        }
        """
        let data = try await postGraphQL(
            apiKey: apiKey,
            query: query,
            variables: ["issueId": issueID, "body": body])
        try Self.parseCommentCreate(data)
    }

    /// Fetches issue panel data used by the popover.
    ///
    /// Issues stay on their own query — that payload already works. Projects and initiatives
    /// are a separate, lighter round-trip. Linear rejects any single request over 10,000
    /// complexity points; nesting `team.states` (default page 50) under
    /// `projects { issues }` and `initiatives { projects { issues } }` blows that cap,
    /// returns HTTP 400, and the old issues-only fallback looked exactly like empty
    /// Projects/Initiatives tabs while Issues still worked.
    func fetchIssueDashboard(apiKey: String, completedSince: Date) async throws -> LinearIssueDashboard {
        let sinceISO = ISO8601DateFormatter().string(from: completedSince)
        let issuesData = try await postGraphQL(
            apiKey: apiKey, query: Self.issuesOnlyQuery, variables: ["since": sinceISO])
        var dashboard = try Self.parseIssueDashboard(issuesData)

        let containerQueries = [
            Self.containersQuery,
            Self.containersSalvageQuery,
            Self.containersBareQuery,
        ]
        for query in containerQueries {
            do {
                let data = try await postGraphQL(apiKey: apiKey, query: query, variables: [:])
                if let overlay = try Self.parseContainerOverlay(data) {
                    dashboard = Self.merging(dashboard, overlay)
                    break
                }
            } catch LinearAPIError.httpStatus(_) {
                continue
            } catch LinearAPIError.decoding {
                continue
            }
        }
        dashboard = Self.hydrateTeamStates(dashboard)
        dashboard = try await fillingMissingTeamStates(apiKey: apiKey, dashboard: dashboard)
        return dashboard
    }

    /// Nested project/initiative issues omit `team.states` (complexity). Copy states
    /// already parsed from the issues query, then look up any remaining teams once.
    private func fillingMissingTeamStates(
        apiKey: String, dashboard: LinearIssueDashboard
    ) async throws -> LinearIssueDashboard {
        let missing = Self.missingTeamIDs(in: dashboard)
        guard !missing.isEmpty else { return dashboard }
        do {
            let data = try await postGraphQL(
                apiKey: apiKey,
                query: Self.teamStatesQuery,
                variables: ["ids": missing, "first": missing.count])
            let extra = try Self.parseTeamStatesByID(data)
            return Self.assigningTeamStates(dashboard, from: extra)
        } catch LinearAPIError.unauthorized {
            throw LinearAPIError.unauthorized
        } catch {
            return dashboard
        }
    }

    private func postGraphQL(apiKey: String, query: String, variables: [String: Any]) async throws -> Data {
        var payload: [String: Any] = ["query": query]
        if !variables.isEmpty { payload["variables"] = variables }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (status, data): (Int, Data)
        do {
            (status, data) = try await http.postGraphQL(apiKey: apiKey, body: body)
        } catch {
            throw LinearAPIError.transport
        }
        if status == 401 || status == 403 { throw LinearAPIError.unauthorized }
        guard (200..<300).contains(status) else { throw LinearAPIError.httpStatus(status) }
        return data
    }

    private static let issueNodeFields = """
    id identifier title url description priority estimate \
    state { id name type } assignee { name email } project { name } \
    team { id name key states { nodes { id name type position } } } \
    labels { nodes { name } } createdAt updatedAt dueDate completedAt
    """

    /// Nested project issues omit `team.states` (default page 50) so container queries
    /// stay under Linear's per-request complexity cap. Workflow states are copied from
    /// the issues query via `hydrateTeamStates`, or fetched once per missing team.
    private static let lightIssueNodeFields = """
    id identifier title url description priority estimate \
    state { id name type } assignee { name email } project { name } \
    team { id name key } createdAt updatedAt dueDate completedAt
    """

    /// One lookup for nested issues whose team never appeared on the issues query.
    private static var teamStatesQuery: String {
        """
        query TeamWorkflowStates($ids: [String!]!, $first: Int!) {
          teams(filter: { id: { in: $ids } }, first: $first) {
            nodes {
              id
              states { nodes { id name type position } }
            }
          }
        }
        """
    }

    private static var issuesOnlyQuery: String {
        let issueFields = issueNodeFields
        return """
        query IssueDashboard($since: DateTimeOrDuration!) {
          completedRecent: issues(
            filter: { completedAt: { gte: $since } }
            first: 100
          ) {
            nodes { \(issueFields) }
          }
          inProgress: issues(first: 100) {
            nodes { \(issueFields) }
          }
        }
        """
    }

    /// Live workspace: project status type `started` covers both In Progress and Production
    /// (custom name). Initiative `status` is the `InitiativeStatus` enum scalar.
    private static var containersQuery: String {
        let issueFields = lightIssueNodeFields
        return """
        query IssueContainers {
          projects(
            first: 50
            filter: { status: { type: { in: ["started"] } } }
          ) {
            nodes {
              id
              name
              url
              description
              targetDate
              lead { name }
              status { type name }
              issues(
                first: 12
                filter: { state: { type: { nin: ["completed", "canceled"] } } }
              ) {
                nodes { \(issueFields) }
              }
            }
          }
          initiatives(
            first: 50
            filter: { status: { in: ["Active", "Planned"] } }
          ) {
            nodes {
              id
              name
              url
              description
              targetDate
              status
              owner { name }
              projects(first: 20) {
                nodes { id name }
              }
            }
          }
        }
        """
    }

    /// Unfiltered, no nested issues — used when the filtered/nested query is rejected.
    private static var containersSalvageQuery: String {
        """
        query IssueContainers {
          projects(first: 100) {
            nodes {
              id
              name
              url
              description
              targetDate
              lead { name }
              status { type name }
            }
          }
          initiatives(first: 50) {
            nodes {
              id
              name
              url
              description
              targetDate
              status
              owner { name }
              projects(first: 20) {
                nodes { id name }
              }
            }
          }
        }
        """
    }

    /// Last container attempt: initiative `status` as an object (schema drift from the enum scalar).
    private static var containersBareQuery: String {
        """
        query IssueContainers {
          projects(first: 100) {
            nodes {
              id
              name
              url
              status { type name }
            }
          }
          initiatives(first: 50) {
            nodes {
              id
              name
              url
              status { name type }
            }
          }
        }
        """
    }

    static func parseIssueStateUpdate(_ data: Data) throws -> LinearIssueStateUpdate {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any],
              let payload = dataObj["issueUpdate"] as? [String: Any],
              payload["success"] as? Bool == true,
              let issue = payload["issue"] as? [String: Any],
              let id = issue["id"] as? String, !id.isEmpty,
              let identifier = issue["identifier"] as? String, !identifier.isEmpty,
              let title = issue["title"] as? String, !title.isEmpty
        else { throw LinearAPIError.decoding }
        let state = issue["state"] as? [String: Any]
        return LinearIssueStateUpdate(
            id: id,
            identifier: identifier,
            title: title,
            stateId: state?["id"] as? String,
            stateName: state?["name"] as? String,
            stateType: state?["type"] as? String,
            completedAt: parseDate(issue["completedAt"]))
    }

    static func parseCommentCreate(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any],
              let payload = dataObj["commentCreate"] as? [String: Any],
              payload["success"] as? Bool == true,
              let comment = payload["comment"] as? [String: Any],
              let id = comment["id"] as? String, !id.isEmpty
        else { throw LinearAPIError.decoding }
    }

    /// XP is granted only when an issue *enters* a completed state.
    static func creditedCompletion(
        wasCompleted: Bool,
        update: LinearIssueStateUpdate
    ) -> LinearCompletedIssue? {
        guard !wasCompleted, (update.stateType ?? "").lowercased() == "completed" else {
            return nil
        }
        return LinearCompletedIssue(
            id: update.id,
            identifier: update.identifier,
            title: update.title,
            completedAt: update.completedAt ?? Date())
    }

    static func parseCompleteIssue(_ data: Data) throws -> LinearCompletedIssue {
        let update = try parseIssueStateUpdate(data)
        return LinearCompletedIssue(
            id: update.id,
            identifier: update.identifier,
            title: update.title,
            completedAt: update.completedAt ?? Date())
    }

    static func parseIssueDashboard(_ data: Data) throws -> LinearIssueDashboard {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
        }
        guard let dataObj = root["data"] as? [String: Any],
              let completedPayload = dataObj["completedRecent"] as? [String: Any],
              let completedNodes = completedPayload["nodes"] as? [[String: Any]],
              let inProgressPayload = dataObj["inProgress"] as? [String: Any],
              let inProgressNodes = inProgressPayload["nodes"] as? [[String: Any]]
        else { throw LinearAPIError.decoding }

        let completed = try completedNodes.map(parseIssueSummary)
        let inProgress = try inProgressNodes
            .map(parseIssueSummary)
            .filter { $0.stateType?.lowercased() == "started" }
        let projects = parseProjects(dataObj["projects"])
        let initiatives = parseInitiatives(dataObj["initiatives"])
        return hydrateTeamStates(
            LinearIssueDashboard(
                completedRecent: sortedByPriority(completed),
                inProgress: sortedByPriority(inProgress),
                projects: keptProjects(projects),
                initiatives: keptInitiatives(initiatives)))
    }

    private struct LinearContainerOverlay {
        var projects: [LinearProjectSummary]
        var initiatives: [LinearInitiativeSummary]
    }

    /// Nil means this payload is incomplete (field error / missing collections) — try the next query.
    private static func parseContainerOverlay(_ data: Data) throws -> LinearContainerOverlay? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            if containerAttemptFailed(errors: errors, data: root["data"] as? [String: Any]) {
                return nil
            }
        }
        guard let dataObj = root["data"] as? [String: Any] else { return nil }
        let hasProjects = (dataObj["projects"] as? [String: Any])?["nodes"] is [[String: Any]]
        let hasInitiatives = (dataObj["initiatives"] as? [String: Any])?["nodes"] is [[String: Any]]
        guard hasProjects || hasInitiatives else { return nil }

        let projects = parseProjects(dataObj["projects"])
        let initiatives = parseInitiatives(
            dataObj["initiatives"],
            projectIssuesByID: projectIssueIndex(projects))
        return LinearContainerOverlay(
            projects: keptProjects(projects),
            initiatives: keptInitiatives(initiatives))
    }

    private static func merging(
        _ dashboard: LinearIssueDashboard,
        _ overlay: LinearContainerOverlay
    ) -> LinearIssueDashboard {
        var copy = dashboard
        copy.projects = overlay.projects
        copy.initiatives = overlay.initiatives
        return copy
    }

    private static func keptProjects(_ projects: [LinearProjectSummary]) -> [LinearProjectSummary] {
        projects
            .filter { shouldKeepProject(name: $0.statusName, type: $0.statusType) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func keptInitiatives(
        _ initiatives: [LinearInitiativeSummary]
    ) -> [LinearInitiativeSummary] {
        initiatives
            .filter { shouldKeepInitiative(name: $0.statusName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func projectIssueIndex(
        _ projects: [LinearProjectSummary]
    ) -> [String: [LinearIssueSummary]] {
        var map: [String: [LinearIssueSummary]] = [:]
        for project in projects { map[project.id] = project.issues }
        return map
    }

    private static func containerAttemptFailed(errors: [[String: Any]], data: [String: Any]?) -> Bool {
        for error in errors {
            if let extensions = error["extensions"] as? [String: Any],
               let code = (extensions["code"] as? String)?.uppercased(),
               code.contains("COMPLEXITY") || code == "RATELIMITED"
            {
                return true
            }
            if let message = error["message"] as? String {
                let normalized = message.lowercased()
                if normalized.contains("too complex") || normalized.contains("query complexity") {
                    return true
                }
            }
            if let path = error["path"] as? [Any], let field = path.first as? String,
               field == "projects" || field == "initiatives"
            {
                let nodes = (data?[field] as? [String: Any])?["nodes"]
                if nodes == nil { return true }
            }
        }
        return false
    }

    static func hydrateCompletedStateIDs(_ dashboard: LinearIssueDashboard) -> LinearIssueDashboard {
        hydrateTeamStates(dashboard)
    }

    static func hydrateTeamStates(_ dashboard: LinearIssueDashboard) -> LinearIssueDashboard {
        var byTeam: [String: [LinearWorkflowState]] = [:]
        func ingest(_ issues: [LinearIssueSummary]) {
            for issue in issues {
                guard let teamID = issue.teamID, !issue.teamStates.isEmpty else { continue }
                byTeam[teamID] = issue.teamStates
            }
        }
        ingest(dashboard.completedRecent)
        ingest(dashboard.inProgress)
        for project in dashboard.projects { ingest(project.issues) }
        for initiative in dashboard.initiatives { ingest(initiative.issues) }
        return assigningTeamStates(dashboard, from: byTeam)
    }

    static func missingTeamIDs(in dashboard: LinearIssueDashboard) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        func walk(_ issues: [LinearIssueSummary]) {
            for issue in issues {
                guard let teamID = issue.teamID, issue.teamStates.isEmpty,
                      seen.insert(teamID).inserted
                else { continue }
                ids.append(teamID)
            }
        }
        walk(dashboard.completedRecent)
        walk(dashboard.inProgress)
        for project in dashboard.projects { walk(project.issues) }
        for initiative in dashboard.initiatives { walk(initiative.issues) }
        return ids
    }

    static func assigningTeamStates(
        _ dashboard: LinearIssueDashboard,
        from byTeam: [String: [LinearWorkflowState]]
    ) -> LinearIssueDashboard {
        guard !byTeam.isEmpty else { return dashboard }

        func fill(_ issues: [LinearIssueSummary]) -> [LinearIssueSummary] {
            issues.map { issue in
                var copy = issue
                if copy.teamStates.isEmpty,
                   let teamID = issue.teamID,
                   let states = byTeam[teamID],
                   !states.isEmpty
                {
                    copy.teamStates = states
                }
                if copy.completedStateId == nil {
                    copy.completedStateId = completedStateID(from: copy.teamStates)
                }
                return copy
            }
        }

        var copy = dashboard
        copy.completedRecent = fill(dashboard.completedRecent)
        copy.inProgress = fill(dashboard.inProgress)
        copy.projects = dashboard.projects.map { project in
            var next = project
            next.issues = fill(project.issues)
            return next
        }
        copy.initiatives = dashboard.initiatives.map { initiative in
            var next = initiative
            next.issues = fill(initiative.issues)
            return next
        }
        return copy
    }

    static func parseTeamStatesByID(_ data: Data) throws -> [String: [LinearWorkflowState]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any] else { throw LinearAPIError.decoding }
        let nodes = ((dataObj["teams"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        var map: [String: [LinearWorkflowState]] = [:]
        for node in nodes {
            guard let id = node["id"] as? String, !id.isEmpty else { continue }
            let states = parseWorkflowStates(from: node)
            if !states.isEmpty { map[id] = states }
        }
        return map
    }

    static func sortedWorkflowStates(_ states: [LinearWorkflowState]) -> [LinearWorkflowState] {
        let allPositioned = states.allSatisfy { $0.position != nil }
        return states.sorted { a, b in
            if allPositioned, let pa = a.position, let pb = b.position, pa != pb {
                return pa < pb
            }
            let ta = workflowTypeRank(a.type)
            let tb = workflowTypeRank(b.type)
            if ta != tb { return ta < tb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func workflowTypeRank(_ type: String) -> Int {
        switch type.lowercased() {
        case "triage": return 0
        case "backlog": return 1
        case "unstarted": return 2
        case "started": return 3
        case "completed": return 4
        case "canceled", "cancelled": return 5
        default: return 6
        }
    }

    static func sortedByPriority(_ issues: [LinearIssueSummary]) -> [LinearIssueSummary] {
        issues.sorted { a, b in
            let pa = prioritySortValue(a.priority)
            let pb = prioritySortValue(b.priority)
            if pa != pb { return pa < pb }
            let ua = a.updatedAt ?? .distantPast
            let ub = b.updatedAt ?? .distantPast
            if ua != ub { return ua > ub }
            return a.identifier < b.identifier
        }
    }

    static func isInProgressContainer(name: String?, type: String?) -> Bool {
        let blocked: Set<String> = [
            "completed", "canceled", "cancelled", "planned", "backlog", "paused"
        ]
        let typeToken = type?.lowercased()
        let nameToken = name?.lowercased()
        if let typeToken {
            if blocked.contains(typeToken) { return false }
            if typeToken == "started" || typeToken == "active" { return true }
        }
        guard let nameToken, !nameToken.isEmpty else { return false }
        if blocked.contains(nameToken) { return false }
        return nameToken == "started" || nameToken == "active" || nameToken == "in progress"
    }

    /// Linear workspaces often use a custom project status named Production.
    static func matchesProjectProduction(name: String?, type: String?) -> Bool {
        statusTokens(name: name, type: type).contains {
            $0 == "production" || $0 == "in production"
        }
    }

    static func matchesProjectInProgressTab(name: String?, type: String?) -> Bool {
        guard !matchesProjectProduction(name: name, type: type) else { return false }
        return isInProgressContainer(name: name, type: type)
    }

    static func matchesInitiativeActive(name: String?) -> Bool {
        (name ?? "").lowercased() == "active"
    }

    static func matchesInitiativePlanned(name: String?) -> Bool {
        (name ?? "").lowercased() == "planned"
    }

    static func shouldKeepProject(name: String?, type: String?) -> Bool {
        matchesProjectProduction(name: name, type: type)
            || isInProgressContainer(name: name, type: type)
    }

    static func shouldKeepInitiative(name: String?) -> Bool {
        matchesInitiativeActive(name: name) || matchesInitiativePlanned(name: name)
    }

    private static func statusTokens(name: String?, type: String?) -> [String] {
        [name, type].compactMap { token in
            let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func completedStateID(from team: [String: Any]?) -> String? {
        completedStateID(from: parseWorkflowStates(from: team))
    }

    static func completedStateID(from states: [LinearWorkflowState]) -> String? {
        let completed = states.filter { $0.type.lowercased() == "completed" }
        if let done = completed.first(where: { $0.name.lowercased() == "done" }) {
            return done.id
        }
        return completed.first?.id
    }

    static func parseWorkflowStates(from team: [String: Any]?) -> [LinearWorkflowState] {
        let nodes = ((team?["states"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let parsed: [LinearWorkflowState] = nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            return LinearWorkflowState(
                id: id,
                name: name,
                type: (node["type"] as? String) ?? "",
                position: parseDouble(node["position"]))
        }
        return sortedWorkflowStates(parsed)
    }

    private static func parseProjects(_ raw: Any?) -> [LinearProjectSummary] {
        let nodes = ((raw as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            let status = parsedStatus(node["status"] ?? node["state"])
            let issues = openIssues(from: node["issues"])
            return LinearProjectSummary(
                id: id,
                name: name,
                url: (node["url"] as? String).flatMap(URL.init(string:)),
                statusName: status.name,
                statusType: status.type,
                leadName: (node["lead"] as? [String: Any])?["name"] as? String,
                targetDate: parseDate(node["targetDate"]),
                descriptionText: node["description"] as? String,
                issues: sortedByPriority(issues))
        }
    }

    private static func parseInitiatives(
        _ raw: Any?,
        projectIssuesByID: [String: [LinearIssueSummary]] = [:]
    ) -> [LinearInitiativeSummary] {
        let nodes = ((raw as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            let status = parsedStatus(node["status"] ?? node["state"])
            let projectNodes = ((node["projects"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            var issues: [LinearIssueSummary] = []
            var seen = Set<String>()
            for project in projectNodes {
                if let projectID = project["id"] as? String,
                   let extras = projectIssuesByID[projectID]
                {
                    for issue in extras where seen.insert(issue.id).inserted {
                        issues.append(issue)
                    }
                }
                for issue in openIssues(from: project["issues"]) where seen.insert(issue.id).inserted {
                    issues.append(issue)
                }
            }
            return LinearInitiativeSummary(
                id: id,
                name: name,
                url: (node["url"] as? String).flatMap(URL.init(string:)),
                statusName: status.name ?? status.type,
                ownerName: (node["owner"] as? [String: Any])?["name"] as? String,
                targetDate: parseDate(node["targetDate"]),
                descriptionText: node["description"] as? String,
                issues: sortedByPriority(issues))
        }
    }

    private static func openIssues(from raw: Any?) -> [LinearIssueSummary] {
        let nodes = ((raw as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return nodes.compactMap { try? parseIssueSummary($0) }
            .filter {
                let type = $0.stateType?.lowercased()
                return type != "completed" && type != "canceled"
            }
    }

    private static func parsedStatus(_ raw: Any?) -> (name: String?, type: String?) {
        if let text = raw as? String { return (text, text) }
        if let object = raw as? [String: Any] {
            return (object["name"] as? String, object["type"] as? String ?? object["name"] as? String)
        }
        return (nil, nil)
    }

    private static func parseIssueSummary(_ node: [String: Any]) throws -> LinearIssueSummary {
        guard let id = node["id"] as? String, !id.isEmpty,
              let identifier = node["identifier"] as? String, !identifier.isEmpty,
              let title = node["title"] as? String, !title.isEmpty
        else { throw LinearAPIError.decoding }

        let state = node["state"] as? [String: Any]
        let assignee = node["assignee"] as? [String: Any]
        let project = node["project"] as? [String: Any]
        let team = node["team"] as? [String: Any]
        let labels = ((node["labels"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let labelNames = labels.compactMap { $0["name"] as? String }
        let teamStates = parseWorkflowStates(from: team)

        return LinearIssueSummary(
            id: id,
            identifier: identifier,
            title: title,
            issueURL: (node["url"] as? String).flatMap(URL.init(string:)),
            priority: parseInt(node["priority"]),
            estimate: parseInt(node["estimate"]),
            stateId: state?["id"] as? String,
            stateName: state?["name"] as? String,
            stateType: state?["type"] as? String,
            assigneeName: assignee?["name"] as? String,
            assigneeEmail: assignee?["email"] as? String,
            projectName: project?["name"] as? String,
            teamName: team?["name"] as? String,
            teamKey: team?["key"] as? String,
            teamID: team?["id"] as? String,
            teamStates: teamStates,
            completedStateId: completedStateID(from: teamStates),
            labelNames: labelNames,
            createdAt: parseDate(node["createdAt"]),
            updatedAt: parseDate(node["updatedAt"]),
            dueDate: parseDate(node["dueDate"]),
            completedAt: parseDate(node["completedAt"]),
            descriptionText: node["description"] as? String)
    }

    private static func prioritySortValue(_ priority: Int?) -> Int {
        guard let priority, priority > 0 else { return Int.max }
        return priority
    }

    private static func parseInt(_ raw: Any?) -> Int? {
        (raw as? Int) ?? (raw as? NSNumber)?.intValue
    }

    private static func parseDouble(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return (raw as? NSNumber)?.doubleValue
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let raw = raw as? String, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainISO = ISO8601DateFormatter()
        if let value = withFractional.date(from: raw) ?? plainISO.date(from: raw) {
            return value
        }
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: raw)
    }

    private static func containsUnauthorizedGraphQLError(_ errors: [[String: Any]]) -> Bool {
        for error in errors {
            if let extensions = error["extensions"] as? [String: Any],
               let code = extensions["code"] as? String {
                let normalized = code.lowercased()
                if normalized.contains("auth") || normalized.contains("unauthorized")
                    || normalized.contains("forbidden")
                {
                    return true
                }
            }
            if let message = error["message"] as? String {
                let normalized = message.lowercased()
                if normalized.contains("unauthorized") || normalized.contains("forbidden")
                    || normalized.contains("invalid token") || normalized.contains("invalid api key")
                    || normalized.contains("authentication") || normalized.contains("auth token")
                {
                    return true
                }
            }
        }
        return false
    }

    /// Pure parser — unit-tested without network.
    static func parseCompletedIssues(_ data: Data) throws -> [LinearCompletedIssue] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let issues = dataObj["issues"] as? [String: Any],
              let nodes = issues["nodes"] as? [[String: Any]]
        else { throw LinearAPIError.decoding }

        return try nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let identifier = node["identifier"] as? String, !identifier.isEmpty,
                  let title = node["title"] as? String, !title.isEmpty,
                  let completedAt = parseDate(node["completedAt"])
            else { throw LinearAPIError.decoding }
            return LinearCompletedIssue(
                id: id, identifier: identifier, title: title, completedAt: completedAt)
        }
    }
}

/// Pure reward math for Linear completions → companion XP.
enum LinearRewards {
    /// XP per newly completed issue (growth only — not `usedSinceInstall`).
    static let xpPerIssue = 2_000_000
    /// How far back to look for completions on each poll.
    static let lookbackDays = 14
    /// Cap persisted credited IDs so saves stay bounded.
    static let maxCreditedIDs = 500

    struct Outcome: Equatable {
        var xp: Int
        var creditedIDs: [String]
        /// True when this was the first successful poll (seed without XP).
        var seeded: Bool
        var newlyCredited: [LinearCompletedIssue]
    }

    /// Deduped grant. First successful poll (`seeded == false`) records IDs with 0 XP
    /// so already-done issues do not dump a backfill.
    static func evaluate(
        issues: [LinearCompletedIssue],
        alreadyCredited: [String],
        seeded: Bool
    ) -> Outcome {
        var credited = alreadyCredited
        var creditedSet = Set(alreadyCredited)
        let fresh = issues.filter { !creditedSet.contains($0.id) }
        guard seeded else {
            for issue in fresh {
                credited.append(issue.id)
                creditedSet.insert(issue.id)
            }
            credited = Array(credited.suffix(maxCreditedIDs))
            return Outcome(xp: 0, creditedIDs: credited, seeded: true, newlyCredited: [])
        }
        guard !fresh.isEmpty else {
            return Outcome(xp: 0, creditedIDs: credited, seeded: true, newlyCredited: [])
        }
        for issue in fresh {
            credited.append(issue.id)
        }
        credited = Array(credited.suffix(maxCreditedIDs))
        let xp = fresh.count * xpPerIssue
        return Outcome(xp: xp, creditedIDs: credited, seeded: true, newlyCredited: fresh)
    }

    static func mergedCreditedIDs(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in a + b {
            if seen.insert(id).inserted { out.append(id) }
        }
        return Array(out.suffix(maxCreditedIDs))
    }

    /// Persist XP only for issues that actually received it (`newlyCredited`). First id wins.
    static func appendingXPRecords(
        existing: [LinearIssueXPRecord],
        newlyCredited: [LinearCompletedIssue]
    ) -> [LinearIssueXPRecord] {
        var seen = Set(existing.map(\.id))
        var out = existing
        for issue in newlyCredited {
            guard seen.insert(issue.id).inserted else { continue }
            out.append(LinearIssueXPRecord(
                id: issue.id,
                identifier: issue.identifier,
                xp: xpPerIssue,
                awardedAt: issue.completedAt))
        }
        return Array(out.suffix(maxCreditedIDs))
    }

    static func mergingXPRecords(
        _ a: [LinearIssueXPRecord],
        _ b: [LinearIssueXPRecord]
    ) -> [LinearIssueXPRecord] {
        var seen = Set<String>()
        var out: [LinearIssueXPRecord] = []
        for record in a + b {
            if seen.insert(record.id).inserted { out.append(record) }
        }
        return Array(out.suffix(maxCreditedIDs))
    }

    static func xpRecord(in records: [LinearIssueXPRecord], id: String) -> LinearIssueXPRecord? {
        records.first { $0.id == id && $0.xp > 0 }
    }
}
