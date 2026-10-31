import SwiftUI
import TrackdoKit

/// One task in full. Completing and timing are frequent, so the checkbox
/// and timer button sit beside the title, one tap each. Planning follows,
/// each field changed in place, then the time entries newest first with
/// their marks. Renaming, moving and deleting are rare, so they wait in the
/// More menu. A subtask links back to its parent above its title.
struct TaskDetailView: View {
    @State private var model: TaskDetailModel
    /// Changes when synced edits arrive, so the entries follow them.
    let revision: Int

    @State private var sheet: EntryTimesSheet.Purpose?
    @State private var pendingDeletion: EntryItem?
    @State private var isRenaming = false
    @State private var isMoving = false
    @State private var isConfirmingTaskDeletion = false
    @Environment(\.dismiss) private var dismiss

    init(taskId: String, store: TrackdoStore, revision: Int) {
        _model = State(initialValue: TaskDetailModel(taskId: taskId, store: store))
        self.revision = revision
    }

    var body: some View {
        List {
            banners
            if let task = model.task {
                header(task)
                    .listRowSeparator(.hidden)
                    .listRowBackground(DadsColor.white)
                Section {
                    TaskPlanningRows(model: model, task: task)
                }
                entriesSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DadsColor.white)
        .navigationTitle(model.task?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.task != nil {
                ToolbarItem(placement: .primaryAction) {
                    moreMenu
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            TaskTitleSheet("Rename Task", confirm: "Save", title: model.task?.title ?? "") { title throws(TitleIssue) in
                try await model.rename(to: title)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isMoving) {
            MoveTaskSheet(model: model)
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $isConfirmingTaskDeletion,
            titleVisibility: .visible,
            presenting: model.task
        ) { _ in
            Button("Delete Task", role: .destructive) {
                Task {
                    await model.delete()
                    dismiss()
                }
            }
        } message: { task in
            task.deletionMessage
        }
        .sheet(item: $sheet) { purpose in
            EntryTimesSheet(model: model, purpose: purpose)
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("Delete Entry", role: .destructive) {
                Task { await model.deleteEntry(entry.id) }
            }
        } message: { entry in
            Text("\(entry.spokenTimeRange) is deleted on every device. This can’t be undone.")
        }
        .task { await model.reload() }
        .onChange(of: revision) {
            Task { await model.reload() }
        }
        .onChange(of: model.issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.title)).post()
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if model.task == nil {
            DadsNotificationBanner(
                kind: .warning,
                title: "This task was deleted",
                description: "It may have been deleted on another device. Go back to see your tasks."
            )
            .bannerRow()
        }
        if let issue = model.issue {
            DadsNotificationBanner(kind: .error, title: issue.title, description: issue.description)
                .bannerRow()
        }
        if model.entries.contains(where: \.needsAttention) {
            DadsNotificationBanner(
                kind: .warning,
                title: "Some times need fixing",
                description: "Edits from two devices left an entry ending before it starts. Edit the entry marked Needs Fixing."
            )
            .bannerRow()
        }
    }

    /// The parent link, then the checkbox, title and timer, then the total.
    private func header(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let parent = model.parent {
                NavigationLink(value: TaskRoute.task(parent.id)) {
                    Label(parent.displayTitle, systemImage: "arrow.turn.left.up")
                        .lineLimit(1)
                        .dadsFont(.dns14N130)
                        .foregroundStyle(DadsColor.gray700)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Part of \(parent.displayTitle)"))
                .accessibilityHint(Text("Shows the parent task."))
            }
            HStack(alignment: .top, spacing: 4) {
                CheckboxButton(priority: task.priority, isDone: task.isDone, title: task.displayTitle) {
                    Task { task.isDone ? await model.reopen(task.id) : await model.complete(task.id) }
                }
                Text(verbatim: task.displayTitle)
                    .strikethrough(task.isDone)
                    .dadsFont(.std24B150)
                    .foregroundStyle(task.isDone ? DadsColor.gray600 : DadsColor.gray900)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(task.isDone ? Text("Done") : Text(verbatim: ""))
                TimerButton(isRunning: task.isRunning, title: task.displayTitle) {
                    Task { task.isRunning ? await model.stopTimer() : await model.start(task.id) }
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let ms = model.totalMs(at: context.date)
                Text("Total \(Text(verbatim: ElapsedTime.clock(ms)).monospacedDigit())")
                    .dadsFont(.dns16N130)
                    .foregroundStyle(DadsColor.gray700)
                    .accessibilityLabel(Text("Total \(ElapsedTime.spoken(ms))"))
            }
            .padding(.leading, 48)
        }
        .padding(.vertical, 8)
    }

    /// Rare actions on the task itself.
    private var moreMenu: some View {
        Menu {
            Button("Rename", systemImage: "pencil") { isRenaming = true }
            Button("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { isMoving = true }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingTaskDeletion = true }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    @ViewBuilder private var entriesSection: some View {
        Section {
            if model.entries.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(DadsColor.white)
            }
            ForEach(model.entries) { entry in
                EntryRow(model: model, entry: entry) { perform($0, on: entry) }
                    .listRowBackground(DadsColor.white)
                    .listRowSeparatorTint(DadsColor.gray420)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash") { perform(.delete, on: entry) }
                            .tint(DadsColor.error1)
                    }
                    .swipeActions(edge: .leading) {
                        if entry.startedAt != nil {
                            Button("Edit Times", systemImage: "pencil") { perform(.edit, on: entry) }
                                .tint(DadsColor.key900)
                        }
                    }
            }
        } header: {
            HStack {
                Text("Time Entries")
                    .dadsFont(.std20B150)
                    .foregroundStyle(DadsColor.gray900)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    sheet = .add
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .tint(DadsColor.key900)
                .accessibilityLabel(Text("Add Past Entry"))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No time recorded yet. Start the timer, or add work you did earlier.")
                .dadsFont(.std16N170)
                .foregroundStyle(DadsColor.gray800)
            Button {
                sheet = .add
            } label: {
                Label("Add Past Entry", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dads(.outline))
        }
        .padding(.vertical, 16)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }
    }

    private func perform(_ action: EntryRowAction, on entry: EntryItem) {
        switch action {
        case .edit: sheet = .edit(entry)
        case .delete: pendingDeletion = entry
        }
    }
}
