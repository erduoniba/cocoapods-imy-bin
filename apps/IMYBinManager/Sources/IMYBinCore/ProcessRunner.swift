import Foundation

public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?

    public init() {}

    public var isRunning: Bool {
        lock.withLock { activeProcess?.isRunning == true }
    }

    public func events(
        for command: CommandSpec,
        workingDirectory: URL,
        environment: [String: String]
    ) throws -> AsyncThrowingStream<ProcessEvent, Error> {
        guard let executable = LoginShellEnvironmentLoader.resolveExecutable(
            named: command.executableName,
            environment: environment
        ) else {
            throw RunnerError.executableNotFound(command.executableName)
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = command.arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardOutput = output
        process.standardError = output

        return AsyncThrowingStream { continuation in
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                continuation.yield(.output(text))
            }

            process.terminationHandler = { [weak self] terminated in
                output.fileHandleForReading.readabilityHandler = nil
                let remaining = output.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    continuation.yield(.output(text))
                }
                self?.clear(process)
                continuation.yield(.finished(terminated.terminationStatus))
                continuation.finish()
            }

            do {
                try setActive(process)
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                clear(process)
                continuation.finish(throwing: error)
            }

            continuation.onTermination = { [weak self] reason in
                if case .cancelled = reason {
                    self?.cancel()
                }
            }
        }
    }

    public func cancel() {
        let process = lock.withLock { activeProcess }
        guard let process, process.isRunning else { return }
        process.interrupt()
    }

    private func setActive(_ process: Process) throws {
        try lock.withLock {
            guard activeProcess?.isRunning != true else { throw RunnerError.alreadyRunning }
            activeProcess = process
        }
    }

    private func clear(_ process: Process) {
        lock.withLock {
            if activeProcess === process {
                activeProcess = nil
            }
        }
    }

    public enum RunnerError: LocalizedError {
        case executableNotFound(String)
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .executableNotFound(let name): "未在登录 shell 的 PATH 中找到 \(name)"
            case .alreadyRunning: "已有任务正在执行"
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
