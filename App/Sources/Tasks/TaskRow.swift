import SwiftUI
import TrackdoKit

/// What a row asks the list to do.
enum TaskRowAction {
    case rename
    case toggleDone
    case delete
}

/// One task in the DADS resource list style (components/resource-list):
/// title and total time, the timer button and a More menu. The menu offers
/// the same actions as the swipe actions, for people who cannot swipe.
struct TaskRow: View {
    let model: TaskListModel
    let item: TaskItem
    let onAction: (TaskRowAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            contents
            HStack(spacing: 8) {
                timerButton
                moreMenu
            }
        }
        .padding(.vertical, 16)
        // The resource list's separator spans the whole row.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: item.displayTitle)
                .dadsFont(.std17B170)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? DadsColor.gray600 : DadsColor.gray900)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let ms = model.totalMs(of: item, at: context.date)
                Text(verbatim: ElapsedTime.clock(ms))
                    .dadsFont(.dns16N130)
                    .monospacedDigit()
                    .foregroundStyle(DadsColor.gray800)
                    .accessibilityLabel(Text("Total \(ElapsedTime.spoken(ms))"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? Text("Done") : Text(verbatim: ""))
    }

    @ViewBuilder private var timerButton: some View {
        if item.isRunning {
            Button {
                Task { await model.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.dads(.solidFill, size: .medium))
            .accessibilityLabel(Text("Stop timer for \(item.displayTitle)"))
        } else {
            Button {
                Task { await model.start(item.id) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.dads(.outline, size: .medium))
            .accessibilityLabel(Text("Start timer for \(item.displayTitle)"))
        }
    }

    /// The resource list's action button: 44 pt wide, as tall as the row.
    private var moreMenu: some View {
        Menu {
            Button("Rename", systemImage: "pencil") { onAction(.rename) }
            if item.isDone {
                Button("Reopen", systemImage: "arrow.uturn.backward") { onAction(.toggleDone) }
            } else {
                Button("Complete", systemImage: "checkmark") { onAction(.toggleDone) }
            }
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
