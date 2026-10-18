import Foundation
import Testing
@testable import TrackdoKit

/// A clock the tests move by hand.
@MainActor
final class ManualClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(by seconds: TimeInterval) {
        now += seconds
    }
}

@MainActor
@Suite struct TaskListModelTests {
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TaskListModelTests-\(UUID().uuidString)")
    )
    let clock = ManualClock()
    let store: TrackdoStore

    init() throws {
        store = try TrackdoStore(file: file)
    }

    func makeModel() async -> TaskListModel {
        let model = TaskListModel(store: store) { [clock] in clock.now }
        await model.reload()
        return model
    }

    @Test func startsEmpty() async {
        let model = await makeModel()

        #expect(model.openTasks.isEmpty)
        #expect(model.doneTasks.isEmpty)
        #expect(model.running == nil)
        #expect(model.issue == nil)
    }

    @Test func reloadShowsChangesMadeElsewhere() async throws {
        let model = await makeModel()

        let id = try await store.create(title: "Write report")
        await model.reload()

        #expect(model.openTasks.map(\.id) == [id])
        #expect(model.openTasks.first?.title == "Write report")
    }

    // MARK: Adding and renaming

    @Test func addedTasksAreListedInOrder() async throws {
        let model = await makeModel()

        try await model.add(title: "First")
        try await model.add(title: "  Second\t")

        #expect(model.openTasks.map(\.title) == ["First", "Second"])
        #expect(await store.tasks().count == 2)
    }

    @Test(arguments: [
        ("", TitleIssue.empty),
        ("   ", .empty),
        ("Two\nlines", .containsLineBreak),
        (String(repeating: "a", count: 10_000), .tooLong(max: 500)),
    ])
    func invalidTitlesAreRejected(title: String, expected: TitleIssue) async {
        let model = await makeModel()

        await #expect(throws: expected) {
            try await model.add(title: title)
        }
        #expect(model.openTasks.isEmpty)
        #expect(model.issue == nil)
    }

    @Test func renamingChangesTheTitle() async throws {
        let model = await makeModel()
        try await model.add(title: "Draft")
        let id = try #require(model.openTasks.first?.id)

        try await model.rename(id, to: " Final ")

        #expect(model.openTasks.first?.title == "Final")
    }

    @Test func renamingToAnInvalidTitleKeepsTheOldOne() async throws {
        let model = await makeModel()
        try await model.add(title: "Draft")
        let id = try #require(model.openTasks.first?.id)

        await #expect(throws: TitleIssue.empty) {
            try await model.rename(id, to: "")
        }
        #expect(model.openTasks.first?.title == "Draft")
    }

    // MARK: Completing and deleting

    @Test func completedTasksMoveToDoneAndBack() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        try await model.add(title: "b")
        let id = try #require(model.openTasks.first?.id)

        await model.complete(id)

        #expect(model.openTasks.map(\.title) == ["b"])
        #expect(model.doneTasks.map(\.id) == [id])
        #expect(model.doneTasks.first?.isDone == true)

        await model.reopen(id)

        #expect(model.openTasks.map(\.title) == ["a", "b"])
        #expect(model.doneTasks.isEmpty)
    }

    @Test func deletedTasksDisappear() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)

        await model.delete(id)

        #expect(model.openTasks.isEmpty)
        #expect(await store.tasks().isEmpty)
    }

    // MARK: Timer

    @Test func startingShowsTheRunningTimer() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)

        await model.start(id)

        #expect(model.running?.taskId == id)
        #expect(model.running?.title == "a")
        #expect(model.openTasks.first?.isRunning == true)
    }

    @Test func startingAnotherTaskMovesTheTimer() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        try await model.add(title: "b")
        let ids = model.openTasks.map(\.id)

        await model.start(ids[0])
        await model.start(ids[1])

        #expect(model.running?.taskId == ids[1])
        #expect(model.openTasks.map(\.isRunning) == [false, true])
    }

    @Test func startingADoneTaskReopensIt() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        await model.complete(id)

        await model.start(id)

        #expect(model.openTasks.map(\.id) == [id])
        #expect(model.running?.taskId == id)
    }

    @Test func stoppingEndsTheTimer() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        await model.start(id)

        await model.stop()

        #expect(model.running == nil)
        #expect(model.openTasks.first?.isRunning == false)
        #expect(await store.runningEntry() == nil)
    }

    @Test func stoppingWithoutATimerDoesNothing() async {
        let model = await makeModel()

        await model.stop()

        #expect(model.issue == nil)
    }

    @Test func deletingTheRunningTaskEndsTheTimer() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        await model.start(id)

        await model.delete(id)

        #expect(model.running == nil)
    }

    @Test func runningTimesCountUpFromTheLastReload() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        try await model.add(title: "b")
        let ids = model.openTasks.map(\.id)
        await model.start(ids[0])
        let running = try #require(model.running)
        let total = try #require(model.openTasks.first)
        let idle = try #require(model.openTasks.last)

        clock.advance(by: 90)

        #expect(model.elapsedMs(of: running, at: clock.now) == running.elapsedMs + 90_000)
        #expect(model.totalMs(of: total, at: clock.now) == total.totalMs + 90_000)
        #expect(model.totalMs(of: idle, at: clock.now) == idle.totalMs)
    }

    @Test func timesNeverCountBackwards() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        await model.start(id)
        let running = try #require(model.running)

        clock.advance(by: -60)

        #expect(model.elapsedMs(of: running, at: clock.now) == running.elapsedMs)
    }

    // MARK: Failures

    @Test func commandsOnTasksGoneElsewhereAreReported() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        try await store.delete(taskId: id)

        await model.complete(id)

        #expect(model.issue == .taskGone)
        #expect(model.openTasks.isEmpty)
    }

    @Test func aSuccessfulCommandClearsTheIssue() async throws {
        let model = await makeModel()
        try await model.add(title: "a")
        let id = try #require(model.openTasks.first?.id)
        try await store.delete(taskId: id)
        await model.start(id)

        try await model.add(title: "b")

        #expect(model.issue == nil)
    }
}
