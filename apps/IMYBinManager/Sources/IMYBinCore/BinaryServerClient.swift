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
}
