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

public struct ComponentPodspecInfo: Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let summary: String?
    public let homepage: String?
    public let deploymentTarget: String?
    public let sourceGit: String?
    public let staticFramework: Bool
    public let podspecURL: URL
    public let repositoryURL: URL
    public let gitBranch: String?
    public let isGitClean: Bool
    public let dirtyFilesSummary: [String]
    public let gitTags: [String]

    public var id: String { podspecURL.standardizedFileURL.path }

    public var hasCurrentVersionTag: Bool {
        gitTags.contains(version) || gitTags.contains("v\(version)")
    }

    public init(
        name: String,
        version: String,
        summary: String?,
        homepage: String?,
        deploymentTarget: String?,
        sourceGit: String?,
        staticFramework: Bool,
        podspecURL: URL,
        repositoryURL: URL,
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
        self.podspecURL = podspecURL
        self.repositoryURL = repositoryURL
        self.gitBranch = gitBranch
        self.isGitClean = isGitClean
        self.dirtyFilesSummary = dirtyFilesSummary
        self.gitTags = gitTags
    }
}

public enum PodspecInspectorError: LocalizedError, Equatable {
    case invalidVersion(String)
    case versionFieldNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let v):
            "版本号格式不合法：\(v)（期望如 0.1.2）"
        case .versionFieldNotFound(let path):
            "在 podspec 中未找到 version 声明：\(path)"
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

        let repositoryURL = podspecURL.standardizedFileURL.deletingLastPathComponent()
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
            podspecURL: podspecURL.standardizedFileURL,
            repositoryURL: repositoryURL,
            gitBranch: gitBranch,
            isGitClean: isGitClean,
            dirtyFilesSummary: dirtyFiles,
            gitTags: gitTags
        )
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
