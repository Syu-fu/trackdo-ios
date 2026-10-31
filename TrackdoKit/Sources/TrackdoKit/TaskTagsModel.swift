import Foundation
import Observation
import TrackdoFFI

/// Why a tag name was not accepted. Core decides.
public enum TagNameIssue: Error, Equatable, Sendable {
    case empty
    case containsLineBreak
    case tooLong(max: Int)
    /// Another tag has the name.
    case taken

    init?(_ error: FfiError) {
        switch error {
        case .EmptyTagName: self = .empty
        case .TagNameContainsLineBreak: self = .containsLineBreak
        case let .TagNameTooLong(max, _): self = .tooLong(max: Int(max))
        case .TagNameTaken: self = .taken
        default: return nil
        }
    }
}

/// Choosing a task's tags among every tag, and creating, renaming and
/// deleting tags.
@MainActor
@Observable
public final class TaskTagsModel {
    public let taskId: String
    /// Every tag that is not deleted, by name.
    public private(set) var tags: [TagItem] = []
    /// Ids of the tags on the task.
    public private(set) var selected: Set<String> = []
    public private(set) var issue: TaskListIssue?

    private let store: TrackdoStore

    public init(taskId: String, store: TrackdoStore) {
        self.taskId = taskId
        self.store = store
    }

    public func reload() async {
        tags = await store.tags().map(TagItem.init)
        let task = await store.tasks().first { $0.id == taskId }
        selected = Set(task?.tags.map(\.id) ?? [])
    }

    /// The tags whose names contain `query`, ignoring case and the spaces
    /// around it; every tag when it is blank.
    public func tags(matching query: String) -> [TagItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return tags
        }
        return tags.filter { $0.name.localizedStandardContains(query) }
    }

    /// Whether creating `name` would make a new tag. Core compares names
    /// exactly, after trimming.
    public func isNew(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !tags.contains { $0.name == name }
    }

    /// Puts the tag on the task or takes it off.
    public func toggle(_ tagId: String) async {
        let isSelected = selected.contains(tagId)
        try? await perform { [taskId] in
            if isSelected {
                try await $0.untagTask(taskId: taskId, tagId: tagId)
            } else {
                try await $0.tagTask(taskId: taskId, tagId: tagId)
            }
        }
    }

    /// Creates the tag, or finds the one already named so, and puts it on
    /// the task.
    public func create(name: String) async throws(TagNameIssue) {
        try await perform { [taskId] in
            let tagId = try await $0.createTag(name: name)
            try await $0.tagTask(taskId: taskId, tagId: tagId)
        }
    }

    public func rename(_ tagId: String, to name: String) async throws(TagNameIssue) {
        try await perform { try await $0.renameTag(tagId: tagId, name: name) }
    }

    /// Takes the tag off every task.
    public func delete(_ tagId: String) async {
        try? await perform { try await $0.deleteTag(tagId: tagId) }
    }

    /// Runs a command and reloads. A name the core refuses is thrown for the
    /// form to show; other failures are kept in ``issue``.
    private func perform(_ command: (TrackdoStore) async throws -> Void) async throws(TagNameIssue) {
        do {
            try await command(store)
            issue = nil
        } catch {
            if let ffiError = error as? FfiError, let nameIssue = TagNameIssue(ffiError) {
                throw nameIssue
            }
            issue = TaskListIssue(error)
        }
        await reload()
    }
}
