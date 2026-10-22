import Foundation
import Testing
@testable import IMYBinCore

@Test func workspaceRegistryPersistsAndOrdersRecents() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("RegistryTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let fileURL = tmpDir.appendingPathComponent("recents.json")
    let registry = WorkspaceRegistry(storageURL: fileURL)

    let urlA = URL(fileURLWithPath: "/Projects/AppA")
    let urlB = URL(fileURLWithPath: "/Projects/AppB")

    registry.addOrUpdate(url: urlA, kind: .hostApp, name: "AppA")
    registry.addOrUpdate(url: urlB, kind: .workspace, name: "AppB")

    let recents1 = registry.allRecents()
    #expect(recents1.count == 2)
    #expect(recents1.first?.name == "AppB")

    // Favorite AppA
    registry.toggleFavorite(url: urlA)
    let recents2 = registry.allRecents()
    #expect(recents2.first?.name == "AppA")
    #expect(registry.favorites().count == 1)

    // Re-load registry from disk
    let registry2 = WorkspaceRegistry(storageURL: fileURL)
    #expect(registry2.allRecents().count == 2)
    #expect(registry2.favorites().first?.name == "AppA")

    registry2.remove(url: urlA)
    #expect(registry2.allRecents().count == 1)
}

@Test func betaVersionBumpAndPromote() {
    #expect(PodspecInspector.bumpBetaVersion("0.1.2") == "0.1.2-beta.1")
    #expect(PodspecInspector.bumpBetaVersion("0.1.2-beta.1") == "0.1.2-beta.2")
    #expect(PodspecInspector.bumpBetaVersion("0.1.2-beta.9") == "0.1.2-beta.10")
    #expect(PodspecInspector.bumpBetaVersion("1.0.0-beta") == "1.0.0-beta.1")

    #expect(PodspecInspector.promoteBetaToRelease("0.1.2-beta.2") == "0.1.2")
    #expect(PodspecInspector.promoteBetaToRelease("1.0.0-rc.1") == "1.0.0")
    #expect(PodspecInspector.promoteBetaToRelease("2.3.4") == "2.3.4")
}

