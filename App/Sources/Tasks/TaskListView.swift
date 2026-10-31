import SwiftUI
import TrackdoKit

/// Where the task list leads.
enum TaskRoute: Hashable {
    case task(String)
    case sync
}

/// What the list asks a title for.
private enum TitleSheet: Identifiable {
    case add
    case rename(TaskItem)

    var id: String {
        switch self {
        case .add: "add"
        case let .rename(item): "rename-\(item.id)"
        }
    }
}

/// The app's home: every task, Sync settings in the navigation bar, and the
/// running timer and Add Task at the bottom. Everything works without a
/// server.
struct TaskListView: View {
    let model: TaskListModel
    let store: TrackdoStore
    let settings: SettingsEditor
    let syncStatus: SyncStatusModel

    @State private var path: [TaskRoute] = []
    @State private var sheet: TitleSheet?
    @State private var pendingDeletion: TaskItem?

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: TaskRoute.self) { route in
                    switch route {
                    case let .task(id):
                        TaskDetailView(taskId: id, store: store, revision: model.revision) { path.append(.task($0)) }
                    case .sync: SettingsView(editor: settings, status: syncStatus)
                    }
                }
        }
    }

    private var list: some View {
        List {
            if let issue = model.issue {
                DadsNotificationBanner(kind: .error, title: issue.title, description: issue.description)
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
                NavigationLink(value: TaskRoute.sync) {
                    Label("Sync Settings", systemImage: "gearshape")
                }
            }
            // Stopping and adding are frequent, so they sit at the bottom,
            // where the thumb of the hand holding the phone reaches; Add
            // Task takes the trailing corner.
            if let timer = model.running {
                ToolbarItem(placement: .bottomBar) {
                    RunningTimerBar(model: model, timer: timer) {
                        path.append(.task(timer.taskId))
                    }
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Add Task", systemImage: "plus") { sheet = .add }
                    .buttonStyle(.glassProminent)
                    .tint(DadsColor.key900)
            }
        }
        .sheet(item: $sheet) { purpose in
            Group {
                switch purpose {
                case .add:
                    TaskTitleSheet("New Task", confirm: "Add") { title throws(TitleIssue) in
                        try await model.add(title: title)
                    }
                case let .rename(item):
                    TaskTitleSheet("Rename Task", confirm: "Save", title: item.title ?? "") { title throws(TitleIssue) in
                        try await model.rename(item.id, to: title)
                    }
                }
            }
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
            item.deletionMessage
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
                    TaskRow(item: item, totalMs: { model.totalMs(of: item, at: $0) }) { perform($0, on: item) }
                        // The row's 44 pt targets carry their own space; the
                        // default insets would only make the row taller.
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
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
        case .open:
            path.append(.task(item.id))
        case .rename:
            sheet = .rename(item)
        case .toggleDone:
            Task { item.isDone ? await model.reopen(item.id) : await model.complete(item.id) }
        case .toggleTimer:
            Task { item.isRunning ? await model.stop() : await model.start(item.id) }
        case .delete:
            pendingDeletion = item
        }
    }
}
