import Foundation
import Testing
@testable import IMYBinCore

@Test func taskHistoryRecordsSuccessfulTaskAndTrimsOutput() throws {
    var history = TaskHistory(maximumRecords: 2, eventLimit: 3)
    let taskID = try history.enqueue(
        kind: .archive,
        workspaceURL: URL(fileURLWithPath: "/tmp/Demo"),
        displayCommand: "pod bin archive Demo.podspec",
        createdAt: Date(timeIntervalSince1970: 1)
    )

    try history.start(taskID, at: Date(timeIntervalSince1970: 2))
    try history.appendOutput("first\n", to: taskID)
    try history.appendOutput("second\n", to: taskID)
    try history.appendOutput("third\n", to: taskID)
    try history.finish(taskID, exitCode: 0, at: Date(timeIntervalSince1970: 3))

    let record = try #require(history.record(id: taskID))
    #expect(record.kind == .archive)
    #expect(record.state == .succeeded)
    #expect(record.exitCode == 0)
    #expect(record.startedAt == Date(timeIntervalSince1970: 2))
    #expect(record.finishedAt == Date(timeIntervalSince1970: 3))
    #expect(record.events.count == 3)
    #expect(!record.renderedLog.contains("first\n"))
    #expect(record.renderedLog.contains("third\n"))
    #expect(record.renderedLog.contains("$ pod bin archive Demo.podspec"))
}

@Test func taskHistoryPreventsConcurrentTasksAndFinishesCancellation() throws {
    var history = TaskHistory()
    let taskID = try history.enqueue(kind: .install)
    try history.start(taskID)

    #expect(throws: TaskHistoryError.self) {
        try history.enqueue(kind: .update)
    }

    try history.requestCancellation(taskID)
    try history.finish(taskID, exitCode: 130)

    let record = try #require(history.record(id: taskID))
    #expect(record.state == .cancelled)
    #expect(record.exitCode == 130)
    #expect(!history.isBusy)
}

@Test func taskHistoryRejectsInvalidTransitionsAndRetainsRecentRecords() throws {
    var history = TaskHistory(maximumRecords: 2)
    let first = try history.enqueue(kind: .inspect)

    #expect(throws: TaskHistoryError.self) {
        try history.finish(first, exitCode: 0)
    }

    try history.cancel(first)
    let second = try history.enqueue(kind: .install)
    try history.start(second)
    try history.finish(second, exitCode: 0)
    let third = try history.enqueue(kind: .update)

    #expect(history.records.count == 2)
    #expect(history.record(id: first) == nil)
    #expect(history.record(id: second) != nil)
    #expect(history.record(id: third) != nil)
}

@Test func taskHistoryIsolatesLogsBetweenAppAndComponents() throws {
    var history = TaskHistory(maximumRecords: 10)
    let appTask = try history.enqueue(
        scope: .app,
        kind: .install,
        title: "App pod install"
    )
    try history.start(appTask)
    try history.appendOutput("Installing Podfile...\n", to: appTask)
    try history.finish(appTask, exitCode: 0)

    let compATask = try history.enqueue(
        scope: .component(name: "HDDynamicPod"),
        kind: .archive,
        title: "Archive HDDynamicPod"
    )
    try history.start(compATask)
    try history.appendOutput("Archiving HDDynamicPod.podspec...\n", to: compATask)
    try history.finish(compATask, exitCode: 0)

    let compBTask = try history.enqueue(
        scope: .component(name: "HDStaticPod"),
        kind: .publish,
        title: "Publish HDStaticPod"
    )
    try history.start(compBTask)
    try history.appendOutput("Pushing HDStaticPod.podspec to repo...\n", to: compBTask)
    try history.finish(compBTask, exitCode: 0)

    let appRecords = history.records(for: .app)
    #expect(appRecords.count == 1)
    #expect(appRecords.first?.title == "App pod install")
    #expect(appRecords.first?.scope == .app)

    let compARecords = history.records(for: .component(name: "HDDynamicPod"))
    #expect(compARecords.count == 1)
    #expect(compARecords.first?.title == "Archive HDDynamicPod")
    #expect(compARecords.first?.scope == .component(name: "HDDynamicPod"))

    let compBRecords = history.records(for: .component(name: "HDStaticPod"))
    #expect(compBRecords.count == 1)
    #expect(compBRecords.first?.title == "Publish HDStaticPod")
    #expect(compBRecords.first?.scope == .component(name: "HDStaticPod"))

    // Clear only Component A's finished records
    history.clearFinishedRecords(for: .component(name: "HDDynamicPod"))
    #expect(history.records(for: .component(name: "HDDynamicPod")).isEmpty)
    #expect(history.records(for: .app).count == 1)
    #expect(history.records(for: .component(name: "HDStaticPod")).count == 1)
}

@Test func taskScopeCodablePreservesScopeAndFallbacksGracefully() throws {
    let appRecord = TaskRecord(scope: .app, kind: .install, title: "App Install")
    let compRecord = TaskRecord(scope: .component(name: "ComponentA"), kind: .archive, title: "Archive A")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let appData = try encoder.encode(appRecord)
    let decodedApp = try decoder.decode(TaskRecord.self, from: appData)
    #expect(decodedApp.scope == .app)
    #expect(decodedApp.title == "App Install")

    let compData = try encoder.encode(compRecord)
    let decodedComp = try decoder.decode(TaskRecord.self, from: compData)
    #expect(decodedComp.scope == .component(name: "ComponentA"))
    #expect(decodedComp.scope.componentName == "ComponentA")
    #expect(decodedComp.title == "Archive A")
}
