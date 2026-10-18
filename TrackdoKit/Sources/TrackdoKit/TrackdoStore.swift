import Foundation
import os
import TrackdoFFI

/// Why syncing is not keeping up right now.
public enum SyncProblem: Sendable, Equatable {
    /// The token was refused. Sending waits for new settings.
    case unauthorized
    /// The app or the server needs updating. Sending waits for new settings.
    case unsupportedProtocol
    /// No network, or the server failed. Retried after backing off.
    case unreachable
    /// The server answered outside its API. Retried after backing off.
    case unexpected(String)
    /// The state could not be written; unsaved changes are retried with the
    /// next save.
    case saveFailed(String)
}

/// Owns the replica: serializes every call to it, saves the state after each
/// change and sends pending ops while connected.
public actor TrackdoStore {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private static let logger = Logger(subsystem: "dev.syufu.trackdo", category: "sync")

    private let core: TrackdoCore
    private let file: StateFile
    private let sleep: Sleep
    private var client: ServerClient?
    private var backoff = Backoff()
    private var pushTask: Task<Void, Never>?
    private var pushRequested = false
    /// Set by responses that retrying cannot fix.
    private var isHalted = false
    private var problemHandler: (@Sendable (SyncProblem?) -> Void)?

    public private(set) var problem: SyncProblem? {
        didSet {
            if problem != oldValue {
                problemHandler?(problem)
            }
        }
    }

    /// Opens the replica saved in `file`, or a new one.
    public init(file: StateFile, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) throws {
        core = try file.openCore()
        self.file = file
        self.sleep = sleep
    }

    /// Called with every change of ``problem``.
    public func onProblem(_ handler: @escaping @Sendable (SyncProblem?) -> Void) {
        problemHandler = handler
    }

    // MARK: Connection

    /// Starts sending with `client`, e.g. after the settings changed.
    public func connect(client: ServerClient) async {
        await stopPushing()
        self.client = client
        isHalted = false
        backoff.reset()
        problem = nil
        requestPush()
    }

    /// Stops sending; edits stay queued until the next ``connect(client:)``.
    public func disconnect() async {
        client = nil
        await stopPushing()
    }

    /// Returns once nothing is being sent.
    func waitUntilIdle() async {
        while let pushTask {
            await pushTask.value
        }
    }

    // MARK: Commands

    /// Returns the new task's id.
    public func create(title: String) throws -> String {
        try perform { try $0.create(title: title) }
    }

    public func rename(taskId: String, title: String) throws {
        try perform { try $0.rename(taskId: taskId, title: title) }
    }

    public func complete(taskId: String) throws {
        try perform { try $0.complete(taskId: taskId) }
    }

    public func reopen(taskId: String) throws {
        try perform { try $0.reopen(taskId: taskId) }
    }

    public func delete(taskId: String) throws {
        try perform { try $0.delete(taskId: taskId) }
    }

    /// Returns the new entry's id.
    @discardableResult
    public func start(taskId: String) throws -> String {
        try perform { try $0.start(taskId: taskId) }
    }

    public func stop(entryId: String) throws {
        try perform { try $0.stop(entryId: entryId) }
    }

    public func editTimes(entryId: String, startedAtMs: UInt64, stoppedAtMs: UInt64?) throws {
        try perform { try $0.editTimes(entryId: entryId, startedAtMs: startedAtMs, stoppedAtMs: stoppedAtMs) }
    }

    public func deleteEntry(entryId: String) throws {
        try perform { try $0.deleteEntry(entryId: entryId) }
    }

    /// Returns the new entry's id.
    @discardableResult
    public func addEntry(taskId: String, startedAtMs: UInt64, stoppedAtMs: UInt64) throws -> String {
        try perform { try $0.addEntry(taskId: taskId, startedAtMs: startedAtMs, stoppedAtMs: stoppedAtMs) }
    }

    // MARK: Queries

    public func tasks() -> [TaskRecord] {
        core.tasks()
    }

    public func runningEntry() -> EntryRecord? {
        core.runningEntry()
    }

    public func entries(for taskId: String) throws -> [EntryRecord] {
        try core.entriesFor(taskId: taskId)
    }

    // MARK: Internals

    /// Runs a command, then saves and sends what it queued. A failed command
    /// changes nothing.
    private func perform<T>(_ command: (TrackdoCore) throws -> T) throws -> T {
        let result = try command(core)
        try file.save(core.stateJson())
        requestPush()
        return result
    }

    private func save() {
        do {
            try file.save(core.stateJson())
        } catch {
            Self.logger.error("Saving the state failed: \(error)")
            problem = .saveFailed(String(describing: error))
        }
    }

    private func requestPush() {
        pushRequested = true
        guard pushTask == nil, client != nil, !isHalted else {
            return
        }
        pushTask = Task {
            await pushPending()
            pushTask = nil
        }
    }

    private func stopPushing() async {
        pushTask?.cancel()
        await waitUntilIdle()
    }

    private func pushPending() async {
        while pushRequested, let client, !isHalted, !Task.isCancelled {
            pushRequested = false
            while let batch = core.nextPushBatch() {
                guard await push(batch, with: client) else {
                    return
                }
            }
        }
    }

    /// Sends one batch. Returns whether to go on sending.
    private func push(_ batch: Data, with client: ServerClient) async -> Bool {
        let outcome: PushOutcome
        do {
            let response = try await client.postOps(batch)
            outcome = core.handlePushResponse(status: UInt16(clamping: response.status), body: response.body)
        } catch {
            return await backOff(because: .unreachable)
        }
        save()

        switch outcome {
        case .accepted:
            backoff.reset()
            problem = nil
            return true
        case let .rejected(opId, code, message):
            Self.logger.error("Server rejected op \(opId) for good (\(code)): \(message)")
            return true
        case .unauthorized:
            return halt(because: .unauthorized)
        case .unsupportedProtocol:
            return halt(because: .unsupportedProtocol)
        case .retry:
            return await backOff(because: .unreachable)
        case let .unexpected(status, message):
            Self.logger.error("Unexpected POST /ops response \(status): \(message)")
            return await backOff(because: .unexpected("\(status): \(message)"))
        }
    }

    private func halt(because problem: SyncProblem) -> Bool {
        isHalted = true
        self.problem = problem
        return false
    }

    /// Waits before the next attempt. Returns `false` when cancelled.
    private func backOff(because problem: SyncProblem) async -> Bool {
        self.problem = problem
        do {
            try await sleep(backoff.nextDelay())
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}
