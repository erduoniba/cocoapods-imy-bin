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
                case .dependencies:
                    ManagedDependenciesView()
                case .build:
                    ComponentPublishView()
                case .server:
                    BinaryServerView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(model.selection?.title ?? "工作台概览")
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
                HStack(spacing: 8) {
                    Label("\(project.appDirectories.count) 个 App", systemImage: "app.badge")
                    Spacer()
                    Label("\(model.componentPodspecs.count) 个组件", systemImage: "shippingbox")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("尚未选择工作区或工程")
                    .foregroundStyle(.secondary)
            }
            Button("选择工作区 / 工程…") { model.selectProject() }
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
                    Text("连接仓库内的 binary-server，浏览已发布的 XCFramework 组件及版本。")
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

                GroupBox("已发布组件版本") {
                    if model.binaryComponents.isEmpty {
                        EmptyHint(text: model.binaryServerCheckedAt == nil ? "连接服务后显示组件。" : "服务中暂无已发布组件。")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.binaryComponents) { component in
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(component.name).font(.headline)
                                            if let local = model.localPodspecInfo(named: component.name) {
                                                Text("本地 podspec: \(local.version)")
                                                    .font(.caption2.monospaced())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.quaternary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(component.versions.joined(separator: "  ·  "))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    if model.localPodspecInfo(named: component.name) != nil {
                                        Button("管理发布") {
                                            model.navigateToPublish(componentName: component.name)
                                        }
                                        .controlSize(.small)
                                    }
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
                    Text("App 依赖与安装管理")
                        .font(.largeTitle.bold())
                    Text("管理宿主 App 的 Podfile 组件依赖模式（local / source / binary），并一键执行 pod bin install / update。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("目标 App 工程与依赖安装") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let project = model.project, !project.appDirectories.isEmpty {
                            HStack {
                                Picker("宿主 App 目录", selection: $model.selectedAppDirectory) {
                                    ForEach(project.appDirectories, id: \.self) { dir in
                                        Text("\(dir.lastPathComponent) (\(dir.path))").tag(Optional(dir))
                                    }
                                }
                                Button("刷新") { model.refreshProject() }
                            }
                        } else {
                            EmptyHint(text: "当前工作区未检测到包含 Podfile 的 App 目录。")
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button("安装依赖 (pod bin install)") { model.runInstall() }
                                .buttonStyle(.borderedProminent)
                            Button("更新依赖 (pod bin update)") { model.runUpdate() }
                            Button("查询依赖状态 (pod bin status)") { model.runStatus() }
                            Spacer()
                            Toggle("切换模式后自动执行 pod bin install", isOn: $model.autoInstallAfterSwitch)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("Podfile 组件依赖（.imy-bin-modes.yml）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.localComponents.isEmpty {
                            EmptyHint(text: "当前 App 的 Podfile 中未检测到可切换的组件声明。")
                        } else {
                            HStack(spacing: 10) {
                                Text("全局切换：").font(.subheadline.bold())
                                Button("全部本地 (local)") { model.switchAllComponents(to: "local") }
                                Button("全部源码 (source)") { model.switchAllComponents(to: "source") }
                                Button("全部二进制 (binary)") { model.switchAllComponents(to: "binary") }
                                Spacer()
                                Button("重置本地覆盖 (--reset)") { model.resetComponentModes() }
                            }
                            Divider()
                            ForEach(model.localComponents) { item in
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(item.name).font(.headline)
                                            ModeBadge(mode: item.effectiveMode, isOverride: item.overrideMode != nil)
                                            if let declared = item.declaredVersion,
                                               model.binaryServerCheckedAt != nil {
                                                let available = model.isVersionPublished(componentName: item.name, version: declared)
                                                Text(available ? "二进制已就绪" : "二进制未发布")
                                                    .font(.caption2)
                                                    .foregroundStyle(available ? .green : .orange)
                                            }
                                        }
                                        Text(
                                            "Podfile 版本：\(item.declaredVersion ?? "未固定")"
                                            + (model.localPodspecInfo(named: item.name).map { " · 本地 podspec：\($0.version)" } ?? "")
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
                                    if model.localPodspecInfo(named: item.name) != nil {
                                        Button("去发布…") {
                                            model.navigateToPublish(componentName: item.name)
                                        }
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 4)
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
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
    }
}

private struct ComponentPublishView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingPublishConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("组件发布管理")
                        .font(.largeTitle.bold())
                    Text("管理组件的 podspec 版本号、Git 标签状态、XCFramework 二进制归档与双轨 Spec 发布。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("选择要管理的组件（.podspec）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.componentPodspecs.isEmpty {
                            EmptyHint(text: "当前工作区没有找到可发布的组件 podspec。")
                        } else {
                            HStack {
                                Picker("目标组件", selection: $model.selectedPodspec) {
                                    ForEach(model.componentPodspecs) { spec in
                                        Text("\(spec.name) (\(spec.version)) — \(spec.podspecURL.lastPathComponent)")
                                            .tag(Optional(spec.podspecURL))
                                    }
                                }
                                Button("刷新状态") {
                                    model.refreshProject()
                                    model.refreshBinaryServer()
                                }
                            }
                            Divider()
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(model.componentPodspecs) { spec in
                                    let isSelected = model.selectedComponentInfo?.id == spec.id
                                    HStack(spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(spec.name).font(.headline)
                                                Text("v\(spec.version)")
                                                    .font(.caption.monospaced())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.quaternary)
                                                    .clipShape(Capsule())
                                                Text(spec.staticFramework ? "静态 XCFramework" : "动态 XCFramework")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(spec.podspecURL.path)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Label(
                                            spec.isGitClean ? "Git 干净" : "有未提交改动",
                                            systemImage: spec.isGitClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(spec.isGitClean ? .green : .orange)

                                        if model.isVersionPublished(componentName: spec.name, version: spec.version) {
                                            Label("已发布二进制", systemImage: "shippingbox.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(8)
                                    .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selectedPodspec = spec.podspecURL
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                if let info = model.selectedComponentInfo {
                    GroupBox("版本管理与 Git 状态 — \(info.name)") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text("当前版本：")
                                    .font(.subheadline.bold())
                                Text(info.version)
                                    .font(.system(.body, design: .monospaced).bold())
                                Divider().frame(height: 18)
                                Text("目标版本：")
                                    .font(.subheadline.bold())
                                TextField("0.1.2", text: $model.editingComponentVersion)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                ForEach(VersionBumpKind.allCases) { kind in
                                    Button(kind.title) {
                                        model.bumpEditingVersion(kind)
                                    }
                                    .controlSize(.small)
                                }
                            }

                            HStack(spacing: 20) {
                                Toggle("同时更新宿主 App Podfile 中的组件版本", isOn: $model.syncVersionToAppPodfile)
                                Toggle("保存版本后自动提交到组件 Git 仓库", isOn: $model.autoCommitVersionBump)
                            }
                            .font(.caption)

                            HStack(spacing: 12) {
                                Button("写入新版本号") {
                                    model.applyComponentVersionUpdate()
                                }
                                .disabled(
                                    model.editingComponentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || model.editingComponentVersion.trimmingCharacters(in: .whitespacesAndNewlines) == info.version
                                )
                                Button("同步当前版本 (\(info.version)) 到 App Podfile") {
                                    model.syncSelectedComponentVersionToPodfile()
                                }
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                StatusRow(
                                    title: "Git 分支与工作区",
                                    value: "\(info.gitBranch ?? "未知分支") · " + (info.isGitClean ? "工作区干净（可发布）" : "存在 \(info.dirtyFilesSummary.count) 个未提交文件"),
                                    success: info.isGitClean
                                )
                                if !info.isGitClean {
                                    Text("未提交文件：" + info.dirtyFilesSummary.joined(separator: "，"))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.orange)
                                }
                                StatusRow(
                                    title: "当前版本 Git Tag (\(info.version))",
                                    value: info.hasCurrentVersionTag ? "已存在 Tag（将复用现有 Tag）" : "尚未打 Tag（发布时将自动创建）",
                                    success: true
                                )
                                let published = model.publishedVersions(for: info.name)
                                StatusRow(
                                    title: "binary-server 制品状态",
                                    value: published.isEmpty
                                        ? (model.binaryServerCheckedAt == nil ? "未检测（点击右上角刷新）" : "尚未上传任何版本")
                                        : "已发布版本：\(published.joined(separator: ", "))",
                                    success: published.contains(info.version)
                                )
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("XCFramework 构建与发布参数") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 24) {
                                Picker("发布环境", selection: $model.environment) {
                                    ForEach(BinEnvironment.allCases) { env in
                                        Text(env.title).tag(env)
                                    }
                                }
                                .frame(maxWidth: 260)

                                Picker("Configuration", selection: $model.configuration) {
                                    ForEach(BuildConfiguration.allCases) { cfg in
                                        Text(cfg.rawValue).tag(cfg)
                                    }
                                }
                                .frame(maxWidth: 220)
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                                Toggle("构建时使用源码依赖（--code-dependencies）", isOn: $model.codeDependencies)
                                Toggle("保留构建中间产物（--no-clean）", isOn: $model.keepIntermediates)
                                Toggle("跳过 Git Tag 创建/校验（--skip-tag）", isOn: $model.skipTag)
                                Toggle("跳过源码 Spec 推送（--skip-code-spec）", isOn: $model.skipCodeSpec)
                                Toggle("归档时构建缺失依赖（--all-make）", isOn: $model.buildMissingDependencies)
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Button("仅构建二进制 (pod bin archive)") {
                                    model.runArchive()
                                }
                                Button("发布预检 (pod bin publish --dry-run)") {
                                    model.runPublishDryRun()
                                }
                                Spacer()
                                Button("正式发布组件 (pod bin publish)") {
                                    isShowingPublishConfirmation = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Text("正式发布将按序执行：Git 工作区与 Tag 检查 → 推送源码 Spec → 构建真机+模拟器 XCFramework → 上传 ZIP 到 binary-server → 生成并推送二进制 Spec（失败自动回滚）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .confirmationDialog(
                        "确认发布 \(info.name) (\(info.version))？",
                        isPresented: $isShowingPublishConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("确认发布 \(info.name) v\(info.version)") {
                            model.runOfficialPublish()
                        }
                        Button("先执行预检 (--dry-run)") {
                            model.runPublishDryRun()
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("组件：\(info.name)\n版本：\(info.version)\n环境：\(model.environment.title) (\(model.configuration.rawValue))\n制品服务：\(model.binaryServerAddress)")
                    }
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
        .overlay {
            if model.project == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("请选择工作区或组件目录")
                        .font(.title2.bold())
                    Text("从左下角选择包含组件 podspec 或宿主 App 的工作区目录。")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GroupBox("工作区概览") {
                    if let project = model.project {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusRow(
                                title: "宿主 App (Podfile)",
                                value: project.appDirectories.isEmpty
                                    ? "未找到"
                                    : project.appDirectories.map(\.lastPathComponent).joined(separator: ", "),
                                success: !project.appDirectories.isEmpty
                            )
                            StatusRow(
                                title: "Podfile.lock",
                                value: project.hasLockfile ? "已生成" : "未生成",
                                success: project.hasLockfile
                            )
                            StatusRow(
                                title: "可发布组件 (podspec)",
                                value: model.componentPodspecs.isEmpty
                                    ? "未找到"
                                    : model.componentPodspecs.map { "\($0.name) (\($0.version))" }.joined(separator: " · "),
                                success: !model.componentPodspecs.isEmpty
                            )
                            HStack(spacing: 12) {
                                Button("管理 App 依赖与安装") { model.selection = .dependencies }
                                    .disabled(project.appDirectories.isEmpty)
                                Button("管理组件发布") { model.selection = .build }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.componentPodspecs.isEmpty)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 6)
                    } else {
                        EmptyHint(text: "选择工作区根目录（如 ImyBin）、App 目录或组件目录后开始扫描。")
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
            Text("CocoaPods 组件化与二进制工作台")
                .font(.largeTitle.bold())
            Text("一站式管理 App 依赖三态切换安装（local / source / binary）与组件 XCFramework 发布。")
                .foregroundStyle(.secondary)
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
                Text("应用读取登录 shell 环境后直接启动 pod / git，自动识别工作区内的 .imy-infra/home 与本地插件源码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("组件发布与依赖切换") {
                Label("已启用 pod bin publish 事务发布与三态切换", systemImage: "checkmark.shield")
                Text("支持在「组件发布管理」页面递增版本、预检、构建真机+模拟器 XCFramework 并发布至源码/二进制 Spec 仓库与 binary-server，在「App 依赖与安装」页面一键切换 local / source / binary 并安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModeBadge: View {
    let mode: String
    let isOverride: Bool

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        let base: String
        switch mode {
        case "local": base = "LOCAL 本地源码"
        case "source": base = "SOURCE 版本源码"
        case "binary": base = "BINARY 二进制"
        default: base = mode.uppercased()
        }
        return isOverride ? "\(base) · 覆盖" : base
    }

    private var color: Color {
        switch mode {
        case "local": .blue
        case "source": .orange
        case "binary": .green
        default: .secondary
        }
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
