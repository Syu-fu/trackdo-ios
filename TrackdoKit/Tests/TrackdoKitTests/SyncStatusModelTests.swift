import Foundation
import Testing
@testable import TrackdoKit

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyncStatusModelTests {
    let server = StubServer(handler: routes())
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "SyncStatusModelTests-\(UUID().uuidString)")
    )
    let store: TrackdoStore

    init() throws {
        server.holdOpen("events")
        store = try TrackdoStore(file: file)
    }

    var client: ServerClient {
        ServerClient(settings: try! ServerSettings(url: server.url, token: "secret"), session: server.session)
    }

    /// Returns once the model shows `status`.
    func wait(for status: SyncStatus, in model: SyncStatusModel) async {
        while model.status != status {
            await Task.yield()
        }
    }

    @Test func startsFromTheStoreStatus() async {
        let model = SyncStatusModel(store: store)

        await model.start()

        #expect(model.status == .off)
    }

    @Test func followsTheStore() async {
        let model = SyncStatusModel(store: store)
        await model.start()

        await store.connect(client: client)
        await wait(for: .live, in: model)
        await store.suspend()
        await wait(for: .paused, in: model)
    }

    @Test(arguments: [
        (SyncStatus.failing(.unreachable), true),
        (.failing(.unexpected("x")), true),
        (.failing(.serverInconsistent("x")), true),
        (.failing(.unauthorized), false),
        (.failing(.unsupportedProtocol), false),
        (.failing(.saveFailed("x")), false),
        (.live, false),
        (.off, false),
    ])
    func onlyFailuresRetryingCanFixOfferRetry(status: SyncStatus, expected: Bool) {
        #expect(status.canRetryNow == expected)
    }
}
