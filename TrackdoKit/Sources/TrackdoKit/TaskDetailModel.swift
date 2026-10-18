import Foundation
import Observation
import TrackdoFFI

/// A time entry as the detail screen shows it.
public struct EntryItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// `nil` until the entry's start arrives from the server.
    public let startedAt: Date?
    /// `nil` while running or before the stop arrives.
    public let stoppedAt: Date?
    public let isRunning: Bool
    /// Stopped automatically because another timer took over.
    public let isStopDerived: Bool
    /// Stops before it starts after concurrent edits; the times need fixing.
    public let needsAttention: Bool
    /// Time measured at the last reload.
    public let durationMs: UInt64

    init(_ record: EntryRecord) {
        id = record.id
        startedAt = record.startedAtMs.map(Date.init(unixMs:))
        stoppedAt = record.stoppedAtMs.map(Date.init(unixMs:))
        isRunning = record.isRunning
        isStopDerived = record.isStopDerived
        needsAttention = record.needsAttention
        durationMs = record.durationMs
    }
}

/// Why entered times were not accepted. Core decides.
public enum EntryTimesIssue: Error, Equatable, Sendable {
    case stopBeforeStart
    case inFuture
}

/// One task's time entries, newest first, with editing, deleting and adding
/// past work.
@MainActor
@Observable
public final class TaskDetailModel {
    public typealias Clock = @MainActor () -> Date

    public let taskId: String
    /// `nil` once the task was deleted.
    public private(set) var task: TaskItem?
    public private(set) var entries: [EntryItem] = []
    public private(set) var issue: TaskListIssue?

    private let store: TrackdoStore
    private let now: Clock
    private var loadedAt: Date

    public init(taskId: String, store: TrackdoStore, now: @escaping Clock = Date.init) {
        self.taskId = taskId
        self.store = store
        self.now = now
        loadedAt = now()
    }

    public func reload() async {
        let record = await store.tasks().first { $0.id == taskId }
        let records = (try? await store.entries(for: taskId)) ?? []
        loadedAt = now()
        task = record.map(TaskItem.init)
        entries = record == nil ? [] : records.map(EntryItem.init).sorted(by: Self.newestFirst)
    }

    // MARK: Commands

    public func addEntry(start: Date, stop: Date) async throws(EntryTimesIssue) {
        try await perform { [taskId] in
            _ = try await $0.addEntry(taskId: taskId, startedAtMs: start.unixMs, stoppedAtMs: stop.unixMs)
        }
    }

    /// `stop` is `nil` only for the running entry, which keeps running.
    public func editTimes(_ entryId: String, start: Date, stop: Date?) async throws(EntryTimesIssue) {
        try await perform {
            try await $0.editTimes(entryId: entryId, startedAtMs: start.unixMs, stoppedAtMs: stop?.unixMs)
        }
    }

    public func deleteEntry(_ entryId: String) async {
        try? await perform { try await $0.deleteEntry(entryId: entryId) }
    }

    // MARK: Live times

    public func durationMs(of entry: EntryItem, at date: Date) -> UInt64 {
        entry.isRunning ? entry.durationMs + sinceReloadMs(at: date) : entry.durationMs
    }

    public func totalMs(at date: Date) -> UInt64 {
        guard let task else {
            return 0
        }
        return task.isRunning ? task.totalMs + sinceReloadMs(at: date) : task.totalMs
    }

    // MARK: Internals

    private func sinceReloadMs(at date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince(loadedAt) * 1000))
    }

    /// Runs a command and reloads. Times the core refuses are thrown for the
    /// form to show; other failures are kept in ``issue``.
    private func perform(_ command: (TrackdoStore) async throws -> Void) async throws(EntryTimesIssue) {
        do {
            try await command(store)
            issue = nil
        } catch {
            switch error as? FfiError {
            case .StopBeforeStart: throw .stopBeforeStart
            case .InFuture: throw .inFuture
            default: issue = TaskListIssue(error)
            }
        }
        await reload()
    }

    /// Entries without a known start go last.
    static func newestFirst(_ a: EntryItem, _ b: EntryItem) -> Bool {
        switch (a.startedAt, b.startedAt) {
        case let (a?, b?): a > b
        case (_?, nil): true
        default: false
        }
    }
}

extension Date {
    init(unixMs: UInt64) {
        self.init(timeIntervalSince1970: Double(unixMs) / 1000)
    }

    var unixMs: UInt64 {
        UInt64(max(0, timeIntervalSince1970 * 1000))
    }
}
