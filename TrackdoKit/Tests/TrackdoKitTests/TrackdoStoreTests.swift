import Foundation
import Testing
import TrackdoFFI
@testable import TrackdoKit

@Suite struct TrackdoStoreTests {
    let server = StubServer(handler: routes())
    let sleeps = RecordedSleeps()
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TrackdoStoreTests-\(UUID().uuidString)")
    )

    /// The snapshot never completes, keeping the event stream out of these
    /// tests of sending.
    init() {
        server.holdOpen("snapshot")
    }

    func makeStore(connected: Bool = true) async throws -> TrackdoStore {
        let sleeps = sleeps
        let store = try TrackdoStore(file: file, sleep: { try await sleeps.sleep($0) })
        if connected {
            await store.connect(client: client)
        }
        return store
    }

    var client: ServerClient {
        ServerClient(settings: try! ServerSettings(url: server.url, token: "secret"), session: server.session)
    }

    func savedCore() throws -> TrackdoCore {
        try file.openCore()
    }

    // MARK: Commands

    @Test func commandsAreSavedAtOnce() async throws {
        let store = try await makeStore(connected: false)

        let id = try await store.create(title: "a")
        try await store.start(taskId: id)

        let saved = try savedCore()
        #expect(saved.tasks().map(\.id) == [id])
        #expect(saved.runningEntry()?.taskId == id)
    }

    @Test func storeReopensWhatWasSaved() async throws {
        let id = try await makeStore(connected: false).create(title: "a")

        let reopened = try await makeStore(connected: false)

        #expect(await reopened.tasks().map(\.id) == [id])
    }

    @Test func failedCommandsChangeNothing() async throws {
        let store = try await makeStore(connected: false)

        await #expect(throws: FfiError.EmptyTitle) {
            try await store.create(title: " ")
        }
        #expect(try file.load() == nil)
    }

    @Test func everyCommandIsAvailable() async throws {
        let store = try await makeStore(connected: false)
        let task = try await store.create(title: "a")
        let entry = try await store.start(taskId: task)
        try await store.stop(entryId: entry)
        let started = try #require(await store.entries(for: task).first?.startedAtMs)

        try await store.rename(taskId: task, title: "b")
        try await store.complete(taskId: task)
        try await store.reopen(taskId: task)
        try await store.editTimes(entryId: entry, startedAtMs: started - 10, stoppedAtMs: started)
        let past = try await store.addEntry(taskId: task, startedAtMs: started - 100, stoppedAtMs: started - 50)
        try await store.deleteEntry(entryId: entry)

        #expect(try await store.entries(for: task).map(\.id) == [past])
        #expect(await store.tasks().first?.title == "b")
        #expect(await store.runningEntry() == nil)
        try await store.delete(taskId: task)
        #expect(await store.tasks().isEmpty)
    }

    // MARK: Pushing

    @Test func nothingIsSentWhileDisconnected() async throws {
        let store = try await makeStore(connected: false)

        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests.isEmpty)
    }

    @Test func commandsArePushedAndAcknowledged() async throws {
        let store = try await makeStore()

        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 1)
        #expect(try savedCore().nextPushBatch() == nil)
        #expect(await store.problem == nil)
    }

    @Test func connectingSendsWhatWasQueuedOffline() async throws {
        let store = try await makeStore(connected: false)
        _ = try await store.create(title: "a")

        await store.connect(client: client)
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 1)
        #expect(try savedCore().nextPushBatch() == nil)
    }

    @Test func largeQueuesAreSentInBatches() async throws {
        let store = try await makeStore(connected: false)
        for index in 0..<300 {
            _ = try await store.create(title: "task \(index)")
        }

        await store.connect(client: client)
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 2)
        #expect(try savedCore().nextPushBatch() == nil)
    }

    @Test func rejectedOpIsDroppedAndTheRestSent() async throws {
        server.respond(routes(ops: inOrder([
            { request in
                let body = #"{"error":{"code":"invalid_op","message":"m","op_id":"\#(firstOpId(of: request))"}}"#
                return (422, Data(body.utf8))
            },
            accepted,
        ])))
        let store = try await makeStore()

        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 2)
        #expect(try savedCore().nextPushBatch() == nil)
        #expect(await store.problem == nil)
    }

    @Test(arguments: [
        (401, #"{"error":{"code":"unauthorized","message":"m"}}"#, SyncProblem.unauthorized),
        (400, #"{"error":{"code":"unsupported_protocol_version","message":"m"}}"#, .unsupportedProtocol),
    ])
    func sendingStopsUntilSettingsChange(status: Int, body: String, problem: SyncProblem) async throws {
        server.respond(routes(ops: TrackdoKitTests.status(status, body)))
        let store = try await makeStore()

        _ = try await store.create(title: "a")
        await store.waitUntilIdle()
        _ = try await store.create(title: "b")
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 1)
        #expect(await store.problem == problem)
        #expect(sleeps.count == 0)
        #expect(try savedCore().nextPushBatch() != nil)
    }

    @Test func reconnectingRetriesAfterAStop() async throws {
        server.respond(routes(ops: inOrder([status(401), accepted])))
        let store = try await makeStore()
        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        await store.connect(client: client)
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 2)
        #expect(await store.problem == nil)
    }

    @Test(arguments: [
        (status(503), SyncProblem.unreachable),
        (offline, .unreachable),
        (status(418, "teapot"), .unexpected("418: teapot")),
    ] as [(StubServer.Handler, SyncProblem)])
    func failuresAreRetriedAfterBackingOff(failure: @escaping StubServer.Handler, problem: SyncProblem) async throws {
        server.respond(routes(ops: inOrder([failure, failure, accepted])))
        let store = try await makeStore()
        let observed = ProblemLog()
        await store.onProblem { observed.append($0) }

        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 3)
        #expect(sleeps.count == 2)
        #expect(observed.values == [problem, nil])
        #expect(await store.problem == nil)
    }

    @Test func disconnectingStopsRetrying() async throws {
        server.respond(routes(ops: status(503)))
        let (backingOff, entered) = AsyncStream<Void>.makeStream()
        let store = try TrackdoStore(file: file, sleep: { _ in
            entered.yield()
            try await Task.sleep(for: .seconds(3600))
        })
        await store.connect(client: client)
        _ = try await store.create(title: "a")
        for await _ in backingOff {
            break
        }

        await store.disconnect()
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 1)
        #expect(try savedCore().nextPushBatch() != nil)
    }
}

final class ProblemLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [SyncProblem?] = []

    var values: [SyncProblem?] { lock.withLock { log } }

    func append(_ problem: SyncProblem?) {
        lock.withLock { log.append(problem) }
    }
}
