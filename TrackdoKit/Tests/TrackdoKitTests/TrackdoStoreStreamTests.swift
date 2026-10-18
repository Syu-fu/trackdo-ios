import Foundation
import Testing
import TrackdoFFI
@testable import TrackdoKit

@Suite(.timeLimit(.minutes(1))) struct TrackdoStoreStreamTests {
    let server = StubServer(handler: routes())
    let gate = SleepGate()
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TrackdoStoreStreamTests-\(UUID().uuidString)")
    )

    init() {
        server.holdOpen("events")
    }

    var client: ServerClient {
        ServerClient(settings: try! ServerSettings(url: server.url, token: "secret"), session: server.session)
    }

    func connectedStore() async throws -> TrackdoStore {
        let gate = gate
        let store = try TrackdoStore(file: file, sleep: { try await gate.sleep($0) })
        await store.connect(client: client)
        return store
    }

    @Test func firstConnectionFetchesSnapshotThenStreamsFromTheStart() async throws {
        _ = try await connectedStore()

        await server.waitForRequests(to: "events", count: 1)

        #expect(server.requests.map(\.path) .filter { !$0.hasSuffix("ops") } == ["/base/snapshot", "/base/events"])
        #expect(server.requests(to: "events")[0].headers["Last-Event-ID"] == nil)
        #expect(try file.openCore().needsSnapshot() == false)
    }

    @Test func receivedOpsAreAppliedSavedAndResumedFrom() async throws {
        let other = TrackdoCore()
        let id = try other.create(title: "from another device")
        let ops = opsOf(other)
        server.respond(routes(events: eventStream(ops)))
        let store = try await connectedStore()

        await store.eventually { await $0.tasks().map(\.id) == [id] }
        await store.retryNow()
        await server.waitForRequests(to: "events", count: 2)

        #expect(try file.openCore().tasks().map(\.title) == ["from another device"])
        #expect(server.requests(to: "events")[1].headers["Last-Event-ID"] == "\(testLog):\(ops.count)")
    }

    @Test func goneStreamPositionResyncsWithoutBackingOff() async throws {
        server.respond(routes(events: inOrder([status(410, #"{"error":{"code":"resync_required","message":"m"}}"#), status(200)])))
        _ = try await connectedStore()

        await server.waitForRequests(to: "events", count: 2)

        #expect(server.requests(to: "snapshot").count == 2)
    }

    @Test func eventOfAnotherLogResyncs() async throws {
        let other = TrackdoCore()
        _ = try other.create(title: "a")
        server.respond(routes(events: inOrder([eventStream(opsOf(other), log: otherLog), status(200)])))
        let store = try await connectedStore()

        await server.waitForRequests(to: "events", count: 2)

        #expect(server.requests(to: "snapshot").count == 2)
        #expect(await store.tasks().isEmpty)
    }

    @Test(arguments: [
        (401, #"{"error":{"code":"unauthorized","message":"m"}}"#, SyncProblem.unauthorized),
        (400, #"{"error":{"code":"unsupported_protocol_version","message":"m"}}"#, .unsupportedProtocol),
    ])
    func refusedStreamStopsSyncing(status: Int, body: String, problem: SyncProblem) async throws {
        server.respond(routes(snapshot: TrackdoKitTests.status(status, body)))
        let store = try await connectedStore()

        await store.eventually { await $0.problem == problem }
        _ = try await store.create(title: "a")
        await store.waitUntilIdle()

        #expect(server.requests(to: "events").isEmpty)
        #expect(server.requests(to: "ops").isEmpty)
    }

    @Test func endedStreamReconnectsAfterBackingOff() async throws {
        let server = StubServer(handler: routes())
        let store = try TrackdoStore(file: file, sleep: { [gate] in try await gate.sleep($0) })
        await store.connect(client: ServerClient(
            settings: try ServerSettings(url: server.url, token: "secret"),
            session: server.session
        ))

        await gate.waitUntilBackingOff()
        #expect(await store.problem == .unreachable)
        await store.retryNow()
        await server.waitForRequests(to: "events", count: 2)
    }

    @Test(arguments: [
        (status(200, "id: \(testLog):1\nevent: op\ndata: {}\n\n"), "invalid"),
        (status(418, "teapot"), "unexpected"),
    ])
    func malformedStreamsAreRetriedAfterBackingOff(events: @escaping StubServer.Handler, kind: String) async throws {
        server.respond(routes(events: events))
        let store = try await connectedStore()

        await gate.waitUntilBackingOff()

        guard case .unexpected = await store.problem else {
            Issue.record("expected an unexpected-response problem for \(kind), got \(String(describing: await store.problem))")
            return
        }
    }

    @Test func healingAfterReceivingIsSent() async throws {
        let local = try TrackdoStore(file: file, sleep: { [gate] in try await gate.sleep($0) })
        let mine = try await local.create(title: "mine")
        let entry = try await local.start(taskId: mine)
        let other = TrackdoCore()
        let theirs = try other.create(title: "theirs")
        _ = try other.start(taskId: theirs)
        server.respond(routes(events: eventStream(opsOf(other))))

        await local.connect(client: client)

        let server = server
        let stopsSent: @Sendable () -> Int = {
            server.requests(to: "ops").flatMap(sentOps).filter { op in
                let target = op["target"] as? [String: Any]
                let change = target?["change"] as? [String: Any]
                return target?["entry_id"] as? String == entry && change?["field"] as? String == "stopped_at"
                    && !(change?["value"] is NSNull)
            }.count
        }
        await local.eventually { _ in stopsSent() > 0 }
        #expect(await local.runningEntry()?.taskId == theirs)
        #expect(stopsSent() == 1)
    }

    @Test func entryMovedByTheServerIsReported() async throws {
        let local = try TrackdoStore(file: file, sleep: { [gate] in try await gate.sleep($0) })
        let task = try await local.create(title: "a")
        let entry = try await local.start(taskId: task)
        let moved = try JSONSerialization.data(withJSONObject: [
            "op_id": UUID().uuidString.lowercased(),
            "hlc": ["wall_ms": 1, "counter": 0, "device": UUID().uuidString.lowercased()],
            "target": [
                "type": "time_entry", "entry_id": entry, "task_id": UUID().uuidString.lowercased(),
                "change": ["field": "deleted", "value": true],
            ],
        ])
        server.respond(routes(events: eventStream([moved])))

        await local.connect(client: client)
        await gate.waitUntilBackingOff()

        guard case .serverInconsistent = await local.problem else {
            Issue.record("expected serverInconsistent, got \(String(describing: await local.problem))")
            return
        }
    }
}
