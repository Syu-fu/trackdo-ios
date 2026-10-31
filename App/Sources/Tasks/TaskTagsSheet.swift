import SwiftUI
import TrackdoKit

/// Chooses a task's tags. Tapping a tag puts it on or takes it off at once,
/// so the sheet only needs Done. The field at the top narrows the tags as
/// it is typed and adds the name as a new tag when none has it. Renaming
/// and deleting a tag are rare, so they wait behind a swipe.
struct TaskTagsSheet: View {
    @State private var model: TaskTagsModel
    @State private var query = ""
    @State private var nameIssue: TagNameIssue?
    @State private var renaming: TagItem?
    @State private var newName = ""
    @State private var pendingDeletion: TagItem?
    @Environment(\.dismiss) private var dismiss

    init(taskId: String, store: TrackdoStore) {
        _model = State(initialValue: TaskTagsModel(taskId: taskId, store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                if let issue = model.issue {
                    DadsNotificationBanner(kind: .error, title: issue.title, description: issue.description)
                        .bannerRow()
                }
                Section {
                    newTagField
                }
                Section {
                    ForEach(model.tags(matching: query)) { tag in
                        row(tag)
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Tag", isPresented: isRenaming, presenting: renaming) { tag in
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { rename(tag) }
            }
            .confirmationDialog(
                "Delete this tag?",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { tag in
                Button("Delete Tag", role: .destructive) {
                    Task { await model.delete(tag.id) }
                }
            } message: { tag in
                Text("“\(tag.name)” is taken off every task on every device. This can’t be undone.")
            }
        }
        .task { await model.reload() }
        .onChange(of: nameIssue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.message)).post()
            }
        }
    }

    private var newTagField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DadsColor.gray600)
                    .accessibilityHidden(true)
                TextField("Find or Add a Tag", text: $query)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .onChange(of: query) { nameIssue = nil }
                if model.isNew(query) {
                    Button("Add", action: create)
                        .buttonStyle(.borderless)
                        .tint(DadsColor.key900)
                        .accessibilityLabel(Text("Add Tag \(query.trimmingCharacters(in: .whitespaces))"))
                }
            }
            .frame(minHeight: 44)
            if let nameIssue {
                Text(nameIssue.message)
                    .dadsFont(.dns14N130)
                    .foregroundStyle(DadsColor.error1)
            }
        }
    }

    private func row(_ tag: TagItem) -> some View {
        let isSelected = model.selected.contains(tag.id)
        return Button {
            Task { await model.toggle(tag.id) }
        } label: {
            HStack {
                TagChip(tag: tag)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DadsColor.key900)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash") { pendingDeletion = tag }
                .tint(DadsColor.error1)
            Button("Rename", systemImage: "pencil") {
                newName = tag.name
                renaming = tag
            }
            .tint(DadsColor.key900)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding { renaming != nil } set: { if !$0 { renaming = nil } }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }
    }

    private func create() {
        guard model.isNew(query) else {
            return
        }
        Task {
            do throws(TagNameIssue) {
                try await model.create(name: query)
                query = ""
            } catch {
                nameIssue = error
            }
        }
    }

    private func rename(_ tag: TagItem) {
        Task {
            do throws(TagNameIssue) {
                try await model.rename(tag.id, to: newName)
                nameIssue = nil
            } catch {
                nameIssue = error
            }
        }
    }
}
