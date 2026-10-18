import SwiftUI
import TrackdoKit

/// The app's home: every task, the running timer on top, and Sync settings
/// in the toolbar. Everything works without a server.
struct TaskListView: View {
    let model: TaskListModel
    let settings: SettingsEditor

    @State private var sheet: TaskTitleSheet.Purpose?
    @State private var pendingDeletion: TaskItem?

    var body: some View {
        List {
            if let issue = model.issue {
                DadsNotificationBanner(kind: .error, title: issue.title, description: issue.description)
                    .bannerRow()
            }
            if let timer = model.running {
                RunningTimerBanner(model: model, timer: timer)
                    .bannerRow()
            }
            if model.openTasks.isEmpty && model.doneTasks.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            }
            section("To Do", model.openTasks)
            section("Done", model.doneTasks)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DadsColor.white)
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(editor: settings)
                } label: {
                    Label("Sync Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Task", systemImage: "plus") { sheet = .add }
            }
        }
        .sheet(item: $sheet) { purpose in
            TaskTitleSheet(model: model, purpose: purpose)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { item in
            Button("Delete Task", role: .destructive) {
                Task { await model.delete(item.id) }
            }
        } message: { item in
            Text("“\(item.displayTitle)” and its time entries are deleted on every device. This can’t be undone.")
        }
        .onChange(of: model.issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.title)).post()
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ items: [TaskItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    TaskRow(model: model, item: item) { perform($0, on: item) }
                        .listRowBackground(DadsColor.white)
                        .listRowSeparatorTint(DadsColor.gray420)
                        .swipeActions(edge: .leading) {
                            Button(item.isDone ? "Reopen" : "Complete",
                                   systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark") {
                                perform(.toggleDone, on: item)
                            }
                            .tint(DadsColor.success2)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash") { perform(.delete, on: item) }
                                .tint(DadsColor.error1)
                        }
                }
            } header: {
                Text(title)
                    .dadsFont(.std20B150)
                    .foregroundStyle(DadsColor.gray900)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No tasks yet")
                .dadsFont(.std20B150)
                .foregroundStyle(DadsColor.gray900)
                .accessibilityAddTraits(.isHeader)
            Text("Add what you work on, then start its timer. Your tasks are kept on this device; set up Sync to see them on your other devices too.")
                .dadsFont(.std16N170)
                .foregroundStyle(DadsColor.gray800)
            Button {
                sheet = .add
            } label: {
                Label("Add Task", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dads(.solidFill))
        }
        .padding(.vertical, 24)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }
    }

    private func perform(_ action: TaskRowAction, on item: TaskItem) {
        switch action {
        case .rename:
            sheet = .rename(item)
        case .toggleDone:
            Task { item.isDone ? await model.reopen(item.id) : await model.complete(item.id) }
        case .delete:
            pendingDeletion = item
        }
    }
}

private extension View {
    /// A banner as a list row: full width, no separator.
    func bannerRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(DadsColor.white)
    }
}
