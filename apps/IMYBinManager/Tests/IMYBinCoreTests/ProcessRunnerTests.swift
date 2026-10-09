import Foundation
import Testing
@testable import IMYBinCore

@Test func processRunnerStreamsOutputAndExitCode() async throws {
    let runner = ProcessRunner()
    let command = CommandSpec(
        executableName: "echo",
        arguments: ["hello from runner"],
        title: "测试",
        mutatesProject: false
    )

    let events = try runner.events(
        for: command,
        workingDirectory: FileManager.default.temporaryDirectory,
        environment: ["PATH": "/usr/bin:/bin"]
    )

    var output = ""
    var exitCode: Int32?
    for try await event in events {
        switch event {
        case .output(let value): output.append(value)
        case .finished(let value): exitCode = value
        }
    }

    #expect(output.contains("hello from runner"))
    #expect(exitCode == 0)
    #expect(!runner.isRunning)
}
