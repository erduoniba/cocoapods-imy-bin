import Foundation

public struct ManagedDependency: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let mode: String
    public var id: String { name }
}

public struct ManagedTarget: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let dependencies: [ManagedDependency]
    public var id: String { name }
}

public struct ManagedPolicySnapshot: Codable, Equatable, Sendable {
    public let project: String
    public let revision: String
    public let targets: [ManagedTarget]

    public static func read(from projectURL: URL) throws -> ManagedPolicySnapshot? {
        let filename = projectURL.appendingPathComponent(".imy-bin-policy.json")
        guard FileManager.default.fileExists(atPath: filename.path) else { return nil }
        let data = try Data(contentsOf: filename)
        let policy = try JSONDecoder().decode(ManagedPolicySnapshot.self, from: data)
        guard !policy.project.isEmpty, UUID(uuidString: policy.revision) != nil,
              !policy.targets.isEmpty,
              policy.targets.allSatisfy({ !$0.name.isEmpty && $0.dependencies.allSatisfy {
                  !$0.name.isEmpty && !$0.version.isEmpty && ["source", "binary"].contains($0.mode)
              } })
        else { throw ManagedPolicyError.invalidSnapshot }
        return policy
    }
}

public enum ManagedPolicyError: LocalizedError {
    case invalidSnapshot

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "本地平台策略快照无效，请重新同步。"
        }
    }
}

public struct LocalComponentDependency: Equatable, Sendable, Identifiable {
    public let name: String
    public let declaredVersion: String?
    public let localPath: String?
    public let effectiveMode: String
    public let overrideMode: String?

    public var id: String { name }
    public var supportsLocal: Bool {
        guard let localPath else { return false }
        return !localPath.isEmpty
    }

    public init(
        name: String,
        declaredVersion: String?,
        localPath: String?,
        effectiveMode: String,
        overrideMode: String?
    ) {
        self.name = name
        self.declaredVersion = declaredVersion
        self.localPath = localPath
        self.effectiveMode = effectiveMode
        self.overrideMode = overrideMode
    }
}

public enum PodfileComponentInspector {
    public static func inspect(from projectURL: URL) -> [LocalComponentDependency] {
        let podfileURL = projectURL.appendingPathComponent("Podfile")
        guard let podfileText = try? String(contentsOf: podfileURL, encoding: .utf8) else {
            return []
        }
        let overrides = readModeOverrides(from: projectURL)
        let defaultMode = podfileText.contains("use_binaries!(false)") ? "source" : "binary"

        var results: [LocalComponentDependency] = []
        var seen: Set<String> = []
        for rawLine in podfileText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            guard let parsed = parseDependencyLine(line), !seen.contains(parsed.name) else { continue }
            seen.insert(parsed.name)
            let overrideMode = overrides[parsed.name]
            let effectiveMode: String
            if let overrideMode {
                effectiveMode = overrideMode
            } else if parsed.isHardcodedPath {
                effectiveMode = "local"
            } else {
                effectiveMode = defaultMode
            }
            results.append(
                LocalComponentDependency(
                    name: parsed.name,
                    declaredVersion: parsed.version,
                    localPath: parsed.path,
                    effectiveMode: effectiveMode,
                    overrideMode: overrideMode
                )
            )
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func readModeOverrides(from projectURL: URL) -> [String: String] {
        let modesURL = projectURL.appendingPathComponent(".imy-bin-modes.yml")
        guard let content = try? String(contentsOf: modesURL, encoding: .utf8) else {
            return [:]
        }
        var map: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "---" || line.hasPrefix("#") { continue }
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            if parts.count == 2, ["local", "source", "binary"].contains(parts[1]) {
                map[parts[0]] = parts[1]
            }
        }
        return map
    }

    private static func parseDependencyLine(
        _ line: String
    ) -> (name: String, version: String?, path: String?, isHardcodedPath: Bool)? {
        let isImyPod = line.hasPrefix("imy_pod ") || line.hasPrefix("imy_pod(")
        let isPod = line.hasPrefix("pod ") || line.hasPrefix("pod(")
        guard isImyPod || isPod else { return nil }

        let tokens = extractSingleOrDoubleQuotedStrings(from: line)
        guard let first = tokens.first, !first.isEmpty else { return nil }
        let rootName = first.split(separator: "/").first.map(String.init) ?? first

        var pathValue: String?
        if let pathRange = line.range(of: #"(:path|path:)\s*(=>)?\s*['"][^'"]+['"]"#, options: .regularExpression) {
            let segment = String(line[pathRange])
            pathValue = extractSingleOrDoubleQuotedStrings(from: segment).last
        }

        var versionValue: String?
        if tokens.count >= 2 {
            let second = tokens[1]
            if second != pathValue {
                versionValue = second
            }
        }
        let isHardcodedPath = isPod && pathValue != nil && versionValue == nil
        return (rootName, versionValue, pathValue, isHardcodedPath)
    }

    private static func extractSingleOrDoubleQuotedStrings(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"['"]([^'"]+)['"]"#) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
