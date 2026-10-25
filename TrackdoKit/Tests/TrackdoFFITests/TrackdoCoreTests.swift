import Testing
import TrackdoFFI

@Suite struct TrackdoCoreTests {
    @Test func speaksProtocolVersion4() {
        #expect(protocolVersion() == 4)
    }

    @Test func createdTaskIsListed() throws {
        let core = TrackdoCore()

        let id = try core.create(title: "buy milk")

        let tasks = core.tasks()
        #expect(tasks.map(\.id) == [id])
        #expect(tasks.first?.title == "buy milk")
    }

    @Test func commandErrorsSurfaceAsFfiError() {
        let core = TrackdoCore()

        #expect(throws: FfiError.EmptyTitle) {
            try core.create(title: "  ")
        }
    }

    @Test func freshCoreNeedsSnapshotAndHasPendingOps() throws {
        let core = TrackdoCore()
        #expect(core.needsSnapshot())

        _ = try core.create(title: "a")

        #expect(core.nextPushBatch() != nil)
    }
}
