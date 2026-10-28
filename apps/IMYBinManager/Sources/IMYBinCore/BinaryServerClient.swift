import Foundation

public struct BinaryComponent: Identifiable, Equatable, Sendable {
    public let name: String
    public let versions: [String]

    public var id: String { name }

    public init(name: String, versions: [String]) {
        self.name = name
        self.versions = versions
    }
}

public enum BinaryServerClientError: LocalizedError, Sendable {
    case invalidAddress
    case unexpectedResponse
    case httpStatus(Int, String)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "服务地址无效，请输入完整的 http:// 或 https:// 地址。"
        case .unexpectedResponse:
            "二进制服务返回了无法识别的响应。"
        case .httpStatus(let status, let message):
            message.isEmpty ? "二进制服务请求失败（HTTP \(status)）。" : "二进制服务请求失败（HTTP \(status)）：\(message)"
        case .invalidPayload:
            "二进制服务返回的数据格式不符合 {组件名: [版本]} 协议。"
        }
    }
}

public struct BinaryServerClient: Sendable {
    public init() {}

    public static func frameworksURL(from address: String) throws -> URL {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else {
            throw BinaryServerClientError.invalidAddress
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            components.path = "/frameworks"
        } else if path.split(separator: "/").last != "frameworks" {
            components.path = "/\(path)/frameworks"
        } else {
            components.path = "/\(path)"
        }
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw BinaryServerClientError.invalidAddress
        }
        return url
    }

    public static func decodeComponents(from data: Data) throws -> [BinaryComponent] {
        guard let payload = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            throw BinaryServerClientError.invalidPayload
        }

        return payload.map { name, versions in
            BinaryComponent(
                name: name,
                versions: versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func listComponents(address: String) async throws -> [BinaryComponent] {
        let url = try Self.frameworksURL(from: address)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try Self.decodeComponents(from: data)
    }

    public static func policyURL(from address: String, project: String, subpath: String? = nil) throws -> URL {
        let base = try frameworksURL(from: address).deletingLastPathComponent()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BinaryServerClientError.invalidAddress
        }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = cleanPath.isEmpty ? "" : "/\(cleanPath)"
        if let subpath, !subpath.isEmpty {
            components.path = "\(prefix)/api/v1/projects/\(project)/policies/\(subpath)"
        } else {
            components.path = "\(prefix)/api/v1/projects/\(project)/policies"
        }
        guard let url = components.url else {
            throw BinaryServerClientError.invalidAddress
        }
        return url
    }

    public static func configTableURL(from address: String, project: String? = nil, subpath: String? = nil) throws -> URL {
        let base = try frameworksURL(from: address).deletingLastPathComponent()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BinaryServerClientError.invalidAddress
        }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = cleanPath.isEmpty ? "" : "/\(cleanPath)"
        if let project, !project.isEmpty {
            if let subpath, !subpath.isEmpty {
                components.path = "\(prefix)/api/v1/config-tables/\(project)/\(subpath)"
            } else {
                components.path = "\(prefix)/api/v1/config-tables/\(project)"
            }
        } else {
            components.path = "\(prefix)/api/v1/config-tables"
        }
        guard let url = components.url else {
            throw BinaryServerClientError.invalidAddress
        }
        return url
    }

    public func listConfigTables(address: String, token: String? = nil) async throws -> [ComponentConfigTable] {
        let url = try Self.configTableURL(from: address)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode([ComponentConfigTable].self, from: data)
    }

    public func fetchConfigTable(address: String, project: String, token: String? = nil) async throws -> ComponentConfigTable {
        let url = try Self.configTableURL(from: address, project: project)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public static func dashboardURL(from address: String) throws -> URL {
        let base = try frameworksURL(from: address).deletingLastPathComponent()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BinaryServerClientError.invalidAddress
        }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = cleanPath.isEmpty ? "" : "/\(cleanPath)"
        components.path = "\(prefix)/dashboard"
        guard let url = components.url else {
            throw BinaryServerClientError.invalidAddress
        }
        return url
    }

    public func createConfigTable(address: String, table: ComponentConfigTable, token: String? = nil) async throws -> ComponentConfigTable {
        let url = try Self.configTableURL(from: address)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(table)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public func deleteConfigTable(address: String, project: String, token: String? = nil) async throws {
        let url = try Self.configTableURL(from: address, project: project)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
    }

    public struct ConfigTableSyncDelta: Encodable, Sendable {
        public let action: String
        public var column: String?
        public var allColumns: Bool?
        public var component: ComponentConfigEntry?
        public var componentName: String?
        public var columnData: ComponentConfigColumn?
        public var columnName: String?
        public var oldName: String?
        public var newName: String?
        public var activeColumn: String?
        public var setActive: Bool?
        public var deletedColumns: [String]?
        public var table: ComponentConfigTable?

        enum CodingKeys: String, CodingKey {
            case action, column, allColumns, component, componentName, columnName, oldName, newName, activeColumn, setActive, deletedColumns, table
        }

        public init(
            action: String = "merge_table",
            column: String? = nil,
            allColumns: Bool? = nil,
            component: ComponentConfigEntry? = nil,
            componentName: String? = nil,
            columnData: ComponentConfigColumn? = nil,
            columnName: String? = nil,
            oldName: String? = nil,
            newName: String? = nil,
            activeColumn: String? = nil,
            setActive: Bool? = nil,
            deletedColumns: [String]? = nil,
            table: ComponentConfigTable? = nil
        ) {
            self.action = action
            self.column = column
            self.allColumns = allColumns
            self.component = component
            self.componentName = componentName
            self.columnData = columnData
            self.columnName = columnName
            self.oldName = oldName
            self.newName = newName
            self.activeColumn = activeColumn
            self.setActive = setActive
            self.deletedColumns = deletedColumns
            self.table = table
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            if let columnData {
                try container.encode(columnData, forKey: .column)
            } else {
                try container.encodeIfPresent(column, forKey: .column)
            }
            try container.encodeIfPresent(allColumns, forKey: .allColumns)
            try container.encodeIfPresent(component, forKey: .component)
            try container.encodeIfPresent(componentName, forKey: .componentName)
            try container.encodeIfPresent(columnName, forKey: .columnName)
            try container.encodeIfPresent(oldName, forKey: .oldName)
            try container.encodeIfPresent(newName, forKey: .newName)
            try container.encodeIfPresent(activeColumn, forKey: .activeColumn)
            try container.encodeIfPresent(setActive, forKey: .setActive)
            try container.encodeIfPresent(deletedColumns, forKey: .deletedColumns)
            try container.encodeIfPresent(table, forKey: .table)
        }
    }

    public func syncConfigTableDelta(
        address: String,
        project: String,
        delta: ConfigTableSyncDelta,
        token: String? = nil
    ) async throws -> ComponentConfigTable {
        let url = try Self.configTableURL(from: address, project: project, subpath: "sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(delta)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public func pushConfigTable(address: String, table: ComponentConfigTable, token: String? = nil) async throws -> ComponentConfigTable {
        let url = try Self.configTableURL(from: address, project: table.project)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(table)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public func duplicateConfigTable(
        address: String,
        project: String,
        targetProject: String? = nil,
        sourceColumn: String? = nil,
        targetColumn: String? = nil,
        description: String? = nil,
        setActive: Bool? = nil,
        token: String? = nil
    ) async throws -> ComponentConfigTable {
        let url = try Self.configTableURL(from: address, project: project, subpath: "duplicate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        struct DuplicatePayload: Encodable {
            let targetProject: String?
            let sourceColumn: String?
            let targetColumn: String?
            let description: String?
            let setActive: Bool?
        }
        request.httpBody = try JSONEncoder().encode(DuplicatePayload(
            targetProject: targetProject,
            sourceColumn: sourceColumn,
            targetColumn: targetColumn,
            description: description,
            setActive: setActive
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public func fetchActivePolicy(address: String, project: String, token: String? = nil) async throws -> ManagedPolicySnapshot {
        let url = try Self.policyURL(from: address, project: project, subpath: "active")
        return try await fetchPolicy(from: url, token: token)
    }

    public func fetchPolicyRevision(address: String, project: String, revision: String, token: String? = nil) async throws -> ManagedPolicySnapshot {
        let url = try Self.policyURL(from: address, project: project, subpath: revision)
        return try await fetchPolicy(from: url, token: token)
    }

    public func pushPolicy(
        address: String,
        project: String,
        targets: [ManagedTarget],
        token: String? = nil
    ) async throws -> ManagedPolicySnapshot {
        let url = try Self.policyURL(from: address, project: project, subpath: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        struct PolicyPayload: Encodable {
            let targets: [ManagedTarget]
        }
        request.httpBody = try JSONEncoder().encode(PolicyPayload(targets: targets))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ManagedPolicySnapshot.self, from: data)
    }

    public func activatePolicy(
        address: String,
        project: String,
        revision: String,
        expectedRevision: String? = nil,
        token: String? = nil
    ) async throws {
        let url = try Self.policyURL(from: address, project: project, subpath: "activate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        struct ActivatePayload: Encodable {
            let revision: String
            let expectedRevision: String?
        }
        request.httpBody = try JSONEncoder().encode(ActivatePayload(revision: revision, expectedRevision: expectedRevision))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
    }

    private func fetchPolicy(from url: URL, token: String?) async throws -> ManagedPolicySnapshot {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinaryServerClientError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BinaryServerClientError.httpStatus(httpResponse.statusCode, message)
        }
        return try JSONDecoder().decode(ManagedPolicySnapshot.self, from: data)
    }
}
