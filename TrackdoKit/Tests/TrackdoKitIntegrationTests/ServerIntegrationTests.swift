#if os(macOS)
import Foundation
import Testing
import TrackdoFFI
import TrackdoKit

/// The server `scripts/integration-test.sh` starts. Tests are skipped without
/// it.
enum TestServer {
    static let environment = ProcessInfo.processInfo.environment

    static var isRunning: Bool {
        environment["TRACKDO_TEST_SERVER_URL"] != nil
    }

    static func settings(token: String? = nil) throws -> ServerSettings {
        try ServerSettings(
            url: ServerURL(environment["TRACKDO_TEST_SERVER_URL"] ?? ""),
            token: token ?? environment["TRACKDO_TEST_SERVER_TOKEN"] ?? ""
        )
    }

    /// Restarts the server on the same database, which gives it a new log.
    ///
    /// Waits through `terminationHandler`: `waitUntilExit()` would spin a run
    /// loop on a concurrency thread and corrupt other tasks running there.
    static func restart() async throws {
        let script = Process()
        script.executableURL = URL(filePath: "/bin/bash")
        script.arguments = [environment["TRACKDO_TEST_SERVER_SCRIPT"] ?? "", "restart"]
        let status: Int32 = try await withCheckedThrowingContinuation { finished in
            script.terminationHandler = { finished.resume(returning: $0.terminationStatus) }
            do {
                try script.run()
            } catch {
                finished.resume(throwing: error)
            }
        }
        #expect(status == 0)
    }
}

/// A device: its own state file and store, syncing with the test server.
struct Device {
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "ServerIntegrationTests-\(UUID().uuidString)")
    )
    let store: TrackdoStore

    init() throws {
        store = try TrackdoStore(file: file)
    }

    func connect(token: String? = nil) async throws {
        let client = ServerClient(settings: try TestServer.settings(token: token), session: ServerClient.makeSession())
        await store.connect(client: client)
    }

    /// Returns once `condition` holds, checking after every change.
    func eventually(_ condition: @Sendable (TrackdoStore) async throws -> Bool) async rethrows {
        let (changes, changed) = AsyncStream<Void>.makeStream()
        await store.onChange { changed.yield() }
        await store.onProblem { _ in changed.yield() }
        if try await condition(store) {
            return
        }
        for await _ in changes {
            if try await condition(store) {
                return
            }
        }
    }

    func title(of id: String) async -> String? {
        await store.tasks().first { $0.id == id }?.title
    }
}

@Suite(.enabled(if: TestServer.isRunning), .serialized, .timeLimit(.minutes(1)))
struct ServerIntegrationTests {
    @Test func serverPassesTheHealthCheck() async throws {
        try await ServerClient.checkHealth(of: TestServer.settings().url, session: ServerClient.makeSession())
    }

    @Test func editsReachAnotherDevice() async throws {
        let phone = try Device()
        let laptop = try Device()
        try await phone.connect()
        try await laptop.connect()

        let id = try await phone.store.create(title: "buy milk")
        try await phone.store.start(taskId: id)

        await laptop.eventually { await $0.runningEntry()?.taskId == id }
        #expect(await laptop.title(of: id) == "buy milk")
    }

    @Test func backgroundEditsReachAnotherDeviceOnReturn() async throws {
        let phone = try Device()
        let laptop = try Device()
        try await phone.connect()
        try await laptop.connect()
        let sent = try await phone.store.create(title: "sent before suspending")

        await phone.store.suspend()
        await laptop.eventually { _ in await laptop.title(of: sent) == "sent before suspending" }
        let later = try await phone.store.create(title: "made in the background")
        await phone.store.resume()

        await laptop.eventually { _ in await laptop.title(of: later) == "made in the background" }
        #expect(await phone.store.syncStatus != .paused)
    }

    @Test func offlineEditsConvergeOnTheLastWrite() async throws {
        let phone = try Device()
        let laptop = try Device()
        try await phone.connect()
        try await laptop.connect()
        let id = try await phone.store.create(title: "draft")
        await laptop.eventually { _ in await laptop.title(of: id) == "draft" }
        await phone.store.disconnect()
        await laptop.store.disconnect()

        try await phone.store.rename(taskId: id, title: "from the phone")
        // Writes within the same millisecond are ordered by HLC counter and
        // device, not by wall order; a later millisecond always wins.
        try await Task.sleep(for: .milliseconds(5))
        try await laptop.store.rename(taskId: id, title: "from the laptop")
        try await phone.connect()
        try await laptop.connect()

        await phone.eventually { _ in await phone.title(of: id) == "from the laptop" }
        await laptop.eventually { _ in await laptop.title(of: id) == "from the laptop" }
    }

    @Test func timersStartedOfflineOnTwoDevicesLeaveOneRunning() async throws {
        let phone = try Device()
        let laptop = try Device()
        let first = try await phone.store.create(title: "first")
        try await phone.store.start(taskId: first)
        let second = try await laptop.store.create(title: "second")
        try await laptop.store.start(taskId: second)

        try await phone.connect()
        try await laptop.connect()

        await phone.eventually { await $0.runningEntry()?.taskId == second }
        await laptop.eventually { await $0.tasks().contains { $0.id == first } }
        #expect(await laptop.store.runningEntry()?.taskId == second)
        let stopped = try await phone.store.entries(for: first)
        #expect(stopped.allSatisfy { !$0.isRunning })
    }

    @Test func wrongTokenIsReported() async throws {
        let device = try Device()

        try await device.connect(token: "wrong-token")

        await device.eventually { await $0.problem == .unauthorized }
    }

    @Test func restartedServerIsResyncedWithoutLosingData() async throws {
        let phone = try Device()
        let laptop = try Device()
        try await phone.connect()
        try await laptop.connect()
        let before = try await phone.store.create(title: "before restart")
        await laptop.eventually { _ in await laptop.title(of: before) != nil }
        let oldPosition = try #require(try laptop.file.openCore().lastEventId())

        try await TestServer.restart()
        let after = try await phone.store.create(title: "after restart")

        await laptop.eventually { _ in await laptop.title(of: after) != nil }
        #expect(await laptop.title(of: before) == "before restart")
        let newPosition = try #require(try laptop.file.openCore().lastEventId())
        #expect(newPosition.split(separator: ":").first != oldPosition.split(separator: ":").first)
    }
}
#endif
