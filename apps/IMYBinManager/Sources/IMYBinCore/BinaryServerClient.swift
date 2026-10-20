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
