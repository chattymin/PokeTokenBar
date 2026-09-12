import Foundation

/// Form payload for Linear `issueCreate`. Empty optionals are omitted on the wire.
struct LinearIssueDraft: Equatable, Sendable {
    var title: String
    var description: String = ""
    var teamId: String
    var projectId: String? = nil
    var assigneeId: String? = nil
    var stateId: String? = nil
    var labelIds: [String] = []
}

struct LinearUserSummary: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var displayName: String?
    var email: String?
}

struct LinearTeamCatalog: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var key: String?
    var defaultIssueState: LinearWorkflowState?
    var states: [LinearWorkflowState]
}

struct LinearLabelSummary: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var teamID: String?
}

/// Closed-state title for the composer labels menu. Catalog order; 1–2 names, else a count.
enum LinearIssueLabelMenuTitle {
    static func text(
        selectedIDs: Set<String>,
        labels: [LinearLabelSummary],
        placeholder: String,
        counted: (Int) -> String
    ) -> String {
        let names = labels.compactMap { selectedIDs.contains($0.id) ? $0.name : nil }
        switch names.count {
        case 0: return placeholder
        case 1, 2: return names.joined(separator: ", ")
        default: return counted(names.count)
        }
    }
}

struct LinearProjectRef: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var teamIDs: [String]
}

struct LinearCreateCatalog: Equatable, Sendable {
    var viewer: LinearUserSummary?
    var teams: [LinearTeamCatalog]
    var users: [LinearUserSummary]
    var labels: [LinearLabelSummary]
    var projects: [LinearProjectRef]
}

extension LinearClient {
    static let lastCreatedTeamDefaultsKey = "linearLastCreatedTeamID"

    /// Teams + workflow states + viewer. Does not nest `team.states` under projects.
    static var createCatalogTeamsQuery: String {
        """
        query CreateCatalogTeams {
          viewer { id name displayName email }
          teams(first: 50) {
            nodes {
              id
              name
              key
              defaultIssueState { id name type position }
              states { nodes { id name type position } }
            }
          }
        }
        """
    }

    static var createCatalogUsersQuery: String {
        """
        query CreateCatalogUsers {
          users(first: 50) {
            nodes { id name displayName email }
          }
        }
        """
    }

    static var createCatalogLabelsQuery: String {
        """
        query CreateCatalogLabels {
          issueLabels(first: 100) {
            nodes { id name team { id } }
          }
        }
        """
    }

    /// Project names + team ids only — no nested issues, no `team.states`.
    static var createCatalogProjectsQuery: String {
        """
        query CreateCatalogProjects {
          projects(first: 100) {
            nodes {
              id
              name
              teams { nodes { id } }
            }
          }
        }
        """
    }

    static var issueCreateMutation: String {
        let issueFields = issueNodeFields
        return """
        mutation CreateLinearIssue($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { \(issueFields) }
          }
        }
        """
    }

    func fetchCreateCatalog(apiKey: String) async throws -> LinearCreateCatalog {
        let teamsData = try await postGraphQL(
            apiKey: apiKey, query: Self.createCatalogTeamsQuery, variables: [:])
        var catalog = try Self.parseCreateCatalogTeams(teamsData)

        let usersData = try await postGraphQL(
            apiKey: apiKey, query: Self.createCatalogUsersQuery, variables: [:])
        catalog.users = try Self.parseCreateCatalogUsers(usersData, viewer: catalog.viewer)

        let labelsData = try await postGraphQL(
            apiKey: apiKey, query: Self.createCatalogLabelsQuery, variables: [:])
        catalog.labels = try Self.parseCreateCatalogLabels(labelsData)

        let projectsData = try await postGraphQL(
            apiKey: apiKey, query: Self.createCatalogProjectsQuery, variables: [:])
        catalog.projects = try Self.parseCreateCatalogProjects(projectsData)
        return catalog
    }

    func createIssue(apiKey: String, draft: LinearIssueDraft) async throws -> LinearIssueSummary {
        let data = try await postGraphQL(
            apiKey: apiKey,
            query: Self.issueCreateMutation,
            variables: Self.issueCreateVariables(draft))
        return try Self.parseIssueCreate(data)
    }

    /// GraphQL `variables` map. Empty optionals are omitted (Linear rejects blank ids).
    static func issueCreateVariables(_ draft: LinearIssueDraft) -> [String: Any] {
        var input: [String: Any] = [
            "teamId": draft.teamId,
            "title": draft.title,
        ]
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { input["description"] = description }
        if let assigneeId = trimmedOptional(draft.assigneeId) { input["assigneeId"] = assigneeId }
        if let stateId = trimmedOptional(draft.stateId) { input["stateId"] = stateId }
        if let projectId = trimmedOptional(draft.projectId) { input["projectId"] = projectId }
        if !draft.labelIds.isEmpty { input["labelIds"] = draft.labelIds }
        return ["input": input]
    }

