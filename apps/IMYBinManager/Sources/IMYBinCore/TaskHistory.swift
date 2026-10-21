import Foundation

public enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case inspect
    case install
    case update
    case archive
    case attachSource
    case publish
    case deleteArtifact
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inspect: "检查工程"
        case .install: "安装依赖"
        case .update: "更新依赖"
        case .archive: "构建二进制"
        case .attachSource: "连接调试源码"
        case .publish: "发布制品"
        case .deleteArtifact: "删除制品"
        case .custom: "自定义任务"
        }
    }
}

public enum TaskState: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        case .queued, .running, .cancelling: false
        }
    }

    public var title: String {
        switch self {
        case .queued: "等待执行"
        case .running: "正在执行"
        case .cancelling: "正在取消"
        case .succeeded: "已完成"
        case .failed: "执行失败"
        case .cancelled: "已取消"
        }
    }
}

public enum TaskEventKind: String, Codable, Sendable {
    case output
    case phase
    case warning
    case error
}

public struct TaskEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: TaskEventKind
    public let message: String
    public let occurredAt: Date

    public init(
        id: UUID = UUID(),
        kind: TaskEventKind,
        message: String,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.occurredAt = occurredAt
    }

    public var renderedText: String {
        switch kind {
        case .output:
            message
        case .phase:
            "\n[阶段] \(message)\n"
        case .warning:
            "\n[警告] \(message)\n"
        case .error:
            "\n[错误] \(message)\n"
        }
    }
}

public enum LogFilterMode: String, CaseIterable, Identifiable, Sendable {
    case all
    case phaseAndWarning
    case errorOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部"
        case .phaseAndWarning: "仅看阶段与警告"
        case .errorOnly: "仅看错误"
        }
    }
}

public enum TaskScope: Codable, Hashable, Sendable {
    case app
    case component(name: String)

    public var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    public var componentName: String? {
        if case .component(let name) = self { return name }
        return nil
    }