@Test func cacheManagerReportsCleanedPaths() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CacheTest-\(UUID().uuidString)")
    let podsComp = tmpDir.appendingPathComponent("Pods/MyPod")
    try FileManager.default.createDirectory(at: podsComp, withIntermediateDirectories: true)
    try "dummy".write(to: podsComp.appendingPathComponent("dummy.txt"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let report = CacheManager.cleanComponentCache(componentName: "MyPod", projectDirectoryURL: tmpDir)
    #expect(report.removedPaths.contains(podsComp.path))
    #expect(!FileManager.default.fileExists(atPath: podsComp.path))
}

@Test func taskHistoryFilterAndExport() throws {
    var history = TaskHistory()
    let id = try history.enqueue(kind: .install, title: "Test Install")
    try history.start(id)
    try history.appendEvent(TaskEvent(kind: .output, message: "normal output line\n"), to: id)
    try history.appendEvent(TaskEvent(kind: .phase, message: "Phase 1: Resolving"), to: id)
    try history.appendEvent(TaskEvent(kind: .error, message: "error: compilation failed\n"), to: id)
    try history.finish(id, exitCode: 1)

    let record = history.record(id: id)!
    let allLog = record.filteredLog(mode: .all)
    #expect(allLog.contains("normal output line"))
    #expect(allLog.contains("Phase 1: Resolving"))
    #expect(allLog.contains("error: compilation failed"))

    let errorLog = record.filteredLog(mode: .errorOnly)
    #expect(!errorLog.contains("normal output line"))
    #expect(errorLog.contains("error: compilation failed"))

    let phaseLog = record.filteredLog(mode: .phaseAndWarning)
    #expect(phaseLog.contains("Phase 1: Resolving"))
    #expect(!phaseLog.contains("normal output line"))

    let queryLog = record.filteredLog(mode: .all, query: "compilation")
    #expect(queryLog.contains("error: compilation failed"))
    #expect(!queryLog.contains("normal output line"))
}

@Test func dependencyGraphAnalyzerDetectsImpact() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("DAGTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let compADir = tmpDir.appendingPathComponent("ComponentA")
    let compBDir = tmpDir.appendingPathComponent("ComponentB")
    let appDir = tmpDir.appendingPathComponent("HostApp")
    try FileManager.default.createDirectory(at: compADir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: compBDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

    let specA = """
    Pod::Spec.new do |s|
      s.name = 'ComponentA'
      s.version = '1.0.0'
      s.ios.deployment_target = '15.0'
    end
    """
    try specA.write(to: compADir.appendingPathComponent("ComponentA.podspec"), atomically: true, encoding: .utf8)

    // ComponentB depends on ComponentA
    let specB = """
    Pod::Spec.new do |s|
      s.name = 'ComponentB'
      s.version = '0.5.0'
      s.ios.deployment_target = '15.0'
      s.dependency 'ComponentA', '1.0.0'
    end
    """
    try specB.write(to: compBDir.appendingPathComponent("ComponentB.podspec"), atomically: true, encoding: .utf8)

    // HostApp config table depends on ComponentA
    let configTable = ComponentConfigTable(
        project: "HostApp",
        components: [
            ComponentConfigEntry(name: "ComponentA", version: "1.0.0", mode: "binary", enabled: true),
            ComponentConfigEntry(name: "ComponentB", version: "0.5.0", mode: "source", enabled: true)
        ]
    )
    try configTable.write(to: appDir)

    let snapshot = ProjectSnapshot(
        rootURL: tmpDir,
        podspecURLs: [compADir.appendingPathComponent("ComponentA.podspec"), compBDir.appendingPathComponent("ComponentB.podspec")],
        hasPodfile: true,
        hasLockfile: false,
        hasArchiveConfiguration: false,
        appDirectories: [appDir]
    )
    let infoA = try PodspecInspector.inspect(compADir.appendingPathComponent("ComponentA.podspec"), includeGitStatus: false)
    let infoB = try PodspecInspector.inspect(compBDir.appendingPathComponent("ComponentB.podspec"), includeGitStatus: false)

    let report = DependencyGraphAnalyzer.analyzeReverseImpact(for: "ComponentA", in: snapshot, podspecs: [infoA, infoB])
    #expect(report.dependentComponents.map(\.name) == ["ComponentB"])
    #expect(report.dependentApps.map(\.name) == ["HostApp"])

    // Cascade version update
    let updated = try DependencyGraphAnalyzer.cascadeSyncVersion(
        targetComponent: "ComponentA",
        newVersion: "1.0.1",
        in: snapshot,
        podspecs: [infoA, infoB]
    )
    #expect(updated.contains("ComponentB"))
    #expect(updated.contains("HostApp"))

    let updatedB = try PodspecInspector.inspect(compBDir.appendingPathComponent("ComponentB.podspec"), includeGitStatus: false)
    #expect(updatedB.dependencies.first?.versionRequirement == "1.0.1")

    let updatedTable = try ComponentConfigTable.read(from: appDir)
    #expect(updatedTable?.components.first(where: { $0.name == "ComponentA" })?.version == "1.0.1")
}

@Test func moduleScaffoldGeneratorCreatesValidModule() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let options = ModuleScaffoldOptions(name: "DemoModule", isStaticFramework: true, deploymentTarget: "15.0")
    let createdURL = try ModuleScaffoldGenerator.generate(options: options, at: tmpDir)

    #expect(FileManager.default.fileExists(atPath: createdURL.appendingPathComponent("DemoModule.podspec").path))
    #expect(FileManager.default.fileExists(atPath: createdURL.appendingPathComponent("Classes/DemoModule.swift").path))
    #expect(FileManager.default.fileExists(atPath: createdURL.appendingPathComponent("Example/Podfile").path))

    let specInfo = try PodspecInspector.inspect(createdURL.appendingPathComponent("DemoModule.podspec"), includeGitStatus: false)
    #expect(specInfo.name == "DemoModule")
    #expect(specInfo.version == "0.1.0")
    #expect(specInfo.staticFramework == true)
}

@Test func configTableExportAndImport() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportImportTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let original = ComponentConfigTable(
        project: "MyProject",
        components: [
            ComponentConfigEntry(name: "PodA", version: "1.0.0", mode: "branch", git: "https://git.com/a.git", branch: "feat/x", enabled: true),
            ComponentConfigEntry(name: "PodB", version: "2.0.0", mode: "binary", enabled: false)
        ]
    )
    let exportURL = tmpDir.appendingPathComponent("snapshot.imy-config.json")
    try ComponentConfigTable.exportTable(original, to: exportURL)

    let imported = try ComponentConfigTable.importTable(from: exportURL)
    #expect(imported.project == "MyProject")
    #expect(imported.components.count == 2)
    #expect(imported.components[0].name == "PodA")
    #expect(imported.components[0].mode == "branch")
    #expect(imported.components[0].branch == "feat/x")
}

