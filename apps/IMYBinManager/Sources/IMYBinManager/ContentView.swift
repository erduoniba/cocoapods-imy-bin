import IMYBinCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppModel.Page.allCases, selection: $model.selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationTitle("IMY Bin")
            .safeAreaInset(edge: .bottom) {
                projectFooter
            }
        } detail: {
            Group {
                switch model.selection ?? .overview {
                case .overview:
                    OverviewView()
                case .server:
                    BinaryServerView()
                case .dependencies:
                    ManagedDependenciesView()
                case .build:
                    TasksView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(model.selection?.title ?? "概览")
        }
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var projectFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let project = model.project {
                Text(project.rootURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.rootURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("尚未选择工程")
                    .foregroundStyle(.secondary)
            }
            Button("选择工程…") { model.selectProject() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.bar)
    }
}

private struct BinaryServerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("二进制制品服务")
                        .font(.largeTitle.bold())
                    Text("连接仓库内的 binary-server，浏览已上传组件及版本。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("连接") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("http://localhost:8080", text: $model.binaryServerAddress)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { model.refreshBinaryServer() }
                            Button("连接并刷新") { model.refreshBinaryServer() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRefreshingBinaryServer)
                        }
                        if model.isRefreshingBinaryServer {
                            ProgressView("正在读取 /frameworks …")
                        } else if let error = model.binaryServerError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        } else if let checkedAt = model.binaryServerCheckedAt {
                            Label(
                                "连接正常：\(model.binaryComponents.count) 个组件，\(model.binaryVersionCount) 个版本",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)
                            Text("上次刷新：\(checkedAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("地址仅保存在本机。点击按钮后才会发起只读请求。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("组件版本") {
                    if model.binaryComponents.isEmpty {
                        EmptyHint(text: model.binaryServerCheckedAt == nil ? "连接服务后显示组件。" : "服务中暂无组件。")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.binaryComponents) { component in
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(component.name).font(.headline)
                                        Text(component.versions.joined(separator: "  ·  "))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Text("\(component.versions.count) 个版本")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                if component.id != model.binaryComponents.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(24)
        }
        .toolbar {
            Button { model.refreshBinaryServer() } label: {
                Label("刷新制品服务", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshingBinaryServer)
        }
    }
}

private struct ManagedDependenciesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工程依赖管理")
                        .font(.largeTitle.bold())
                    Text("管理 Podfile 中的组件模式（local / source / binary），或同步团队平台策略快照。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Podfile 组件依赖（.imy-bin-modes.yml）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.localComponents.isEmpty {
                            EmptyHint(text: "当前工程的 Podfile 中未检测到可切换的组件声明。")
                        } else {
                            HStack(spacing: 10) {
                                Text("全局切换：").font(.subheadline.bold())
                                Button("全部本地 (local)") { model.switchAllComponents(to: "local") }
                                Button("全部源码 (source)") { model.switchAllComponents(to: "source") }
                                Button("全部二进制 (binary)") { model.switchAllComponents(to: "binary") }
                                Spacer()
                                Button("重置覆盖") { model.resetComponentModes() }
                            }
                            Divider()
                            ForEach(model.localComponents) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.headline)
                                        Text(
                                            "\(item.declaredVersion ?? "未固定版本") · 当前模式：\(item.effectiveMode)"
                                            + (item.overrideMode != nil ? "（本地覆盖）" : "")
                                            + (item.localPath.map { " · path: \($0)" } ?? "")
                                        )
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("本地") { model.switchLocalComponent(item.name, to: "local") }
                                        .disabled(!item.supportsLocal || item.effectiveMode == "local")
                                    Button("源码") { model.switchLocalComponent(item.name, to: "source") }
                                        .disabled(item.effectiveMode == "source")
                                    Button("二进制") { model.switchLocalComponent(item.name, to: "binary") }
                                        .disabled(item.effectiveMode == "binary")
                                }
                                if item.id != model.localComponents.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("同步平台策略快照（可选）") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("平台工程标识", text: $model.managedProjectKey)
                        TextField("策略版本 UUID（开发环境可留空使用已启用版本）", text: $model.managedPolicyRevision)
                        Text("平台令牌从登录 Shell 的 IMY_BIN_PLATFORM_TOKEN 读取，不保存在客户端。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("同步策略") { model.runPolicySync() }
                            .buttonStyle(.borderedProminent)
                        if let error = model.managedPolicyError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let policy = model.managedPolicy {
                    Text("\(policy.project) · 版本 \(policy.revision)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    ForEach(policy.targets) { target in
                        GroupBox(target.name) {
                            if target.dependencies.isEmpty {
                                EmptyHint(text: "该 target 没有平台托管的内部组件。")
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(target.dependencies) { dependency in
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(dependency.name).font(.headline)
                                                Text("\(dependency.version) · 团队策略：\(dependency.mode)")
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button("本地源码") { model.switchMode(dependency, to: "source") }
                                            Button("本地二进制") { model.switchMode(dependency, to: "binary") }
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    EmptyHint(text: "当前工程没有策略快照。先配置平台服务和工程标识，然后同步。")
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GroupBox("工程检查") {
                    if let project = model.project {
                        VStack(spacing: 10) {
                            StatusRow(title: "Podfile", value: project.hasPodfile ? "已找到" : "未找到", success: project.hasPodfile)
                            StatusRow(title: "Podfile.lock", value: project.hasLockfile ? "已找到" : "未找到", success: project.hasLockfile)
                            StatusRow(title: "BinArchive.json", value: project.hasArchiveConfiguration ? "已找到" : "可选", success: true)
                            StatusRow(title: "podspec", value: "\(project.podspecURLs.count) 个", success: !project.podspecURLs.isEmpty)
                        }
                        .padding(.top, 6)
                    } else {
                        EmptyHint(text: "选择一个 CocoaPods 工程后开始扫描。")
                    }
                }
                GroupBox("本机工具链") {
                    if model.isInspectingToolchain {
                        ProgressView("正在从登录 shell 读取环境…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else if let report = model.toolchain {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Shell")
                                Spacer()
                                Text(report.shellPath).foregroundStyle(.secondary)
                            }
                            ForEach(report.probes) { probe in
                                StatusRow(
                                    title: probe.name,
                                    value: probe.version ?? probe.error ?? "未知",
                                    success: probe.isAvailable
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                GroupBox("二进制制品服务") {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusRow(
                            title: "binary-server",
                            value: model.binaryServerError
                                ?? (model.binaryServerCheckedAt == nil
                                    ? "尚未检测"
                                    : "\(model.binaryComponents.count) 个组件 / \(model.binaryVersionCount) 个版本"),
                            success: model.binaryServerCheckedAt != nil && model.binaryServerError == nil
                        )
                        HStack {
                            Text(model.binaryServerAddress)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Spacer()
                            Button("检测") { model.refreshBinaryServer() }
                                .disabled(model.isRefreshingBinaryServer)
                            Button("查看组件") { model.selection = .server }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .toolbar {
            Button { model.refreshToolchain() } label: {
                Label("刷新工具链", systemImage: "arrow.clockwise")
            }
            Button { model.refreshProject() } label: {
                Label("刷新工程", systemImage: "folder.badge.gearshape")
            }
            .disabled(model.project == nil)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CocoaPods 二进制工作台")
                .font(.largeTitle.bold())
            Text("保留 Ruby 插件作为执行引擎，由桌面端提供环境诊断、任务编排和日志。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TasksView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("组件") {
                if let project = model.project, !project.podspecURLs.isEmpty {
                    Picker("podspec", selection: $model.selectedPodspec) {
                        ForEach(project.podspecURLs, id: \.self) { url in
                            Text(url.lastPathComponent).tag(Optional(url))
                        }
                    }
                } else {
                    Text("当前工程没有找到 podspec")
                        .foregroundStyle(.secondary)
                }
            }

            Section("构建选项") {
                Picker("环境", selection: $model.environment) {
                    ForEach(BinEnvironment.allCases) { environment in
                        Text(environment.title).tag(environment)
                    }
                }
                Picker("Configuration", selection: $model.configuration) {
                    ForEach(BuildConfiguration.allCases) { configuration in
                        Text(configuration.rawValue).tag(configuration)
                    }
                }
                Toggle("构建缺失二进制的依赖（--all-make）", isOn: $model.buildMissingDependencies)
                Toggle("构建时使用源码依赖（--code-dependencies）", isOn: $model.codeDependencies)
                Toggle("保留中间产物（--no-clean）", isOn: $model.keepIntermediates)
                Toggle("发布预检模式，只构建不上传（--dry-run）", isOn: $model.publishDryRun)
            }

            Section("操作") {
                HStack(spacing: 12) {
                    Button("安装依赖") { model.runInstall() }
                    Button("更新依赖") { model.runUpdate() }
                    Button("构建二进制") { model.runArchive() }
                        .disabled(model.selectedPodspec == nil)
                    Button(model.publishDryRun ? "发布预检 (Dry Run)" : "发布组件 (Publish)") { model.runPublish() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedPodspec == nil)
                }
                Text("操作会调用当前环境的 pod bin：构建出 XCFramework 并发布到源码/二进制 spec 仓库与 binary-server。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.project == nil || model.isRunning)
        .overlay {
            if model.project == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("请选择工程")
                        .font(.title2.bold())
                    Text("从左下角选择包含 Podfile 或 podspec 的目录。")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let task = model.selectedTask {
                    Label("\(task.title) · \(task.state.title)", systemImage: statusImage(for: task.state))
                        .foregroundStyle(statusColor(for: task.state))
                } else if model.isRunning {
                    ProgressView().controlSize(.small)
                    Text(model.activeCommandTitle ?? "正在执行")
                } else {
                    Text("没有任务记录").foregroundStyle(.secondary)
                }
                Spacer()
                if !model.taskHistory.records.isEmpty {
                    Menu("任务历史") {
                        ForEach(model.taskHistory.records.reversed(), id: \.id) { task in
                            Button("\(task.title) · \(task.state.title)") {
                                model.selectTask(task.id)
                            }
                        }
                    }
                }
                Button("清空历史") { model.clearLog() }
                    .disabled(model.isRunning || model.taskHistory.records.isEmpty)
                Button("取消", role: .destructive) { model.cancelTask() }.disabled(!model.isRunning)
            }
            .padding(12)
            Divider()
            ScrollView {
                Text(model.log.isEmpty ? "运行日志将在这里显示。" : model.log)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(model.log.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func statusImage(for state: TaskState) -> String {
        switch state {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .cancelling: "stop.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle.fill"
        }
    }

    private func statusColor(for state: TaskState) -> Color {
        switch state {
        case .succeeded: .green
        case .failed: .red
        case .cancelled, .cancelling: .orange
        case .queued, .running: .primary
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("执行方式") {
                LabeledContent("登录 Shell", value: model.toolchain?.shellPath ?? "检测中")
                Text("应用读取登录 shell 环境后直接启动 pod，不拼接用户输入的 shell 命令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("发布能力") {
                Label("MVP 禁用 pod bin auto", systemImage: "lock.shield")
                Text("服务端已具备令牌认证和上传校验；客户端仍需完成发布预检、二次确认、审计和回滚编排后才会开放发布。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let success: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(success ? .green : .orange)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
