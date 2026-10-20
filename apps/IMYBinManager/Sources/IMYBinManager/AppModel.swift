import AppKit
import Foundation
import IMYBinCore

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case overview
        case dependencies
        case server
        case logs
        case settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "App 概览"
            case .dependencies: "App 配置表与安装"
            case .server: "制品服务"
            case .logs: "App 运行日志"
            case .settings: "设置"
            }
        }
        var systemImage: String {
            switch self {
            case .overview: "rectangle.3.group"
            case .dependencies: "tablecells"
            case .server: "shippingbox"
            case .logs: "terminal"
            case .settings: "gearshape"
            }
        }
    }

    enum ComponentPage: String, CaseIterable, Identifiable {
        case dependencies
        case publish
        case logs

        var id: String { rawValue }
        var title: String {
            switch self {
            case .dependencies: "组件依赖管理"
            case .publish: "组件版本与发布"
            case .logs: "组件任务日志"
            }
        }
        var systemImage: String {
            switch self {
            case .dependencies: "square.stack.3d.up"
            case .publish: "paperplane.fill"
            case .logs: "terminal"
            }
        }
    }

    private enum LogDestination {
        case appWindow
        case componentWindow
    }

    @Published var selection: Page? = .overview
    @Published var componentSelection: ComponentPage? = .dependencies
    @Published private(set) var project: ProjectSnapshot?
    @Published var selectedAppDirectory: URL? {
        didSet {
            guard selectedAppDirectory != oldValue else { return }
            reloadAppDirectoryState()
        }
    }
    @Published var selectedPodspec: URL? {
        didSet {
            guard selectedPodspec != oldValue else { return }
            reloadSelectedComponentState()
        }
    }
    @Published private(set) var componentPodspecs: [ComponentPodspecInfo] = []
    @Published var editingComponentVersion = ""
    @Published var syncVersionToAppPodfile = true
    @Published var autoCommitVersionBump = true
    @Published var autoInstallAfterSwitch = false

    // Component's own dependencies (podspec s.dependency + Example/.imy-bin-config.json)
    @Published var newPodspecDepName = ""
    @Published var newPodspecDepVersion = ""
    @Published var componentConfigTable: ComponentConfigTable?
    @Published private(set) var hasSavedComponentConfigTable = false
    @Published var autoInstallComponentExampleAfterSwitch = false

    // Host App's dependency config table (.imy-bin-config.json)
    @Published var configTable: ComponentConfigTable?
    @Published private(set) var hasSavedConfigTable = false
    @Published private(set) var localComponents: [LocalComponentDependency] = []
    @Published private(set) var managedPolicy: ManagedPolicySnapshot?
    @Published var managedPolicyError: String?
    @Published var managedProjectKey = ""
    @Published var managedPolicyRevision = ""

    @Published var environment: BinEnvironment = .dev
    @Published var configuration: BuildConfiguration = .release
    @Published var buildMissingDependencies = false
    @Published var keepIntermediates = true
    @Published var codeDependencies = true
    @Published var skipTag = false
    @Published var skipCodeSpec = false
    @Published var publishDryRun = false

    // REQ-01: Recent Workspaces & Favorites
    @Published private(set) var recentWorkspaces: [RecentWorkspace] = []
    @Published private(set) var favoriteWorkspaces: [RecentWorkspace] = []
    public let workspaceRegistry = WorkspaceRegistry()

    // REQ-02: Search & Filter in Config Tables
    @Published var appSearchText = ""
    @Published var appModeFilter = "all" // all, local, source, binary, branch, unreleased
    @Published var compSearchText = ""
    @Published var compModeFilter = "all"

    // REQ-04: Git Branches & Artifact Inspection
    @Published private(set) var currentGitBranchInfo: GitBranchInfo?
    @Published private(set) var latestArtifactReport: ArtifactReport?

    // REQ-06: Reverse Impact Analysis
    @Published private(set) var reverseImpactReport: ReverseImpactReport?

    // REQ-03: Cache Sizes
    @Published private(set) var derivedDataSize: Int64 = 0
    @Published private(set) var tmpReleaseSize: Int64 = 0

    // REQ-07: Log Filtering
    @Published var logFilterMode: LogFilterMode = .all
    @Published var logSearchQuery = ""

    // Toolchain & Custom Path Overrides
    @Published var customCPHomeDir: String {
        didSet {
            UserDefaults.standard.set(customCPHomeDir, forKey: Self.customCPHomeDirKey)
        }
    }
    @Published var customPluginLibDir: String {
        didSet {
            UserDefaults.standard.set(customPluginLibDir, forKey: Self.customPluginLibDirKey)
        }
    }

    @Published private(set) var toolchain: ToolchainReport?
    @Published private(set) var isInspectingToolchain = false
    @Published private(set) var taskHistory = TaskHistory(persistenceURL: TaskHistory.defaultPersistenceURL)
    @Published private(set) var selectedTaskID: UUID?
    @Published var binaryServerAddress: String {
        didSet {
            UserDefaults.standard.set(binaryServerAddress, forKey: Self.binaryServerAddressKey)
        }
    }
    @Published private(set) var binaryComponents: [BinaryComponent] = []
    @Published private(set) var isRefreshingBinaryServer = false
    @Published private(set) var binaryServerError: String?
    @Published private(set) var binaryServerCheckedAt: Date?
    @Published var alertMessage: String?

    private static let binaryServerAddressKey = "binaryServerAddress"
    private static let customCPHomeDirKey = "IMYBinManager.customCPHomeDir"
    private static let customPluginLibDirKey = "IMYBinManager.customPluginLibDir"
    private let projectInspector = ProjectInspector()
    private let processRunner = ProcessRunner()
    private let binaryServerClient = BinaryServerClient()
    private var executionTask: Task<Void, Never>?

    init() {
        binaryServerAddress = UserDefaults.standard.string(forKey: Self.binaryServerAddressKey)
            ?? "http://localhost:8080"
        customCPHomeDir = UserDefaults.standard.string(forKey: Self.customCPHomeDirKey) ?? ""
        customPluginLibDir = UserDefaults.standard.string(forKey: Self.customPluginLibDirKey) ?? ""
        refreshToolchain()
        refreshRecents()
        refreshCacheSizes()
    }

    var hostAppDirectories: [URL] {
        guard let project else { return [] }
        let nonExample = project.appDirectories.filter { $0.lastPathComponent.lowercased() != "example" }
        return nonExample.isEmpty ? project.appDirectories : nonExample
    }

    var binaryVersionCount: Int {
        binaryComponents.reduce(0) { $0 + $1.versions.count }
    }

    var isRunning: Bool {
        taskHistory.isBusy
    }

    var activeCommandTitle: String? {
        taskHistory.activeTask?.title
    }

    var selectedTask: TaskRecord? {
        if let selectedTaskID, let task = taskHistory.record(id: selectedTaskID) {
            return task
        }
        return taskHistory.records.last
    }

    var log: String {
        guard let task = selectedTask else { return "" }
        return task.filteredLog(mode: logFilterMode, query: logSearchQuery)
    }

    var filteredConfigEntries: [ComponentConfigEntry] {
        guard let components = configTable?.components else { return [] }
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return components.filter { entry in
            if !query.isEmpty && !entry.name.lowercased().contains(query) && !(entry.version?.lowercased().contains(query) ?? false) {
                return false
            }
            switch appModeFilter {
            case "all": return true
            case "local": return entry.mode == "local"
            case "source": return entry.mode == "source"
            case "binary": return entry.mode == "binary"
            case "branch": return entry.mode == "branch"
            case "unreleased":
                guard entry.mode == "binary" else { return false }
                return !isVersionPublished(componentName: entry.name, version: entry.version)
            default: return true
            }
        }
    }

    var filteredComponentExampleEntries: [ComponentConfigEntry] {
        guard let components = componentConfigTable?.components else { return [] }
        let query = compSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return components.filter { entry in
            if !query.isEmpty && !entry.name.lowercased().contains(query) && !(entry.version?.lowercased().contains(query) ?? false) {
                return false
            }
            switch compModeFilter {
            case "all": return true
            case "local": return entry.mode == "local"
            case "source": return entry.mode == "source"
            case "binary": return entry.mode == "binary"
            case "branch": return entry.mode == "branch"
            case "unreleased":
                guard entry.mode == "binary" else { return false }
                return !isVersionPublished(componentName: entry.name, version: entry.version)
            default: return true
            }
        }
    }

    var selectedComponentInfo: ComponentPodspecInfo? {
        guard let selectedPodspec else { return componentPodspecs.first }
        let std = selectedPodspec.standardizedFileURL.path
        return componentPodspecs.first { $0.podspecURL.standardizedFileURL.path == std }
            ?? componentPodspecs.first
    }

    var configTableFileURL: URL? {
        guard let appDir = selectedAppDirectory ?? hostAppDirectories.first else { return nil }
        return ComponentConfigTable.fileURL(in: appDir)
    }

    var componentExampleConfigFileURL: URL? {
        guard let exampleDir = selectedComponentInfo?.exampleDirectoryURL else { return nil }
        return ComponentConfigTable.fileURL(in: exampleDir)
    }

    func publishedVersions(for componentName: String) -> [String] {
        binaryComponents.first { $0.name == componentName }?.versions ?? []
    }

    func isVersionPublished(componentName: String, version: String?) -> Bool {
        guard let version, !version.isEmpty else { return false }
        return publishedVersions(for: componentName).contains(version)
    }

    func localPodspecInfo(named componentName: String) -> ComponentPodspecInfo? {
        componentPodspecs.first { $0.name == componentName }
    }

    func selectProject() {
        let panel = NSOpenPanel()
        panel.title = "选择工作区、App 工程目录或组件目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspectProject(url, navigateToOverview: true)
    }

    func inspectProject(_ url: URL, navigateToOverview: Bool) {
        do {
            let snapshot = try projectInspector.inspect(url)
            project = snapshot
            componentPodspecs = snapshot.podspecURLs.compactMap { try? PodspecInspector.inspect($0) }

            if let currentPodspec = selectedPodspec,
               snapshot.podspecURLs.contains(where: { $0.standardizedFileURL == currentPodspec.standardizedFileURL }) {
                reloadSelectedComponentState()
            } else {
                selectedPodspec = snapshot.podspecURLs.first
                reloadSelectedComponentState()
            }

            let availableHostApps = hostAppDirectories
            if let currentApp = selectedAppDirectory,
               availableHostApps.contains(where: { $0.standardizedFileURL == currentApp.standardizedFileURL }) {
                reloadAppDirectoryState()
            } else {
                selectedAppDirectory = availableHostApps.first
                reloadAppDirectoryState()
            }

            if navigateToOverview {
                selection = .overview
            }
            let kind: WorkspaceKind = snapshot.podspecURLs.isEmpty ? .hostApp : (snapshot.hasPodfile ? .workspace : .component)
            workspaceRegistry.addOrUpdate(url: url, kind: kind)
            refreshRecents()
            refreshCacheSizes()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshProject() {
        guard let rootURL = project?.rootURL else { return }
        inspectProject(rootURL, navigateToOverview: false)
    }

    private func reloadAppDirectoryState() {
        guard let appDir = selectedAppDirectory ?? hostAppDirectories.first else {
            configTable = nil
            hasSavedConfigTable = false
            localComponents = []
            managedPolicy = nil
            managedPolicyError = nil
            return
        }
        let table = ComponentConfigTable.loadOrBootstrap(from: appDir, workspacePodspecs: componentPodspecs)
        configTable = table
        hasSavedConfigTable = ComponentConfigTable.exists(in: appDir)
        localComponents = table.components.map { entry in
            LocalComponentDependency(
                name: entry.name,
                declaredVersion: entry.version,
                localPath: entry.path,
                effectiveMode: entry.mode,
                overrideMode: hasSavedConfigTable ? entry.mode : nil
            )
        }

        do {
            managedPolicy = try ManagedPolicySnapshot.read(from: appDir)
            managedPolicyError = nil
            if let managedPolicy {
                managedProjectKey = managedPolicy.project
                managedPolicyRevision = managedPolicy.revision
            } else if managedProjectKey.isEmpty {
                managedProjectKey = appDir.lastPathComponent
                managedPolicyRevision = ""
            }
        } catch {
            managedPolicy = nil
            managedPolicyError = error.localizedDescription
        }
    }

    private func reloadSelectedComponentState() {
        guard let info = selectedComponentInfo else {
            editingComponentVersion = ""
            componentConfigTable = nil
            hasSavedComponentConfigTable = false
            return
        }
        editingComponentVersion = info.version
        guard let exampleDir = info.exampleDirectoryURL else {
            componentConfigTable = nil
            hasSavedComponentConfigTable = false
            return
        }
        let declaredDepNames = Set(info.dependencies.map { $0.name.split(separator: "/").first.map(String.init) ?? $0.name })
        componentConfigTable = ComponentConfigTable.loadOrBootstrap(
            from: exampleDir,
            workspacePodspecs: componentPodspecs,
            excludingSelfComponent: info.name,
            defaultEnabledNames: declaredDepNames
        )
        hasSavedComponentConfigTable = ComponentConfigTable.exists(in: exampleDir)
        refreshGitBranchInfo()
        refreshLatestArtifactReport()
        refreshReverseImpactReport()
    }

    // MARK: - Host App Config Table (.imy-bin-config.json)

    @discardableResult
    func saveConfigTable() -> Bool {
        guard let appDir = requireAppDirectory() else { return false }
        let table = configTable ?? ComponentConfigTable.loadOrBootstrap(from: appDir, workspacePodspecs: componentPodspecs)
        do {
            try table.write(to: appDir)
            reloadAppDirectoryState()
            return true
        } catch {
            alertMessage = "写入配置表失败：\(error.localizedDescription)"
            return false
        }
    }

    func saveConfigTableAndInstall() {
        guard saveConfigTable() else { return }
        runInstall()
    }

    func updateConfigEntryVersion(_ componentName: String, to version: String) {
        guard var table = configTable,
              let idx = table.components.firstIndex(where: { $0.name == componentName }) else { return }
        table.components[idx].version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        configTable = table
        _ = saveConfigTable()
    }

    func updateConfigEntryEnabled(_ componentName: String, enabled: Bool) {
        guard var table = configTable,
              let idx = table.components.firstIndex(where: { $0.name == componentName }) else { return }
        table.components[idx].enabled = enabled
        configTable = table
        _ = saveConfigTable()
    }

    func syncConfigVersionFromLocalPodspec(_ componentName: String) {
        guard let local = localPodspecInfo(named: componentName) else { return }
        updateConfigEntryVersion(componentName, to: local.version)
    }

    func focusComponent(_ componentName: String, tab: ComponentPage = .publish) {
        if let match = componentPodspecs.first(where: { $0.name == componentName }) {
            selectedPodspec = match.podspecURL
        }
        componentSelection = tab
    }

    // MARK: - Component's Own Dependencies (podspec s.dependency & Example/.imy-bin-config.json)

    func addOrUpdateSelectedPodspecDependency(name: String? = nil, versionRequirement: String? = nil) {
        guard let info = selectedComponentInfo else {
            alertMessage = "请先选择一个组件"
            return
        }
        let targetName = (name ?? newPodspecDepName).trimmingCharacters(in: .whitespacesAndNewlines)
        let targetVersion = (versionRequirement ?? newPodspecDepVersion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetName.isEmpty else {
            alertMessage = "请输入或选择依赖的组件名称"
            return
        }
        guard targetName != info.name else {
            alertMessage = "组件不能依赖自身（\(info.name)）"
            return
        }
        do {
            try PodspecInspector.upsertDependency(
                in: info.podspecURL,
                name: targetName,
                versionRequirement: targetVersion.isEmpty ? nil : targetVersion
            )
            newPodspecDepName = ""
            newPodspecDepVersion = ""
            if var table = componentConfigTable,
               let idx = table.components.firstIndex(where: { $0.name == targetName }) {
                table.components[idx].enabled = true
                if !targetVersion.isEmpty, PodspecInspector.isValidVersion(targetVersion) {
                    table.components[idx].version = targetVersion
                }
                componentConfigTable = table
                _ = saveComponentExampleConfigTable()
            }
            refreshProject()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func removeSelectedPodspecDependency(_ depName: String) {
        guard let info = selectedComponentInfo else { return }
        do {
            try PodspecInspector.removeDependency(in: info.podspecURL, name: depName)
            refreshProject()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveComponentExampleConfigTable() -> Bool {
        guard let info = selectedComponentInfo,
              let exampleDir = info.exampleDirectoryURL else {
            alertMessage = "当前组件未包含 Example 工程目录"
            return false
        }
        let declaredDepNames = Set(info.dependencies.map { $0.name.split(separator: "/").first.map(String.init) ?? $0.name })
        let table = componentConfigTable ?? ComponentConfigTable.loadOrBootstrap(
            from: exampleDir,
            workspacePodspecs: componentPodspecs,
            excludingSelfComponent: info.name,
            defaultEnabledNames: declaredDepNames
        )
        do {
            try PodspecInspector.ensureExamplePodfileUsesConfigTable(
                in: exampleDir,
                selfPodName: info.name,
                deploymentTarget: info.deploymentTarget ?? "15.0"
            )
            try table.write(to: exampleDir)
            reloadSelectedComponentState()
            return true
        } catch {
            alertMessage = "写入组件 Example 配置表失败：\(error.localizedDescription)"
            return false
        }
    }

    func syncPodspecDependenciesToComponentExampleConfig() {
        guard let info = selectedComponentInfo else { return }
        let declared = Dictionary(uniqueKeysWithValues: info.dependencies.map {
            (String($0.name.split(separator: "/").first ?? Substring($0.name)), $0.versionRequirement)
        })
        guard var table = componentConfigTable else { return }
        for idx in table.components.indices {
            let name = table.components[idx].name
            if let reqOpt = declared[name] {
                table.components[idx].enabled = true
                if let req = reqOpt, PodspecInspector.isValidVersion(req) {
                    table.components[idx].version = req
                }
            }
        }
        componentConfigTable = table
        _ = saveComponentExampleConfigTable()
    }

    func updateComponentExampleEntryVersion(_ depName: String, to version: String) {
        guard var table = componentConfigTable,
              let idx = table.components.firstIndex(where: { $0.name == depName }) else { return }
        table.components[idx].version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        componentConfigTable = table
        _ = saveComponentExampleConfigTable()
    }

    func updateComponentExampleEntryEnabled(_ depName: String, enabled: Bool) {
        guard var table = componentConfigTable,
              let idx = table.components.firstIndex(where: { $0.name == depName }) else { return }
        table.components[idx].enabled = enabled
        componentConfigTable = table
        _ = saveComponentExampleConfigTable()
    }

    func switchComponentExampleDepMode(_ depName: String, to mode: String) {
        guard let exampleDir = selectedComponentInfo?.exampleDirectoryURL else { return }
        if var table = componentConfigTable,
           let idx = table.components.firstIndex(where: { $0.name == depName }) {
            table.components[idx].mode = mode
            componentConfigTable = table
            guard saveComponentExampleConfigTable() else { return }
        }
        var commands = [BinCommandBuilder.switchMode(component: depName, mode: mode)]
        if autoInstallComponentExampleAfterSwitch {
            commands.append(BinCommandBuilder.install())
        }
        run(commands, in: exampleDir, logDestination: .componentWindow)
    }

    func switchAllComponentExampleDeps(to mode: String) {
        guard let exampleDir = selectedComponentInfo?.exampleDirectoryURL else { return }
        if var table = componentConfigTable {
            for idx in table.components.indices {
                if mode == "local" && !table.components[idx].supportsLocal { continue }
                table.components[idx].mode = mode
            }
            table.defaultMode = mode
            componentConfigTable = table
            guard saveComponentExampleConfigTable() else { return }
        }
        var commands = [BinCommandBuilder.switchAll(mode: mode)]
        if autoInstallComponentExampleAfterSwitch {
            commands.append(BinCommandBuilder.install())
        }
        run(commands, in: exampleDir, logDestination: .componentWindow)
    }

    func installComponentExampleDependencies() {
        guard let exampleDir = selectedComponentInfo?.exampleDirectoryURL else {
            alertMessage = "当前组件没有 Example 工程目录"
            return
        }
        guard saveComponentExampleConfigTable() else { return }
        run([BinCommandBuilder.install()], in: exampleDir, logDestination: .componentWindow)
    }

    func updateComponentExampleDependencies() {
        guard let exampleDir = selectedComponentInfo?.exampleDirectoryURL else {
            alertMessage = "当前组件没有 Example 工程目录"
            return
        }
        guard saveComponentExampleConfigTable() else { return }
        run([BinCommandBuilder.update()], in: exampleDir, logDestination: .componentWindow)
    }

    // MARK: - Component Versioning & Publishing

    func bumpEditingVersion(_ kind: VersionBumpKind) {
        let base = editingComponentVersion.isEmpty ? (selectedComponentInfo?.version ?? "0.1.0") : editingComponentVersion
        if let bumped = PodspecInspector.bumpVersion(base, kind: kind) {
            editingComponentVersion = bumped
        } else {
            alertMessage = "当前版本号 \(base) 无法自动递增，请手动输入 x.y.z 格式。"
        }
    }

    func bumpEditingBetaVersion() {
        let base = editingComponentVersion.isEmpty ? (selectedComponentInfo?.version ?? "0.1.0") : editingComponentVersion
        editingComponentVersion = PodspecInspector.bumpBetaVersion(base)
    }

    func promoteEditingBetaToRelease() {
        let base = editingComponentVersion.isEmpty ? (selectedComponentInfo?.version ?? "0.1.0") : editingComponentVersion
        editingComponentVersion = PodspecInspector.promoteBetaToRelease(base)
    }

    func refreshRecents() {
        recentWorkspaces = workspaceRegistry.allRecents()
        favoriteWorkspaces = workspaceRegistry.favorites()
    }

    func toggleWorkspaceFavorite(_ url: URL) {
        workspaceRegistry.toggleFavorite(url: url)
        refreshRecents()
    }

    func removeRecentWorkspace(_ url: URL) {
        workspaceRegistry.remove(url: url)
        refreshRecents()
    }

    func openHostAppInXcode() {
        if let dir = selectedAppDirectory ?? hostAppDirectories.first ?? project?.rootURL {
            WorkspaceOpener.openInXcode(at: dir)
        }
    }

    func showHostAppInFinder() {
        if let dir = selectedAppDirectory ?? hostAppDirectories.first ?? project?.rootURL {
            WorkspaceOpener.showInFinder(at: dir)
        }
    }

    func openHostAppInTerminal() {
        if let dir = selectedAppDirectory ?? hostAppDirectories.first ?? project?.rootURL {
            WorkspaceOpener.openInTerminal(at: dir)
        }
    }

    func openComponentInXcode() {
        if let dir = selectedComponentInfo?.exampleDirectoryURL ?? selectedComponentInfo?.repositoryURL {
            WorkspaceOpener.openInXcode(at: dir)
        }
    }

    func showComponentInFinder() {
        if let dir = selectedComponentInfo?.repositoryURL {
            WorkspaceOpener.showInFinder(at: dir)
        }
    }

    func openComponentInTerminal() {
        if let dir = selectedComponentInfo?.repositoryURL {
            WorkspaceOpener.openInTerminal(at: dir)
        }
    }

    func refreshGitBranchInfo() {
        guard let repo = selectedComponentInfo?.repositoryURL else {
            currentGitBranchInfo = nil
            return
        }
        currentGitBranchInfo = GitBranchManager.branches(in: repo)
    }

    func checkoutBranch(_ branch: String) {
        guard let repo = selectedComponentInfo?.repositoryURL else { return }
        do {
            try GitBranchManager.checkout(branch: branch, in: repo)
            refreshGitBranchInfo()
            refreshProject()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func pullCurrentBranch() {
        guard let repo = selectedComponentInfo?.repositoryURL else { return }
        do {
            try GitBranchManager.pull(in: repo)
            refreshGitBranchInfo()
            refreshProject()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func fetchRemoteBranches(for gitURL: String) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            GitBranchManager.remoteHeads(for: gitURL)
        }.value
    }

    func refreshCacheSizes() {
        Task.detached(priority: .background) {
            let dd = CacheManager.directorySize(at: CacheManager.derivedDataDirectoryURL)
            let tmp = CacheManager.directorySize(at: CacheManager.tmpReleaseDirectoryURL)
            await MainActor.run {
                self.derivedDataSize = dd
                self.tmpReleaseSize = tmp
            }
        }
    }

    func runRepoUpdate(all: Bool = false) {
        guard let appDir = requireAppDirectory() else { return }
        run([BinCommandBuilder.repoUpdate(all: all)], in: appDir, logDestination: .appWindow)
    }

    func cleanSelectedComponentCache(andInstall: Bool = false) {
        guard let componentName = selectedComponentInfo?.name else { return }
        let appDir = selectedAppDirectory ?? hostAppDirectories.first
        let report = CacheManager.cleanComponentCache(componentName: componentName, projectDirectoryURL: appDir)
        refreshCacheSizes()
        if andInstall {
            runInstall()
        } else {
            alertMessage = "已清理组件 \(componentName) 缓存文件 \(report.removedPaths.count) 项"
        }
    }

    func cleanComponentCache(named name: String) {
        let appDir = selectedAppDirectory ?? hostAppDirectories.first
        let report = CacheManager.cleanComponentCache(componentName: name, projectDirectoryURL: appDir)
        refreshCacheSizes()
        alertMessage = "已清理组件 \(name) 缓存文件 \(report.removedPaths.count) 项"
    }

    func runCleanCocoaPodsCache() {
        guard let appDir = requireAppDirectory() else { return }
        run([BinCommandBuilder.cleanCocoaPodsCache()], in: appDir, logDestination: .appWindow)
    }

    func cleanDerivedData() {
        do {
            try CacheManager.cleanDirectoryContents(at: CacheManager.derivedDataDirectoryURL)
            refreshCacheSizes()
            alertMessage = "已清理 Xcode DerivedData 缓存"
        } catch {
            alertMessage = "清理 DerivedData 失败：\(error.localizedDescription)"
        }
    }

    func cleanTmpRelease() {
        do {
            try CacheManager.cleanDirectoryContents(at: CacheManager.tmpReleaseDirectoryURL)
            refreshCacheSizes()
            alertMessage = "已清理临时构建目录"
        } catch {
            alertMessage = "清理临时构建目录失败：\(error.localizedDescription)"
        }
    }

    func refreshLatestArtifactReport() {
        guard let comp = selectedComponentInfo else {
            latestArtifactReport = nil
            return
        }
        latestArtifactReport = ArtifactInspector.inspectLatestArtifact(for: comp.name)
    }

    func refreshReverseImpactReport() {
        guard let project, let comp = selectedComponentInfo else {
            reverseImpactReport = nil
            return
        }
        reverseImpactReport = DependencyGraphAnalyzer.analyzeReverseImpact(
            for: comp.name,
            in: project,
            podspecs: componentPodspecs
        )
    }

    func cascadeSyncSelectedComponentVersion() {
        guard let project, let comp = selectedComponentInfo else { return }
        let targetVer = editingComponentVersion.isEmpty ? comp.version : editingComponentVersion
        do {
            let updated = try DependencyGraphAnalyzer.cascadeSyncVersion(
                targetComponent: comp.name,
                newVersion: targetVer,
                in: project,
                podspecs: componentPodspecs
            )
            refreshProject()
            alertMessage = "已级联同步更新版本 \(targetVer) 至 \(updated.count) 个依赖方：\(updated.joined(separator: ", "))"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func createNewModule(options: ModuleScaffoldOptions) {
        guard let root = project?.rootURL else {
            alertMessage = "请先选择工程根目录"
            return
        }
        do {
            _ = try ModuleScaffoldGenerator.generate(options: options, at: root)
            inspectProject(root, navigateToOverview: false)
            focusComponent(options.name)
            alertMessage = "已成功创建组件：\(options.name)"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func runComponentUnitTest() {
        guard let info = selectedComponentInfo, let exampleDir = info.exampleDirectoryURL else {
            alertMessage = "当前组件未包含 Example 工程"
            return
        }
        guard let wsOrProj = WorkspaceOpener.findXcodeWorkspaceOrProject(in: exampleDir) else {
            alertMessage = "在 Example 目录下未找到 .xcworkspace 或 .xcodeproj"
            return
        }
        let scheme = WorkspaceOpener.resolveTestScheme(for: info.name, in: wsOrProj)
        run([BinCommandBuilder.testComponent(workspaceOrProjectURL: wsOrProj, scheme: scheme)], in: exampleDir, logDestination: .componentWindow)
    }

    func exportCurrentConfigTable(to fileURL: URL) {
        guard let table = configTable else { return }
        do {
            try ComponentConfigTable.exportTable(table, to: fileURL)
            alertMessage = "配置表快照已成功导出到：\(fileURL.lastPathComponent)"
        } catch {
            alertMessage = "导出配置表失败：\(error.localizedDescription)"
        }
    }

    func importConfigTable(from fileURL: URL) {
        guard let appDir = requireAppDirectory() else { return }
        do {
            let imported = try ComponentConfigTable.importTable(from: fileURL)
            configTable = imported
            try imported.write(to: appDir)
            reloadAppDirectoryState()
            alertMessage = "已成功导入配置表：\(fileURL.lastPathComponent)"
        } catch {
            alertMessage = "导入配置表失败：\(error.localizedDescription)"
        }
    }

    func pushPolicyToServer() {
        guard let table = configTable, let appDir = requireAppDirectory() else { return }
        let projectKey = managedProjectKey.isEmpty ? appDir.lastPathComponent : managedProjectKey
        let target = ManagedTarget(
            name: appDir.lastPathComponent,
            dependencies: table.components.filter(\.enabled).map {
                ManagedDependency(name: $0.name, version: $0.version ?? "0.1.0", mode: $0.mode == "source" ? "source" : "binary")
            }
        )
        Task {
            do {
                let policy = try await binaryServerClient.pushPolicy(
                    address: binaryServerAddress,
                    project: projectKey,
                    targets: [target]
                )
                managedPolicyRevision = policy.revision
                managedPolicy = policy
                alertMessage = "成功推送平台策略！版本 Revision: \(policy.revision)"
            } catch {
                alertMessage = "推送策略失败：\(error.localizedDescription)"
            }
        }
    }

    func pullPolicyFromServer(revision: String) {
        let rev = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rev.isEmpty, let appDir = requireAppDirectory() else { return }
        let projectKey = managedProjectKey.isEmpty ? appDir.lastPathComponent : managedProjectKey
        Task {
            do {
                let policy = try await binaryServerClient.fetchPolicyRevision(
                    address: binaryServerAddress,
                    project: projectKey,
                    revision: rev
                )
                managedPolicy = policy
                managedPolicyRevision = policy.revision
                if var table = configTable {
                    let map = Dictionary(uniqueKeysWithValues: (policy.targets.first?.dependencies ?? []).map { ($0.name, $0) })
                    for idx in table.components.indices {
                        if let dep = map[table.components[idx].name] {
                            table.components[idx].version = dep.version
                            table.components[idx].mode = dep.mode
                        }
                    }
                    configTable = table
                    _ = saveConfigTable()
                }
                alertMessage = "成功拉取服务端策略 \(rev) 并应用到本地配置表！"
            } catch {
                alertMessage = "拉取策略失败：\(error.localizedDescription)"
            }
        }
    }

    func updateConfigEntryBranch(_ componentName: String, git: String?, branch: String?) {
        guard var table = configTable,
              let idx = table.components.firstIndex(where: { $0.name == componentName }) else { return }
        table.components[idx].mode = "branch"
        if let git { table.components[idx].git = git.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let branch { table.components[idx].branch = branch.trimmingCharacters(in: .whitespacesAndNewlines) }
        configTable = table
        _ = saveConfigTable()
    }

    func updateComponentExampleEntryBranch(_ componentName: String, git: String?, branch: String?) {
        guard var table = componentConfigTable,
              let idx = table.components.firstIndex(where: { $0.name == componentName }) else { return }
        table.components[idx].mode = "branch"
        if let git { table.components[idx].git = git.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let branch { table.components[idx].branch = branch.trimmingCharacters(in: .whitespacesAndNewlines) }
        componentConfigTable = table
        _ = saveComponentExampleConfigTable()
    }

    func applyComponentVersionUpdate() {
        guard let info = selectedComponentInfo else {
            alertMessage = "请先选择一个组件 podspec"
            return
        }
        let targetVersion = editingComponentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try PodspecInspector.updateVersion(in: info.podspecURL, to: targetVersion)
            if syncVersionToAppPodfile {
                for appDir in hostAppDirectories {
                    _ = try? ComponentConfigTable.updateComponentVersion(
                        in: appDir,
                        workspacePodspecs: componentPodspecs,
                        component: info.name,
                        to: targetVersion
                    )
                }
            }
            refreshProject()
            if autoCommitVersionBump {
                let commitCommand = BinCommandBuilder.commitComponentVersion(
                    podspecFileName: info.podspecURL.lastPathComponent,
                    version: targetVersion
                )
                run([commitCommand], in: info.repositoryURL, logDestination: .componentWindow)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func syncSelectedComponentVersionToPodfile() {
        guard let info = selectedComponentInfo else {
            alertMessage = "请先选择一个组件"
            return
        }
        let apps = hostAppDirectories
        guard !apps.isEmpty else {
            alertMessage = "未找到包含 Podfile 的宿主 App 目录"
            return
        }
        do {
            for appDir in apps {
                _ = try ComponentConfigTable.updateComponentVersion(
                    in: appDir,
                    workspacePodspecs: componentPodspecs,
                    component: info.name,
                    to: info.version
                )
            }
            refreshProject()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshToolchain() {
        guard !isInspectingToolchain else { return }
        isInspectingToolchain = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                ToolchainInspector().inspect()
            }.value
            toolchain = report
            isInspectingToolchain = false
        }
    }

    func refreshBinaryServer() {
        guard !isRefreshingBinaryServer else { return }

        let address = binaryServerAddress
        do {
            _ = try BinaryServerClient.frameworksURL(from: address)
        } catch {
            binaryServerError = error.localizedDescription
            binaryServerCheckedAt = Date()
            return
        }

        isRefreshingBinaryServer = true
        binaryServerError = nil
        Task {
            do {
                binaryComponents = try await binaryServerClient.listComponents(address: address)
            } catch {
                binaryComponents = []
                binaryServerError = error.localizedDescription
            }
            binaryServerCheckedAt = Date()
            isRefreshingBinaryServer = false
        }
    }

    func runInstall() {
        guard let appDir = requireAppDirectory() else { return }
        _ = saveConfigTable()
        run([BinCommandBuilder.install()], in: appDir, logDestination: .appWindow)
    }

    func runUpdate() {
        guard let appDir = requireAppDirectory() else { return }
        _ = saveConfigTable()
        run([BinCommandBuilder.update()], in: appDir, logDestination: .appWindow)
    }

    func runStatus() {
        guard let appDir = requireAppDirectory() else { return }
        _ = saveConfigTable()
        run([BinCommandBuilder.status()], in: appDir, logDestination: .appWindow)
    }

    func runPolicySync() {
        guard let appDir = requireAppDirectory() else { return }
        let projectKey = managedProjectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else {
            alertMessage = "请填写平台工程标识"
            return
        }
        guard let address = URLComponents(string: binaryServerAddress),
              let scheme = address.scheme?.lowercased(),
              let host = address.host?.lowercased(),
              address.user == nil, address.password == nil,
              address.query == nil, address.fragment == nil,
              (scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)))
        else {
            alertMessage = "策略同步仅接受无凭据的 HTTPS 服务地址（本机 HTTP 例外）"
            return
        }
        run([BinCommandBuilder.syncPolicy(
            project: projectKey,
            revision: managedPolicyRevision.trimmingCharacters(in: .whitespacesAndNewlines),
            server: binaryServerAddress
        )], in: appDir, logDestination: .appWindow)
    }

    func switchMode(_ dependency: ManagedDependency, to mode: String) {
        switchLocalComponent(dependency.name, to: mode)
    }

    func switchLocalComponent(_ componentName: String, to mode: String) {
        guard let appDir = requireAppDirectory() else { return }
        if var table = configTable,
           let idx = table.components.firstIndex(where: { $0.name == componentName }) {
            table.components[idx].mode = mode
            configTable = table
            _ = saveConfigTable()
        }
        var commands = [BinCommandBuilder.switchMode(component: componentName, mode: mode)]
        if autoInstallAfterSwitch {
            commands.append(BinCommandBuilder.install())
        }
        run(commands, in: appDir, logDestination: .appWindow)
    }

    func switchAllComponents(to mode: String) {
        guard let appDir = requireAppDirectory() else { return }
        if var table = configTable {
            for idx in table.components.indices {
                if mode == "local" && !table.components[idx].supportsLocal { continue }
                table.components[idx].mode = mode
            }
            table.defaultMode = mode
            configTable = table
            _ = saveConfigTable()
        }
        var commands = [BinCommandBuilder.switchAll(mode: mode)]
        if autoInstallAfterSwitch {
            commands.append(BinCommandBuilder.install())
        }
        run(commands, in: appDir, logDestination: .appWindow)
    }

    func resetComponentModes() {
        guard let appDir = requireAppDirectory() else { return }
        if var table = configTable {
            for idx in table.components.indices {
                table.components[idx].mode = "binary"
            }
            table.defaultMode = "binary"
            configTable = table
            _ = saveConfigTable()
        }
        var commands = [BinCommandBuilder.resetModes()]
        if autoInstallAfterSwitch {
            commands.append(BinCommandBuilder.install())
        }
        run(commands, in: appDir, logDestination: .appWindow)
    }

    func runArchive() {
        guard let podspec = selectedPodspec ?? selectedComponentInfo?.podspecURL else {
            alertMessage = "请先选择一个 podspec"
            return
        }
        let workingDir = podspec.standardizedFileURL.deletingLastPathComponent()
        run([BinCommandBuilder.archive(
            podspecURL: podspec,
            environment: environment,
            configuration: configuration,
            buildMissingDependencies: buildMissingDependencies,
            keepIntermediates: keepIntermediates
        )], in: workingDir, logDestination: .componentWindow)
    }

    func runPublishDryRun() {
        executePublish(dryRun: true)
    }

    func runPublish() {
        executePublish(dryRun: publishDryRun)
    }

    func runOfficialPublish() {
        executePublish(dryRun: false)
    }

    private func executePublish(dryRun: Bool) {
        guard let podspec = selectedPodspec ?? selectedComponentInfo?.podspecURL else {
            alertMessage = "请先选择一个 podspec"
            return
        }
        let workingDir = podspec.standardizedFileURL.deletingLastPathComponent()
        let currentVer = editingComponentVersion.isEmpty ? (selectedComponentInfo?.version ?? "") : editingComponentVersion
        let isPrerelease = currentVer.contains("-") || currentVer.localizedCaseInsensitiveContains("beta")
        let command = BinCommandBuilder.publish(
            podspecURL: podspec,
            environment: environment,
            configuration: configuration,
            codeDependencies: codeDependencies,
            keepIntermediates: keepIntermediates,
            skipTag: skipTag,
            skipCodeSpec: skipCodeSpec,
            dryRun: dryRun,
            allowPrerelease: isPrerelease
        )
        run(
            [command],
            in: workingDir,
            logDestination: .componentWindow,
            refreshBinaryServerOnCompletion: !dryRun
        )
    }

    func cancelTask() {
        guard let taskID = taskHistory.activeTask?.id else { return }
        do {
            try taskHistory.requestCancellation(taskID)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        processRunner.cancel()
        executionTask?.cancel()
    }

    func clearLog() {
        guard !isRunning else { return }
        taskHistory.clearFinishedRecords()
        selectedTaskID = nil
    }

    func selectTask(_ id: UUID) {
        selectedTaskID = id
    }

    private func requireAppDirectory() -> URL? {
        if let dir = selectedAppDirectory ?? hostAppDirectories.first {
            return dir
        }
        alertMessage = "当前工程未找到包含 Podfile 的宿主 App 目录"
        return nil
    }

    private func run(
        _ commands: [CommandSpec],
        in workingDirectory: URL,
        logDestination: LogDestination,
        refreshBinaryServerOnCompletion: Bool = false
    ) {
        guard project != nil else {
            alertMessage = "请先选择工程目录"
            return
        }
        guard let first = commands.first else { return }
        guard !isRunning else {
            alertMessage = "已有任务正在执行"
            return
        }

        let combinedTitle = commands.map(\.title).joined(separator: " → ")
        let combinedDisplay = commands.map(\.displayCommand).joined(separator: " && ")

        let taskID: UUID
        do {
            taskID = try taskHistory.enqueue(
                kind: first.taskKind,
                title: combinedTitle,
                workspaceURL: workingDirectory,
                displayCommand: combinedDisplay
            )
            try taskHistory.start(taskID)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        selectedTaskID = taskID
        switch logDestination {
        case .appWindow:
            selection = .logs
        case .componentWindow:
            componentSelection = .logs
        }

        executionTask = Task {
            var finalExitCode: Int32 = 0
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try LoginShellEnvironmentLoader().load()
                }.value
                var env = loaded.environment
                Self.injectLocalInfraEnvironment(
                    for: workingDirectory,
                    customCPHome: customCPHomeDir,
                    customPluginLib: customPluginLibDir,
                    into: &env
                )

                for (index, command) in commands.enumerated() {
                    if index > 0 {
                        try taskHistory.appendEvent(
                            TaskEvent(kind: .phase, message: "继续执行：\(command.title) (\(command.displayCommand))"),
                            to: taskID
                        )
                    }
                    let events = try processRunner.events(
                        for: command,
                        workingDirectory: workingDirectory,
                        environment: env
                    )
                    for try await event in events {
                        switch event {
                        case .output(let text):
                            try taskHistory.appendOutput(text, to: taskID)
                        case .finished(let code):
                            finalExitCode = code
                        }
                    }
                    if finalExitCode != 0 {
                        break
                    }
                }
                try taskHistory.finish(taskID, exitCode: finalExitCode)
            } catch is CancellationError {
                try? taskHistory.cancel(taskID)
            } catch {
                alertMessage = error.localizedDescription
                try? taskHistory.fail(taskID, summary: error.localizedDescription)
            }
            executionTask = nil
            refreshProject()
            refreshLatestArtifactReport()
            if refreshBinaryServerOnCompletion && finalExitCode == 0 {
                refreshBinaryServer()
            }
        }
    }

    private static func injectLocalInfraEnvironment(
        for workspaceURL: URL,
        customCPHome: String = "",
        customPluginLib: String = "",
        into env: inout [String: String]
    ) {
        let fm = FileManager.default
        let trimmedCP = customCPHome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCP.isEmpty, fm.fileExists(atPath: trimmedCP) {
            env["CP_HOME_DIR"] = trimmedCP
        }
        let trimmedPlugin = customPluginLib.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlugin.isEmpty, fm.fileExists(atPath: trimmedPlugin) {
            let existing = env["RUBYLIB"] ?? ""
            if !existing.contains(trimmedPlugin) {
                env["RUBYLIB"] = existing.isEmpty ? trimmedPlugin : "\(trimmedPlugin):\(existing)"
            }
        }

        var candidates: [URL] = []
        var current = workspaceURL.standardizedFileURL
        for _ in 0..<5 {
            candidates.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        for root in candidates {
            let infraHome = root.appendingPathComponent(".imy-infra/home")
            let binDev = infraHome.appendingPathComponent("bin_dev.yml")
            if env["CP_HOME_DIR"] == nil, fm.fileExists(atPath: binDev.path) {
                env["CP_HOME_DIR"] = infraHome.path
            }
            let pluginLib = root.appendingPathComponent("cocoapods-imy-bin-fork/cocoapods-imy-bin/lib")
            if fm.fileExists(atPath: pluginLib.path) {
                let existing = env["RUBYLIB"] ?? ""
                if !existing.contains(pluginLib.path) {
                    env["RUBYLIB"] = existing.isEmpty ? pluginLib.path : "\(pluginLib.path):\(existing)"
                }
            }
        }
    }
}
