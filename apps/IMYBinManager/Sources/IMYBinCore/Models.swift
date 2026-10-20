import Foundation

public enum BinEnvironment: String, CaseIterable, Identifiable, Sendable {
    case dev
    case debugDevice = "debug_iphoneos"
    case releaseDevice = "release_iphoneos"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dev: "开发"
        case .debugDevice: "真机 Debug"
        case .releaseDevice: "真机 Release"
        }
    }
}

public enum BuildConfiguration: String, CaseIterable, Identifiable, Sendable {
    case debug = "Debug"
    case release = "Release"

    public var id: String { rawValue }
}

public struct ProjectSnapshot: Equatable, Sendable {
    public let rootURL: URL
    public let podspecURLs: [URL]
    public let appDirectories: [URL]
    public let hasPodfile: Bool
    public let hasLockfile: Bool
    public let hasArchiveConfiguration: Bool

    public var primaryAppDirectory: URL? {
        appDirectories.first ?? (hasPodfile ? rootURL : nil)
    }

    public init(
        rootURL: URL,
        podspecURLs: [URL],
        hasPodfile: Bool,
        hasLockfile: Bool,
        hasArchiveConfiguration: Bool,
        appDirectories: [URL]? = nil
    ) {
        self.rootURL = rootURL
        self.podspecURLs = podspecURLs
        self.hasPodfile = hasPodfile
        self.hasLockfile = hasLockfile
        self.hasArchiveConfiguration = hasArchiveConfiguration
        if let appDirectories {
            self.appDirectories = appDirectories
        } else {
            self.appDirectories = hasPodfile ? [rootURL] : []
        }
    }
}

public struct ToolProbe: Identifiable, Equatable, Sendable {
    public let name: String
    public let executablePath: String?
    public let version: String?
    public let error: String?

    public var id: String { name }
    public var isAvailable: Bool { executablePath != nil && error == nil }

    public init(name: String, executablePath: String?, version: String?, error: String?) {
        self.name = name
        self.executablePath = executablePath
        self.version = version
        self.error = error
    }
}

public struct ToolchainReport: Equatable, Sendable {
    public let shellPath: String
    public let probes: [ToolProbe]

    public init(shellPath: String, probes: [ToolProbe]) {
        self.shellPath = shellPath
        self.probes = probes
    }
}

public struct CommandSpec: Equatable, Sendable {
    public let executableName: String
    public let arguments: [String]
    public let title: String
    public let mutatesProject: Bool
    public let taskKind: TaskKind

    public init(
        executableName: String,
        arguments: [String],
        title: String,
        mutatesProject: Bool,
        taskKind: TaskKind = .custom
    ) {
        self.executableName = executableName
        self.arguments = arguments
        self.title = title
        self.mutatesProject = mutatesProject
        self.taskKind = taskKind
    }

    public var displayCommand: String {
        ([executableName] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/:"))
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum ProcessEvent: Sendable {
    case output(String)
    case finished(Int32)
}
