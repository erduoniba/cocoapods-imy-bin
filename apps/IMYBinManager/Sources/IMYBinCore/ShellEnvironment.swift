import Foundation

public struct LoginShellEnvironmentLoader: Sendable {
    public init() {}

    public func load() throws -> (shellPath: String, environment: [String: String]) {
        let base = ProcessInfo.processInfo.environment
        let shellPath = base["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
            ?? "/bin/zsh"

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", "/usr/bin/env -0"]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "登录 shell 启动失败"
            throw EnvironmentError.shellFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var environment = base
        for pair in Self.parseNullSeparatedEnvironment(data) {
            environment[pair.key] = pair.value
        }
        environment["PATH"] = Self.normalizedPath(environment["PATH"])
        return (shellPath, environment)
    }

    public static func parseNullSeparatedEnvironment(_ data: Data) -> [String: String] {
        guard let value = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for entry in value.components(separatedBy: "\0") {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            let content = String(entry[entry.index(after: separator)...])
            guard !key.isEmpty else { continue }
            result[key] = content
        }
        return result
    }

    public static func resolveExecutable(named name: String, environment: [String: String]) -> URL? {
        guard !name.contains("/") else {
            return FileManager.default.isExecutableFile(atPath: name) ? URL(fileURLWithPath: name) : nil
        }
        for directory in normalizedPath(environment["PATH"]).split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func normalizedPath(_ value: String?) -> String {
        let systemPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var paths = (value ?? "").split(separator: ":").map(String.init)
        for path in systemPaths where !paths.contains(path) {
            paths.append(path)
        }
        return paths.joined(separator: ":")
    }

    public enum EnvironmentError: LocalizedError {
        case shellFailed(String)

        public var errorDescription: String? {
            switch self {
            case .shellFailed(let message): "读取登录 shell 环境失败：\(message)"
            }
        }
    }
}
