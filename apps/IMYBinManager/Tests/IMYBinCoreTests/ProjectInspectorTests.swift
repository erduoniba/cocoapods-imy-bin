import Foundation
import Testing
@testable import IMYBinCore

@Test func inspectorFindsProjectFilesAndSkipsPods() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IMYBinManagerTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("Podfile"))
    try Data().write(to: root.appendingPathComponent("Podfile.lock"))
    try Data().write(to: root.appendingPathComponent("BinArchive.json"))
    try Data().write(to: root.appendingPathComponent("Demo.podspec"))

    let pods = root.appendingPathComponent("Pods")
    try FileManager.default.createDirectory(at: pods, withIntermediateDirectories: true)
    try Data().write(to: pods.appendingPathComponent("Ignored.podspec"))

    let snapshot = try ProjectInspector().inspect(root)
    #expect(snapshot.hasPodfile)
    #expect(snapshot.hasLockfile)
    #expect(snapshot.hasArchiveConfiguration)
    #expect(snapshot.podspecURLs.map(\.lastPathComponent) == ["Demo.podspec"])
}

@Test func inspectorDiscoversReferencedSiblingPodspecsFromAppPodfile() throws {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("IMYBinWorkspace-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }

    let appDir = workspace.appendingPathComponent("HostApp")
    let compDir = workspace.appendingPathComponent("MyComponent")
    try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: compDir, withIntermediateDirectories: true)

    let podfile = """
    target 'HostApp' do
      imy_pod 'MyComponent', '0.1.0', :path => '../MyComponent'
    end
    """
    try podfile.write(to: appDir.appendingPathComponent("Podfile"), atomically: true, encoding: .utf8)
    let podspec = """
    Pod::Spec.new do |s|
      s.name = 'MyComponent'
      s.version = '0.1.0'
      s.ios.deployment_target = '15.0'
      s.static_framework = true
    end
    """
    let podspecURL = compDir.appendingPathComponent("MyComponent.podspec")
    try podspec.write(to: podspecURL, atomically: true, encoding: .utf8)

    // Opening HostApp directly discovers ../MyComponent/MyComponent.podspec
    let appSnapshot = try ProjectInspector().inspect(appDir)
    #expect(appSnapshot.hasPodfile)
    #expect(appSnapshot.podspecURLs.map(\.lastPathComponent) == ["MyComponent.podspec"])

    // Opening workspace root discovers both HostApp and MyComponent.podspec
    let workspaceSnapshot = try ProjectInspector().inspect(workspace)
    #expect(workspaceSnapshot.hasPodfile)
    #expect(workspaceSnapshot.primaryAppDirectory?.lastPathComponent == "HostApp")
    #expect(workspaceSnapshot.podspecURLs.map(\.lastPathComponent) == ["MyComponent.podspec"])

    // PodspecInspector parses and updates version
    let info = try PodspecInspector.inspect(podspecURL, includeGitStatus: false)
    #expect(info.name == "MyComponent")
    #expect(info.version == "0.1.0")
    #expect(info.deploymentTarget == "15.0")
    #expect(info.staticFramework == true)
    #expect(PodspecInspector.bumpVersion(info.version, kind: .patch) == "0.1.1")

    try PodspecInspector.updateVersion(in: podspecURL, to: "0.1.1")
    let updatedInfo = try PodspecInspector.inspect(podspecURL, includeGitStatus: false)
    #expect(updatedInfo.version == "0.1.1")
}
