import SwiftUI
import TrackdoKit

/// One task's time entries: the total, the entries newest first with their
/// marks, and editing, deleting and adding past work.
struct TaskDetailView: View {
    @State private var model: TaskDetailModel
    /// Changes when synced edits arrive, so the entries follow them.
    let revision: Int

    @State private var sheet: EntryTimesSheet.Purpose?
    @State private var pendingDeletion: EntryItem?

    init(taskId: String, store: TrackdoStore, revision: Int) {
        _model = State(initialValue: TaskDetailModel(taskId: taskId, store: store))
        self.revision = revision
    }

    var body: some View {
        List {
            banners
            if let task = model.task {
                summary(task)
                    .listRowSeparator(.hidden)
                    .listRowBackground(DadsColor.white)
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
                    Button("Add Past Entry", systemImage: "plus") { sheet = .add }
                }
            }
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

    /// Title and total, as a DADS heading and description list.
    private func summary(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: task.displayTitle)
                .dadsFont(.std24B150)
                .foregroundStyle(DadsColor.gray900)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .dadsFont(.std16B170)
                    .foregroundStyle(DadsColor.gray800)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let ms = model.totalMs(at: context.date)
                    Text(verbatim: ElapsedTime.clock(ms))
                        .dadsFont(.std20B150)
                        .monospacedDigit()
                        .foregroundStyle(DadsColor.gray900)
                        .accessibilityLabel(Text(verbatim: ElapsedTime.spoken(ms)))
                }
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .dadsFont(.std16B170)
                    .foregroundStyle(DadsColor.gray800)
                Text(task.isRunning ? "Timer running" : task.isDone ? "Done" : "To do")
                    .dadsFont(.std16N170)
                    .foregroundStyle(DadsColor.gray900)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 16)
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
            Text("Time Entries")
                .dadsFont(.std20B150)
                .foregroundStyle(DadsColor.gray900)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No time recorded yet. Start the timer from the task list, or add work you did earlier.")
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
