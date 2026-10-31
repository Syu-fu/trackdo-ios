import SwiftUI
import TrackdoKit

/// Puts a task under another one, or back at the top level. Its own
/// subtasks are not offered. Choosing moves it and closes the sheet.
struct MoveTaskSheet: View {
    let model: TaskDetailModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                destination(nil) {
                    Label("Top Level", systemImage: "tray")
                }
                if !model.moveTargets.isEmpty {
                    Section("Under a Task") {
                        ForEach(model.moveTargets) { target in
                            destination(target.id) {
                                Text(verbatim: target.displayTitle)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func destination(_ parentId: String?, @ViewBuilder label: () -> some View) -> some View {
        let isCurrent = model.parent?.id == parentId
        return Button {
            Task {
                if !isCurrent {
                    await model.move(under: parentId)
                }
                dismiss()
            }
        } label: {
            HStack {
                label()
                    .foregroundStyle(DadsColor.gray900)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DadsColor.key900)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
