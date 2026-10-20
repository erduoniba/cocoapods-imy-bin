import Foundation

public enum WorkspaceKind: String, Codable, CaseIterable, Sendable {
    case workspace
    case hostApp
    case component

    public var title: String {
        switch self {
        case .workspace: "工作区"
        case .hostApp: "宿主 App"
        case .component: "组件"
        }
    }
}

public struct RecentWorkspace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var name: String
    public var kind: WorkspaceKind
    public var isFavorite: Bool
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        kind: WorkspaceKind = .workspace,
        isFavorite: Bool = false,
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.name = name ?? url.lastPathComponent
        self.kind = kind
        self.isFavorite = isFavorite
        self.lastOpenedAt = lastOpenedAt
    }
}

public final class WorkspaceRegistry: @unchecked Sendable {
    private let storageURL: URL
    private let lock = NSLock()
    private var items: [RecentWorkspace] = []

    public static let defaultStorageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("IMYBinManager", isDirectory: true)
            .appendingPathComponent("recent_workspaces.json")
    }()

    public init(storageURL: URL = WorkspaceRegistry.defaultStorageURL) {
        self.storageURL = storageURL
        load()
    }

    public func allRecents() -> [RecentWorkspace] {
        lock.lock()
        defer { lock.unlock() }
        return items.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.lastOpenedAt > rhs.lastOpenedAt
        }
    }

    public func favorites() -> [RecentWorkspace] {
        lock.lock()
        defer { lock.unlock() }
        return items.filter(\.isFavorite).sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    @discardableResult
    public func addOrUpdate(url: URL, kind: WorkspaceKind = .workspace, name: String? = nil) -> RecentWorkspace {
        lock.lock()
        defer { lock.unlock() }
        let stdURL = url.standardizedFileURL
        let displayName = name ?? url.lastPathComponent
        if let idx = items.firstIndex(where: { $0.url.path == stdURL.path }) {
            items[idx].lastOpenedAt = Date()
            items[idx].name = displayName
            items[idx].kind = kind
            let updated = items[idx]
            save()
            return updated
        } else {
            let record = RecentWorkspace(
                url: stdURL,
                name: displayName,
                kind: kind,
                isFavorite: false,
                lastOpenedAt: Date()
            )
            items.insert(record, at: 0)
            if items.count > 50 {
                items = Array(items.prefix(50))
            }
            save()
            return record
        }
    }

    public func toggleFavorite(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let stdPath = url.standardizedFileURL.path
        if let idx = items.firstIndex(where: { $0.url.path == stdPath }) {
            items[idx].isFavorite.toggle()
            save()
        }
    }

    public func remove(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let stdPath = url.standardizedFileURL.path
        items.removeAll { $0.url.path == stdPath }
        save()
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            items = try JSONDecoder().decode([RecentWorkspace].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Ignore write failures gracefully
        }
    }
}

public enum WorkspaceOpener {
    public static func findXcodeWorkspaceOrProject(in directoryURL: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        let workspaces = contents.filter { $0.pathExtension == "xcworkspace" }
        let nonPodsWorkspaces = workspaces.filter { $0.lastPathComponent != "Pods.xcworkspace" }
        if let preferred = nonPodsWorkspaces.first {
            return preferred
        }
        if let first = workspaces.first {
            return first
        }

        let projects = contents.filter { $0.pathExtension == "xcodeproj" }
        let nonPodsProjects = projects.filter { $0.lastPathComponent != "Pods.xcodeproj" }
        return nonPodsProjects.first ?? projects.first
    }

    @discardableResult
    public static func openInXcode(at directoryURL: URL) -> Bool {
        guard let target = findXcodeWorkspaceOrProject(in: directoryURL) else {
            return runOpenCommand(["-a", "Xcode", directoryURL.path])
        }
        return runOpenCommand([target.path])
    }

    @discardableResult
    public static func showInFinder(at url: URL) -> Bool {
        runOpenCommand(["-R", url.path])
    }

    @discardableResult
    public static func openInTerminal(at directoryURL: URL) -> Bool {
        runOpenCommand(["-a", "Terminal", directoryURL.path])
    }

    private static func runOpenCommand(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
