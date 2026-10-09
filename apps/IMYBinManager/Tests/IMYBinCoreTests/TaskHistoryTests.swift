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
