import Foundation

public struct ManagedDependency: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let mode: String
    public var id: String { name }

    public init(name: String, version: String, mode: String) {
        self.name = name
        self.version = version
        self.mode = mode
    }
}

public struct ManagedTarget: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let dependencies: [ManagedDependency]
    public var id: String { name }

    public init(name: String, dependencies: [ManagedDependency]) {
        self.name = name
        self.dependencies = dependencies
    }
}

public struct ManagedPolicySnapshot: Codable, Equatable, Sendable {
    public let project: String
    public let revision: String
    public let targets: [ManagedTarget]

    public init(project: String, revision: String, targets: [ManagedTarget]) {
        self.project = project
        self.revision = revision
        self.targets = targets
    }

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
    public var git: String?
    public var branch: String?
    public var tag: String?
    public var commit: String?
    public var targets: [String]?
    public var enabled: Bool

    public var id: String { name }

    public var supportsLocal: Bool {
        guard let path else { return false }
        return !path.isEmpty
    }

    public var isBranchMode: Bool {
        mode == "branch"
    }

    public init(
        name: String,
        version: String?,
        mode: String = "binary",
        path: String? = nil,
        git: String? = nil,
        branch: String? = nil,
        tag: String? = nil,
        commit: String? = nil,
        targets: [String]? = nil,
        enabled: Bool = true
    ) {
        self.name = name
        self.version = version
        self.mode = mode
        self.path = path
        self.git = git
        self.branch = branch
        self.tag = tag
        self.commit = commit
        self.targets = targets
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case name, version, mode, path, git, branch, tag, commit, targets, enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "binary"
        path = try container.decodeIfPresent(String.self, forKey: .path)
        git = try container.decodeIfPresent(String.self, forKey: .git)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        commit = try container.decodeIfPresent(String.self, forKey: .commit)
        targets = try container.decodeIfPresent([String].self, forKey: .targets)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// 配置表中的单个 App 版本列（每列对应一个 App 版本或环境分支的组件依赖基线）
public struct ComponentConfigColumn: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    /// 版本列名称（如 "1.0.0", "1.1.0", "1.2.0", "main"）
    public var name: String
    /// 版本列说明（如 "App 1.2.0 迭代发版基线"）
    public var description: String?
    public var createdAt: String?
    public var updatedAt: String?
    /// 该版本列专属的组件依赖清单
    public var components: [ComponentConfigEntry]

    public init(
        name: String,
        description: String? = nil,
        createdAt: String? = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String? = ISO8601DateFormatter().string(from: Date()),
        components: [ComponentConfigEntry] = []
    ) {
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.components = components
    }
}

public struct ComponentConfigTable: Codable, Equatable, Sendable {
    public static let filename = ".imy-bin-config.json"

    public var version: Int
    public var project: String
    public var environment: String
    public var defaultMode: String
    public var updatedAt: String
    /// 当前生效的 App 版本列名称
    public var activeColumn: String?
    /// 多版本列配置清单
    public var columns: [ComponentConfigColumn]?
    /// 当前生效列的组件项（同时保留顶层，确保向下兼容与 CLI 零冲突）
    public var components: [ComponentConfigEntry]

    enum CodingKeys: String, CodingKey {
        case version, project, environment, defaultMode, updatedAt, activeColumn, columns, components
    }

