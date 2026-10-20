import SwiftUI

@main
struct IMYBinManagerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("IMY Bin — App 依赖管理工作台", id: "app-manager") {
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
                    openWindow(id: "app-manager")
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])

                Button("打开组件管理与发布窗口") {
                    openWindow(id: "component-manager")
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            }
        }

        Window("IMY Bin — 组件管理与发布工作台", id: "component-manager") {
            ComponentWorkspaceView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}
