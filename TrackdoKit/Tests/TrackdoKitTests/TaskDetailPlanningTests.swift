import Foundation
import Testing
@testable import TrackdoKit

@MainActor
@Suite struct TaskDetailPlanningTests {
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TaskDetailPlanningTests-\(UUID().uuidString)")
    )
    let store: TrackdoStore

    init() throws {
        store = try TrackdoStore(file: file)
    }

    func makeModel(for taskId: String) async -> TaskDetailModel {
        let model = TaskDetailModel(taskId: taskId, store: store)
        await model.reload()
        return model
    }

    // MARK: Planning

    @Test func planningFieldsCanBeSetAndCleared() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)
        let due = CalendarDay(year: 2026, month: 10, day: 31)
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)

        await model.setPriority(.medium)
        try await model.setNote("Ask first\n")
        await model.setDue(due)
        await model.schedule(scheduled)
        let planned = try #require(model.task)
        try await model.setNote(" ")
        await model.setDue(nil)
        await model.schedule(nil)

        #expect(planned.priority == .medium)
        #expect(planned.note == "Ask first")
        #expect(planned.due == due)
        #expect(planned.scheduledAt == scheduled)
        #expect(model.task?.note == nil)
        #expect(model.task?.due == nil)
        #expect(model.task?.scheduledAt == nil)
        #expect(model.issue == nil)
    }

    @Test func renamingChecksTheTitle() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        try await model.rename(to: " Summary ")
        await #expect(throws: TitleIssue.empty) {
            try await model.rename(to: "  ")
        }

        #expect(model.task?.title == "Summary")
    }

    @Test func aTooLongNoteIsRefused() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        await #expect(throws: NoteIssue.tooLong(max: 10_000)) {
            try await model.setNote(String(repeating: "a", count: 10_001))
        }
        #expect(model.task?.note == nil)
    }

    @Test func deletingTakesTheSubtasksAlong() async throws {
        let id = try await store.create(title: "Move house")
        try await store.createSubtask(parentId: id, title: "Boxes")
        let model = await makeModel(for: id)

        await model.delete()

        #expect(model.task == nil)
        #expect(model.subtasks.isEmpty)
        #expect(await store.tasks().isEmpty)
    }

    // MARK: Subtasks

    @Test func showsTheParentAndTheSubtasks() async throws {
        let parent = try await store.create(title: "Move house")
        let id = try await store.createSubtask(parentId: parent, title: "Boxes")
        let first = try await store.createSubtask(parentId: id, title: "Buy")
        let second = try await store.createSubtask(parentId: id, title: "Pack")
        try await store.complete(taskId: second)

        let model = await makeModel(for: id)

        #expect(model.parent?.id == parent)
        #expect(model.subtasks.map(\.id) == [first, second])
        #expect(model.subtasks.map(\.isDone) == [false, true])
        #expect(model.task?.subtaskCount == 2)
        #expect(model.task?.doneSubtaskCount == 1)
    }

    @Test func subtasksCanBeAddedCompletedAndTimed() async throws {
        let id = try await store.create(title: "Move house")
        let model = await makeModel(for: id)

        try await model.addSubtask(title: " Boxes ")
        let sub = try #require(model.subtasks.first)
        await model.start(sub.id)
        let running = model.subtasks.first?.isRunning
        await model.stopTimer()
        await model.complete(sub.id)
        let done = model.subtasks.first?.isDone
        await model.reopen(sub.id)

        #expect(sub.title == "Boxes")
        #expect(running == true)
        #expect(done == true)
        #expect(model.subtasks.first?.isDone == false)
        #expect(model.subtasks.first?.isRunning == false)
        await #expect(throws: TitleIssue.empty) {
            try await model.addSubtask(title: " ")
        }
        #expect(model.subtasks.count == 1)
    }

    @Test func stoppingWithoutATimerDoesNothing() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        await model.stopTimer()

        #expect(model.issue == nil)
    }

    @Test func movingOffersEveryTaskNotBelowIt() async throws {
        let root = try await store.create(title: "Root")
        let child = try await store.createSubtask(parentId: root, title: "Child")
        let grandchild = try await store.createSubtask(parentId: child, title: "Grandchild")
        let other = try await store.create(title: "Other")

        let model = await makeModel(for: child)

        #expect(model.moveTargets.map(\.id) == [root, other])
        #expect(!model.moveTargets.contains { $0.id == grandchild })
    }

    @Test func movingChangesTheParent() async throws {
        let id = try await store.create(title: "Boxes")
        let other = try await store.create(title: "Move house")
        let model = await makeModel(for: id)

        await model.move(under: other)
        let moved = model.parent?.id
        await model.move(under: nil)

        #expect(moved == other)
        #expect(model.parent == nil)
    }

    @Test func aMoveIntoItselfIsReported() async throws {
        let root = try await store.create(title: "Root")
        let child = try await store.createSubtask(parentId: root, title: "Child")
        let model = await makeModel(for: root)

        await model.move(under: child)

        #expect(model.issue == .wouldCycle)
        #expect(model.parent == nil)
    }
}