    public var title: String {
        switch self {
        case .app: return "App"
        case .component(let name): return name
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app:
            try container.encode("app", forKey: .type)
        case .component(let name):
            try container.encode("component", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "component" {
            let name = try container.decode(String.self, forKey: .name)
            self = .component(name: name)
        } else {
            self = .app
        }
    }
}

public struct TaskRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let scope: TaskScope
    public let kind: TaskKind
    public let title: String
    public let workspaceURL: URL?
    public let displayCommand: String?
    public private(set) var state: TaskState
    public let createdAt: Date
    public private(set) var startedAt: Date?
    public private(set) var finishedAt: Date?
    public private(set) var exitCode: Int32?
    public private(set) var failureSummary: String?
    public private(set) var events: [TaskEvent]

    public init(
        id: UUID = UUID(),
        scope: TaskScope = .app,
        kind: TaskKind,
        title: String? = nil,
        workspaceURL: URL? = nil,
        displayCommand: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.kind = kind
        self.title = title ?? kind.title
        self.workspaceURL = workspaceURL
        self.displayCommand = displayCommand
        self.state = .queued
        self.createdAt = createdAt
        self.events = []
    }

    enum CodingKeys: String, CodingKey {
        case id, scope, kind, title, workspaceURL, displayCommand, state, createdAt, startedAt, finishedAt, exitCode, failureSummary, events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.scope = try container.decodeIfPresent(TaskScope.self, forKey: .scope) ?? .app
        self.kind = try container.decode(TaskKind.self, forKey: .kind)
        self.title = try container.decode(String.self, forKey: .title)
        self.workspaceURL = try container.decodeIfPresent(URL.self, forKey: .workspaceURL)
        self.displayCommand = try container.decodeIfPresent(String.self, forKey: .displayCommand)
        self.state = try container.decode(TaskState.self, forKey: .state)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        self.failureSummary = try container.decodeIfPresent(String.self, forKey: .failureSummary)
        self.events = try container.decode([TaskEvent].self, forKey: .events)
    }

    public var renderedLog: String {
        let command = displayCommand.map { "$ \($0)\n" } ?? ""
        return command + events.map(\.renderedText).joined()
    }

    public func filteredLog(mode: LogFilterMode = .all, query: String = "") -> String {
        let command = displayCommand.map { "$ \($0)\n" } ?? ""
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filteredEvents = events.filter { event in
            switch mode {
            case .all:
                break
            case .phaseAndWarning:
                guard event.kind == .phase || event.kind == .warning else { return false }
            case .errorOnly:
                guard event.kind == .error || event.message.localizedCaseInsensitiveContains("error:") else { return false }
            }

            if !trimmedQuery.isEmpty {
                return event.message.lowercased().contains(trimmedQuery)
            }
            return true
        }

        return command + filteredEvents.map(\.renderedText).joined()
    }

    public func exportLog(to fileURL: URL) throws {
        try renderedLog.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    mutating func transition(to state: TaskState, at date: Date) throws {
        guard Self.canTransition(from: self.state, to: state) else {
            throw TaskHistoryError.invalidTransition(from: self.state, to: state)
        }
        self.state = state
        switch state {
        case .running:
            startedAt = date
        case .succeeded, .failed, .cancelled:
            finishedAt = date
        case .queued, .cancelling:
            break
        }
    }

    mutating func append(_ event: TaskEvent, eventLimit: Int) {
        events.append(event)
        let overflow = events.count - eventLimit
        if overflow > 0 {
            events.removeFirst(overflow)
        }
    }

    mutating func finish(exitCode: Int32, at date: Date) throws {
        self.exitCode = exitCode
        let terminalState: TaskState = state == .cancelling ? .cancelled : (exitCode == 0 ? .succeeded : .failed)
        try transition(to: terminalState, at: date)
    }

    mutating func fail(summary: String, at date: Date) throws {
        failureSummary = summary
        try transition(to: .failed, at: date)
    }

    mutating func cancel(at date: Date) throws {
        try transition(to: .cancelled, at: date)
    }

    private static func canTransition(from: TaskState, to: TaskState) -> Bool {
        switch (from, to) {
        case (.queued, .running), (.queued, .cancelled),
             (.running, .cancelling), (.running, .succeeded), (.running, .failed),
             (.cancelling, .cancelled), (.cancelling, .failed):
            true
        default:
            false
        }
    }
}

public struct TaskHistory: Equatable, Sendable {
    public private(set) var records: [TaskRecord]
    public let maximumRecords: Int
    public let eventLimit: Int
    public let persistenceURL: URL?

    public static let defaultPersistenceURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("IMYBinManager", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent("task_history.json")
    }()

    public init(maximumRecords: Int = 50, eventLimit: Int = 1_000, persistenceURL: URL? = nil) {
        precondition(maximumRecords > 0)
        precondition(eventLimit > 0)
        self.maximumRecords = maximumRecords
        self.eventLimit = eventLimit
        self.persistenceURL = persistenceURL

        if let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path),
           let data = try? Data(contentsOf: persistenceURL),
           let loaded = try? JSONDecoder().decode([TaskRecord].self, from: data) {
            self.records = Array(loaded.filter(\.state.isTerminal).suffix(maximumRecords))
        } else {
            self.records = []
        }
    }

    public var activeTask: TaskRecord? {
        records.first { !$0.state.isTerminal }
    }

    public var isBusy: Bool {
        activeTask != nil
    }

    public func activeTask(for scope: TaskScope) -> TaskRecord? {
        records.first { $0.scope == scope && !$0.state.isTerminal }
    }

    public func isBusy(for scope: TaskScope) -> Bool {
        activeTask(for: scope) != nil
    }

    public func records(for scope: TaskScope) -> [TaskRecord] {
        records.filter { $0.scope == scope }
    }

    public func record(id: UUID) -> TaskRecord? {
        records.first { $0.id == id }
    }

    @discardableResult
    public mutating func enqueue(
        scope: TaskScope = .app,
        kind: TaskKind,
        title: String? = nil,
        workspaceURL: URL? = nil,
        displayCommand: String? = nil,
        createdAt: Date = Date()
    ) throws -> UUID {
        guard !isBusy(for: scope) else { throw TaskHistoryError.activeTaskExists }

        let record = TaskRecord(
            scope: scope,
            kind: kind,
            title: title,
            workspaceURL: workspaceURL,
            displayCommand: displayCommand,
            createdAt: createdAt
        )
        records.append(record)
        pruneFinishedRecords()
        return record.id
    }

    public mutating func start(_ id: UUID, at date: Date = Date()) throws {
        let limit = eventLimit
        try update(id) { record in
            try record.transition(to: .running, at: date)
            record.append(TaskEvent(kind: .phase, message: "任务已开始", occurredAt: date), eventLimit: limit)
        }
    }

    public mutating func requestCancellation(_ id: UUID, at date: Date = Date()) throws {
        let limit = eventLimit
        try update(id) { record in
            try record.transition(to: .cancelling, at: date)
            record.append(TaskEvent(kind: .phase, message: "正在取消任务…", occurredAt: date), eventLimit: limit)
        }
    }

    public mutating func appendOutput(_ message: String, to id: UUID, at date: Date = Date()) throws {
        try appendEvent(TaskEvent(kind: .output, message: message, occurredAt: date), to: id)
    }

    public mutating func appendEvent(_ event: TaskEvent, to id: UUID) throws {
        let limit = eventLimit
        try update(id) { record in
            record.append(event, eventLimit: limit)
        }
    }

    public mutating func finish(_ id: UUID, exitCode: Int32, at date: Date = Date()) throws {
        let limit = eventLimit
        try update(id) { record in
            try record.finish(exitCode: exitCode, at: date)
            let message = record.state == .succeeded
                ? "任务完成，退出码 \(exitCode)"
                : "进程结束，退出码 \(exitCode)"
            record.append(TaskEvent(kind: record.state == .succeeded ? .phase : .error, message: message, occurredAt: date), eventLimit: limit)
        }
        saveToDisk()
    }

    public mutating func fail(_ id: UUID, summary: String, at date: Date = Date()) throws {
        let limit = eventLimit
        try update(id) { record in
            try record.fail(summary: summary, at: date)
            record.append(TaskEvent(kind: .error, message: summary, occurredAt: date), eventLimit: limit)
        }
        saveToDisk()
    }

    public mutating func cancel(_ id: UUID, at date: Date = Date()) throws {
        let limit = eventLimit
        try update(id) { record in
            try record.cancel(at: date)
            record.append(TaskEvent(kind: .phase, message: "任务已取消", occurredAt: date), eventLimit: limit)
        }
        saveToDisk()
    }

    public mutating func clearFinishedRecords() {
        records.removeAll { $0.state.isTerminal }
        saveToDisk()
    }

    public mutating func clearFinishedRecords(for scope: TaskScope) {
        records.removeAll { $0.scope == scope && $0.state.isTerminal }
        saveToDisk()
    }

    private func saveToDisk() {
        guard let persistenceURL else { return }
        do {
            let dir = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Ignore error gracefully
        }
    }

    private mutating func update(_ id: UUID, mutate: (inout TaskRecord) throws -> Void) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw TaskHistoryError.recordNotFound(id)
        }
        try mutate(&records[index])
    }

    private mutating func pruneFinishedRecords() {
        while records.count > maximumRecords,
              let oldestFinished = records.firstIndex(where: { $0.state.isTerminal }) {
            records.remove(at: oldestFinished)
        }
    }
}

public enum TaskHistoryError: LocalizedError, Equatable, Sendable {
    case activeTaskExists
    case recordNotFound(UUID)
    case invalidTransition(from: TaskState, to: TaskState)

    public var errorDescription: String? {
        switch self {
        case .activeTaskExists:
            "已有任务正在执行"
        case .recordNotFound:
            "未找到指定任务"
        case .invalidTransition(let from, let to):
            "任务不能从 \(from.title) 转换为 \(to.title)"
        }
    }
}