    static func parseIssueCreate(_ data: Data) throws -> LinearIssueSummary {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any],
              let payload = dataObj["issueCreate"] as? [String: Any],
              payload["success"] as? Bool == true,
              let issue = payload["issue"] as? [String: Any]
        else { throw LinearAPIError.decoding }
        return try parseIssueSummary(issue)
    }

    static func parseCreateCatalogTeams(_ data: Data) throws -> LinearCreateCatalog {
        let dataObj = try graphQLData(data)
        let viewer = parseUser(dataObj["viewer"] as? [String: Any])
        let nodes = ((dataObj["teams"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let teams: [LinearTeamCatalog] = nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            let states = parseWorkflowStates(from: node)
            let defaultNode = node["defaultIssueState"] as? [String: Any]
            let defaultState: LinearWorkflowState?
            if let defaultNode,
               let stateID = defaultNode["id"] as? String, !stateID.isEmpty,
               let stateName = defaultNode["name"] as? String, !stateName.isEmpty
            {
                defaultState = LinearWorkflowState(
                    id: stateID,
                    name: stateName,
                    type: (defaultNode["type"] as? String) ?? "",
                    position: parseDoublePublic(defaultNode["position"]))
            } else {
                defaultState = nil
            }
            return LinearTeamCatalog(
                id: id,
                name: name,
                key: node["key"] as? String,
                defaultIssueState: defaultState,
                states: states)
        }
        return LinearCreateCatalog(
            viewer: viewer,
            teams: teams,
            users: viewer.map { [$0] } ?? [],
            labels: [],
            projects: [])
    }

    static func parseCreateCatalogUsers(
        _ data: Data, viewer: LinearUserSummary?
    ) throws -> [LinearUserSummary] {
        let dataObj = try graphQLData(data)
        let nodes = ((dataObj["users"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        var users = nodes.compactMap(parseUser)
        if let viewer, !users.contains(where: { $0.id == viewer.id }) {
            users.insert(viewer, at: 0)
        }
        return users
    }

    static func parseCreateCatalogLabels(_ data: Data) throws -> [LinearLabelSummary] {
        let dataObj = try graphQLData(data)
        let nodes = ((dataObj["issueLabels"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            return LinearLabelSummary(
                id: id,
                name: name,
                teamID: (node["team"] as? [String: Any])?["id"] as? String)
        }
    }

    static func parseCreateCatalogProjects(_ data: Data) throws -> [LinearProjectRef] {
        let dataObj = try graphQLData(data)
        let nodes = ((dataObj["projects"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, !id.isEmpty,
                  let name = node["name"] as? String, !name.isEmpty
            else { return nil }
            let teamNodes = ((node["teams"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            let teamIDs = teamNodes.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
            return LinearProjectRef(id: id, name: name, teamIDs: teamIDs)
        }
    }

    /// Team default workflow state, else first unstarted/backlog type.
    static func defaultCreateState(for team: LinearTeamCatalog) -> LinearWorkflowState? {
        if let def = team.defaultIssueState { return def }
        return team.states.first {
            let type = $0.type.lowercased()
            return type == "unstarted" || type == "backlog"
        }
    }

    static func labels(in catalog: LinearCreateCatalog, forTeamID teamID: String) -> [LinearLabelSummary] {
        catalog.labels.filter { label in
            guard let labelTeam = label.teamID, !labelTeam.isEmpty else { return true }
            return labelTeam == teamID
        }
    }

    static func projects(in catalog: LinearCreateCatalog, forTeamID teamID: String) -> [LinearProjectRef] {
        catalog.projects.filter { $0.teamIDs.contains(teamID) || $0.teamIDs.isEmpty }
    }

    private static func parseUser(_ node: [String: Any]?) -> LinearUserSummary? {
        guard let node,
              let id = node["id"] as? String, !id.isEmpty
        else { return nil }
        let name = (node["name"] as? String)
            ?? (node["displayName"] as? String)
            ?? (node["email"] as? String)
            ?? ""
        guard !name.isEmpty else { return nil }
        return LinearUserSummary(
            id: id,
            name: name,
            displayName: node["displayName"] as? String,
            email: node["email"] as? String)
    }

    private static func graphQLData(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.decoding
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            if containsUnauthorizedGraphQLError(errors) { throw LinearAPIError.unauthorized }
            throw LinearAPIError.decoding
        }
        guard let dataObj = root["data"] as? [String: Any] else { throw LinearAPIError.decoding }
        return dataObj
    }

    private static func trimmedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDoublePublic(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return (raw as? NSNumber)?.doubleValue
    }
}