@Test func configTableSupportsDistinctLocalDirectoriesPerComponent() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("MultiDirTest-\(UUID().uuidString)")
    let appDir = tmpDir.appendingPathComponent("HostApp")
    let compADir = tmpDir.appendingPathComponent("WorkspacePods/PodA")
    let compBDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExternalRepos/PodB-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: compADir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: compBDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tmpDir)
        try? FileManager.default.removeItem(at: compBDir)
    }

    let relPathA = ComponentConfigTable.relativePath(from: appDir, to: compADir)
    let absPathB = compBDir.path

    let table = ComponentConfigTable(
        project: "HostApp",
        components: [
            ComponentConfigEntry(name: "PodA", version: "1.0.0", mode: "local", path: relPathA, enabled: true),
            ComponentConfigEntry(name: "PodB", version: "2.0.0", mode: "local", path: absPathB, enabled: true)
        ]
    )
    try table.write(to: appDir)

    let loaded = try ComponentConfigTable.read(from: appDir)
    let reloadedTable = try #require(loaded)
    #expect(reloadedTable.components.count == 2)
    let entryA = try #require(reloadedTable.components.first(where: { $0.name == "PodA" }))
    let entryB = try #require(reloadedTable.components.first(where: { $0.name == "PodB" }))
    #expect(entryA.mode == "local")
    #expect(entryA.path == relPathA)
    #expect(entryA.supportsLocal == true)
    #expect(entryB.mode == "local")
    #expect(entryB.path == absPathB)
    #expect(entryB.supportsLocal == true)
}

@Test func configTableMultiColumnAppVersionsSupport() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("MultiColumnTest-\(UUID().uuidString)")
    let appDir = tmpDir.appendingPathComponent("HostApp")
    try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    var table = ComponentConfigTable(
        project: "HostApp",
        components: [
            ComponentConfigEntry(name: "HDDynamicPod", version: "0.1.0", mode: "binary", enabled: true),
            ComponentConfigEntry(name: "HDStaticPod", version: "0.1.9", mode: "binary", enabled: true)
        ]
    )
    #expect(table.currentColumnName == "1.0.0")
    #expect(table.columns?.count == 1)

    // 新建 1.1.0 列并复制当前依赖
    let created = table.createColumn(name: "1.1.0", description: "App 1.1.0 迭代", copyFromCurrent: true)
    #expect(created)
    #expect(table.columns?.count == 2)

    // 切换至 1.1.0 列
    let switched = table.switchActiveColumn(to: "1.1.0")
    #expect(switched)
    #expect(table.currentColumnName == "1.1.0")

    // 修改 1.1.0 列中的版本
    table.components[0].version = "0.1.5"
    table.components[0].mode = "source"
    try table.write(to: appDir)

    // 从磁盘重新读取并验证
    let reloaded = try ComponentConfigTable.read(from: appDir)
    let nonNilTable = try #require(reloaded)
    #expect(nonNilTable.activeColumn == "1.1.0")
    #expect(nonNilTable.components[0].version == "0.1.5")
    #expect(nonNilTable.components[0].mode == "source")
    #expect(nonNilTable.columns?.count == 2)

    // 切换回 1.0.0 列验证旧版本未被污染
    var switchedBack = nonNilTable
    switchedBack.switchActiveColumn(to: "1.0.0")
    #expect(switchedBack.currentColumnName == "1.0.0")
    #expect(switchedBack.components[0].version == "0.1.0")
    #expect(switchedBack.components[0].mode == "binary")

    // 重命名列
    let renamed = switchedBack.renameColumn(from: "1.1.0", to: "1.1.0-release")
    #expect(renamed)
    #expect(switchedBack.columns?.contains(where: { $0.name == "1.1.0-release" }) == true)

    // 删除列
    let deleted = switchedBack.deleteColumn(name: "1.1.0-release")
    #expect(deleted)
    #expect(switchedBack.columns?.count == 1)
}

