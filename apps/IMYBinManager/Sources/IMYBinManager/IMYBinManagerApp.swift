import IMYBinCore
import SwiftUI

@main
struct IMYBinManagerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("IMY Bin — App 依赖管理工作台", id: WorkbenchWindowIdentifier.appManager) {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("刷新工具链") {
                    model.refreshToolchain()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("工作台窗口") {
                Button("打开 App 依赖管理窗口") {
                    WindowManager.activateOrCreateAppManagerWindow(openWindow: openWindow)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])

                Button("打开组件管理与发布窗口") {
                    WindowManager.activateOrCreateComponentManagerWindow(openWindow: openWindow)
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                if !model.componentPodspecs.isEmpty {
                    Divider()
                    Menu("打开独立组件窗口") {
                        ForEach(model.componentPodspecs) { spec in
                            Button("打开 \(spec.name) 窗口") {
                                openWindow(id: WorkbenchWindowIdentifier.componentWindow, value: spec.name)
                            }
                        }
                    }
                }
            }
        }

        WindowGroup("IMY Bin — 组件工作台", id: WorkbenchWindowIdentifier.componentWindow, for: String.self) { $componentName in
            ComponentWorkspaceView(boundComponentName: componentName)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)

        Window("IMY Bin — 组件管理与发布工作台", id: WorkbenchWindowIdentifier.componentManager) {
            ComponentWorkspaceView(boundComponentName: nil)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("IMY Bin", systemImage: model.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "shippingbox") {
            VStack(alignment: .leading, spacing: 4) {
                if let project = model.project {
                    Text("工程: \(project.rootURL.lastPathComponent)")
                        .font(.headline)
                } else {
                    Text("未打开工程")
                        .foregroundStyle(.secondary)
                }

                if model.isRunning {
                    Text("执行中: \(model.activeCommandTitle ?? "")")
                        .foregroundStyle(.orange)
                } else {
                    Text("状态: 空闲就绪")
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button("打开 App 依赖管理窗口 (⇧⌘1)") {
                    WindowManager.activateOrCreateAppManagerWindow(openWindow: openWindow)
                }

                Button("打开组件管理与发布窗口 (⇧⌘2)") {
                    WindowManager.activateOrCreateComponentManagerWindow(openWindow: openWindow)
                }

                if !model.componentPodspecs.isEmpty {
                    Menu("打开独立组件窗口") {
                        ForEach(model.componentPodspecs) { spec in
                            Button("打开 \(spec.name) 窗口") {
                                openWindow(id: WorkbenchWindowIdentifier.componentWindow, value: spec.name)
                            }
                        }
                    }
                }

                Divider()

                Button("用 Xcode 打开工程") {
                    model.openHostAppInXcode()
                }
                .disabled(model.project == nil)

                Button("在终端中打开工程") {
                    model.openHostAppInTerminal()
                }
                .disabled(model.project == nil)

                Divider()

                Button("退出 IMY Bin") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
