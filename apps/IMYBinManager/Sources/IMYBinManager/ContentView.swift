import IMYBinCore
import SwiftUI

// MARK: - Window 1: App 依赖管理工作台 (参考 MTool 极简一屏式交互)

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部操作栏（工程切换、Xcode/Finder/Terminal 联动、一键安装、更新、工具箱）
            AppTopBar()

            Divider()

            // 2. 次顶部控制栏（搜索过滤、模式筛选分段、全量快速切换）
            AppFilterBar()

            Divider()

            // 3. 核心主体：组件依赖列表
            ComponentConfigTableView()

            Divider()

            // 4. 底部控制台日志抽屉（折叠为状态条，运行/展开时显示终端控制台）
            ConsoleDrawer(
                scope: .app,
                isExpanded: $model.isAppLogDrawerExpanded
            )
        }
        .sheet(isPresented: $model.isToolboxSheetPresented) {
            ToolboxSheetView()
                .frame(minWidth: 720, minHeight: 540)
        }
        .alert(
            model.appAlert?.title ?? "提示",
            isPresented: Binding(
                get: { model.appAlert != nil },
                set: { if !$0 { model.appAlert = nil } }
            ),
            presenting: model.appAlert
        ) { alert in
            if alert.isError {
                Button("查看日志") {
                    model.isAppLogDrawerExpanded = true
                    model.appAlert = nil
                }
                Button("关闭", role: .cancel) {
                    model.appAlert = nil
                }
            } else {
                Button("确定", role: .cancel) {
                    model.appAlert = nil
                }
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

// MARK: - App 顶部工具栏 (AppTopBar)

private struct AppTopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            // 左侧：工程选择下拉菜单
            Menu {
                if !model.favoriteWorkspaces.isEmpty {
                    Section("收藏工程") {
                        ForEach(model.favoriteWorkspaces) { item in
                            Button("★ \(item.name) (\(item.kind.title))") {
                                model.inspectProject(item.url, navigateToOverview: false)
                            }
                        }
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Section("最近打开") {
                        ForEach(model.recentWorkspaces) { item in
                            Button("\(item.name) (\(item.kind.title))") {
                                model.inspectProject(item.url, navigateToOverview: false)
                            }
                        }
                    }
                }
                Divider()
                Button("选择新工作区 / App 工程…") {
                    model.selectProject()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .foregroundStyle(Color.accentColor)
                    Text(model.project?.rootURL.lastPathComponent ?? "未选择工程")
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let project = model.project {
                Button {
                    model.toggleWorkspaceFavorite(project.rootURL)
                } label: {
                    Image(systemName: model.favoriteWorkspaces.contains(where: { $0.url.path == project.rootURL.path }) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .help("收藏此工程")
            }

            // 多宿主 App 切换
            if model.hostAppDirectories.count > 1 {
                Picker("", selection: $model.selectedAppDirectory) {
                    ForEach(model.hostAppDirectories, id: \.self) { dir in
                        Text(dir.lastPathComponent).tag(Optional(dir))
                    }
                }
                .frame(maxWidth: 160)
            }

            // 快捷打开工具：Xcode, Finder, Terminal
            HStack(spacing: 4) {
                Button {
                    model.openHostAppInXcode()
                } label: {
                    Label("Xcode", systemImage: "hammer.fill")
                }
                .controlSize(.small)
                .help("用 Xcode 打开宿主工程 workspace")

                Button {
                    model.showHostAppInFinder()
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .controlSize(.small)
                .help("在 Finder 中显示工程目录")

                Button {
                    model.openHostAppInTerminal()
                } label: {
                    Label("终端", systemImage: "terminal")
                }
                .controlSize(.small)
                .help("在终端中打开工程目录")
            }

            Spacer()

            // 右侧核心主操作（一键安装、更新、工具箱、组件管理）
            HStack(spacing: 8) {
                Button {
                    model.saveConfigTableAndInstall()
                } label: {
                    Label("一键安装 (pod bin install)", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.hostAppDirectories.isEmpty || model.isRunning)
                .help("保存配置表并安装 CocoaPods 依赖 (⌘R)")

                Button {
                    model.runUpdate()
                } label: {
                    Label("更新依赖", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.hostAppDirectories.isEmpty || model.isRunning)
                .help("执行 pod bin update")

                Button {
                    model.isToolboxSheetPresented = true
                } label: {
                    Label("工具箱", systemImage: "wrench.and.screwdriver")
                }
                .help("缓存清理、Spec仓库更新、策略云端同步、工具链检查")

                Menu {
                    Button("打开通用组件工作台") {
                        openWindow(id: "component-manager")
                    }
                    if !model.componentPodspecs.isEmpty {
                        Divider()
                        ForEach(model.componentPodspecs) { spec in
                            Button("打开 \(spec.name) 专属工作台") {
                                openWindow(id: "component-window", value: spec.name)
                            }
                        }
                    }
                } label: {
                    Label("组件工作台", systemImage: "shippingbox.fill")
                }
                .help("打开独立的组件管理与发布窗口 (⇧⌘2)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - App 过滤与快捷操作栏 (AppFilterBar)

private struct AppFilterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索组件名称…", text: $model.appSearchText)
                    .textFieldStyle(.plain)
                if !model.appSearchText.isEmpty {
                    Button {
                        model.appSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 220)

            // 模式过滤 Segment
            Picker("模式过滤", selection: $model.appModeFilter) {
                Text("全部 (\(totalCount))").tag("all")
                Text("本地 (\(localCount))").tag("local")
                Text("源码 (\(sourceCount))").tag("source")
                Text("二进制 (\(binaryCount))").tag("binary")
                Text("分支 (\(branchCount))").tag("branch")
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 420, maxWidth: 480)

            Spacer()

            // 批量切换快捷操作
            HStack(spacing: 6) {
                Text("批量切换:").font(.subheadline).foregroundStyle(.secondary)
                Button("全转本地") { model.switchAllComponents(to: "local") }
                    .controlSize(.regular)
                Button("全转源码") { model.switchAllComponents(to: "source") }
                    .controlSize(.regular)
                Button("全转二进制") { model.switchAllComponents(to: "binary") }
                    .controlSize(.regular)
                Button("重置") { model.resetComponentModes() }
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var totalCount: Int {
        model.configTable?.components.count ?? 0
    }
    private var localCount: Int {
        model.configTable?.components.filter { $0.mode == "local" }.count ?? 0
    }
    private var sourceCount: Int {
        model.configTable?.components.filter { $0.mode == "source" }.count ?? 0
    }
    private var binaryCount: Int {
        model.configTable?.components.filter { $0.mode == "binary" }.count ?? 0
    }
    private var branchCount: Int {
        model.configTable?.components.filter { $0.mode == "branch" }.count ?? 0
    }
}

// MARK: - 组件依赖列表主体 (ComponentConfigTableView)

private struct ComponentConfigTableView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.project == nil {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("请选择工作区根目录（如 ImyBin）或 App 目录")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button("打开工程…") {
                        model.selectProject()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entries = model.configTable?.components, !entries.isEmpty {
                let filtered = model.filteredConfigEntries
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("没有匹配当前筛选条件的组件")
                            .foregroundStyle(.secondary)
                        Button("清除搜索与筛选") {
                            model.appSearchText = ""
                            model.appModeFilter = "all"
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { entry in
                                ComponentConfigCard(entry: entry)
                            }
                        }
                        .padding(16)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("当前 App 尚未配置组件依赖表")
                        .font(.headline)
                    Text("点击「生成配置表并安装」可自动识别工作区组件并生成 .imy-bin-config.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("生成配置表并安装") {
                        model.saveConfigTableAndInstall()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}

// MARK: - 极简单行组件依赖卡片 (ComponentConfigCard)

private struct ComponentConfigCard: View {
    enum ModeConfigSheet: String, Identifiable {
        case branch
        case local

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let entry: ComponentConfigEntry
    @State private var activeModeConfig: ModeConfigSheet?
    @State private var versionDraft: String = ""
    @State private var branchDraft = ""
    @State private var gitURLDraft = ""
    @State private var localPathDraft = ""

    var body: some View {
        let localInfo = model.localPodspecInfo(named: entry.name)
        let remoteVersions = model.publishedVersions(for: entry.name)
        let isPublished = entry.version != nil && model.isVersionPublished(componentName: entry.name, version: entry.version!)

        HStack(alignment: .center, spacing: 14) {
            // 启用勾选
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { model.updateConfigEntryEnabled(entry.name, enabled: $0) }
            ))
            .labelsHidden()

            // 组件名称与版本信息
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .strikethrough(!entry.enabled)

                    // 状态 Badge
                    if isPublished {
                        HStack(spacing: 3) {
                            Circle().fill(.green).frame(width: 7, height: 7)
                            Text("二进制已发布").font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                        }
                    } else if entry.mode == "binary" {
                        HStack(spacing: 3) {
                            Circle().fill(.orange).frame(width: 7, height: 7)
                            Text("二进制未发布").font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("版本:")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Text("v\(entry.version ?? localInfo?.version ?? "未知")")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))

                    if let localInfo, localInfo.version != entry.version {
                        Button("同步本地 v\(localInfo.version)") {
                            model.syncConfigVersionFromLocalPodspec(entry.name)
                        }
                        .controlSize(.small)
                    }

                    if !remoteVersions.isEmpty {
                        Menu {
                            ForEach(remoteVersions, id: \.self) { v in
                                Button("切换至 v\(v)") {
                                    model.updateConfigEntryVersion(entry.name, to: v)
                                }
                            }
                        } label: {
                            Text("历史版本 (\(remoteVersions.count))")
                                .font(.system(size: 12))
                        }
                        .controlSize(.small)
                    }

                    if entry.mode == "branch", let b = entry.branch {
                        Text("分支: \(b)")
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.purple)
                    } else if entry.mode == "local" {
                        HStack(spacing: 4) {
                            Text("本地路径: \(entry.path ?? "未配置")")
                                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(entry.path == nil || entry.path?.isEmpty == true ? .red : .secondary)

                            Button {
                                initLocalPathDraft()
                                activeModeConfig = .local
                            } label: {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help("更改本地组件源码目录")
                        }
                    } else if let path = entry.path {
                        HStack(spacing: 4) {
                            Text("路径: \(path)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)

                            Button {
                                initLocalPathDraft()
                                activeModeConfig = .local
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            .help("配置本地目录并切换为本地")
                        }
                    }
                }
            }

            Spacer()

            // 模式切换 Segmented 控制（去除冗余英文括号，宽度给足，100% 完整展示绝不截断）
            Picker("", selection: Binding(
                get: { entry.mode },
                set: { newMode in
                    if newMode == "branch" {
                        branchDraft = entry.branch ?? "main"
                        gitURLDraft = entry.git ?? ""
                        activeModeConfig = .branch
                    } else if newMode == "local" {
                        initLocalPathDraft()
                        activeModeConfig = .local
                    } else {
                        model.switchLocalComponent(entry.name, to: newMode)
                    }
                }
            )) {
                Text("本地").tag("local")
                Text("源码").tag("source")
                Text("二进制").tag("binary")
                Text("分支").tag("branch")
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .popover(item: $activeModeConfig) { sheet in
                switch sheet {
                case .branch:
                    branchPopoverView
                case .local:
                    localPathPopoverView
                }
            }

            // 跳转到组件工作台发版
            Button {
                openWindow(id: "component-window", value: entry.name)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("在组件工作台管理与发布 \(entry.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var branchPopoverView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置 \(entry.name) Git 分支源码")
                .font(.headline)
            TextField("Git 仓库地址 (如 https://git.xx.com/foo.git)", text: $gitURLDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            TextField("分支名 (如 feature/dev)", text: $branchDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Button("取消") { activeModeConfig = nil }
                Spacer()
                Button("应用分支") {
                    model.updateConfigEntryBranch(entry.name, git: gitURLDraft, branch: branchDraft)
                    activeModeConfig = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(branchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            gitURLDraft = entry.git ?? ""
            branchDraft = entry.branch ?? "main"
        }
    }

    private var localPathPopoverView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("选择 \(entry.name) 本地组件目录")
                        .font(.headline)
                    Text("组件可位于本机任意目录，不要求在同一工作区。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("本地源码目录：")
                    .font(.caption.bold())

                HStack(spacing: 8) {
                    TextField("输入或选择目录路径 (如 /Users/.../\(entry.name) 或 ../\(entry.name))", text: $localPathDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)

                    Button {
                        if let chosen = model.chooseLocalDirectory(for: entry.name, initialPath: localPathDraft) {
                            localPathDraft = chosen
                        }
                    } label: {
                        Label("选择目录…", systemImage: "folder")
                    }
                }

                Button {
                    if let chosen = model.chooseLocalDirectory(for: entry.name, initialPath: localPathDraft) {
                        localPathDraft = chosen
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("打开 Finder 选择 \(entry.name) 目录…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }

            // 路径校验与 Podspec 状态反馈
            let validation = validateLocalPath(localPathDraft)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: validation.statusIcon)
                    .foregroundStyle(validation.statusColor)
                Text(validation.message)
                    .font(.caption)
                    .foregroundStyle(validation.statusColor)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(validation.statusColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 快捷推荐：如果工作区检测到同名组件
            if let detected = model.componentPodspecs.first(where: { $0.name == entry.name }),
               let appDir = model.selectedAppDirectory {
                let detectedRel = ComponentConfigTable.relativePath(from: appDir, to: detected.repositoryURL)
                if localPathDraft != detectedRel && localPathDraft != detected.repositoryURL.path {
                    Button {
                        localPathDraft = detectedRel
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("使用工作区检测到的路径：\(detectedRel)")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }

            Divider()

            HStack {
                Button("取消") {
                    activeModeConfig = nil
                }
                Spacer()
                Button("确定并切换为本地") {
                    model.updateConfigEntryLocalPath(entry.name, path: localPathDraft)
                    activeModeConfig = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(localPathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func initLocalPathDraft() {
        if let p = entry.path, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            localPathDraft = p
        } else if let detected = model.componentPodspecs.first(where: { $0.name == entry.name }),
                  let appDir = model.selectedAppDirectory {
            localPathDraft = ComponentConfigTable.relativePath(from: appDir, to: detected.repositoryURL)
        } else {
            localPathDraft = ""
        }
    }

    private func validateLocalPath(_ path: String) -> (isValid: Bool, message: String, statusIcon: String, statusColor: Color) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "请点击「选择目录…」或输入该组件在本地的根目录路径", "info.circle", .secondary)
        }

        let resolvedURL: URL
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: expanded).standardizedFileURL
        } else if let appDir = model.selectedAppDirectory {
            resolvedURL = appDir.appendingPathComponent(expanded).standardizedFileURL
        } else {
            resolvedURL = URL(fileURLWithPath: expanded).standardizedFileURL
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory)
        guard exists && isDirectory.boolValue else {
            return (false, "目录不存在：\(resolvedURL.path)", "xmark.circle.fill", .red)
        }

        let exactPodspec = resolvedURL.appendingPathComponent("\(entry.name).podspec")
        if FileManager.default.fileExists(atPath: exactPodspec.path) {
            return (true, "已验证：检测到 \(entry.name).podspec", "checkmark.circle.fill", .green)
        }

        if let files = try? FileManager.default.contentsOfDirectory(atPath: resolvedURL.path),
           let otherSpec = files.first(where: { $0.hasSuffix(".podspec") }) {
            return (true, "已验证：检测到规格文件 \(otherSpec)", "checkmark.circle.fill", .green)
        }

        return (true, "提示：目录存在，但未在该层级检测到 .podspec，请确认是否为组件根目录", "exclamationmark.triangle.fill", .orange)
    }
}

// MARK: - 通用底部控制台抽屉 (ConsoleDrawer)

private struct ConsoleDrawer: View {
    @EnvironmentObject private var model: AppModel
    let scope: TaskScope
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 抽屉状态头部栏
            HStack(spacing: 10) {
                // 运行状态指示灯
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 右侧控制按钮
                if isExpanded {
                    HStack(spacing: 8) {
                        // 字体缩放快捷调节
                        HStack(spacing: 2) {
                            Button {
                                model.decreaseConsoleFontSize()
                            } label: {
                                Image(systemName: "textformat.size.smaller")
                            }
                            .controlSize(.small)
                            .help("减小控制台字体")

                            Text("\(Int(model.consoleFontSize))pt")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 32)

                            Button {
                                model.increaseConsoleFontSize()
                            } label: {
                                Image(systemName: "textformat.size.larger")
                            }
                            .controlSize(.small)
                            .help("放大控制台字体")
                        }
                        .padding(.horizontal, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        TextField("搜索日志…", text: $model.logSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(minWidth: 130, idealWidth: 160, maxWidth: 220)

                        Picker("", selection: $model.logFilterMode) {
                            Text("全部日志").tag(LogFilterMode.all)
                            Text("阶段与告警").tag(LogFilterMode.phaseAndWarning)
                            Text("仅看错误").tag(LogFilterMode.errorOnly)
                        }
                        .controlSize(.small)
                        .frame(width: 105)

                        let records = model.taskRecords(for: scope)
                        if !records.isEmpty {
                            Menu("历史 (\(records.count))") {
                                ForEach(records.reversed(), id: \.id) { task in
                                    Button("\(task.title) · \(task.state.title)") {
                                        model.selectTask(task.id, for: scope)
                                    }
                                }
                            }
                            .controlSize(.small)
                        }

                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(logContent, forType: .string)
                        }
                        .controlSize(.small)

                        Button("清屏") {
                            model.clearLog(for: scope)
                        }
                        .controlSize(.small)
                        .disabled(model.isBusy(for: scope) || records.isEmpty)

                        if model.isBusy(for: scope) {
                            Button("取消", role: .destructive) {
                                model.cancelTask(for: scope)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        Text(isExpanded ? "收起日志" : "控制台日志")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.bar)

            // 展开的日志终端内容
            if isExpanded {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(logContent.isEmpty ? "控制台输出将在这里实时显示。" : logContent)
                            .font(.system(size: model.consoleFontSize, weight: .regular, design: .monospaced))
                            .lineSpacing(4)
                            .foregroundStyle(logContent.isEmpty ? .secondary : Color(nsColor: .textColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                            .id("logBottom")
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: logContent) { _ in
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
                .frame(height: 280)
            }
        }
    }

    private var logContent: String {
        model.log(for: scope, mode: model.logFilterMode, query: model.logSearchQuery)
    }

    private var statusColor: Color {
        if model.isBusy(for: scope) {
            return .orange
        }
        if let state = model.selectedTask(for: scope)?.state {
            switch state {
            case .succeeded: return .green
            case .failed: return .red
            case .cancelled, .cancelling: return .orange
            default: return .secondary
            }
        }
        return .green
    }

    private var statusText: String {
        if model.isBusy(for: scope) {
            return "[\(scope.title)] 执行中: \(model.activeTaskTitle(for: scope) ?? "正在处理")"
        }
        if let task = model.selectedTask(for: scope) {
            return "[\(scope.title)] \(task.title) · \(task.state.title)"
        }
        return "[\(scope.title)] 就绪 · 二进制服务: \(model.binaryServerAddress)"
    }
}

// MARK: - Window 2: 组件管理与发布工作台 (ComponentWorkspaceView)

struct ComponentWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var boundComponentName: String? = nil

    private var activeComponentInfo: ComponentPodspecInfo? {
        if let boundComponentName, let info = model.localPodspecInfo(named: boundComponentName) {
            return info
        }
        return model.selectedComponentInfo
    }

    private var activeComponentName: String {
        activeComponentInfo?.name ?? boundComponentName ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部操作栏（组件选择、Xcode/Finder/Terminal、App 窗口跳转）
            ComponentTopBar(boundComponentName: boundComponentName)

            Divider()

            // 2. 主体：发版核心卡片 + 依赖关联卡片
            ScrollView {
                VStack(spacing: 16) {
                    // 常驻可主动关闭的工作台执行状态提示条
                    if let banner = model.componentTaskBanner(for: activeComponentName) {
                        HStack(spacing: 10) {
                            Image(systemName: banner.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(banner.isError ? .red : .green)
                                .font(.system(size: 16))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(banner.title)
                                    .font(.system(size: 13.5, weight: .bold))
                                Text(banner.message)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                model.dismissComponentTaskBanner(for: activeComponentName)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("关闭此提示")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(banner.isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(banner.isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                        )
                    }

                    if let info = activeComponentInfo {
                        // 核心卡片 1：组件版本与发布
                        ComponentPublishCard(info: info)

                        // 核心卡片 2：依赖管理与反向引用
                        ComponentDependenciesCard(info: info)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("未选择组件 podspec")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Button("打开工作区…") {
                                model.selectProject()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            // 3. 底部控制台抽屉
            ConsoleDrawer(
                scope: .component(name: activeComponentName),
                isExpanded: $model.isComponentLogDrawerExpanded
            )
        }
        .onAppear {
            if let boundComponentName, let info = model.localPodspecInfo(named: boundComponentName) {
                model.selectedPodspec = info.podspecURL
            }
        }
        .alert(
            model.componentAlert(for: activeComponentName)?.title ?? "提示",
            isPresented: Binding(
                get: { model.componentAlert(for: activeComponentName) != nil },
                set: { if !$0 { model.dismissComponentAlert(for: activeComponentName) } }
            ),
            presenting: model.componentAlert(for: activeComponentName)
        ) { alert in
            if alert.isError {
                Button("查看日志") {
                    model.isComponentLogDrawerExpanded = true
                    model.dismissComponentAlert(for: activeComponentName)
                }
                Button("关闭", role: .cancel) {
                    model.dismissComponentAlert(for: activeComponentName)
                }
            } else {
                Button("确定", role: .cancel) {
                    model.dismissComponentAlert(for: activeComponentName)
                }
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

// MARK: - 组件顶部工具栏 (ComponentTopBar)

private struct ComponentTopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var boundComponentName: String? = nil

    private var activeComponentInfo: ComponentPodspecInfo? {
        if let boundComponentName, let info = model.localPodspecInfo(named: boundComponentName) {
            return info
        }
        return model.selectedComponentInfo
    }

    var body: some View {
        HStack(spacing: 12) {
            // 组件选择下拉
            Menu {
                if let bound = boundComponentName, !bound.isEmpty {
                    Text("当前窗口专属组件：\(bound)").font(.system(size: 13, weight: .medium))
                    Divider()
                    ForEach(model.componentPodspecs) { spec in
                        if spec.name != bound {
                            Button("打开 \(spec.name) 专属窗口") {
                                openWindow(id: "component-window", value: spec.name)
                            }
                        }
                    }
                } else {
                    ForEach(model.componentPodspecs) { spec in
                        Button(spec.name) {
                            model.selectedPodspec = spec.podspecURL
                        }
                    }
                    Divider()
                    ForEach(model.componentPodspecs) { spec in
                        Button("在专属独立窗口打开 \(spec.name)") {
                            openWindow(id: "component-window", value: spec.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(activeComponentInfo?.name ?? boundComponentName ?? "选择组件")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let info = activeComponentInfo {
                Text("v\(info.version)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())

                // 反向影响提示
                if let report = model.reverseImpactReport, !report.dependentApps.isEmpty {
                    Text("被 \(report.dependentApps.map(\.name).joined(separator: ", ")) 引用")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // 快捷打开工具
                HStack(spacing: 6) {
                    Button {
                        if let dir = info.exampleDirectoryURL ?? info.repositoryURL as URL? {
                            _ = WorkspaceOpener.openInXcode(at: dir)
                        }
                    } label: {
                        Label("Xcode", systemImage: "hammer.fill")
                    }
                    .controlSize(.regular)

                    Button {
                        NSWorkspace.shared.selectFile(info.podspecURL.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .controlSize(.regular)

                    Button {
                        WorkspaceOpener.openInTerminal(at: info.repositoryURL)
                    } label: {
                        Label("终端", systemImage: "terminal")
                    }
                    .controlSize(.regular)
                }

                // 安装依赖快捷按钮组
                HStack(spacing: 4) {
                    Button {
                        model.runComponentInstall(for: info.name)
                    } label: {
                        Label("安装依赖 (pod install)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(model.isBusy(for: .component(name: info.name)))
                    .help("执行 pod bin install 安装下层依赖与 Example 工程依赖")

                    Menu {
                        Button("更新依赖 (pod bin update)") {
                            model.runComponentUpdate(for: info.name)
                        }
                        Divider()
                        Button("重新生成 Example 配置表并安装") {
                            _ = model.saveComponentExampleConfigTable(for: info.name)
                            model.runComponentInstall(for: info.name)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.regular)
                    .frame(width: 28)
                    .disabled(model.isBusy(for: .component(name: info.name)))
                }
            }

            Spacer()

            // 返回 App 依赖窗口
            Button {
                openWindow(id: "app-manager")
            } label: {
                Label("App 依赖窗口 (⇧⌘1)", systemImage: "app.badge")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - 核心卡片 1：组件版本与正式发布 (ComponentPublishCard)

private struct ComponentPublishCard: View {
    @EnvironmentObject private var model: AppModel
    let info: ComponentPodspecInfo
    @State private var isShowingPublishConfirmation = false
    @State private var isAdvancedOptionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("版本与正式发布", systemImage: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("当前发布环境: \(model.environment.title)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 版本号与快捷递增
            HStack(spacing: 12) {
                Text("当前: v\(info.version)")
                    .font(.system(size: 14.5, weight: .bold))

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                TextField("新版本", text: $model.editingComponentVersion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(minWidth: 140, idealWidth: 160, maxWidth: 190)

                Button("+Patch") {
                    model.bumpEditingVersion(.patch)
                }
                .controlSize(.regular)

                Button("+Minor") {
                    model.bumpEditingVersion(.minor)
                }
                .controlSize(.regular)

                Button("+Beta") {
                    model.bumpEditingBetaVersion()
                }
                .controlSize(.regular)

                if model.editingComponentVersion.contains("-beta") {
                    Button("转正式版") {
                        model.promoteEditingBetaToRelease()
                    }
                    .controlSize(.regular)
                }

                Button("应用版本") {
                    model.applyComponentVersionUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            // 核心发布开关
            VStack(alignment: .leading, spacing: 10) {
                Toggle("发布前自动提交并推送本地代码（Git commit & push）", isOn: $model.autoCommitAndPushBeforePublish)
                    .font(.system(size: 14, weight: .medium))
                Toggle("构建时下层依赖使用源码（--code-dependencies）", isOn: $model.codeDependencies)
                    .font(.system(size: 14, weight: .medium))

                DisclosureGroup("高级构建与发布参数", isExpanded: $isAdvancedOptionsExpanded) {
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("保留构建中间产物（--no-clean）", isOn: $model.keepIntermediates)
                        Toggle("跳过 Git Tag 创建/校验（--skip-tag）", isOn: $model.skipTag)
                        Toggle("跳过源码 Spec 推送（--skip-code-spec）", isOn: $model.skipCodeSpec)
                        Toggle("归档时构建缺失依赖（--all-make）", isOn: $model.buildMissingDependencies)
                    }
                    .font(.system(size: 13))
                    .padding(.top, 6)
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Divider()

            // 发布主操作按钮
            HStack(spacing: 12) {
                Button {
                    model.runComponentInstall(for: info.name)
                } label: {
                    Label("安装依赖", systemImage: "arrow.down.circle")
                }
                .controlSize(.regular)
                .disabled(model.isBusy(for: .component(name: info.name)))
                .help("执行 pod bin install 安装下层依赖与 Example 工程依赖")

                Button("仅构建二进制 (pod bin archive)") {
                    model.runArchive(for: info.name)
                }
                .controlSize(.regular)
                .disabled(model.isBusy(for: .component(name: info.name)))

                Button("发布预检 (pod bin publish --dry-run)") {
                    model.runPublishDryRun(for: info.name)
                }
                .controlSize(.regular)
                .disabled(model.isBusy(for: .component(name: info.name)))

                Spacer()

                Button {
                    isShowingPublishConfirmation = true
                } label: {
                    Label("正式发布组件 (pod bin publish)", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.isBusy(for: .component(name: info.name)))
            }

            // 最近产物展示
            if let artifact = model.latestArtifactReport {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill").foregroundStyle(.tint)
                    Text(artifact.fileURL.lastPathComponent).font(.system(size: 13, design: .monospaced))
                    Spacer()
                    Text("体积: \(artifact.formattedSize)").font(.system(size: 13, weight: .bold)).foregroundStyle(.blue)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "确认发布 \(info.name) (v\(info.version))？",
            isPresented: $isShowingPublishConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认发布 \(info.name) v\(info.version)") {
                model.runOfficialPublish(for: info.name)
            }
            Button("先执行预检 (--dry-run)") {
                model.runPublishDryRun(for: info.name)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将按序执行：\(model.autoCommitAndPushBeforePublish ? "自动提交代码并推送远端 → 更新 Tag → " : "")编译 XCFramework → 上传制品到 binary-server → 推送双轨 Spec。")
        }
    }
}

// MARK: - 核心卡片 2：依赖管理与关联 (ComponentDependenciesCard)

private struct ComponentDependenciesCard: View {
    @EnvironmentObject private var model: AppModel
    let info: ComponentPodspecInfo
    @State private var newDepName = ""
    @State private var newDepVersion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("组件依赖关系 (s.dependency)", systemImage: "link")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button {
                    model.runComponentInstall(for: info.name)
                } label: {
                    Label("安装依赖", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isBusy(for: .component(name: info.name)))
                .help("执行 pod bin install 安装下层依赖与 Example 工程依赖")

                Button {
                    model.runComponentUpdate(for: info.name)
                } label: {
                    Label("更新依赖", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.isBusy(for: .component(name: info.name)))

                Text("\(info.dependencies.count) 个声明依赖")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 1. 已声明依赖列表
            if info.dependencies.isEmpty {
                Text("此组件尚未在 \(info.podspecURL.lastPathComponent) 中声明外部依赖。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(info.dependencies) { dep in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(dep.name)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            if let req = dep.versionRequirement, !req.isEmpty {
                                Text(req)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()

                            // 快捷更新版本约束
                            let remoteVersions = model.publishedVersions(for: dep.name)
                            if !remoteVersions.isEmpty {
                                Menu {
                                    ForEach(remoteVersions, id: \.self) { v in
                                        Button("~> \(v)") {
                                            model.addOrUpdatePodspecDependency(for: info.name, name: dep.name, versionRequirement: "~> \(v)")
                                        }
                                    }
                                } label: {
                                    Text("修改版本")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                            }

                            Button(role: .destructive) {
                                model.removePodspecDependency(for: info.name, depName: dep.name)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("从 \(info.podspecURL.lastPathComponent) 移除此依赖")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Divider()

            // 2. 快捷选择可添加组件 (工作区已有组件 + 二进制服务组件)
            let candidates = model.availableDependencyCandidates(excluding: info.name)
            let unaddedCandidates = candidates.filter { cand in
                !info.dependencies.contains(where: {
                    ($0.name.split(separator: "/").first.map(String.init) ?? $0.name) == cand.name
                })
            }

            if !unaddedCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("快捷选择已有组件添加依赖：")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unaddedCandidates) { cand in
                                Button {
                                    newDepName = cand.name
                                    newDepVersion = cand.version.isEmpty ? "" : "~> \(cand.version)"
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(cand.isLocal ? Color.accentColor : Color.green)
                                        Text(cand.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                        if !cand.version.isEmpty {
                                            Text("v\(cand.version)")
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(cand.isLocal ? "本地" : "二进制")
                                            .font(.system(size: 9.5))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(cand.isLocal ? Color.accentColor.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 3. 依赖添加表单 (包含下拉选择菜单与手动输入)
            HStack(spacing: 8) {
                // 下拉选择组件
                Menu {
                    if !unaddedCandidates.isEmpty {
                        Section("工作区与服务已有组件") {
                            ForEach(unaddedCandidates) { cand in
                                Button {
                                    newDepName = cand.name
                                    newDepVersion = cand.version.isEmpty ? "" : "~> \(cand.version)"
                                } label: {
                                    HStack {
                                        Text(cand.name)
                                        if !cand.version.isEmpty {
                                            Text("(v\(cand.version))")
                                        }
                                        Text(cand.isLocal ? "· 工作区本地" : "· 二进制服务")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("清空并手动输入…") {
                        newDepName = ""
                        newDepVersion = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                        Text(newDepName.isEmpty ? "选择已有组件…" : newDepName)
                            .lineLimit(1)
                    }
                }
                .controlSize(.regular)
                .frame(minWidth: 150, maxWidth: 200)

                TextField("或手动输入 (如 AFNetworking)", text: $newDepName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .font(.system(size: 13.5))
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: .infinity)

                TextField("版本约束 (如 ~> 0.1.0)", text: $newDepVersion)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .font(.system(size: 13.5))
                    .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)

                Button("添加依赖") {
                    model.addOrUpdatePodspecDependency(for: info.name, name: newDepName, versionRequirement: newDepVersion)
                    newDepName = ""
                    newDepVersion = ""
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .disabled(newDepName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // 4. Example 调试工程依赖模式管理
            if info.exampleDirectoryURL != nil {
                Divider()
                ComponentExampleDependenciesSection(info: info)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            model.ensureComponentConfigTableLoaded(for: info.name)
        }
        .onChange(of: info.name) { newName in
            model.ensureComponentConfigTableLoaded(for: newName)
        }
    }
}

// MARK: - 组件 Example 调试工程依赖模式 Section

private struct ComponentExampleDependenciesSection: View {
    @EnvironmentObject private var model: AppModel
    let info: ComponentPodspecInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Example 调试工程组件模式 (Example/.imy-bin-config.json)", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button("从 podspec 同步") {
                    model.syncPodspecDependenciesToComponentExampleConfig(for: info.name)
                }
                .controlSize(.small)

                Button("更新依赖 (pod update)") {
                    model.runComponentUpdate(for: info.name)
                }
                .controlSize(.small)
                .disabled(model.isBusy(for: .component(name: info.name)))

                Button("安装依赖 (pod install)") {
                    model.runComponentInstall(for: info.name)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isBusy(for: .component(name: info.name)))
            }

            HStack {
                Text("为当前组件的 Example 演示工程选择依赖模式（本地源码调试或二进制集成）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("切换后自动执行 pod bin install", isOn: $model.autoInstallComponentExampleAfterSwitch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            if let entries = model.componentConfigTable?.components, !entries.isEmpty {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        ComponentExampleDepRow(componentName: info.name, entry: entry)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Example 工程中暂无其他下层依赖组件。在上方添加依赖后，点击「从 podspec 同步」即可在此管理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Example 依赖单项行 (ComponentExampleDepRow)

private struct ComponentExampleDepRow: View {
    enum ModeSheet: String, Identifiable {
        case branch
        case local

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    let componentName: String
    let entry: ComponentConfigEntry

    @State private var activeSheet: ModeSheet?
    @State private var localPathDraft = ""
    @State private var branchDraft = ""
    @State private var gitURLDraft = ""

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { model.updateComponentExampleEntryEnabled(entry.name, enabled: $0, for: componentName) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .strikethrough(!entry.enabled)

                    if let v = entry.version, !v.isEmpty {
                        Text("v\(v)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if entry.mode == "branch", let b = entry.branch {
                    Text("分支: \(b)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.purple)
                } else if entry.mode == "local" {
                    HStack(spacing: 4) {
                        Text("本地路径: \(entry.path ?? "未配置")")
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.path == nil || entry.path?.isEmpty == true ? .red : .secondary)

                        Button {
                            localPathDraft = entry.path ?? ""
                            activeSheet = .local
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("选择本地目录")
                    }
                } else if let path = entry.path {
                    Text("路径: \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("", selection: Binding(
                get: { entry.mode },
                set: { newMode in
                    if newMode == "branch" {
                        branchDraft = entry.branch ?? "main"
                        gitURLDraft = entry.git ?? ""
                        activeSheet = .branch
                    } else if newMode == "local" {
                        localPathDraft = entry.path ?? ""
                        activeSheet = .local
                    } else {
                        model.switchComponentExampleDepMode(entry.name, to: newMode, for: componentName)
                    }
                }
            )) {
                Text("本地").tag("local")
                Text("源码").tag("source")
                Text("二进制").tag("binary")
                Text("分支").tag("branch")
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .popover(item: $activeSheet) { sheet in
                switch sheet {
                case .branch:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("配置 \(entry.name) Git 分支")
                            .font(.headline)
                        TextField("Git 仓库地址", text: $gitURLDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                        TextField("分支名 (如 feature/dev)", text: $branchDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                        HStack {
                            Button("取消") { activeSheet = nil }
                            Spacer()
                            Button("应用") {
                                model.updateComponentExampleEntryBranch(entry.name, git: gitURLDraft, branch: branchDraft)
                                activeSheet = nil
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width: 340)

                case .local:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择 \(entry.name) 本地源码目录")
                            .font(.headline)
                        HStack {
                            TextField("路径 (如 ../\(entry.name))", text: $localPathDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                            Button("浏览…") {
                                if let chosen = model.chooseExampleLocalDirectory(for: entry.name, in: componentName, initialPath: localPathDraft) {
                                    localPathDraft = chosen
                                }
                            }
                        }
                        HStack {
                            Button("取消") { activeSheet = nil }
                            Spacer()
                            Button("确定切换为本地") {
                                model.updateComponentExampleEntryLocalPath(entry.name, path: localPathDraft, for: componentName)
                                activeSheet = nil
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width: 380)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 工具箱弹窗面板 (ToolboxSheetView)

private struct ToolboxSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("工具箱与环境维护", systemImage: "wrench.and.screwdriver.fill")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)

            Divider()

            TabView(selection: $selectedTab) {
                MaintenanceTab()
                    .tabItem { Label("缓存与Spec维护", systemImage: "trash") }
                    .tag(0)

                PolicySyncTab()
                    .tabItem { Label("策略与快照", systemImage: "cloud") }
                    .tag(1)

                ToolchainTab()
                    .tabItem { Label("工具链与环境", systemImage: "terminal") }
                    .tag(2)

                BinaryServerTab()
                    .tabItem { Label("制品服务状态", systemImage: "server.rack") }
                    .tag(3)

                ScaffoldTab()
                    .tabItem { Label("新建组件", systemImage: "plus.square") }
                    .tag(4)
            }
            .padding(16)
        }
    }
}

// MARK: - 工具箱各 Tab

private struct MaintenanceTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var cleanComponent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("私有 Spec 仓库维护").font(.headline)
            HStack(spacing: 12) {
                Button("更新二进制 Spec 仓库 (pod bin repo update)") {
                    model.runRepoUpdate()
                }
                Button("更新全部 Spec 仓库 (pod repo update)") {
                    model.runRepoUpdate(all: true)
                }
            }

            Divider()

            Text("缓存清理").font(.headline)
            HStack(spacing: 12) {
                Button("清理全量 CocoaPods 缓存") {
                    model.runCleanCocoaPodsCache()
                }
                Button("清理 DerivedData (\(ByteCountFormatter.string(fromByteCount: model.derivedDataSize, countStyle: .file)))") {
                    model.cleanDerivedData()
                }
            }

            HStack {
                Picker("按组件清理缓存:", selection: $cleanComponent) {
                    Text("选择组件").tag("")
                    ForEach(model.componentPodspecs) { spec in
                        Text(spec.name).tag(spec.name)
                    }
                }
                .frame(width: 220)

                Button("清理该组件缓存") {
                    model.cleanComponentCache(named: cleanComponent)
                }
                .disabled(cleanComponent.isEmpty)
            }
            Spacer()
        }
    }
}

private struct PolicySyncTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置表快照导出与导入").font(.headline)
            HStack(spacing: 12) {
                Button("导出当前配置表快照…") {
                    let panel = NSSavePanel()
                    panel.title = "导出配置表快照"
                    panel.nameFieldStringValue = "\(model.selectedAppDirectory?.lastPathComponent ?? "app")-config.imy-config.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        model.exportCurrentConfigTable(to: url)
                    }
                }
                Button("导入配置表快照…") {
                    let panel = NSOpenPanel()
                    panel.title = "选择配置表快照文件"
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        model.importConfigTable(from: url)
                    }
                }
            }

            Divider()

            Text("服务端策略同步").font(.headline)
            HStack {
                TextField("工程标识 Key", text: $model.managedProjectKey)
                Button("推送配置到服务端") {
                    model.pushPolicyToServer()
                }
            }
            HStack {
                TextField("策略 Revision", text: $model.managedPolicyRevision)
                Button("拉取并应用策略") {
                    model.pullPolicyFromServer(revision: model.managedPolicyRevision)
                }
                .disabled(model.managedPolicyRevision.isEmpty)
            }
            Spacer()
        }
    }
}

private struct ToolchainTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本机工具链检测").font(.headline)
                Spacer()
                Button("刷新工具链") { model.refreshToolchain() }
            }

            if let report = model.toolchain {
                Text("Shell: \(report.shellPath)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                ForEach(report.probes) { probe in
                    HStack {
                        Label(probe.name, systemImage: probe.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(probe.isAvailable ? .green : .red)
                        Spacer()
                        Text(probe.version ?? probe.error ?? "未知")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }
}

private struct BinaryServerTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("binary-server 制品服务").font(.headline)
                Spacer()
                Button("检测服务") { model.refreshBinaryServer() }
            }
            Text("服务地址: \(model.binaryServerAddress)").font(.system(size: 13, design: .monospaced))
            Text("已发布组件: \(model.binaryComponents.count) 个 / \(model.binaryVersionCount) 个版本")
                .font(.subheadline)

            List(model.binaryComponents) { comp in
                HStack {
                    Text(comp.name).font(.headline)
                    Spacer()
                    Text(comp.versions.joined(separator: ", "))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ScaffoldTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var name: String = ""
    @State private var isStaticFramework: Bool = true
    @State private var deploymentTarget: String = "15.0"
    @State private var author: String = NSFullUserName()
    @State private var summary: String = "A modular CocoaPods component built for XCFramework distribution."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建二进制组件向导").font(.headline)
            TextField("组件名称 (如 HDCommonUI):", text: $name)
            Picker("架构类型:", selection: $isStaticFramework) {
                Text("静态库 XCFramework (推荐)").tag(true)
                Text("动态库 XCFramework").tag(false)
            }
            TextField("iOS 部署版本:", text: $deploymentTarget)
            TextField("作者:", text: $author)
            TextField("描述:", text: $summary)

            HStack {
                Spacer()
                Button("立即生成组件骨架") {
                    let options = ModuleScaffoldOptions(
                        name: name,
                        isStaticFramework: isStaticFramework,
                        deploymentTarget: deploymentTarget,
                        author: author,
                        summary: summary
                    )
                    model.createNewModule(options: options)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
    }
}
