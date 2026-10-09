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
