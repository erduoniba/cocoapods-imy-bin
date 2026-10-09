import Foundation
import Testing
@testable import IMYBinCore

@Test func parsesNullSeparatedEnvironmentAndPreservesEquals() {
    let data = Data("PATH=/usr/bin:/bin\0TOKEN=a=b=c\0EMPTY=\0".utf8)
    let result = LoginShellEnvironmentLoader.parseNullSeparatedEnvironment(data)

    #expect(result["PATH"] == "/usr/bin:/bin")
    #expect(result["TOKEN"] == "a=b=c")
    #expect(result["EMPTY"] == "")
}

@Test func resolvesExecutableFromPath() {
    let result = LoginShellEnvironmentLoader.resolveExecutable(
        named: "sh",
        environment: ["PATH": "/bin"]
    )
    #expect(result?.path == "/bin/sh")
}
