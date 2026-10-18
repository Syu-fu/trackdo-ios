import Foundation
import Testing
import TrackdoFFI
@testable import TrackdoKit

/// Suspending in the background, resuming in the foreground, and the sync
/// status the settings screen shows.
@Suite(.timeLimit(.minutes(1))) struct TrackdoStoreLifecycleTests {
    let server = StubServer(handler: routes())
    let gate = SleepGate()
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TrackdoStoreLifecycleTests-\(UUID().uuidString)")
    )

    init() {
        server.holdOpen("events")
    }

    var client: ServerClient {
        ServerClient(settings: try! ServerSettings(url: server.url, token: "secret"), session: server.session)
    }

    func makeStore(connected: Bool = true) async throws -> TrackdoStore {
        let store = try TrackdoStore(file: file, sleep: { [gate] in try await gate.sleep($0) })
        if connected {
            await store.connect(client: client)
        }
        return store
    }

    func hasPendingOps() throws -> Bool {
        try file.openCore().nextPushBatch() != nil
    }

    // MARK: Suspending

    @Test func suspendingSendsWhatIsPendingWithoutWaitingOutTheBackoff() async throws {
        server.respond(routes(ops: inOrder([status(503), accepted])))
        let store = try await makeStore()
        _ = try await store.create(title: "a")
        await gate.waitUntilBackingOff()

        await store.suspend()

        #expect(server.requests(to: "ops").count == 2)
        #expect(try !hasPendingOps())
        #expect(await store.syncStatus == .paused)
    }

    @Test func suspendingTriesOnlyOnce() async throws {
        server.respond(routes(ops: status(503)))
        let store = try await makeStore(connected: false)
        _ = try await store.create(title: "a")
        await store.connect(client: client)
        await gate.waitUntilBackingOff()

        await store.suspend()

        #expect(server.requests(to: "ops").count == 2)
        #expect(try hasPendingOps())
    }

    @Test func suspendingClosesTheStream() async throws {
        let store = try await makeStore()
        await server.waitForRequests(to: "events", count: 1)

        await store.suspend()
        await store.retryNow()
        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "events").count == 1)
        #expect(server.requests(to: "ops").isEmpty)
        #expect(try hasPendingOps())
    }

    @Test func resumingReconnectsAndSendsEditsMadeMeanwhile() async throws {
        let store = try await makeStore()
        await server.waitForRequests(to: "events", count: 1)
        await store.suspend()
        _ = try await store.create(title: "a")

        await store.resume()
        await server.waitForRequests(to: "events", count: 2)
        await store.waitUntilIdle()

        #expect(server.requests(to: "ops").count == 1)
        #expect(try !hasPendingOps())
        await store.eventually { await $0.syncStatus == .live }
    }

    @Test func resumingWithoutSettingsStaysOff() async throws {
        let store = try await makeStore(connected: false)

        await store.suspend()
        await store.resume()

        #expect(await store.syncStatus == .off)
        #expect(server.requests.isEmpty)
    }

    @Test func resumingKeepsARefusedTokenStopped() async throws {
        server.respond(routes(snapshot: status(401, #"{"error":{"code":"unauthorized","message":"m"}}"#)))
        let store = try await makeStore()
        await store.eventually { await $0.problem == .unauthorized }

        await store.suspend()
        await store.resume()
        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "snapshot").count == 1)
        #expect(await store.syncStatus == .failing(.unauthorized))
    }

    // MARK: Status

    @Test func statusIsOffWithoutSettings() async throws {
        let store = try await makeStore(connected: false)

        #expect(await store.syncStatus == .off)
    }

    @Test func statusIsLiveOnceTheStreamIsOpen() async throws {
        let store = try await makeStore()

        await store.eventually { await $0.syncStatus == .live }
        let observed = StatusLog()
        await store.onSyncStatus { observed.append($0) }
        await store.disconnect()

        #expect(observed.values.last == .off)
    }

    @Test func statusReportsFailuresUntilTheStreamOpensAgain() async throws {
        server.respond(routes(events: inOrder([offline, status(200)])))
        let store = try await makeStore()
        await gate.waitUntilBackingOff()

        #expect(await store.syncStatus == .failing(.unreachable))

        await store.retryNow()
        await store.eventually { await $0.syncStatus == .live }
        #expect(await store.problem == nil)
    }
}

final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SyncStatus] = []

    var values: [SyncStatus] { lock.withLock { recorded } }

    func append(_ status: SyncStatus) {
        lock.withLock { recorded.append(status) }
    }
}
