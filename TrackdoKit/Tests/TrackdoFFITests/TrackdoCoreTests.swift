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

    @Test func planningFieldsCrossTheBindings() throws {
        let core = TrackdoCore()
        let parent = try core.create(title: "project")

        let child = try core.createSubtask(parentId: parent, title: "step")
        try core.setPriority(taskId: child, priority: .high)
        try core.setDue(taskId: child, due: CalendarDate(year: 2026, month: 10, day: 31))
        let tag = try core.createTag(name: "home")
        try core.tagTask(taskId: child, tagId: tag)

        let listed = try #require(core.tasks().first { $0.id == child })
        #expect(listed.parentId == parent)
        #expect(listed.priority == .high)
        #expect(listed.due == CalendarDate(year: 2026, month: 10, day: 31))
        #expect(listed.tags == [TagRecord(id: tag, name: "home")])
        #expect(core.tags().map(\.name) == ["home"])
    }

    @Test func freshCoreNeedsSnapshotAndHasPendingOps() throws {
        let core = TrackdoCore()
        #expect(core.needsSnapshot())

        _ = try core.create(title: "a")

        #expect(core.nextPushBatch() != nil)
    }
}
