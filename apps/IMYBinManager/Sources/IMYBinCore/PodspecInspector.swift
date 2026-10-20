import Foundation

public enum VersionBumpKind: String, CaseIterable, Identifiable, Sendable {
    case patch
    case minor
    case major

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .patch: "修订号 +1 (Patch)"
        case .minor: "次版本 +1 (Minor)"
        case .major: "主版本 +1 (Major)"
        }
    }
}

public struct PodspecDependency: Equatable, Sendable, Identifiable {
    public var name: String
    public var versionRequirement: String?

    public var id: String { name }

    public init(name: String, versionRequirement: String? = nil) {
        self.name = name
        self.versionRequirement = versionRequirement
    }
}

public struct ComponentPodspecInfo: Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let summary: String?
    public let homepage: String?
    public let deploymentTarget: String?
    public let sourceGit: String?
    public let staticFramework: Bool
    public let dependencies: [PodspecDependency]
    public let podspecURL: URL
    public let repositoryURL: URL
    public let exampleDirectoryURL: URL?
    public let gitBranch: String?
    public let isGitClean: Bool
    public let dirtyFilesSummary: [String]
    public let gitTags: [String]

    public var id: String { podspecURL.standardizedFileURL.path }

    public var hasCurrentVersionTag: Bool {
        gitTags.contains(version) || gitTags.contains("v\(version)")
    }

    public var hasExampleProject: Bool {
        exampleDirectoryURL != nil
    }

    public init(
        name: String,
        version: String,
        summary: String?,
        homepage: String?,
        deploymentTarget: String?,
        sourceGit: String?,
        staticFramework: Bool,
        dependencies: [PodspecDependency] = [],
        podspecURL: URL,
        repositoryURL: URL,
        exampleDirectoryURL: URL? = nil,
        gitBranch: String?,
        isGitClean: Bool,
        dirtyFilesSummary: [String],
        gitTags: [String]
    ) {
        self.name = name
        self.version = version
        self.summary = summary
        self.homepage = homepage
        self.deploymentTarget = deploymentTarget
        self.sourceGit = sourceGit
        self.staticFramework = staticFramework
        self.dependencies = dependencies
        self.podspecURL = podspecURL
        self.repositoryURL = repositoryURL
        self.exampleDirectoryURL = exampleDirectoryURL
        self.gitBranch = gitBranch
        self.isGitClean = isGitClean
        self.dirtyFilesSummary = dirtyFilesSummary
        self.gitTags = gitTags
    }
}

public enum PodspecInspectorError: LocalizedError, Equatable {
    case invalidVersion(String)
    case versionFieldNotFound(String)
    case invalidDependencyName(String)
    case podspecEndNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let v):
            "版本号格式不合法：\(v)（期望如 0.1.2）"
        case .versionFieldNotFound(let path):
            "在 podspec 中未找到 version 声明：\(path)"
        case .invalidDependencyName(let name):
            "依赖组件名称不合法：\(name)"
        case .podspecEndNotFound(let path):
            "无法定位 podspec 结尾 end：\(path)"
        }
    }
}

