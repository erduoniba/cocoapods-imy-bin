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
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
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
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let entry: ComponentConfigEntry
    @State private var versionDraft: String = ""
    @State private var isBranchPopoverPresented = false
    @State private var branchDraft = ""
    @State private var gitURLDraft = ""

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
                    } else if let path = entry.path {
                        Text("路径: \(path)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 模式切换 Segmented 控制（去除冗余英文括号，宽度给足，100% 完整展示绝不截断）
            Picker("", selection: Binding(
                get: { entry.mode },
                set: { newMode in
                    if newMode == "branch" {
                        isBranchPopoverPresented = true
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
            .popover(isPresented: $isBranchPopoverPresented) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("配置 \(entry.name) Git 分支源码")
                        .font(.headline)
                    TextField("Git 仓库地址 (如 https://git.xx.com/foo.git)", text: $gitURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    TextField("分支名 (如 feature/dev)", text: $branchDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    HStack {
                        Button("取消") { isBranchPopoverPresented = false }
                        Spacer()
                        Button("应用分支") {
                            model.updateConfigEntryBranch(entry.name, git: gitURLDraft, branch: branchDraft)
                            isBranchPopoverPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(branchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .onAppear {
                    gitURLDraft = entry.git ?? ""
                    branchDraft = entry.branch ?? "main"
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
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
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
                        .font(.caption.monospaced())
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
                            .frame(width: 130)

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
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
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
                    Text("当前窗口专属组件：\(bound)").font(.caption)
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
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let info = activeComponentInfo {
                Text("v\(info.version)")
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                // 反向影响提示
                if let report = model.reverseImpactReport, !report.dependentApps.isEmpty {
                    Text("被 \(report.dependentApps.map(\.name).joined(separator: ", ")) 引用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 快捷打开工具
                HStack(spacing: 4) {
                    Button {
                        if let dir = info.exampleDirectoryURL ?? info.repositoryURL as URL? {
                            _ = WorkspaceOpener.openInXcode(at: dir)
                        }
                    } label: {
                        Label("Xcode", systemImage: "hammer.fill")
                    }
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.selectFile(info.podspecURL.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .controlSize(.small)

                    Button {
                        WorkspaceOpener.openInTerminal(at: info.repositoryURL)
                    } label: {
                        Label("终端", systemImage: "terminal")
                    }
                    .controlSize(.small)
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
                    .font(.headline)
                Spacer()
                Text("当前发布环境: \(model.environment.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 版本号与快捷递增
            HStack(spacing: 12) {
                Text("当前: v\(info.version)").font(.subheadline.bold())

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                TextField("新版本", text: $model.editingComponentVersion)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.monospaced().bold())
                    .frame(width: 100)

                Button("+Patch") {
                    model.bumpEditingVersion(.patch)
                }
                .controlSize(.small)

                Button("+Minor") {
                    model.bumpEditingVersion(.minor)
                }
                .controlSize(.small)

                Button("+Beta") {
                    model.bumpEditingBetaVersion()
                }
                .controlSize(.small)

                if model.editingComponentVersion.contains("-beta") {
                    Button("转正式版") {
                        model.promoteEditingBetaToRelease()
                    }
                    .controlSize(.small)
                }

                Button("应用版本") {
                    model.applyComponentVersionUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // 核心发布开关
            VStack(alignment: .leading, spacing: 8) {
                Toggle("发布前自动提交并推送本地代码（Git commit & push）", isOn: $model.autoCommitAndPushBeforePublish)
                    .font(.subheadline)
                Toggle("构建时下层依赖使用源码（--code-dependencies）", isOn: $model.codeDependencies)
                    .font(.subheadline)

                DisclosureGroup("高级构建与发布参数", isExpanded: $isAdvancedOptionsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("保留构建中间产物（--no-clean）", isOn: $model.keepIntermediates)
                        Toggle("跳过 Git Tag 创建/校验（--skip-tag）", isOn: $model.skipTag)
                        Toggle("跳过源码 Spec 推送（--skip-code-spec）", isOn: $model.skipCodeSpec)
                        Toggle("归档时构建缺失依赖（--all-make）", isOn: $model.buildMissingDependencies)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            // 发布主操作按钮
            HStack(spacing: 12) {
                Button("仅构建二进制 (pod bin archive)") {
                    model.runArchive(for: info.name)
                }
                .disabled(model.isBusy(for: .component(name: info.name)))

                Button("发布预检 (pod bin publish --dry-run)") {
                    model.runPublishDryRun(for: info.name)
                }
                .disabled(model.isBusy(for: .component(name: info.name)))

                Spacer()

                Button {
                    isShowingPublishConfirmation = true
                } label: {
                    Label("正式发布组件 (pod bin publish)", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy(for: .component(name: info.name)))
            }

            // 最近产物展示
            if let artifact = model.latestArtifactReport {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill").foregroundStyle(.tint)
                    Text(artifact.fileURL.lastPathComponent).font(.caption.monospaced())
                    Spacer()
                    Text("体积: \(artifact.formattedSize)").font(.caption.bold()).foregroundStyle(.blue)
                }
                .padding(8)
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
            Label("组件依赖关系 (s.dependency)", systemImage: "link")
                .font(.headline)

            Divider()

            if info.dependencies.isEmpty {
                Text("此组件无外部依赖。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(info.dependencies) { dep in
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                        Text(dep.name).font(.caption.monospaced().bold())
                        if let req = dep.versionRequirement, !req.isEmpty {
                            Text(req).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.removeSelectedPodspecDependency(dep.name)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // 快速添加依赖
            HStack {
                TextField("依赖名 (如 AFNetworking)", text: $newDepName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("版本约束 (如 ~> 0.1.0)", text: $newDepVersion)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Button("添加依赖") {
                    model.addOrUpdateSelectedPodspecDependency(name: newDepName, versionRequirement: newDepVersion)
                    newDepName = ""
                    newDepVersion = ""
                }
                .controlSize(.small)
                .disabled(newDepName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                Text("Shell: \(report.shellPath)").font(.caption.monospaced()).foregroundStyle(.secondary)
                ForEach(report.probes) { probe in
                    HStack {
                        Label(probe.name, systemImage: probe.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(probe.isAvailable ? .green : .red)
                        Spacer()
                        Text(probe.version ?? probe.error ?? "未知")
                            .font(.caption.monospaced())
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
            Text("服务地址: \(model.binaryServerAddress)").font(.caption.monospaced())
            Text("已发布组件: \(model.binaryComponents.count) 个 / \(model.binaryVersionCount) 个版本")
                .font(.subheadline)

            List(model.binaryComponents) { comp in
                HStack {
                    Text(comp.name).font(.headline)
                    Spacer()
                    Text(comp.versions.joined(separator: ", "))
                        .font(.caption.monospaced())
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
