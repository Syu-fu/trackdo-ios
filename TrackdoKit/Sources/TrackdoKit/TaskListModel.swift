import Foundation
import Observation
import TrackdoFFI

/// A task as the list shows it.
public struct TaskItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// `nil` until the task's title arrives from the server.
    public let title: String?
    public let isDone: Bool
    public let isRunning: Bool
    /// Time spent at the last reload.
    public let totalMs: UInt64
}

/// The running timer as the list shows it.
public struct RunningTimer: Equatable, Sendable {
    public let entryId: String
    public let taskId: String
    public let title: String?
    /// Time measured at the last reload.
    public let elapsedMs: UInt64
}

/// Why a title was not accepted. Core decides; the list only trims it.
public enum TitleIssue: Error, Equatable, Sendable {
    case empty
    case containsLineBreak
    case tooLong(max: Int)
}

/// Why the last command changed nothing.
public enum TaskListIssue: Equatable, Sendable {
    /// The task was deleted, e.g. on another device.
    case taskGone
    /// The command failed otherwise, e.g. the state could not be saved.
    case failed(String)
}

/// The task list screen's state. Every edit goes through the store, which
/// works without a server; syncing only adds other devices' changes, picked
/// up by ``reload()``.
@MainActor
@Observable
public final class TaskListModel {
    public typealias Clock = @MainActor () -> Date

    public private(set) var openTasks: [TaskItem] = []
    public private(set) var doneTasks: [TaskItem] = []
    public private(set) var running: RunningTimer?
    public private(set) var issue: TaskListIssue?

    private let store: TrackdoStore
    private let now: Clock
    private var loadedAt: Date

    public init(store: TrackdoStore, now: @escaping Clock = Date.init) {
        self.store = store
        self.now = now
        loadedAt = now()
    }

    /// Reads the tasks and the running timer from the store.
    public func reload() async {
        let records = await store.tasks()
        let entry = await store.runningEntry()
        loadedAt = now()
        let items = records.map {
            TaskItem(id: $0.id, title: $0.title, isDone: $0.isDone, isRunning: $0.isInProgress, totalMs: $0.totalMs)
        }
        openTasks = items.filter { !$0.isDone }
        doneTasks = items.filter(\.isDone)
        running = entry.map { entry in
            RunningTimer(
                entryId: entry.id,
                taskId: entry.taskId,
                title: items.first { $0.id == entry.taskId }?.title,
                elapsedMs: entry.durationMs
            )
        }
    }

    // MARK: Commands

    public func add(title: String) async throws(TitleIssue) {
        let title = Self.trimmed(title)
        try await perform { _ = try await $0.create(title: title) }
    }

    public func rename(_ taskId: String, to title: String) async throws(TitleIssue) {
        let title = Self.trimmed(title)
        try await perform { try await $0.rename(taskId: taskId, title: title) }
    }

    public func complete(_ taskId: String) async {
        try? await perform { try await $0.complete(taskId: taskId) }
    }

    public func reopen(_ taskId: String) async {
        try? await perform { try await $0.reopen(taskId: taskId) }
    }

    /// Also stops the task's timer.
    public func delete(_ taskId: String) async {
        try? await perform { try await $0.delete(taskId: taskId) }
    }

    /// Stops any other timer and reopens a done task.
    public func start(_ taskId: String) async {
        try? await perform { try await $0.start(taskId: taskId) }
    }

    public func stop() async {
        guard let running else {
            return
        }
        try? await perform { try await $0.stop(entryId: running.entryId) }
    }

    // MARK: Live times

    /// `item`'s time at `date`, counting its running timer since the last
    /// reload.
    public func totalMs(of item: TaskItem, at date: Date) -> UInt64 {
        item.isRunning ? item.totalMs + sinceReloadMs(at: date) : item.totalMs
    }

    public func elapsedMs(of timer: RunningTimer, at date: Date) -> UInt64 {
        timer.elapsedMs + sinceReloadMs(at: date)
    }

    // MARK: Internals

    private func sinceReloadMs(at date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince(loadedAt) * 1000))
    }

    /// Runs a command and reloads. A title the core refuses is thrown for
    /// the form to show; other failures are kept in ``issue``.
    private func perform(_ command: (TrackdoStore) async throws -> Void) async throws(TitleIssue) {
        do {
            try await command(store)
            issue = nil
        } catch let error as FfiError {
            if let titleIssue = Self.titleIssue(error) {
                throw titleIssue
            }
            issue = Self.listIssue(error)
        } catch {
            issue = .failed(String(describing: error))
        }
        await reload()
    }

    private static func trimmed(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces)
    }

    private static func titleIssue(_ error: FfiError) -> TitleIssue? {
        switch error {
        case .EmptyTitle: .empty
        case .TitleContainsLineBreak: .containsLineBreak
        case let .TitleTooLong(max, _): .tooLong(max: Int(max))
        default: nil
        }
    }

    private static func listIssue(_ error: FfiError) -> TaskListIssue {
        switch error {
        case .TaskNotFound, .TaskDeleted, .EntryNotFound, .EntryDeleted, .EntryNotRunning: .taskGone
        default: .failed(error.localizedDescription)
        }
    }
}
