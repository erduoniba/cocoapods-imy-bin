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
