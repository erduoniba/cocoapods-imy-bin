import SwiftUI

@main
struct IMYBinManagerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
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
        }
    }
}
