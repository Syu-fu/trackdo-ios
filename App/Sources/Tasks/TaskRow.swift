import SwiftUI
import TrackdoKit

/// What a row asks the list to do.
enum TaskRowAction {
    case open
    case rename
    case toggleDone
    case delete
}

/// One task in the DADS resource list style (components/resource-list),
/// laid out by how often each part is used. Completing and timing are
/// frequent, so each takes one tap: the checkbox on the leading side, as
/// DADS places checkboxes, and the timer button. Renaming and deleting are
/// rare, so they wait in the More menu, which also stands in for the swipe
/// actions. Dense text keeps the row short so more tasks fit on screen.
/// The row holds buttons, so only the title and time open the task.
struct TaskRow: View {
    let model: TaskListModel
    let item: TaskItem
    let onAction: (TaskRowAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        HStack(spacing: 4) {
            doneButton
            layout {
                contents
                HStack(spacing: 4) {
                    timerButton
                    moreMenu
                }
            }
        }
        .padding(.vertical, 4)
        // The resource list's separator spans the whole row, between the
        // list's 16 pt margins; the row itself is inset only 6 pt.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 10 }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width - 10 }
    }

    private var doneButton: some View {
        Button {
            onAction(.toggleDone)
        } label: {
            Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(item.isDone ? DadsColor.key900 : DadsColor.gray600)
        }
        .buttonStyle(CheckboxButtonStyle())
        .accessibilityLabel(item.isDone
            ? Text("Reopen \(item.displayTitle)")
            : Text("Complete \(item.displayTitle)"))
    }

    private var contents: some View {
        Button {
            onAction(.open)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.displayTitle)
                    .strikethrough(item.isDone)
                    .multilineTextAlignment(.leading)
                    .dadsFont(.dns16B130)
                    .foregroundStyle(item.isDone ? DadsColor.gray600 : DadsColor.gray900)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let ms = model.totalMs(of: item, at: context.date)
                    Text(verbatim: ElapsedTime.clock(ms))
                        .dadsFont(.dns14N130)
                        .monospacedDigit()
                        .foregroundStyle(DadsColor.gray700)
                        .accessibilityLabel(Text("Total \(ElapsedTime.spoken(ms))"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? Text("Done") : Text(verbatim: ""))
        .accessibilityHint(Text("Shows its time entries."))
    }

    @ViewBuilder private var timerButton: some View {
        if item.isRunning {
            Button {
                Task { await model.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.dads(.solidFill, size: .icon))
            .accessibilityLabel(Text("Stop timer for \(item.displayTitle)"))
        } else {
            Button {
                Task { await model.start(item.id) }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.dads(.outline, size: .icon))
            .accessibilityLabel(Text("Start timer for \(item.displayTitle)"))
        }
    }

    /// The resource list's action button, 44 pt square.
    private var moreMenu: some View {
        Menu {
            Button("Rename", systemImage: "pencil") { onAction(.rename) }
            Button("Delete", systemImage: "trash", role: .destructive) { onAction(.delete) }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundStyle(DadsColor.gray800)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("More for \(item.displayTitle)"))
    }
}

/// The checkbox's 44 pt target, dimmed while pressed.
private struct CheckboxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