public enum PodspecInspector {
    public static func inspect(_ podspecURL: URL, includeGitStatus: Bool = true) throws -> ComponentPodspecInfo {
        let text = try String(contentsOf: podspecURL, encoding: .utf8)
        let fallbackName = podspecURL.deletingPathExtension().lastPathComponent
        let name = firstMatch(in: text, pattern: #"\.name\s*=\s*['"]([^'"]+)['"]"#) ?? fallbackName
        let version = firstMatch(in: text, pattern: #"\.version\s*=\s*['"]([^'"]+)['"]"#) ?? "0.1.0"
        let summary = firstMatch(in: text, pattern: #"\.summary\s*=\s*['"]([^'"]+)['"]"#)
        let homepage = firstMatch(in: text, pattern: #"\.homepage\s*=\s*['"]([^'"]+)['"]"#)
        let deploymentTarget = firstMatch(in: text, pattern: #"\.ios\.deployment_target\s*=\s*['"]([^'"]+)['"]"#)
        let sourceGit = firstMatch(in: text, pattern: #"(:git|git:)\s*(=>)?\s*['"]([^'"]+)['"]"#, group: 3)
        let staticFrameworkText = firstMatch(in: text, pattern: #"\.static_framework\s*=\s*(true|false)"#)
        let staticFramework = staticFrameworkText == "true"
        let dependencies = parseDependencies(in: text)

        let repositoryURL = podspecURL.standardizedFileURL.deletingLastPathComponent()
        let exampleCandidate = repositoryURL.appendingPathComponent("Example")
        let examplePodfile = exampleCandidate.appendingPathComponent("Podfile")
        let exampleDirectoryURL = FileManager.default.fileExists(atPath: examplePodfile.path) ? exampleCandidate : nil

        var gitBranch: String?
        var isGitClean = true
        var dirtyFiles: [String] = []
        var gitTags: [String] = []

        if includeGitStatus {
            let gitDir = repositoryURL.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                gitBranch = runGit(in: repositoryURL, args: ["rev-parse", "--abbrev-ref", "HEAD"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let statusOut = runGit(in: repositoryURL, args: ["status", "--porcelain"]) {
                    dirtyFiles = statusOut
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    isGitClean = dirtyFiles.isEmpty
                }
                if let tagOut = runGit(in: repositoryURL, args: ["tag", "--list"]) {
                    gitTags = tagOut
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
                }
            }
        }

        return ComponentPodspecInfo(
            name: name,
            version: version,
            summary: summary,
            homepage: homepage,
            deploymentTarget: deploymentTarget,
            sourceGit: sourceGit,
            staticFramework: staticFramework,
            dependencies: dependencies,
            podspecURL: podspecURL.standardizedFileURL,
            repositoryURL: repositoryURL,
            exampleDirectoryURL: exampleDirectoryURL,
            gitBranch: gitBranch,
            isGitClean: isGitClean,
            dirtyFilesSummary: dirtyFiles,
            gitTags: gitTags
        )
    }

    public static func parseDependencies(in text: String) -> [PodspecDependency] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\.dependency\s+['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?"#
        ) else {
            return []
        }
        var results: [PodspecDependency] = []
        var indexByName: [String: Int] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            let nsRange = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            guard let match = regex.firstMatch(in: rawLine, range: nsRange),
                  match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: rawLine)
            else { continue }
            let depName = String(rawLine[nameRange])
            var versionReq: String?
            if match.numberOfRanges > 2,
               match.range(at: 2).location != NSNotFound,
               let reqRange = Range(match.range(at: 2), in: rawLine) {
                versionReq = String(rawLine[reqRange])
            }
            let dep = PodspecDependency(name: depName, versionRequirement: versionReq)
            if let existingIdx = indexByName[depName] {
                results[existingIdx] = dep
            } else {
                indexByName[depName] = results.count
                results.append(dep)
            }
        }
        return results
    }

    public static func upsertDependency(
        in podspecURL: URL,
        name: String,
        versionRequirement: String?
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              trimmedName.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+/-]*$"#, options: .regularExpression) != nil
        else {
            throw PodspecInspectorError.invalidDependencyName(name)
        }
        let trimmedReq = versionRequirement?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReq = trimmedReq != nil && !trimmedReq!.isEmpty

        let text = try String(contentsOf: podspecURL, encoding: .utf8)
        let specVar = detectSpecVariable(in: text) ?? "s"
        let newLine: String
        if let req = trimmedReq, hasReq {
            newLine = "  \(specVar).dependency '\(trimmedName)', '\(req)'"
        } else {
            newLine = "  \(specVar).dependency '\(trimmedName)'"
        }

        let escapedName = NSRegularExpression.escapedPattern(for: trimmedName)
        let linePattern = #"^[ \t]*[A-Za-z_][A-Za-z0-9_]*\.dependency\s+['"]\#(escapedName)['"].*$"#
        var lines = text.components(separatedBy: "\n")
        var replaced = false
        for idx in lines.indices {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            if lines[idx].range(of: linePattern, options: .regularExpression) != nil {
                lines[idx] = newLine
                replaced = true
                break
            }
        }

        if !replaced {
            guard let endIdx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "end" }) else {
                throw PodspecInspectorError.podspecEndNotFound(podspecURL.path)
            }
            lines.insert(newLine, at: endIdx)
        }

        let updated = lines.joined(separator: "\n")
        try updated.write(to: podspecURL, atomically: true, encoding: .utf8)
    }

    public static func removeDependency(
        in podspecURL: URL,
        name: String
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedName = NSRegularExpression.escapedPattern(for: trimmedName)
        let linePattern = #"^[ \t]*[A-Za-z_][A-Za-z0-9_]*\.dependency\s+['"]\#(escapedName)['"].*$"#

        let text = try String(contentsOf: podspecURL, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { return true }
            return line.range(of: linePattern, options: .regularExpression) == nil
        }
        let updated = filtered.joined(separator: "\n")
        try updated.write(to: podspecURL, atomically: true, encoding: .utf8)
    }

    public static func ensureExamplePodfileUsesConfigTable(
        in exampleDirectoryURL: URL,
        selfPodName: String,
        deploymentTarget: String = "15.0"
    ) throws {
        let podfileURL = exampleDirectoryURL.appendingPathComponent("Podfile")
        guard FileManager.default.fileExists(atPath: podfileURL.path) else { return }
        let existing = try String(contentsOf: podfileURL, encoding: .utf8)
        if existing.contains("imy_bin_config_dependencies") {
            return
        }
        let template = """
        use_frameworks!

        platform :ios, '\(deploymentTarget)'

        plugin 'cocoapods-imy-bin'
        set_configuration_env 'dev'
        use_binaries!

        target '\(selfPodName)_Example' do
          pod '\(selfPodName)', :path => '../'
          imy_bin_config_dependencies

          target '\(selfPodName)_Tests' do
            inherit! :search_paths
          end
        end
        """
        try (template + "\n").write(to: podfileURL, atomically: true, encoding: .utf8)
    }

    public static func isValidVersion(_ version: String) -> Bool {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$"#, options: .regularExpression) != nil
    }

    public static func bumpVersion(_ version: String, kind: VersionBumpKind) -> String? {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        var major = parts[0]
        var minor = parts[1]
        var patch = parts[2]
        switch kind {
        case .patch:
            patch += 1
        case .minor:
            minor += 1
            patch = 0
        case .major:
            major += 1
            minor = 0
            patch = 0
        }
        return "\(major).\(minor).\(patch)"
    }

    public static func updateVersion(in podspecURL: URL, to newVersion: String) throws {
        let trimmed = newVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidVersion(trimmed) else {
            throw PodspecInspectorError.invalidVersion(newVersion)
        }
        let text = try String(contentsOf: podspecURL, encoding: .utf8)
        let pattern = #"(\.version\s*=\s*['"])([^'"]+)(['"])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw PodspecInspectorError.versionFieldNotFound(podspecURL.path)
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard regex.firstMatch(in: text, range: nsRange) != nil else {
            throw PodspecInspectorError.versionFieldNotFound(podspecURL.path)
        }
        let updated = regex.stringByReplacingMatches(
            in: text,
            range: nsRange,
            withTemplate: "$1\(trimmed)$3"
        )
        try updated.write(to: podspecURL, atomically: true, encoding: .utf8)
    }

    private static func detectSpecVariable(in text: String) -> String? {
        firstMatch(in: text, pattern: #"Pod::Spec\.new\s+do\s*\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|"#)
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            let nsRange = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            if let match = regex.firstMatch(in: rawLine, range: nsRange),
               match.numberOfRanges > group,
               let range = Range(match.range(at: group), in: rawLine) {
                return String(rawLine[range])
            }
        }
        return nil
    }

    private static func runGit(in directoryURL: URL, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directoryURL.path] + args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
