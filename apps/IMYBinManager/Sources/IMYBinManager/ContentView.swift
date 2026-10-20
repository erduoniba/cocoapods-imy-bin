import IMYBinCore
import SwiftUI

// MARK: - Window 1: App 依赖管理工作台

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(AppModel.Page.allCases, selection: $model.selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationTitle("App 依赖工作台")
            .safeAreaInset(edge: .bottom) {
                appWindowFooter
            }
        } detail: {
            Group {
                switch model.selection ?? .overview {
                case .overview:
                    OverviewView()
                case .dependencies:
                    ManagedDependenciesView()
                case .server:
                    BinaryServerView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(model.selection?.title ?? "App 概览")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWindow(id: "component-manager")
                    } label: {
                        Label("组件管理窗口", systemImage: "macwindow.badge.plus")
                    }
                    .help("打开独立的「组件管理与发布工作台」窗口 (⇧⌘2)")
                }
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

    private var appWindowFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let project = model.project {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.rootURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(project.rootURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.toggleWorkspaceFavorite(project.rootURL)
                    } label: {
                        Image(systemName: model.favoriteWorkspaces.contains(where: { $0.url.path == project.rootURL.path }) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("收藏此工程")
                }

                HStack(spacing: 8) {
                    Label("\(model.hostAppDirectories.count) 个宿主 App", systemImage: "app.badge")
                    Spacer()
                    Label("\(model.componentPodspecs.count) 个组件", systemImage: "shippingbox")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button {
                        model.openHostAppInXcode()
                    } label: {
                        Label("Xcode", systemImage: "hammer.fill")
                    }
                    .controlSize(.small)

                    Button {
                        model.showHostAppInFinder()
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .controlSize(.small)

                    Button {
                        model.openHostAppInTerminal()
                    } label: {
                        Label("终端", systemImage: "terminal")
                    }
                    .controlSize(.small)
                }
            } else {
                Text("尚未选择工作区或 App 工程")
                    .foregroundStyle(.secondary)
            }

            if !model.recentWorkspaces.isEmpty {
                Menu {
                    if !model.favoriteWorkspaces.isEmpty {
                        Section("收藏工程") {
                            ForEach(model.favoriteWorkspaces) { item in
                                Button("★ \(item.name) (\(item.kind.title))") {
                                    model.inspectProject(item.url, navigateToOverview: true)
                                }
                            }
                        }
                    }
                    Section("最近打开") {
                        ForEach(model.recentWorkspaces) { item in
                            Button("\(item.name) (\(item.kind.title))") {
                                model.inspectProject(item.url, navigateToOverview: true)
                            }
                        }
                    }
                } label: {
                    Label("最近工程 (\(model.recentWorkspaces.count))", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
            }

            Button("选择工作区 / App 工程…") { model.selectProject() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            Button {
                openWindow(id: "component-manager")
            } label: {
                Label("打开组件管理窗口…", systemImage: "macwindow.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Window 2: 组件管理与发布工作台

struct ComponentWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(AppModel.ComponentPage.allCases, selection: $model.componentSelection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationTitle("组件管理工作台")
            .safeAreaInset(edge: .bottom) {
                componentWindowFooter
            }
        } detail: {
            Group {
                switch model.componentSelection ?? .dependencies {
                case .dependencies:
                    ComponentDependenciesView()
                case .publish:
                    ComponentPublishView()
                case .logs:
                    LogsView()
                }
            }
            .navigationTitle(model.componentSelection?.title ?? "组件依赖管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWindow(id: "app-manager")
                    } label: {
                        Label("App 依赖窗口", systemImage: "app.badge")
                    }
                    .help("打开「App 依赖管理工作台」窗口 (⇧⌘1)")
                }
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

    private var componentWindowFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let info = model.selectedComponentInfo {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.name) (v\(info.version))")
                            .font(.headline)
                            .lineLimit(1)
                        Text(info.repositoryURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.toggleWorkspaceFavorite(info.repositoryURL)
                    } label: {
                        Image(systemName: model.favoriteWorkspaces.contains(where: { $0.url.path == info.repositoryURL.path }) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("收藏此组件")
                }

                HStack(spacing: 8) {
                    Label("\(info.dependencies.count) 个 podspec 依赖", systemImage: "link")
                    Spacer()
                    Label(info.hasExampleProject ? "含 Example" : "无 Example", systemImage: "hammer")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button {
                        model.openComponentInXcode()
                    } label: {
                        Label("Xcode", systemImage: "hammer.fill")
                    }
                    .controlSize(.small)

                    Button {
                        model.showComponentInFinder()
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .controlSize(.small)

                    Button {
                        model.openComponentInTerminal()
                    } label: {
                        Label("终端", systemImage: "terminal")
                    }
                    .controlSize(.small)
                }
            } else {
                Text("尚未选择组件工程")
                    .foregroundStyle(.secondary)
            }

            if !model.recentWorkspaces.isEmpty {
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
                    Section("最近打开") {
                        ForEach(model.recentWorkspaces) { item in
                            Button("\(item.name) (\(item.kind.title))") {
                                model.inspectProject(item.url, navigateToOverview: false)
                            }
                        }
                    }
                } label: {
                    Label("最近工程 (\(model.recentWorkspaces.count))", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
            }

            Button("选择工作区 / 组件目录…") { model.selectProject() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            Button {
                openWindow(id: "app-manager")
            } label: {
                Label("打开 App 依赖窗口…", systemImage: "app.badge")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - 组件窗口：组件依赖管理页（podspec s.dependency + Example 配置表）

private struct ComponentDependenciesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingScaffoldWizard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("组件自身依赖管理")
                            .font(.largeTitle.bold())
                        Text("管理组件在 .podspec 中对外声明的 s.dependency，以及组件 Example 调试工程的依赖配置表与反向依赖分析。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isShowingScaffoldWizard = true
                    } label: {
                        Label("新建组件…", systemImage: "plus.square.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                ComponentSelectorCard()

                if let info = model.selectedComponentInfo {
                    GroupBox("1. 组件对外依赖声明（\(info.podspecURL.lastPathComponent) 中的 s.dependency）") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("声明该组件编译 XCFramework 及被上层集成时所依赖的下层组件或第三方库。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                TextField("依赖组件名（如 HDStaticPod）", text: $model.newPodspecDepName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 220)

                                let candidateNames = availableDependencyCandidates(excluding: info.name)
                                if !candidateNames.isEmpty {
                                    Menu("选择已有组件") {
                                        ForEach(candidateNames, id: \.name) { item in
                                            Button("\(item.name) (\(item.version))") {
                                                model.newPodspecDepName = item.name
                                                model.newPodspecDepVersion = "~> \(item.version)"
                                            }
                                        }
                                    }
                                    .frame(width: 130)
                                }

                                TextField("版本约束（如 ~> 0.1.11，可留空）", text: $model.newPodspecDepVersion)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 220)

                                Button("添加 / 更新到 podspec") {
                                    model.addOrUpdateSelectedPodspecDependency()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.newPodspecDepName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            Divider()

                            if info.dependencies.isEmpty {
                                EmptyHint(text: "当前 \(info.podspecURL.lastPathComponent) 未声明任何 s.dependency。")
                            } else {
                                ForEach(info.dependencies) { dep in
                                    PodspecDependencyRowView(dep: dep)
                                    if dep.id != info.dependencies.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("2. 组件 Example 调试工程依赖配置表与安装（\(info.name)/Example/.imy-bin-config.json）") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let exampleDir = info.exampleDirectoryURL {
                                HStack(spacing: 8) {
                                    Label(
                                        model.hasSavedComponentConfigTable
                                            ? "已生成 Example 配置表：\(exampleDir.appendingPathComponent(".imy-bin-config.json").path)"
                                            : "待生成 Example 配置表：\(exampleDir.appendingPathComponent(".imy-bin-config.json").path)",
                                        systemImage: model.hasSavedComponentConfigTable ? "checkmark.circle.fill" : "doc.badge.plus"
                                    )
                                    .font(.caption.monospaced())
                                    .foregroundStyle(model.hasSavedComponentConfigTable ? .green : .secondary)
                                    Spacer()
                                    Button("从 podspec 同步依赖") {
                                        model.syncPodspecDependenciesToComponentExampleConfig()
                                    }
                                    .controlSize(.small)
                                    Button("仅保存 Example 配置表") {
                                        _ = model.saveComponentExampleConfigTable()
                                    }
                                    .controlSize(.small)
                                }

                                Divider()

                                HStack(spacing: 12) {
                                    Button("生成 Example 配置表并安装 (pod bin install)") {
                                        model.installComponentExampleDependencies()
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("更新 Example 依赖 (pod bin update)") {
                                        model.updateComponentExampleDependencies()
                                    }
                                    Spacer()
                                    Toggle("切换模式后自动执行 pod bin install", isOn: $model.autoInstallComponentExampleAfterSwitch)
                                        .toggleStyle(.switch)
                                }

                                Divider()

                                if let entries = model.componentConfigTable?.components, !entries.isEmpty {
                                    HStack(spacing: 10) {
                                        Text("Example 依赖全局切换：").font(.subheadline.bold())
                                        Button("全部本地 (local)") { model.switchAllComponentExampleDeps(to: "local") }
                                        Button("全部源码 (source)") { model.switchAllComponentExampleDeps(to: "source") }
                                        Button("全部二进制 (binary)") { model.switchAllComponentExampleDeps(to: "binary") }
                                    }

                                    HStack(spacing: 12) {
                                        TextField("搜索 Example 组件…", text: $model.compSearchText)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 200)

                                        Picker("模式过滤", selection: $model.compModeFilter) {
                                            Text("全部模式").tag("all")
                                            Text("仅 local").tag("local")
                                            Text("仅 source").tag("source")
                                            Text("仅 binary").tag("binary")
                                            Text("仅 branch").tag("branch")
                                            Text("仅未发布二进制").tag("unreleased")
                                        }
                                        .frame(width: 150)
                                    }

                                    Divider()
                                    let filtered = model.filteredComponentExampleEntries
                                    if filtered.isEmpty {
                                        EmptyHint(text: "没有匹配搜索或筛选条件的 Example 依赖组件。")
                                    } else {
                                        ForEach(filtered) { entry in
                                            ComponentExampleDepRowView(
                                                entry: entry,
                                                isDeclaredInPodspec: info.dependencies.contains {
                                                    ($0.name.split(separator: "/").first.map(String.init) ?? $0.name) == entry.name
                                                }
                                            )
                                            if entry.id != filtered.last?.id {
                                                Divider()
                                            }
                                        }
                                    }
                                } else {
                                    EmptyHint(text: "工作区中没有其他可作为下层依赖的组件。")
                                }
                            } else {
                                EmptyHint(text: "当前组件目录下未检测到 Example/Podfile 工程。")
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("3. 反向影响分析（谁依赖了我 / Who Depends On Me）") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("扫描工作区内所有上层组件的 .podspec 与宿主 App 配置表，展示直接依赖当前组件的模块列表。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let report = model.reverseImpactReport, report.totalCount > 0 {
                                HStack {
                                    Label("\(report.dependentComponents.count) 个上层组件，\(report.dependentApps.count) 个宿主 App 依赖本组件", systemImage: "network")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button("级联更新新版本到所有依赖方 (\(info.version))") {
                                        model.cascadeSyncSelectedComponentVersion()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }

                                Divider()

                                if !report.dependentComponents.isEmpty {
                                    Text("依赖本组件的上层组件：").font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(report.dependentComponents) { dep in
                                        HStack {
                                            Label(dep.name, systemImage: "shippingbox")
                                                .font(.headline)
                                            Spacer()
                                            Text("约束: \(dep.currentRequirement ?? "未限制")")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                            Button("查看组件") {
                                                model.focusComponent(dep.name, tab: .dependencies)
                                            }
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                if !report.dependentApps.isEmpty {
                                    Divider()
                                    Text("依赖本组件的宿主 App：").font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(report.dependentApps) { app in
                                        HStack {
                                            Label(app.name, systemImage: "app.badge")
                                                .font(.headline)
                                            Spacer()
                                            Text("版本: \(app.currentRequirement ?? "未锁定")")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } else {
                                EmptyHint(text: "工作区内暂无其他组件或 App 声明依赖 \(info.name)。")
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
        .sheet(isPresented: $isShowingScaffoldWizard) {
            ModuleScaffoldWizardView()
                .environmentObject(model)
        }
    }

    private func availableDependencyCandidates(excluding selfName: String) -> [(name: String, version: String)] {
        var map: [String: String] = [:]
        for spec in model.componentPodspecs where spec.name != selfName {
            map[spec.name] = spec.version
        }
        for remote in model.binaryComponents where remote.name != selfName {
            if map[remote.name] == nil, let latest = remote.versions.first {
                map[remote.name] = latest
            }
        }
        return map.map { (name: $0.key, version: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct PodspecDependencyRowView: View {
    @EnvironmentObject private var model: AppModel
    let dep: PodspecDependency
    @State private var reqDraft: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .foregroundStyle(.tint)
            Text(dep.name)
                .font(.headline)
            TextField("版本约束（可留空）", text: $reqDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 150)
                .onSubmit {
                    model.addOrUpdateSelectedPodspecDependency(name: dep.name, versionRequirement: reqDraft)
                }
            if reqDraft != (dep.versionRequirement ?? "") {
                Button("更新约束") {
                    model.addOrUpdateSelectedPodspecDependency(name: dep.name, versionRequirement: reqDraft)
                }
                .controlSize(.small)
            }
            Spacer()
            Button("移除", role: .destructive) {
                model.removeSelectedPodspecDependency(dep.name)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .onAppear {
            reqDraft = dep.versionRequirement ?? ""
        }
        .onChange(of: dep.versionRequirement) { newValue in
            reqDraft = newValue ?? ""
        }
    }
}

private struct ComponentExampleDepRowView: View {
    @EnvironmentObject private var model: AppModel
    let entry: ComponentConfigEntry
    let isDeclaredInPodspec: Bool
    @State private var versionDraft: String = ""
    @State private var isEditingBranch: Bool = false
    @State private var gitURLDraft: String = ""
    @State private var branchDraft: String = ""
    @State private var remoteBranches: [String] = []
    @State private var isFetchingBranches: Bool = false

    var body: some View {
        let localInfo = model.localPodspecInfo(named: entry.name)
        let remoteVersions = model.publishedVersions(for: entry.name)

        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { model.updateComponentExampleEntryEnabled(entry.name, enabled: $0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.headline)
                        .strikethrough(!entry.enabled)
                    ModeBadge(mode: entry.mode, isOverride: model.hasSavedComponentConfigTable)
                    if isDeclaredInPodspec {
                        Text("podspec 已声明")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("版本:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("版本", text: $versionDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .frame(width: 90)
                        .onSubmit {
                            model.updateComponentExampleEntryVersion(entry.name, to: versionDraft)
                        }
                    if versionDraft != (entry.version ?? "") {
                        Button("保存") {
                            model.updateComponentExampleEntryVersion(entry.name, to: versionDraft)
                        }
                        .controlSize(.mini)
                    }
                    if let localInfo, localInfo.version != entry.version {
                        Button("本地版 (\(localInfo.version))") {
                            versionDraft = localInfo.version
                            model.updateComponentExampleEntryVersion(entry.name, to: localInfo.version)
                        }
                        .controlSize(.mini)
                    }
                    if !remoteVersions.isEmpty {
                        Menu("选已发布版") {
                            ForEach(remoteVersions, id: \.self) { v in
                                Button(v) {
                                    versionDraft = v
                                    model.updateComponentExampleEntryVersion(entry.name, to: v)
                                }
                            }
                        }
                        .controlSize(.mini)
                        .frame(width: 100)
                    }
                    if entry.mode == "branch", let b = entry.branch {
                        Text("分支: \(b)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.purple)
                    } else if let path = entry.path {
                        Text("path: \(path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button("本地") { model.switchComponentExampleDepMode(entry.name, to: "local") }
                .disabled(!entry.supportsLocal || entry.mode == "local")
            Button("源码") { model.switchComponentExampleDepMode(entry.name, to: "source") }
                .disabled(entry.mode == "source")
            Button("二进制") { model.switchComponentExampleDepMode(entry.name, to: "binary") }
                .disabled(entry.mode == "binary")

            Button("远端分支") {
                gitURLDraft = entry.git ?? localInfo?.sourceGit ?? ""
                branchDraft = entry.branch ?? ""
                isEditingBranch = true
            }
            .popover(isPresented: $isEditingBranch) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("配置 \(entry.name) 远端分支").font(.headline)
                    TextField("Git 仓库地址", text: $gitURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                    HStack {
                        TextField("分支名称 (如 feat/login)", text: $branchDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                        if !remoteBranches.isEmpty {
                            Menu("选分支") {
                                ForEach(remoteBranches, id: \.self) { b in
                                    Button(b) { branchDraft = b }
                                }
                            }
                            .frame(width: 80)
                        }
                        Button("拉取远端分支") {
                            isFetchingBranches = true
                            Task {
                                remoteBranches = await model.fetchRemoteBranches(for: gitURLDraft)
                                isFetchingBranches = false
                            }
                        }
                        .disabled(gitURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Button("取消") { isEditingBranch = false }
                        Spacer()
                        Button("切换并保存") {
                            model.updateComponentExampleEntryBranch(entry.name, git: gitURLDraft, branch: branchDraft)
                            isEditingBranch = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(branchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            versionDraft = entry.version ?? ""
        }
        .onChange(of: entry.version) { newValue in
            versionDraft = newValue ?? ""
        }
    }
}

private struct ComponentSelectorCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GroupBox("当前管理的组件（.podspec）") {
            VStack(alignment: .leading, spacing: 12) {
                if model.componentPodspecs.isEmpty {
                    EmptyHint(text: "当前工作区没有找到可管理的组件 podspec。请从左下角选择工作区或组件目录。")
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
                                        Text("\(spec.dependencies.count) 个依赖")
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
    }
}

// MARK: - 组件窗口：组件版本与发布页

private struct ComponentPublishView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingPublishConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("组件版本与发布管理")
                        .font(.largeTitle.bold())
                    Text("管理组件的 podspec 版本号、Git 标签状态、XCFramework 二进制归档与双轨 Spec 发布。")
                        .foregroundStyle(.secondary)
                }

                ComponentSelectorCard()

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
                                Button("Beta +1") {
                                    model.bumpEditingBetaVersion()
                                }
                                .controlSize(.small)
                                Button("转为正式版") {
                                    model.promoteEditingBetaToRelease()
                                }
                                .controlSize(.small)
                            }

                            HStack(spacing: 20) {
                                Toggle("同时更新宿主 App 配置表（.imy-bin-config.json，不修改 Podfile）", isOn: $model.syncVersionToAppPodfile)
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
                                Button("同步当前版本 (\(info.version)) 到宿主 App 配置表") {
                                    model.syncSelectedComponentVersionToPodfile()
                                }
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Label("当前 Git 分支：\(info.gitBranch ?? "未知")", systemImage: "arrow.triangle.branch")
                                    .font(.subheadline.bold())

                                if let branchInfo = model.currentGitBranchInfo {
                                    Menu("切换分支") {
                                        if !branchInfo.localBranches.isEmpty {
                                            Section("本地分支") {
                                                ForEach(branchInfo.localBranches, id: \.self) { branch in
                                                    Button(branch) {
                                                        model.checkoutBranch(branch)
                                                    }
                                                }
                                            }
                                        }
                                        if !branchInfo.remoteBranches.isEmpty {
                                            Section("远端分支") {
                                                ForEach(branchInfo.remoteBranches, id: \.self) { branch in
                                                    Button(branch) {
                                                        model.checkoutBranch(branch)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }

                                Button("拉取最新 (git pull)") {
                                    model.pullCurrentBranch()
                                }
                                .controlSize(.small)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                StatusRow(
                                    title: "Git 工作区状态",
                                    value: info.isGitClean ? "工作区干净（可发布）" : "存在 \(info.dirtyFilesSummary.count) 个未提交文件",
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
                                Toggle("构建时下层依赖使用源码（--code-dependencies）", isOn: $model.codeDependencies)
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

                    if let artifact = model.latestArtifactReport {
                        GroupBox("最新生成的 XCFramework 制品") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(artifact.fileURL.lastPathComponent, systemImage: "archivebox.fill")
                                        .font(.headline)
                                    Spacer()
                                    Text("产物体积: \(artifact.formattedSize)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.blue)
                                }
                                HStack {
                                    Text("SHA-256: \(artifact.sha256)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("复制校验值") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(artifact.sha256, forType: .string)
                                    }
                                    .controlSize(.mini)
                                }
                                Text("文件路径: \(artifact.fileURL.path)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.top, 4)
                        }
                    }

                    GroupBox("组件单元测试 (xcodebuild test)") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("在 Example 调试工程中运行单测")
                                    .font(.headline)
                                Text("执行 xcodebuild test 运行组件测试用例并在控制台查看通过/失败报告。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("运行单元测试") {
                                model.runComponentUnitTest()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(info.exampleDirectoryURL == nil)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
    }
}

// MARK: - App 窗口页面

private struct BinaryServerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

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
                                        Button("在组件窗口管理…") {
                                            model.focusComponent(component.name, tab: .publish)
                                            openWindow(id: "component-manager")
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
                    Text("App 依赖配置表与安装")
                        .font(.largeTitle.bold())
                    Text("由 IMYBinManager 生成配置表（.imy-bin-config.json）驱动安装，保持 Podfile 零修改，彻底避免多人协作时的 Podfile 冲突。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("宿主 App 与配置表操作") {
                    VStack(alignment: .leading, spacing: 12) {
                        let hostApps = model.hostAppDirectories
                        if !hostApps.isEmpty {
                            HStack {
                                Picker("宿主 App 目录", selection: $model.selectedAppDirectory) {
                                    ForEach(hostApps, id: \.self) { dir in
                                        Text("\(dir.lastPathComponent) (\(dir.path))").tag(Optional(dir))
                                    }
                                }
                                Button("刷新") { model.refreshProject() }
                            }
                            if let configURL = model.configTableFileURL {
                                HStack(spacing: 8) {
                                    Label(
                                        model.hasSavedConfigTable ? "已生成配置表：\(configURL.path)" : "待生成配置表：\(configURL.path)",
                                        systemImage: model.hasSavedConfigTable ? "checkmark.circle.fill" : "doc.badge.plus"
                                    )
                                    .font(.caption.monospaced())
                                    .foregroundStyle(model.hasSavedConfigTable ? .green : .secondary)
                                    Spacer()
                                    Button("仅保存配置表") { _ = model.saveConfigTable() }
                                        .controlSize(.small)
                                }
                            }
                        } else {
                            EmptyHint(text: "当前工作区未检测到包含 Podfile 的宿主 App 目录。")
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button("生成配置表并安装 (pod bin install)") { model.saveConfigTableAndInstall() }
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

                GroupBox("组件依赖配置表（.imy-bin-config.json）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let entries = model.configTable?.components, !entries.isEmpty {
                            HStack(spacing: 10) {
                                Text("全局模式：").font(.subheadline.bold())
                                Button("全部本地 (local)") { model.switchAllComponents(to: "local") }
                                Button("全部源码 (source)") { model.switchAllComponents(to: "source") }
                                Button("全部二进制 (binary)") { model.switchAllComponents(to: "binary") }
                                Spacer()
                                Button("重置为默认二进制 (--reset)") { model.resetComponentModes() }
                            }

                            HStack(spacing: 12) {
                                TextField("搜索组件依赖…", text: $model.appSearchText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 240)

                                Picker("模式过滤", selection: $model.appModeFilter) {
                                    Text("全部模式").tag("all")
                                    Text("仅 local").tag("local")
                                    Text("仅 source").tag("source")
                                    Text("仅 binary").tag("binary")
                                    Text("仅 branch").tag("branch")
                                    Text("仅未发布二进制").tag("unreleased")
                                }
                                .frame(width: 160)

                                Spacer()

                                Button("导出快照…") {
                                    let panel = NSSavePanel()
                                    panel.title = "导出配置表快照"
                                    panel.nameFieldStringValue = "\(model.selectedAppDirectory?.lastPathComponent ?? "app")-config-\(Int(Date().timeIntervalSince1970)).imy-config.json"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        model.exportCurrentConfigTable(to: url)
                                    }
                                }
                                .controlSize(.small)

                                Button("导入快照…") {
                                    let panel = NSOpenPanel()
                                    panel.title = "选择配置表快照文件"
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    panel.canChooseFiles = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        model.importConfigTable(from: url)
                                    }
                                }
                                .controlSize(.small)
                            }

                            Divider()
                            let filtered = model.filteredConfigEntries
                            if filtered.isEmpty {
                                EmptyHint(text: "没有匹配搜索或筛选条件的组件。")
                            } else {
                                ForEach(filtered) { entry in
                                    ComponentConfigRowView(entry: entry)
                                    if entry.id != filtered.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        } else {
                            EmptyHint(text: "当前 App 尚未配置组件依赖。")
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("服务端策略快照与云端共享") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("平台工程标识", text: $model.managedProjectKey)
                            Button("推送当前配置到服务端") {
                                model.pushPolicyToServer()
                            }
                            .controlSize(.small)
                        }
                        HStack {
                            TextField("策略版本 Revision", text: $model.managedPolicyRevision)
                            Button("从服务端拉取并应用") {
                                model.pullPolicyFromServer(revision: model.managedPolicyRevision)
                            }
                            .controlSize(.small)
                            .disabled(model.managedPolicyRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        HStack {
                            Button("执行 CLI 策略同步 (pod bin sync)") { model.runPolicySync() }
                            Spacer()
                            Text("认证令牌从 IMY_BIN_PLATFORM_TOKEN 环境变量读取。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let error = model.managedPolicyError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(24)
        }
        .disabled(model.project == nil || model.isRunning)
    }
}

private struct ComponentConfigRowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let entry: ComponentConfigEntry
    @State private var versionDraft: String = ""
    @State private var isEditingBranch: Bool = false
    @State private var gitURLDraft: String = ""
    @State private var branchDraft: String = ""
    @State private var remoteBranches: [String] = []
    @State private var isFetchingBranches: Bool = false

    var body: some View {
        let localInfo = model.localPodspecInfo(named: entry.name)
        let remoteVersions = model.publishedVersions(for: entry.name)

        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { model.updateConfigEntryEnabled(entry.name, enabled: $0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.headline)
                        .strikethrough(!entry.enabled)
                    ModeBadge(mode: entry.mode, isOverride: model.hasSavedConfigTable)
                    if let ver = entry.version, !ver.isEmpty, model.binaryServerCheckedAt != nil {
                        let available = model.isVersionPublished(componentName: entry.name, version: ver)
                        Text(available ? "二进制已就绪" : "二进制未发布")
                            .font(.caption2)
                            .foregroundStyle(available ? .green : .orange)
                    }
                }

                HStack(spacing: 8) {
                    Text("配置版本:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("版本", text: $versionDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .frame(width: 90)
                        .onSubmit {
                            model.updateConfigEntryVersion(entry.name, to: versionDraft)
                        }
                    if versionDraft != (entry.version ?? "") {
                        Button("保存版本") {
                            model.updateConfigEntryVersion(entry.name, to: versionDraft)
                        }
                        .controlSize(.mini)
                    }
                    if let localInfo, localInfo.version != entry.version {
                        Button("用本地版 (\(localInfo.version))") {
                            versionDraft = localInfo.version
                            model.syncConfigVersionFromLocalPodspec(entry.name)
                        }
                        .controlSize(.mini)
                    }
                    if !remoteVersions.isEmpty {
                        Menu("选已发布版本") {
                            ForEach(remoteVersions, id: \.self) { v in
                                Button(v) {
                                    versionDraft = v
                                    model.updateConfigEntryVersion(entry.name, to: v)
                                }
                            }
                        }
                        .controlSize(.mini)
                        .frame(width: 110)
                    }
                    if entry.mode == "branch", let b = entry.branch {
                        Text("分支: \(b)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.purple)
                    } else if let path = entry.path {
                        Text("path: \(path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button("本地") { model.switchLocalComponent(entry.name, to: "local") }
                .disabled(!entry.supportsLocal || entry.mode == "local")
            Button("源码") { model.switchLocalComponent(entry.name, to: "source") }
                .disabled(entry.mode == "source")
            Button("二进制") { model.switchLocalComponent(entry.name, to: "binary") }
                .disabled(entry.mode == "binary")

            Button("远端分支") {
                gitURLDraft = entry.git ?? localInfo?.sourceGit ?? ""
                branchDraft = entry.branch ?? ""
                isEditingBranch = true
            }
            .popover(isPresented: $isEditingBranch) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("配置 \(entry.name) 远端分支").font(.headline)
                    TextField("Git 仓库地址", text: $gitURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                    HStack {
                        TextField("分支名称 (如 feat/login)", text: $branchDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                        if !remoteBranches.isEmpty {
                            Menu("选分支") {
                                ForEach(remoteBranches, id: \.self) { b in
                                    Button(b) { branchDraft = b }
                                }
                            }
                            .frame(width: 80)
                        }
                        Button("拉取远端分支") {
                            isFetchingBranches = true
                            Task {
                                remoteBranches = await model.fetchRemoteBranches(for: gitURLDraft)
                                isFetchingBranches = false
                            }
                        }
                        .disabled(gitURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Button("取消") { isEditingBranch = false }
                        Spacer()
                        Button("切换并保存") {
                            model.updateConfigEntryBranch(entry.name, git: gitURLDraft, branch: branchDraft)
                            isEditingBranch = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(branchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
            }

            if localInfo != nil {
                Button("组件窗口…") {
                    model.focusComponent(entry.name, tab: .dependencies)
                    openWindow(id: "component-manager")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            versionDraft = entry.version ?? ""
        }
        .onChange(of: entry.version) { newValue in
            versionDraft = newValue ?? ""
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GroupBox("工作区概览") {
                    if let project = model.project {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusRow(
                                title: "宿主 App (Podfile)",
                                value: model.hostAppDirectories.isEmpty
                                    ? "未找到"
                                    : model.hostAppDirectories.map(\.lastPathComponent).joined(separator: ", "),
                                success: !model.hostAppDirectories.isEmpty
                            )
                            StatusRow(
                                title: "App 依赖配置表 (.imy-bin-config.json)",
                                value: model.hasSavedConfigTable ? "已生成（Podfile 免修改）" : "未生成（将在安装或切换时自动生成）",
                                success: true
                            )
                            StatusRow(
                                title: "Podfile.lock",
                                value: project.hasLockfile ? "已生成" : "未生成",
                                success: project.hasLockfile
                            )
                            StatusRow(
                                title: "可管理组件 (podspec)",
                                value: model.componentPodspecs.isEmpty
                                    ? "未找到"
                                    : model.componentPodspecs.map { "\($0.name) (\($0.version))" }.joined(separator: " · "),
                                success: !model.componentPodspecs.isEmpty
                            )
                            HStack(spacing: 12) {
                                Button("管理 App 配置表与安装") { model.selection = .dependencies }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.hostAppDirectories.isEmpty)
                                Button("在独立窗口打开组件管理与发布…") {
                                    openWindow(id: "component-manager")
                                }
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
            Text("CocoaPods App 依赖工作台")
                .font(.largeTitle.bold())
            Text("基于 .imy-bin-config.json 配置表驱动宿主 App 依赖安装（零 Podfile 冲突）；组件自身的依赖与发布请在独立的「组件管理工作台」窗口操作。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
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

                TextField("搜索日志…", text: $model.logSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Picker("过滤", selection: $model.logFilterMode) {
                    ForEach(LogFilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 130)

                Button("复制日志") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log, forType: .string)
                }
                .controlSize(.small)

                Button("导出…") {
                    let panel = NSSavePanel()
                    panel.title = "导出任务运行日志"
                    panel.nameFieldStringValue = "task-\(Int(Date().timeIntervalSince1970)).log"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? model.log.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                .controlSize(.small)

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
    @State private var selectedComponentForClean: String = ""

    var body: some View {
        Form {
            Section("Spec 仓库与缓存维护中心") {
                HStack(spacing: 12) {
                    Button("更新二进制 Spec 仓库 (pod bin repo update)") {
                        model.runRepoUpdate()
                    }
                    Button("更新全部 Spec 仓库 (pod repo update)") {
                        model.runRepoUpdate(all: true)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("组件缓存清理（清理 Pods 目录与 CocoaPods 本机缓存）").font(.subheadline.bold())
                    HStack {
                        let names = model.componentPodspecs.map(\.name)
                        if !names.isEmpty {
                            Picker("选择组件", selection: $selectedComponentForClean) {
                                Text("请选择组件").tag("")
                                ForEach(names, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .frame(width: 200)

                            Button("清理组件缓存") {
                                model.cleanComponentCache(named: selectedComponentForClean)
                            }
                            .disabled(selectedComponentForClean.isEmpty)
                        } else {
                            Text("未发现可管理的组件。").foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("全局缓存清理与体积统计").font(.subheadline.bold())
                    HStack(spacing: 16) {
                        Button("清理 CocoaPods 全量缓存 (pod cache clean --all)") {
                            model.runCleanCocoaPodsCache()
                        }
                    }
                    HStack {
                        LabeledContent("Xcode DerivedData 体积", value: CacheManager.formatBytes(model.derivedDataSize))
                        Button("清理 DerivedData") {
                            model.cleanDerivedData()
                        }
                        .controlSize(.small)
                    }
                    HStack {
                        LabeledContent("tmpRelease 二进制构建缓存", value: CacheManager.formatBytes(model.tmpReleaseSize))
                        Button("清理 tmpRelease") {
                            model.cleanTmpRelease()
                        }
                        .controlSize(.small)
                    }
                    Button("刷新缓存体积统计") {
                        model.refreshCacheSizes()
                    }
                    .controlSize(.small)
                }
            }

            Section("双窗口架构") {
                Label("App 依赖工作台 与 组件管理工作台 独立分窗", systemImage: "macwindow.on.rectangle")
                Text("• App 依赖工作台窗口（⇧⌘1）：管理宿主 App 的 .imy-bin-config.json 配置表与安装。\n• 组件管理与发布工作台窗口（⇧⌘2）：管理组件自身的 podspec s.dependency、组件 Example 调试配置表以及组件版本发布。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("执行方式") {
                LabeledContent("登录 Shell", value: model.toolchain?.shellPath ?? "检测中")
                Text("应用读取登录 shell 环境后直接启动 pod / git，自动识别工作区内的 .imy-infra/home 与本地插件源码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("配置表驱动安装（防止 Podfile 冲突）") {
                Label("通过 .imy-bin-config.json 管理组件版本、模式与本地路径", systemImage: "tablecells.badge.ellipsis")
                Text("宿主 App 与组件 Example 的 Podfile 只需声明 `imy_bin_config_dependencies`，无需写死组件版本号或本地路径。升级版本或切换 local / source / binary 时仅更新 .imy-bin-config.json，不再修改 Podfile。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshCacheSizes()
            if let first = model.componentPodspecs.first?.name {
                selectedComponentForClean = first
            }
        }
    }
}

private struct ModuleScaffoldWizardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isStaticFramework: Bool = true
    @State private var deploymentTarget: String = "15.0"
    @State private var author: String = NSFullUserName()
    @State private var summary: String = "A modular CocoaPods component built for XCFramework distribution."
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "plus.square.dashed")
                        .font(.title)
                        .foregroundStyle(.tint)
                    Text("新建 CocoaPods 二进制组件向导")
                        .font(.title2.bold())
                }
                Text("一键生成标准的二进制组件目录架构：包含 podspec 规格、Classes 源码骨架、接入 imy_bin_config_dependencies 的 Example 调试工程及 Git 仓库初始化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("组件名称（如 HDCommonUI）:", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("组件包架构:", selection: $isStaticFramework) {
                    Text("静态库 XCFramework (推荐，避免动态库启动开销)").tag(true)
                    Text("动态库 XCFramework").tag(false)
                }

                TextField("iOS 部署版本:", text: $deploymentTarget)
                    .textFieldStyle(.roundedBorder)

                TextField("作者名称:", text: $author)
                    .textFieldStyle(.roundedBorder)

                TextField("组件简要描述:", text: $summary)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") {
                    dismiss()
                }
                Spacer()
                Button("创建组件") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        errorMessage = "组件名称不能为空"
                        return
                    }
                    guard trimmed.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                        errorMessage = "组件名称必须以英文字母开头，且只包含字母、数字和下划线"
                        return
                    }

                    let options = ModuleScaffoldOptions(
                        name: trimmed,
                        isStaticFramework: isStaticFramework,
                        deploymentTarget: deploymentTarget,
                        author: author,
                        summary: summary
                    )
                    model.createNewModule(options: options)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
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
        return isOverride ? "\(base) · 配置表" : base
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
