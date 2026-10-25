import Foundation
import Testing
@testable import TrackdoKit

@MainActor
@Suite struct TaskTagsModelTests {
    let file = StateFile(
        directory: FileManager.default.temporaryDirectory.appending(path: "TaskTagsModelTests-\(UUID().uuidString)")
    )
    let store: TrackdoStore

    init() throws {
        store = try TrackdoStore(file: file)
    }

    func makeModel(for taskId: String) async -> TaskTagsModel {
        let model = TaskTagsModel(taskId: taskId, store: store)
        await model.reload()
        return model
    }

    @Test func showsEveryTagAndWhichAreOnTheTask() async throws {
        let id = try await store.create(title: "Report")
        let work = try await store.createTag(name: "work")
        let home = try await store.createTag(name: "home")
        try await store.tagTask(taskId: id, tagId: work)

        let model = await makeModel(for: id)

        #expect(model.tags.map(\.id) == [home, work])
        #expect(model.selected == [work])
    }

    @Test func togglingPutsATagOnAndTakesItOff() async throws {
        let id = try await store.create(title: "Report")
        let work = try await store.createTag(name: "work")
        let model = await makeModel(for: id)

        await model.toggle(work)
        let on = model.selected
        await model.toggle(work)

        #expect(on == [work])
        #expect(model.selected.isEmpty)
    }

    @Test func creatingPutsTheNewTagOnTheTask() async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        try await model.create(name: " work ")

        #expect(model.tags.map(\.name) == ["work"])
        #expect(model.selected == Set(model.tags.map(\.id)))
        await #expect(throws: TagNameIssue.empty) {
            try await model.create(name: " ")
        }
    }

    @Test func renamingRefusesATakenName() async throws {
        let id = try await store.create(title: "Report")
        let work = try await store.createTag(name: "work")
        try await store.createTag(name: "home")
        let model = await makeModel(for: id)

        try await model.rename(work, to: "office")
        await #expect(throws: TagNameIssue.taken) {
            try await model.rename(work, to: "home")
        }

        #expect(model.tags.map(\.name) == ["home", "office"])
    }

    @Test(arguments: [
        ("a\nb", TagNameIssue.containsLineBreak),
        (String(repeating: "a", count: 51), .tooLong(max: 50)),
    ])
    func invalidNamesAreRefused(name: String, expected: TagNameIssue) async throws {
        let id = try await store.create(title: "Report")
        let model = await makeModel(for: id)

        await #expect(throws: expected) {
            try await model.create(name: name)
        }
    }

    @Test func deletingTakesTheTagOffEveryTask() async throws {
        let id = try await store.create(title: "Report")
        let work = try await store.createTag(name: "work")
        try await store.tagTask(taskId: id, tagId: work)
        let model = await makeModel(for: id)

        await model.delete(work)

        #expect(model.tags.isEmpty)
        #expect(model.selected.isEmpty)
        #expect(await store.tasks().first?.tags.isEmpty == true)
    }

    @Test func aTagGoneElsewhereIsReported() async throws {
        let id = try await store.create(title: "Report")
        let work = try await store.createTag(name: "work")
        let model = await makeModel(for: id)
        try await store.deleteTag(tagId: work)

        await model.toggle(work)

        #expect(model.issue == .tagGone)
        #expect(model.tags.isEmpty)
    }
}
