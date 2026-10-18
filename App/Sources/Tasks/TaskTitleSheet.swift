import SwiftUI
import TrackdoKit

/// Adds a task, or renames one. The sheet stays open until the title is
/// accepted.
struct TaskTitleSheet: View {
    enum Purpose: Identifiable {
        case add
        case rename(TaskItem)

        var id: String {
            switch self {
            case .add: "add"
            case let .rename(item): "rename-\(item.id)"
            }
        }
    }

    let model: TaskListModel
    let purpose: Purpose

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var issue: TitleIssue?
    @FocusState private var isFocused: Bool

    init(model: TaskListModel, purpose: Purpose) {
        self.model = model
        self.purpose = purpose
        switch purpose {
        case .add: _title = State(initialValue: "")
        case let .rename(item): _title = State(initialValue: item.title ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DadsInputText(
                    label: "Title",
                    isRequired: true,
                    support: "One line, for example Write the weekly report.",
                    error: issue?.message,
                    isFocused: isFocused
                ) {
                    TextField("", text: $title)
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(save)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .background(DadsColor.white)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: save)
                }
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.message)).post()
            }
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch purpose {
        case .add: "New Task"
        case .rename: "Rename Task"
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch purpose {
        case .add: "Add"
        case .rename: "Save"
        }
    }

    private func save() {
        Task {
            do throws(TitleIssue) {
                switch purpose {
                case .add: try await model.add(title: title)
                case let .rename(item): try await model.rename(item.id, to: title)
                }
                dismiss()
            } catch {
                issue = error
            }
        }
    }
}
