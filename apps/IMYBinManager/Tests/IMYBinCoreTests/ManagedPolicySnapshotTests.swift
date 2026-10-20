import Foundation
import Testing
@testable import IMYBinCore

@Test func managedPolicySnapshotReadsCachedTargets() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = """
    {"project":"SampleApp","revision":"d31d30d7-bfe3-4bc0-b101-a7855327def1","targets":[{"name":"App","dependencies":[{"name":"Foo","version":"1.0.0","mode":"binary"}]}]}
    """.data(using: .utf8)!
    try data.write(to: directory.appendingPathComponent(".imy-bin-policy.json"))
    let snapshot = try ManagedPolicySnapshot.read(from: directory)
    let policy = try #require(snapshot)
    #expect(policy.project == "SampleApp")
    #expect(policy.targets.first?.dependencies.first?.mode == "binary")
    let sync = BinCommandBuilder.syncPolicy(project: policy.project, revision: policy.revision, server: "https://platform.example")
    #expect(sync.arguments.contains("--revision=\(policy.revision)"))
    #expect(sync.displayCommand.contains("bin sync"))
    let mode = BinCommandBuilder.switchMode(component: "Foo", mode: "source")
    #expect(mode.arguments == ["bin", "switch", "Foo", "source"])
}

@Test func podfileComponentInspectorReadsImyPodAndLocalModeOverrides() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let podfile = """
    plugin 'cocoapods-imy-bin'
    use_binaries!
    target 'HDImyBinApp' do
      imy_pod 'HDDynamicPod', '0.1.1', :path => '../HDDynamicPod'
      imy_pod 'HDStaticPod', '0.1.11', :path => '../HDStaticPod'
    end
    """
    try podfile.write(to: directory.appendingPathComponent("Podfile"), atomically: true, encoding: .utf8)
    let modes = "---\nHDStaticPod: local\n"
    try modes.write(to: directory.appendingPathComponent(".imy-bin-modes.yml"), atomically: true, encoding: .utf8)

    let components = PodfileComponentInspector.inspect(from: directory)
    #expect(components.count == 2)
    #expect(components[0].name == "HDDynamicPod")
    #expect(components[0].declaredVersion == "0.1.1")
    #expect(components[0].effectiveMode == "binary")
    #expect(components[0].supportsLocal)
    #expect(components[1].name == "HDStaticPod")
    #expect(components[1].declaredVersion == "0.1.11")
    #expect(components[1].effectiveMode == "local")
    #expect(components[1].overrideMode == "local")

    let updated = try PodfileComponentInspector.updateDependencyVersion(
        in: directory,
        component: "HDDynamicPod",
        to: "0.1.2"
    )
    #expect(updated)
    let reloaded = PodfileComponentInspector.inspect(from: directory)
    #expect(reloaded[0].declaredVersion == "0.1.2")
}
