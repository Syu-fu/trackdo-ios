import Foundation
import Testing
import TrackdoFFI
@testable import TrackdoKit

@MainActor
@Suite struct TaskDetailModelTests {
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TaskDetailModelTests-\(UUID().uuidString)")
    )
    let clock = ManualClock()
    let store: TrackdoStore
    /// Two hours ago, on a whole second.
    let earlier = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 7200).rounded(.down))

    init() throws {
        store = try TrackdoStore(file: file)
    }

    func makeModel(for taskId: String) async -> TaskDetailModel {
        let model = TaskDetailModel(taskId: taskId, store: store) { [clock] in clock.now }
        await model.reload()
        return model
    }

    func ms(_ date: Date) -> UInt64 {
        UInt64(date.timeIntervalSince1970 * 1000)
    }

    @Test func showsTheTaskAndItsEntriesNewestFirst() async throws {
        let id = try await store.create(title: "Report")
        let older = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 600))
        let newer = try await store.addEntry(
            taskId: id, startedAtMs: ms(earlier + 3600), stoppedAtMs: ms(earlier + 4500)
        )

        let model = await makeModel(for: id)

        #expect(model.task?.title == "Report")
        #expect(model.task?.totalMs == 1_500_000)
        #expect(model.entries.map(\.id) == [newer, older])
        let entry = try #require(model.entries.last)
        #expect(entry.startedAt == earlier)
        #expect(entry.stoppedAt == earlier + 600)
        #expect(entry.durationMs == 600_000)
        #expect(!entry.isRunning)
        #expect(!entry.needsAttention)
        #expect(model.issue == nil)
    }

    @Test func aDeletedTaskShowsNothing() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)

        try await store.delete(taskId: id)
        await model.reload()

        #expect(model.task == nil)
        #expect(model.entries.isEmpty)
    }

    // MARK: Adding

    @Test func addingRecordsPastWork() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        try await model.addEntry(start: earlier, stop: earlier + 900)

        #expect(model.entries.map(\.durationMs) == [900_000])
        #expect(model.task?.totalMs == 900_000)
        #expect(try await store.entries(for: id).count == 1)
    }

    @Test func addingRejectsAStopBeforeTheStart() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        await #expect(throws: EntryTimesIssue.stopBeforeStart) {
            try await model.addEntry(start: earlier + 900, stop: earlier)
        }
        #expect(model.entries.isEmpty)
        #expect(model.issue == nil)
    }

    @Test func addingRejectsTimesInTheFuture() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        await #expect(throws: EntryTimesIssue.inFuture) {
            try await model.addEntry(start: earlier, stop: Date() + 3600)
        }
        #expect(model.entries.isEmpty)
    }

    // MARK: Editing and deleting

    @Test func editingChangesTheTimes() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)

        try await model.editTimes(entry.id, start: earlier - 60, stop: earlier + 120)

        #expect(model.entries.first?.startedAt == earlier - 60)
        #expect(model.entries.first?.durationMs == 180_000)
    }

    @Test func editingToInvalidTimesKeepsTheOldOnes() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)

        await #expect(throws: EntryTimesIssue.stopBeforeStart) {
            try await model.editTimes(entry.id, start: earlier, stop: earlier - 60)
        }
        #expect(model.entries.first == entry)
    }

    @Test func editingTheRunningEntryKeepsItRunning() async throws {
        let id = try await store.create(title: "Report")
        try await store.start(taskId: id)
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)

        try await model.editTimes(entry.id, start: earlier, stop: nil)

        #expect(model.entries.first?.isRunning == true)
        #expect(model.entries.first?.startedAt == earlier)
    }

    @Test func deletedEntriesDisappear() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)

        await model.deleteEntry(entry.id)

        #expect(model.entries.isEmpty)
        #expect(model.task?.totalMs == 0)
    }

    @Test func entriesGoneElsewhereAreReported() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)
        try await store.deleteEntry(entryId: entry.id)

        await model.deleteEntry(entry.id)

        #expect(model.issue == .taskGone)
        #expect(model.entries.isEmpty)
    }

    // MARK: Marks and live times

    /// Derived stops and conflicting times arise only from synced writes,
    /// so the conversion is checked directly.
    @Test func entriesKeepTheirMarks() {
        let record = EntryRecord(
            id: "e", taskId: "t", startedAtMs: 2000, stoppedAtMs: 1000, isRunning: false,
            isStopDerived: true, needsAttention: true, durationMs: 0
        )

        let entry = EntryItem(record)

        #expect(entry.isStopDerived)
        #expect(entry.needsAttention)
        #expect(entry.startedAt == Date(timeIntervalSince1970: 2))
        #expect(entry.stoppedAt == Date(timeIntervalSince1970: 1))
    }

    @Test func entriesWithoutAKnownStartGoLast() {
        let known = EntryItem(EntryRecord(
            id: "known", taskId: "t", startedAtMs: 1000, stoppedAtMs: 2000, isRunning: false,
            isStopDerived: false, needsAttention: false, durationMs: 1000
        ))
        let unknown = EntryItem(EntryRecord(
            id: "unknown", taskId: "t", startedAtMs: nil, stoppedAtMs: nil, isRunning: false,
            isStopDerived: false, needsAttention: false, durationMs: 0
        ))

        #expect([unknown, known].sorted(by: TaskDetailModel.newestFirst).map(\.id) == ["known", "unknown"])
        #expect([known, unknown].sorted(by: TaskDetailModel.newestFirst).map(\.id) == ["known", "unknown"])
    }

    @Test func theRunningEntryCountsUpFromTheLastReload() async throws {
        let id = try await store.create(title: "Report")
        try await store.start(taskId: id)
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)
        let task = try #require(model.task)

        clock.advance(by: 30)

        #expect(model.durationMs(of: entry, at: clock.now) == entry.durationMs + 30_000)
        #expect(model.totalMs(at: clock.now) == task.totalMs + 30_000)
    }

    @Test func stoppedEntriesDoNotCountUp() async throws {
        let id = try await store.create(title: "Report")
        _ = try await store.addEntry(taskId: id, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        let model = await makeModel(for: id)
        let entry = try #require(model.entries.first)

        clock.advance(by: 30)

        #expect(model.durationMs(of: entry, at: clock.now) == 60_000)
        #expect(model.totalMs(at: clock.now) == 60_000)
    }

    @Test func aRunningSubtaskCountsUpFromTheLastReload() async throws {
        let id = try await store.create(title: "Move")
        let running = try await store.createSubtask(parentId: id, title: "Pack")
        let idle = try await store.createSubtask(parentId: id, title: "Buy")
        _ = try await store.addEntry(taskId: idle, startedAtMs: ms(earlier), stoppedAtMs: ms(earlier + 60))
        try await store.start(taskId: running)
        let model = await makeModel(for: id)
        let subtasks = Dictionary(uniqueKeysWithValues: model.subtasks.map { ($0.id, $0) })

        clock.advance(by: 30)

        let runningItem = try #require(subtasks[running])
        #expect(model.totalMs(of: runningItem, at: clock.now) == runningItem.totalMs + 30_000)
        #expect(model.totalMs(of: try #require(subtasks[idle]), at: clock.now) == 60_000)
        #expect(model.totalMs(at: clock.now) == 0)
    }
}
