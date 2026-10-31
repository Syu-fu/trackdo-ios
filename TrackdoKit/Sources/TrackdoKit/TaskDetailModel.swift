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

/// Why a note was not accepted. Core decides.
public enum NoteIssue: Error, Equatable, Sendable {
    case tooLong(max: Int)
}

/// One task in full: its planning, its subtasks and its time entries, newest
/// first, with editing all of them.
@MainActor
@Observable
public final class TaskDetailModel {
    public typealias Clock = @MainActor () -> Date

    public let taskId: String
    /// `nil` once the task was deleted.
    public private(set) var task: TaskItem?
    /// `nil` at the top level.
    public private(set) var parent: TaskItem?
    /// Direct subtasks, oldest first.
    public private(set) var subtasks: [TaskItem] = []
    /// Tasks this one can move under: every other task not below it.
    public private(set) var moveTargets: [TaskItem] = []
    public private(set) var entries: [EntryItem] = []
    public private(set) var issue: TaskListIssue?
    private var runningEntryId: String?

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
        let tasks = await store.tasks()
        let record = tasks.first { $0.id == taskId }
        let entryRecords = (try? await store.entries(for: taskId)) ?? []
        runningEntryId = await store.runningEntry()?.id
        loadedAt = now()
        let item = { (record: TaskRecord) in TaskItem(record, among: tasks) }
        task = record.map(item)
        guard let record else {
            parent = nil
            subtasks = []
            moveTargets = []
            entries = []
            return
        }
        parent = tasks.first { $0.id == record.parentId }.map(item)
        subtasks = tasks.filter { $0.parentId == taskId }.map(item)
        let below = Self.ids(below: taskId, in: tasks)
        moveTargets = tasks.filter { $0.id != taskId && !below.contains($0.id) }.map(item)
        entries = entryRecords.map(EntryItem.init).sorted(by: Self.newestFirst)
    }

    // MARK: Planning

    public func rename(to title: String) async throws(TitleIssue) {
        let title = title.trimmingCharacters(in: .whitespaces)
        try await perform({ [taskId] in try await $0.rename(taskId: taskId, title: title) }, refusing: TitleIssue.init)
    }

    public func setPriority(_ priority: TaskPriority) async {
        await perform { [taskId] in try await $0.setPriority(taskId: taskId, priority: priority.ffi) }
    }

    /// An empty note removes the note.
    public func setNote(_ note: String) async throws(NoteIssue) {
        try await perform({ [taskId] in try await $0.setNote(taskId: taskId, note: note) }, refusing: NoteIssue.init)
    }

    /// `nil` clears the due date.
    public func setDue(_ due: CalendarDay?) async {
        await perform { [taskId] in try await $0.setDue(taskId: taskId, due: due?.ffi) }
    }

    /// `nil` unschedules the task.
    public func schedule(_ date: Date?) async {
        await perform { [taskId] in try await $0.schedule(taskId: taskId, atMs: date?.unixMs) }
    }

    /// `nil` moves the task to the top level.
    public func move(under parentId: String?) async {
        await perform { [taskId] in try await $0.setParent(taskId: taskId, parentId: parentId) }
    }

    /// Also deletes its subtasks and stops their timers.
    public func delete() async {
        await perform { [taskId] in try await $0.delete(taskId: taskId) }
    }

    // MARK: Subtasks and timing

    public func addSubtask(title: String) async throws(TitleIssue) {
        let title = title.trimmingCharacters(in: .whitespaces)
        try await perform(
            { [taskId] in _ = try await $0.createSubtask(parentId: taskId, title: title) },
            refusing: TitleIssue.init
        )
    }

    /// For the task itself or one of its subtasks.
    public func complete(_ id: String) async {
        await perform { try await $0.complete(taskId: id) }
    }

    public func reopen(_ id: String) async {
        await perform { try await $0.reopen(taskId: id) }
    }

    /// Stops any other timer and reopens a done task.
    public func start(_ id: String) async {
        await perform { try await $0.start(taskId: id) }
    }

    public func stopTimer() async {
        guard let runningEntryId else {
            return
        }
        await perform { try await $0.stop(entryId: runningEntryId) }
    }

    // MARK: Entries

    public func addEntry(start: Date, stop: Date) async throws(EntryTimesIssue) {
        try await perform({ [taskId] in
            _ = try await $0.addEntry(taskId: taskId, startedAtMs: start.unixMs, stoppedAtMs: stop.unixMs)
        }, refusing: EntryTimesIssue.init)
    }

    /// `stop` is `nil` only for the running entry, which keeps running.
    public func editTimes(_ entryId: String, start: Date, stop: Date?) async throws(EntryTimesIssue) {
        try await perform({
            try await $0.editTimes(entryId: entryId, startedAtMs: start.unixMs, stoppedAtMs: stop?.unixMs)
        }, refusing: EntryTimesIssue.init)
    }

    public func deleteEntry(_ entryId: String) async {
        await perform { try await $0.deleteEntry(entryId: entryId) }
    }

    // MARK: Live times

    public func durationMs(of entry: EntryItem, at date: Date) -> UInt64 {
        entry.isRunning ? entry.durationMs + sinceReloadMs(at: date) : entry.durationMs
    }

    public func totalMs(at date: Date) -> UInt64 {
        task.map { totalMs(of: $0, at: date) } ?? 0
    }

    /// For the task itself or one of its subtasks.
    public func totalMs(of item: TaskItem, at date: Date) -> UInt64 {
        item.isRunning ? item.totalMs + sinceReloadMs(at: date) : item.totalMs
    }

    // MARK: Internals

    private func sinceReloadMs(at date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince(loadedAt) * 1000))
    }

    /// Runs a command and reloads. Input the core refuses, as `refusing`
    /// recognizes it, is thrown for the form to show; other failures are
    /// kept in ``issue``.
    private func perform<Issue: Error>(
        _ command: (TrackdoStore) async throws -> Void,
        refusing refusal: (FfiError) -> Issue?
    ) async throws(Issue) {
        do {
            try await command(store)
            issue = nil
        } catch {
            if let ffiError = error as? FfiError, let refused = refusal(ffiError) {
                throw refused
            }
            issue = TaskListIssue(error)
        }
        await reload()
    }

    private func perform(_ command: (TrackdoStore) async throws -> Void) async {
        await perform(command, refusing: { _ -> Never? in nil })
    }

    /// Every task below `id`, at any depth.
    private static func ids(below id: String, in tasks: [TaskRecord]) -> Set<String> {
        var below: Set<String> = []
        var frontier = [id]
        while let current = frontier.popLast() {
            let children = tasks.filter { $0.parentId == current }.map(\.id).filter { !below.contains($0) }
            below.formUnion(children)
            frontier += children
        }
        return below
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

extension EntryTimesIssue {
    init?(_ error: FfiError) {
        switch error {
        case .StopBeforeStart: self = .stopBeforeStart
        case .InFuture: self = .inFuture
        default: return nil
        }
    }
}

extension NoteIssue {
    init?(_ error: FfiError) {
        guard case let .NoteTooLong(max, _) = error else {
            return nil
        }
        self = .tooLong(max: Int(max))
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
