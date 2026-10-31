import SwiftUI
import TrackdoKit

/// Asks for a task's title, to add a task or subtask or to rename one. The
/// sheet stays open until the title is accepted.
struct TaskTitleSheet: View {
    let navigationTitle: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let save: (String) async throws(TitleIssue) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var issue: TitleIssue?
    @FocusState private var isFocused: Bool

    init(
        _ navigationTitle: LocalizedStringKey,
        confirm confirmTitle: LocalizedStringKey,
        title: String = "",
        save: @escaping (String) async throws(TitleIssue) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.confirmTitle = confirmTitle
        self.save = save
        _title = State(initialValue: title)
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
                        .onSubmit(submit)
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
                    Button(confirmTitle, action: submit)
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

    private func submit() {
        Task {
            do throws(TitleIssue) {
                try await save(title)
                dismiss()
            } catch {
                issue = error
            }
        }
    }
}
