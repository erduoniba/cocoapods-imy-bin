import Foundation

public struct ToolchainInspector: Sendable {
    private let environmentLoader: LoginShellEnvironmentLoader

    public init(environmentLoader: LoginShellEnvironmentLoader = .init()) {
        self.environmentLoader = environmentLoader
    }

    public func inspect() -> ToolchainReport {
        do {
            let loaded = try environmentLoader.load()
            let tools: [(String, [String])] = [
                ("ruby", ["--version"]),
                ("bundle", ["--version"]),
                ("pod", ["--version"]),
                ("xcodebuild", ["-version"]),
            ]
            let probes = tools.map { probe(name: $0.0, arguments: $0.1, environment: loaded.environment) }
            return ToolchainReport(shellPath: loaded.shellPath, probes: probes)
        } catch {
            return ToolchainReport(
                shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                probes: [ToolProbe(name: "登录 Shell", executablePath: nil, version: nil, error: error.localizedDescription)]
            )
        }
    }

    private func probe(name: String, arguments: [String], environment: [String: String]) -> ToolProbe {
        guard let executable = LoginShellEnvironmentLoader.resolveExecutable(named: name, environment: environment) else {
            return ToolProbe(name: name, executablePath: nil, version: nil, error: "未在 PATH 中找到")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let error = process.terminationStatus == 0 ? nil : "退出码 \(process.terminationStatus)"
            return ToolProbe(name: name, executablePath: executable.path, version: output, error: error)
        } catch {
            return ToolProbe(name: name, executablePath: executable.path, version: nil, error: error.localizedDescription)
        }
    }
}
