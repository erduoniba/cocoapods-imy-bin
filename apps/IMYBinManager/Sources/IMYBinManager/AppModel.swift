import AppKit
import Foundation
import IMYBinCore

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case overview
        case server
        case dependencies
        case build
        case logs
        case settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "概览"
            case .server: "制品服务"
            case .dependencies: "工程依赖"
            case .build: "组件任务"
            case .logs: "运行日志"
            case .settings: "设置"
            }
        }
        var systemImage: String {
            switch self {
            case .overview: "rectangle.3.group"
            case .server: "shippingbox"
            case .dependencies: "square.3.layers.3d"
            case .build: "hammer"
            case .logs: "terminal"
            case .settings: "gearshape"
            }
        }
    }

    @Published var selection: Page? = .overview
    @Published private(set) var project: ProjectSnapshot?
    @Published var selectedPodspec: URL?
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
    @Published var publishDryRun = false
    @Published private(set) var toolchain: ToolchainReport?
    @Published private(set) var isInspectingToolchain = false
    @Published private(set) var taskHistory = TaskHistory()
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
    private let projectInspector = ProjectInspector()
    private let processRunner = ProcessRunner()
    private let binaryServerClient = BinaryServerClient()
    private var executionTask: Task<Void, Never>?

    init() {
        binaryServerAddress = UserDefaults.standard.string(forKey: Self.binaryServerAddressKey)
            ?? "http://localhost:8080"
        refreshToolchain()
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
        selectedTask?.renderedLog ?? ""
    }

    func selectProject() {
        let panel = NSOpenPanel()
        panel.title = "选择包含 Podfile 或 podspec 的工程目录"
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
            selectedPodspec = snapshot.podspecURLs.first
            localComponents = PodfileComponentInspector.inspect(from: snapshot.rootURL)
            do {
                managedPolicy = try ManagedPolicySnapshot.read(from: snapshot.rootURL)
                managedPolicyError = nil
                if let managedPolicy {
                    managedProjectKey = managedPolicy.project
                    managedPolicyRevision = managedPolicy.revision
                } else if navigateToOverview {
                    managedProjectKey = snapshot.rootURL.lastPathComponent
                    managedPolicyRevision = ""
                }
            } catch {
                managedPolicy = nil
                managedPolicyError = error.localizedDescription
            }
            if navigateToOverview {
                selection = .overview
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshProject() {
        guard let rootURL = project?.rootURL else { return }
        inspectProject(rootURL, navigateToOverview: false)
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
        run(BinCommandBuilder.install())
    }

    func runUpdate() {
        run(BinCommandBuilder.update())
    }

    func runPolicySync() {
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
        run(BinCommandBuilder.syncPolicy(
            project: projectKey,
            revision: managedPolicyRevision.trimmingCharacters(in: .whitespacesAndNewlines),
            server: binaryServerAddress
        ))
    }

    func switchMode(_ dependency: ManagedDependency, to mode: String) {
        run(BinCommandBuilder.switchMode(component: dependency.name, mode: mode))
    }

    func switchLocalComponent(_ componentName: String, to mode: String) {
        run(BinCommandBuilder.switchMode(component: componentName, mode: mode))
    }

    func switchAllComponents(to mode: String) {
        run(BinCommandBuilder.switchAll(mode: mode))
    }

    func resetComponentModes() {
        run(BinCommandBuilder.resetModes())
    }

    func runArchive() {
        guard let selectedPodspec else {
            alertMessage = "请先选择一个 podspec"
            return
        }
        run(BinCommandBuilder.archive(
            podspecURL: selectedPodspec,
            environment: environment,
            configuration: configuration,
            buildMissingDependencies: buildMissingDependencies,
            keepIntermediates: keepIntermediates
        ))
    }

    func runPublish() {
        guard let selectedPodspec else {
            alertMessage = "请先选择一个 podspec"
            return
        }
        run(BinCommandBuilder.publish(
            podspecURL: selectedPodspec,
            environment: environment,
            configuration: configuration,
            codeDependencies: codeDependencies,
            keepIntermediates: keepIntermediates,
            dryRun: publishDryRun
        ))
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

    private func run(_ command: CommandSpec) {
        guard let project else {
            alertMessage = "请先选择工程目录"
            return
        }
        guard !isRunning else {
            alertMessage = "已有任务正在执行"
            return
        }

        let taskID: UUID
        do {
            taskID = try taskHistory.enqueue(
                kind: command.taskKind,
                title: command.title,
                workspaceURL: project.rootURL,
                displayCommand: command.displayCommand
            )
            try taskHistory.start(taskID)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        selectedTaskID = taskID
        selection = .logs

        executionTask = Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try LoginShellEnvironmentLoader().load()
                }.value
                var env = loaded.environment
                Self.injectLocalInfraEnvironment(for: project.rootURL, into: &env)
                let events = try processRunner.events(
                    for: command,
                    workingDirectory: project.rootURL,
                    environment: env
                )
                for try await event in events {
                    switch event {
                    case .output(let text):
                        try taskHistory.appendOutput(text, to: taskID)
                    case .finished(let code):
                        try taskHistory.finish(taskID, exitCode: code)
                    }
                }
            } catch is CancellationError {
                try? taskHistory.cancel(taskID)
            } catch {
                alertMessage = error.localizedDescription
                try? taskHistory.fail(taskID, summary: error.localizedDescription)
            }
            executionTask = nil
            refreshProject()
        }
    }

    private static func injectLocalInfraEnvironment(for workspaceURL: URL, into env: inout [String: String]) {
        let fm = FileManager.default
        let candidates = [workspaceURL, workspaceURL.deletingLastPathComponent()]
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
