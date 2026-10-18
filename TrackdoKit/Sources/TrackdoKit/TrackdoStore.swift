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
    /// The server sent data a correct server never sends, e.g. a time entry
    /// under another task. Retried after backing off; worth reporting.
    case serverInconsistent(String)
}

/// Why the event stream has to be reopened.
private enum StreamFailure: Error {
    case invalid(String)
    case inconsistent(String)
    case ended
}

/// Owns the replica: serializes every call to it, saves the state after each
/// change, and while connected sends pending ops and receives the event
/// stream.
public actor TrackdoStore {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private static let logger = Logger(subsystem: "dev.syufu.trackdo", category: "sync")

    private let core: TrackdoCore
    private let file: StateFile
    private let sleep: Sleep
    private var client: ServerClient?
    private var backoff = Backoff()
    private var streamBackoff = Backoff()
    private var pushTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var pushRequested = false
    /// Set by responses that retrying cannot fix.
    private var isHalted = false
    private var problemHandler: (@Sendable (SyncProblem?) -> Void)?
    private var changeHandler: (@Sendable () -> Void)?

    public private(set) var problem: SyncProblem? {
        didSet {
            if problem != oldValue {
                problemHandler?(problem)
            }
        }
    }

    /// Opens the replica saved in `file`, or a new one. `sleep` waits out
    /// backoff delays; `nil` waits in real time.
    public init(file: StateFile, sleep: Sleep? = nil) throws {
        core = try file.openCore()
        self.file = file
        // Not a default argument: Swift 6.3 corrupts the task allocator when
        // an async closure in a default argument is awaited.
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
    }

    /// Called with every change of ``problem``.
    public func onProblem(_ handler: @escaping @Sendable (SyncProblem?) -> Void) {
        problemHandler = handler
    }

    /// Called after every change to tasks, entries or unsent ops.
    public func onChange(_ handler: @escaping @Sendable () -> Void) {
        changeHandler = handler
    }

    // MARK: Connection

    /// Starts syncing with `client`, e.g. after the settings changed.
    public func connect(client: ServerClient) async {
        await stopSyncing()
        self.client = client
        isHalted = false
        backoff.reset()
        streamBackoff.reset()
        problem = nil
        requestPush()
        streamTask = Task {
            await streamEvents()
            streamTask = nil
        }
    }

    /// Stops syncing; edits stay queued until the next ``connect(client:)``.
    public func disconnect() async {
        client = nil
        await stopSyncing()
    }

    /// Reconnects at once instead of waiting out a backoff, e.g. when the
    /// network came back. Does nothing while stopped for new settings.
    public func retryNow() async {
        guard let client, !isHalted else {
            return
        }
        await connect(client: client)
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
        defer { changeHandler?() }
        try file.save(core.stateJson())
        requestPush()
        return result
    }

    /// Saves after syncing changed the state. A failure is reported, and the
    /// next save writes the change too.
    private func save() {
        defer { changeHandler?() }
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

    private func stopSyncing() async {
        pushTask?.cancel()
        streamTask?.cancel()
        await waitUntilIdle()
        while let streamTask {
            await streamTask.value
        }
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

    // MARK: Event stream

    private func streamEvents() async {
        var mustResync = false
        while let client, !isHalted, !Task.isCancelled {
            do {
                if mustResync || core.needsSnapshot() {
                    try await resync(with: client)
                    mustResync = false
                }
                let events = try await client.events(lastEventId: core.lastEventId())
                streamBackoff.reset()
                try await receive(events)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                switch error {
                case ServerError.resyncRequired:
                    mustResync = true
                case ServerError.unauthorized:
                    _ = halt(because: .unauthorized)
                case ServerError.unsupportedProtocol:
                    _ = halt(because: .unsupportedProtocol)
                default:
                    guard await waitToReconnect(because: Self.problem(for: error)) else {
                        return
                    }
                }
            }
        }
    }

    /// Applies `op` events until the stream ends or must be reopened.
    private func receive(_ events: ServerSentEvents<URLSession.AsyncBytes>) async throws {
        for try await event in events {
            guard event.event == "op", let id = event.id else {
                continue
            }
            switch core.handleEvent(id: id, data: Data(event.data.utf8)) {
            case let .applied(needsPush):
                save()
                if needsPush {
                    requestPush()
                }
            case .resyncRequired:
                throw ServerError.resyncRequired
            case let .invalid(message):
                throw StreamFailure.invalid(message)
            case let .taskMismatch(entryId, expected, actual):
                throw StreamFailure.inconsistent("entry \(entryId) of task \(expected) sent under \(actual)")
            }
        }
        throw StreamFailure.ended
    }

    private func resync(with client: ServerClient) async throws {
        let body = try await client.snapshot()
        switch core.applySnapshot(body: body) {
        case let .applied(needsPush):
            save()
            if needsPush {
                requestPush()
            }
        case let .invalid(message):
            throw StreamFailure.invalid(message)
        case let .taskMismatch(entryId, expected, actual):
            throw StreamFailure.inconsistent("snapshot moves entry \(entryId) from task \(expected) to \(actual)")
        }
    }

    private static func problem(for error: any Error) -> SyncProblem {
        switch error {
        case let StreamFailure.invalid(message):
            logger.error("Invalid data from the server: \(message)")
            return .unexpected(message)
        case let StreamFailure.inconsistent(message):
            logger.fault("Inconsistent data from the server: \(message)")
            return .serverInconsistent(message)
        case let ServerError.unexpected(status, message):
            logger.error("Unexpected response \(status): \(message)")
            return .unexpected("\(status): \(message)")
        default:
            return .unreachable
        }
    }

    /// Waits before reopening the stream. Returns `false` when cancelled.
    private func waitToReconnect(because problem: SyncProblem) async -> Bool {
        self.problem = problem
        do {
            try await sleep(streamBackoff.nextDelay())
        } catch {
            return false
        }
        return !Task.isCancelled
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