@Test func podspecDependencyUpsertAndRemove() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("PodspecDepTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let specFile = tmpDir.appendingPathComponent("DemoModule.podspec")
    let initialSpec = """
    Pod::Spec.new do |s|
      s.name = 'DemoModule'
      s.version = '0.1.0'
      s.summary = 'Demo'
      s.homepage = 'https://example.com'
      s.license = 'MIT'
      s.author = { 'dev' => 'dev@example.com' }
      s.source = { :git => 'https://example.com/demo.git', :tag => s.version.to_s }
      s.ios.deployment_target = '15.0'
      s.source_files = 'Classes/**/*'
    end
    """
    try initialSpec.write(to: specFile, atomically: true, encoding: .utf8)

    // Add dependency
    try PodspecInspector.upsertDependency(in: specFile, name: "HDStaticPod", versionRequirement: "~> 0.1.11")
    let info1 = try PodspecInspector.inspect(specFile, includeGitStatus: false)
    #expect(info1.dependencies.count == 1)
    #expect(info1.dependencies.first?.name == "HDStaticPod")
    #expect(info1.dependencies.first?.versionRequirement == "~> 0.1.11")

    // Update dependency version
    try PodspecInspector.upsertDependency(in: specFile, name: "HDStaticPod", versionRequirement: "~> 0.2.0")
    let info2 = try PodspecInspector.inspect(specFile, includeGitStatus: false)
    #expect(info2.dependencies.count == 1)
    #expect(info2.dependencies.first?.versionRequirement == "~> 0.2.0")

    // Remove dependency
    try PodspecInspector.removeDependency(in: specFile, name: "HDStaticPod")
    let info3 = try PodspecInspector.inspect(specFile, includeGitStatus: false)
    #expect(info3.dependencies.isEmpty)
}

@Test func workbenchWindowIdentifierMatching() {
    #expect(WorkbenchWindowIdentifier.isAppManagerWindow(title: "IMY Bin — App 依赖管理工作台", identifier: "app-manager"))
    #expect(WorkbenchWindowIdentifier.isAppManagerWindow(title: "IMY Bin — App 依赖管理工作台", identifier: nil))
    #expect(WorkbenchWindowIdentifier.isAppManagerWindow(title: "App 依赖管理工作台", identifier: "app-manager-AppKitWindow"))
    #expect(WorkbenchWindowIdentifier.isAppManagerWindow(title: "", identifier: "app-manager"))
    #expect(!WorkbenchWindowIdentifier.isAppManagerWindow(title: "IMY Bin — 组件管理与发布工作台", identifier: "component-manager"))
    #expect(!WorkbenchWindowIdentifier.isAppManagerWindow(title: "IMY Bin — 组件工作台", identifier: "component-window"))

    #expect(WorkbenchWindowIdentifier.isComponentManagerWindow(title: "IMY Bin — 组件管理与发布工作台", identifier: "component-manager"))
    #expect(WorkbenchWindowIdentifier.isComponentManagerWindow(title: "组件管理与发布工作台", identifier: nil))
    #expect(!WorkbenchWindowIdentifier.isComponentManagerWindow(title: "IMY Bin — App 依赖管理工作台", identifier: "app-manager"))
    #expect(!WorkbenchWindowIdentifier.isComponentManagerWindow(title: "IMY Bin — 组件工作台", identifier: "component-window"))
}

@Test func sourceDebuggingCommandSpecsAndPolicyTransitions() {
    let spec = BinCommandBuilder.attachSource(component: "HDStaticPod", sourceURL: URL(fileURLWithPath: "/Projects/HDStaticPod"))
    #expect(spec.arguments.contains("code"))
    #expect(spec.arguments.contains("HDStaticPod"))
    #expect(spec.arguments.contains("--source=/Projects/HDStaticPod"))

    let cleanSpec = BinCommandBuilder.cleanAttachedSources(component: "HDStaticPod")
    #expect(cleanSpec.arguments.contains("--clean"))
    #expect(cleanSpec.arguments.contains("HDStaticPod"))

    let allCleanSpec = BinCommandBuilder.cleanAttachedSources(component: nil)
    #expect(allCleanSpec.arguments.contains("--all-clean"))

    var entry = ComponentConfigEntry(name: "HDStaticPod", version: "0.1.11", mode: "binary", path: "../HDStaticPod")
    #expect(entry.supportsLocal)
    #expect(entry.mode == "binary")

    // Switching to local for debugging
    entry.mode = entry.supportsLocal ? "local" : "source"
    #expect(entry.mode == "local")

    // Switching to source
    entry.mode = "source"
    #expect(entry.mode == "source")

    // Reverting to binary
    entry.mode = "binary"
    #expect(entry.mode == "binary")
}