    public init(
        version: Int = 1,
        project: String,
        environment: String = "dev",
        defaultMode: String = "binary",
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        activeColumn: String? = nil,
        columns: [ComponentConfigColumn]? = nil,
        components: [ComponentConfigEntry]
    ) {
        self.version = version
        self.project = project
        self.environment = environment
        self.defaultMode = defaultMode
        self.updatedAt = updatedAt
        self.components = components

        if let columns = columns, !columns.isEmpty {
            self.columns = columns
            self.activeColumn = activeColumn ?? columns.first?.name ?? "1.0.0"
        } else {
            let colName = activeColumn ?? "1.0.0"
            self.columns = [
                ComponentConfigColumn(
                    name: colName,
                    description: "默认 App 版本列",
                    components: components
                )
            ]
            self.activeColumn = colName
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? ""
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "dev"
        defaultMode = try container.decodeIfPresent(String.self, forKey: .defaultMode) ?? "binary"
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        let decodedComponents = try container.decodeIfPresent([ComponentConfigEntry].self, forKey: .components) ?? []
        let decodedColumns = try container.decodeIfPresent([ComponentConfigColumn].self, forKey: .columns)
        let decodedActive = try container.decodeIfPresent(String.self, forKey: .activeColumn)

        if let decodedColumns, !decodedColumns.isEmpty {
            columns = decodedColumns
            let targetActive = decodedActive ?? decodedColumns.first?.name ?? "1.0.0"
            activeColumn = targetActive
            if let activeCol = decodedColumns.first(where: { $0.name == targetActive }) {
                components = activeCol.components
            } else {
                components = decodedComponents.isEmpty ? (decodedColumns.first?.components ?? []) : decodedComponents
            }
        } else {
            let defaultColName = decodedActive ?? "1.0.0"
            columns = [
                ComponentConfigColumn(
                    name: defaultColName,
                    description: "默认 App 版本列",
                    components: decodedComponents
                )
            ]
            activeColumn = defaultColName
            components = decodedComponents
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(project, forKey: .project)
        try container.encode(environment, forKey: .environment)
        try container.encode(defaultMode, forKey: .defaultMode)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(activeColumn, forKey: .activeColumn)
        try container.encodeIfPresent(columns, forKey: .columns)
        try container.encode(components, forKey: .components)
    }

    /// 获取当前生效列名称
    public var currentColumnName: String {
        activeColumn ?? columns?.first?.name ?? "1.0.0"
    }

    /// 保证 columns 存在且包含当前列
    public mutating func ensureColumnsInitialized() {
        if columns == nil || columns?.isEmpty == true {
            let colName = currentColumnName
            columns = [ComponentConfigColumn(name: colName, description: "默认 App 版本列", components: components)]
            activeColumn = colName
        }
    }

    /// 将当前工作区 components 修改同步回当前活跃列
    public mutating func syncComponentsToActiveColumn() {
        ensureColumnsInitialized()
        if let idx = columns?.firstIndex(where: { $0.name == currentColumnName }) {
            columns?[idx].components = components
            columns?[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        }
    }

    /// 切换当前生效版本列
    @discardableResult
    public mutating func switchActiveColumn(to targetName: String) -> Bool {
        ensureColumnsInitialized()
        guard let cols = columns, let targetIndex = cols.firstIndex(where: { $0.name == targetName }) else {
            return false
        }
        syncComponentsToActiveColumn()
        activeColumn = targetName
        components = cols[targetIndex].components
        return true
    }

    /// 新建 App 版本列
    @discardableResult
    public mutating func createColumn(name: String, description: String? = nil, copyFromCurrent: Bool = true) -> Bool {
        ensureColumnsInitialized()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if columns?.contains(where: { $0.name == trimmed }) == true {
            return false
        }
        syncComponentsToActiveColumn()
        let now = ISO8601DateFormatter().string(from: Date())
        let newEntries = copyFromCurrent ? components : []
        let newCol = ComponentConfigColumn(
            name: trimmed,
            description: description,
            createdAt: now,
            updatedAt: now,
            components: newEntries
        )
        columns?.append(newCol)
        return true
    }

    /// 删除指定版本列（至少保留一列）
    @discardableResult
    public mutating func deleteColumn(name: String) -> Bool {
        ensureColumnsInitialized()
        guard let count = columns?.count, count > 1 else {
            return false
        }
        guard let idx = columns?.firstIndex(where: { $0.name == name }) else {
            return false
        }
        columns?.remove(at: idx)
        if activeColumn == name {
            if let first = columns?.first {
                activeColumn = first.name
                components = first.components
            }
        }
        return true
    }

    /// 重命名指定版本列
    @discardableResult
    public mutating func renameColumn(from oldName: String, to newName: String) -> Bool {
        ensureColumnsInitialized()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return false }
        if columns?.contains(where: { $0.name == trimmed }) == true {
            return false
        }
        guard let idx = columns?.firstIndex(where: { $0.name == oldName }) else {
            return false
        }
        columns?[idx].name = trimmed
        if activeColumn == oldName {
            activeColumn = trimmed
        }
        return true
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
        let effectiveSelf: String? = excludingSelfComponent ?? {
            let parent = appDirectoryURL.deletingLastPathComponent()
            if let files = try? FileManager.default.contentsOfDirectory(atPath: parent.path) {
                if let specFile = files.first(where: { $0.hasSuffix(".podspec") && !$0.hasSuffix(".podspec.json") }) {
                    return (specFile as NSString).deletingPathExtension
                }
            }
            return nil
        }()

        let overrides = PodfileComponentInspector.readModeOverrides(from: appDirectoryURL)
        if var existing = try? read(from: appDirectoryURL) {
            if let effectiveSelf {
                existing.components.removeAll { $0.name == effectiveSelf }
            }
            var seen = Set(existing.components.map(\.name))
            for idx in existing.components.indices {
                let compName = existing.components[idx].name
                if let overrideMode = overrides[compName] {
                    existing.components[idx].mode = overrideMode
                }
            }
            for spec in workspacePodspecs where !seen.contains(spec.name) && spec.name != effectiveSelf {
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
        for dep in podfileDeps where dep.name != effectiveSelf {
            map[dep.name] = ComponentConfigEntry(
                name: dep.name,
                version: dep.declaredVersion,
                mode: dep.effectiveMode,
                path: dep.localPath,
                enabled: true
            )
        }
        for spec in workspacePodspecs where spec.name != effectiveSelf {
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
        let detectedSelf: String? = {
            let parent = appDirectoryURL.deletingLastPathComponent()
            if let files = try? FileManager.default.contentsOfDirectory(atPath: parent.path) {
                if let specFile = files.first(where: { $0.hasSuffix(".podspec") && !$0.hasSuffix(".podspec.json") }) {
                    return (specFile as NSString).deletingPathExtension
                }
            }
            return nil
        }()
        if let detectedSelf {
            copy.components.removeAll { $0.name == detectedSelf }
        }
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        copy.components.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        copy.syncComponentsToActiveColumn()

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

    public static func exportTable(_ table: ComponentConfigTable, to destinationURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(table)
        try data.write(to: destinationURL, options: .atomic)
    }

    public static func importTable(from sourceURL: URL) throws -> ComponentConfigTable {
        let data = try Data(contentsOf: sourceURL)
        return try JSONDecoder().decode(ComponentConfigTable.self, from: data)
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
    public let git: String?
    public let branch: String?
    public let tag: String?
    public let targets: [String]?
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
        git: String? = nil,
        branch: String? = nil,
        tag: String? = nil,
        targets: [String]? = nil,
        effectiveMode: String,
        overrideMode: String?
    ) {
        self.name = name
        self.declaredVersion = declaredVersion
        self.localPath = localPath
        self.git = git
        self.branch = branch
        self.tag = tag
        self.targets = targets
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
                        git: entry.git,
                        branch: entry.branch,
                        tag: entry.tag,
                        targets: entry.targets,
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
            if parts.count == 2, ["local", "source", "binary", "branch"].contains(parts[1]) {
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
