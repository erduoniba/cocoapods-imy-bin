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

public struct ComponentConfigEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var version: String?
    public var mode: String
    public var path: String?
    public var enabled: Bool

    public var id: String { name }

    public var supportsLocal: Bool {
        guard let path else { return false }
        return !path.isEmpty
    }

    public init(
        name: String,
        version: String?,
        mode: String = "binary",
        path: String? = nil,
        enabled: Bool = true
    ) {
        self.name = name
        self.version = version
        self.mode = mode
        self.path = path
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case name, version, mode, path, enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "binary"
        path = try container.decodeIfPresent(String.self, forKey: .path)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct ComponentConfigTable: Codable, Equatable, Sendable {
    public static let filename = ".imy-bin-config.json"

    public var version: Int
    public var project: String
    public var environment: String
    public var defaultMode: String
    public var updatedAt: String
    public var components: [ComponentConfigEntry]

    public init(
        version: Int = 1,
        project: String,
        environment: String = "dev",
        defaultMode: String = "binary",
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        components: [ComponentConfigEntry]
    ) {
        self.version = version
        self.project = project
        self.environment = environment
        self.defaultMode = defaultMode
        self.updatedAt = updatedAt
        self.components = components
    }

    public static func fileURL(in appDirectoryURL: URL) -> URL {
        appDirectoryURL.appendingPathComponent(filename)
    }

    public static func exists(in appDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(in: appDirectoryURL).path)
    }

    public static func read(from appDirectoryURL: URL) throws -> ComponentConfigTable? {
        let url = fileURL(in: appDirectoryURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
    }

    public static func loadOrBootstrap(
        from appDirectoryURL: URL,
        workspacePodspecs: [ComponentPodspecInfo] = [],
        excludingSelfComponent: String? = nil,
        defaultEnabledNames: Set<String>? = nil
    ) -> ComponentConfigTable {
        let overrides = PodfileComponentInspector.readModeOverrides(from: appDirectoryURL)
        if var existing = try? read(from: appDirectoryURL) {
            if let excludingSelfComponent {
                existing.components.removeAll { $0.name == excludingSelfComponent }
            }
            var seen = Set(existing.components.map(\.name))
            for idx in existing.components.indices {
                let compName = existing.components[idx].name
                if let overrideMode = overrides[compName] {
                    existing.components[idx].mode = overrideMode
                }
            }
            for spec in workspacePodspecs where !seen.contains(spec.name) && spec.name != excludingSelfComponent {
                seen.insert(spec.name)
                let relPath = relativePath(from: appDirectoryURL, to: spec.repositoryURL)
                let isEnabled = defaultEnabledNames.map { $0.contains(spec.name) } ?? true
                existing.components.append(
                    ComponentConfigEntry(
                        name: spec.name,
                        version: spec.version,
                        mode: overrides[spec.name] ?? existing.defaultMode,
                        path: relPath,
                        enabled: isEnabled
                    )
                )
            }
            existing.components.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return existing
        }

        let podfileDeps = PodfileComponentInspector.inspectPodfileDeclarationsOnly(from: appDirectoryURL)
        var map: [String: ComponentConfigEntry] = [:]
        for dep in podfileDeps where dep.name != excludingSelfComponent {
            map[dep.name] = ComponentConfigEntry(
                name: dep.name,
                version: dep.declaredVersion,
                mode: dep.effectiveMode,
                path: dep.localPath,
                enabled: true
            )
        }
        for spec in workspacePodspecs where spec.name != excludingSelfComponent {
            let relPath = relativePath(from: appDirectoryURL, to: spec.repositoryURL)
            if var entry = map[spec.name] {
                if entry.version == nil || entry.version?.isEmpty == true {
                    entry.version = spec.version
                }
                if entry.path == nil || entry.path?.isEmpty == true {
                    entry.path = relPath
                }
                map[spec.name] = entry
            } else {
                let isEnabled = defaultEnabledNames.map { $0.contains(spec.name) } ?? true
                map[spec.name] = ComponentConfigEntry(
                    name: spec.name,
                    version: spec.version,
                    mode: overrides[spec.name] ?? "binary",
                    path: relPath,
                    enabled: isEnabled
                )
            }
        }

        let entries = map.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return ComponentConfigTable(
            project: appDirectoryURL.lastPathComponent,
            environment: "dev",
            defaultMode: "binary",
            components: entries
        )
    }

    public func write(to appDirectoryURL: URL) throws {
        var copy = self
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        copy.components.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(copy)
        let targetURL = Self.fileURL(in: appDirectoryURL)
        try data.write(to: targetURL, options: .atomic)

        // Sync .imy-bin-modes.yml so CLI commands (`pod bin status` / `pod bin switch`) stay in sync
        let modesURL = appDirectoryURL.appendingPathComponent(".imy-bin-modes.yml")
        let enabledEntries = copy.components.filter(\.enabled)
        if enabledEntries.isEmpty {
            try? FileManager.default.removeItem(at: modesURL)
        } else {
            let yamlLines = ["---"] + enabledEntries.map { "\($0.name): \($0.mode)" }
            let yamlText = yamlLines.joined(separator: "\n") + "\n"
            try yamlText.write(to: modesURL, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    public static func updateComponentVersion(
        in appDirectoryURL: URL,
        workspacePodspecs: [ComponentPodspecInfo] = [],
        component: String,
        to newVersion: String
    ) throws -> Bool {
        var table = loadOrBootstrap(from: appDirectoryURL, workspacePodspecs: workspacePodspecs)
        guard let idx = table.components.firstIndex(where: { $0.name == component }) else {
            return false
        }
        table.components[idx].version = newVersion
        try table.write(to: appDirectoryURL)
        return true
    }

    public static func relativePath(from baseDirectoryURL: URL, to targetDirectoryURL: URL) -> String {
        let baseComponents = baseDirectoryURL.standardizedFileURL.pathComponents
        let targetComponents = targetDirectoryURL.standardizedFileURL.pathComponents
        var commonCount = 0
        while commonCount < min(baseComponents.count, targetComponents.count),
              baseComponents[commonCount] == targetComponents[commonCount] {
            commonCount += 1
        }
        if commonCount == 0 {
            return targetDirectoryURL.standardizedFileURL.path
        }
        let upMoves = Array(repeating: "..", count: baseComponents.count - commonCount)
        let downMoves = Array(targetComponents.dropFirst(commonCount))
        let combined = upMoves + downMoves
        return combined.isEmpty ? "." : combined.joined(separator: "/")
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
        let overrides = readModeOverrides(from: projectURL)
        if let configTable = try? ComponentConfigTable.read(from: projectURL), !configTable.components.isEmpty {
            return configTable.components
                .filter(\.enabled)
                .map { entry in
                    let overrideMode = overrides[entry.name]
                    let effectiveMode = overrideMode ?? entry.mode
                    return LocalComponentDependency(
                        name: entry.name,
                        declaredVersion: entry.version,
                        localPath: entry.path,
                        effectiveMode: effectiveMode,
                        overrideMode: overrideMode ?? entry.mode
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return inspectPodfileDeclarationsOnly(from: projectURL)
    }

    public static func inspectPodfileDeclarationsOnly(from projectURL: URL) -> [LocalComponentDependency] {
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

    /// Updates the component version in `.imy-bin-config.json` (configuration table) instead of modifying `Podfile`,
    /// preventing Git merge conflicts on `Podfile`.
    @discardableResult
    public static func updateDependencyVersion(
        in projectURL: URL,
        component: String,
        to newVersion: String
    ) throws -> Bool {
        var table = ComponentConfigTable.loadOrBootstrap(from: projectURL)
        if let idx = table.components.firstIndex(where: { $0.name == component }) {
            table.components[idx].version = newVersion
            try table.write(to: projectURL)
            return true
        }
        return false
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
