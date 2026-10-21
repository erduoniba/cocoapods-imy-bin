import Foundation
import Testing
@testable import IMYBinCore

@Test func archiveCommandContainsSelectedOptions() {
    let podspec = URL(fileURLWithPath: "/tmp/Project With Spaces/Demo.podspec")
    let command = BinCommandBuilder.archive(
        podspecURL: podspec,
        environment: .debugDevice,
        configuration: .debug,
        buildMissingDependencies: true,
        keepIntermediates: true
    )

    #expect(command.executableName == "pod")
    #expect(command.arguments == [
        "bin",
        "archive",
        "/tmp/Project With Spaces/Demo.podspec",
        "--env=debug_iphoneos",
        "--configuration=Debug",
        "--all-make",
        "--no-clean",
    ])
    #expect(command.displayCommand.contains("'/tmp/Project With Spaces/Demo.podspec'"))
}

@Test func installAndUpdateAreMarkedAsMutating() {
    #expect(BinCommandBuilder.install().mutatesProject)
    #expect(BinCommandBuilder.update().mutatesProject)
}

@Test func publishAndSwitchCommandsIncludeExpectedFlags() {
    let podspec = URL(fileURLWithPath: "/tmp/HDStaticPod.podspec")
    let publish = BinCommandBuilder.publish(
        podspecURL: podspec,
        environment: .dev,
        configuration: .release,
        codeDependencies: true,
        keepIntermediates: false,
        skipTag: true,
        skipCodeSpec: true,
        dryRun: true,
        autoCommit: true,
        push: true
    )
    #expect(publish.taskKind == .publish)
    #expect(publish.arguments == [
        "bin",
        "publish",
        "/tmp/HDStaticPod.podspec",
        "--env=dev",
        "--configuration=Release",
        "--code-dependencies",
        "--skip-tag",
        "--skip-code-spec",
        "--dry-run",
        "--auto-commit",
        "--push",
    ])
    #expect(BinCommandBuilder.status(json: true).arguments == ["bin", "status", "--json"])
    #expect(BinCommandBuilder.switchAll(mode: "local").arguments == ["bin", "switch", "--all", "local"])
    #expect(BinCommandBuilder.resetModes().arguments == ["bin", "switch", "--reset"])

    let gitCommit = BinCommandBuilder.gitAutoCommitAndPush(componentName: "HDDynamicPod", version: "0.1.4")
    #expect(gitCommit.executableName == "sh")
    #expect(gitCommit.arguments.count == 2)
    #expect(gitCommit.arguments[0] == "-c")
    #expect(gitCommit.arguments[1].contains("git add -A"))
    #expect(gitCommit.arguments[1].contains("chore: release HDDynamicPod 0.1.4"))
    #expect(gitCommit.arguments[1].contains("git push origin HEAD"))

    let gitTag = BinCommandBuilder.gitTagAndPush(version: "0.1.4")
    #expect(gitTag.executableName == "sh")
    #expect(gitTag.arguments[1].contains("git tag -f \"0.1.4\""))
    #expect(gitTag.arguments[1].contains("git push origin \"0.1.4\" --force"))
}
