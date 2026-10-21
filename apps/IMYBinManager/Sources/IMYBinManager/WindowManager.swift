import AppKit
import IMYBinCore
import SwiftUI

@MainActor
public enum WindowManager {
    /// 检查 App 依赖管理工作台窗口是否处于打开状态（包含正常可见或最小化到 Dock 中）
    public static func isAppManagerWindowOpen() -> Bool {
        return findAppManagerWindow() != nil
    }

    /// 查找当前打开的 App 依赖管理工作台窗口
    public static func findAppManagerWindow() -> NSWindow? {
        return NSApplication.shared.windows.first { window in
            guard window.styleMask.contains(.titled) else { return false }
            let matches = WorkbenchWindowIdentifier.isAppManagerWindow(
                title: window.title,
                identifier: window.identifier?.rawValue
            )
            guard matches else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    /// 激活已存在的 App 依赖管理窗口；如果未打开，则调用 openWindow 打开新窗口。
    public static func activateOrCreateAppManagerWindow(openWindow: OpenWindowAction) {
        if let window = findAppManagerWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: WorkbenchWindowIdentifier.appManager)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// 检查组件管理与发布工作台窗口是否处于打开状态
    public static func isComponentManagerWindowOpen() -> Bool {
        return findComponentManagerWindow() != nil
    }

    /// 查找当前打开的通用组件管理与发布工作台窗口
    public static func findComponentManagerWindow() -> NSWindow? {
        return NSApplication.shared.windows.first { window in
            guard window.styleMask.contains(.titled) else { return false }
            let matches = WorkbenchWindowIdentifier.isComponentManagerWindow(
                title: window.title,
                identifier: window.identifier?.rawValue
            )
            guard matches else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    /// 激活已存在的组件管理与发布窗口；如果未打开，则调用 openWindow 打开新窗口。
    public static func activateOrCreateComponentManagerWindow(openWindow: OpenWindowAction) {
        if let window = findComponentManagerWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: WorkbenchWindowIdentifier.componentManager)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
