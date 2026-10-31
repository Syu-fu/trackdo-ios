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
/// frequent, so each takes one tap: the checkbox on the leading side, tinted
/// by priority, and the timer button. Renaming and deleting are
/// rare, so they wait in the More menu, which also stands in for the swipe
/// actions. Dense text keeps the row short so more tasks fit on screen;
/// planning details follow the time and wrap onto more lines rather than
/// being cut off. The row holds buttons, so only the title and details open
/// the task.
struct TaskRow: View {
    let model: TaskListModel
    let item: TaskItem
    let onAction: (TaskRowAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        HStack(alignment: .top, spacing: 4) {
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
            EmptyView()
        }
        .buttonStyle(CheckboxButtonStyle(priority: item.priority, isDone: item.isDone))
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
                    let summary = TaskSummary(item: item, today: CalendarDay(context.date))
                    FlowLayout(spacing: 10, lineSpacing: 2) {
                        Text(verbatim: ElapsedTime.clock(ms)).monospacedDigit()
                        ForEach(Array(summary.texts.enumerated()), id: \.offset) { $0.element }
                        ForEach(item.tags) { TagChip(tag: $0) }
                    }
                    .dadsFont(.dns14N130)
                    .foregroundStyle(DadsColor.gray700)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Total \(ElapsedTime.spoken(ms))"))
                    .accessibilityValue(Text(verbatim: summary.spoken))
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

    /// A ring as light as the checkbox while idle, so it does not outweigh
    /// the title; filled with the key color while running, the one state
    /// worth catching the eye.
    @ViewBuilder private var timerButton: some View {
        if item.isRunning {
            Button {
                Task { await model.stop() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(DadsColor.key900)
            }
            .buttonStyle(TimerButtonStyle())
            .accessibilityLabel(Text("Stop timer for \(item.displayTitle)"))
        } else {
            Button {
                Task { await model.start(item.id) }
            } label: {
                Image(systemName: "play.circle")
                    .foregroundStyle(DadsColor.gray600)
            }
            .buttonStyle(TimerButtonStyle())
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

/// The timer button's 44 pt target, dimmed while pressed.
private struct TimerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .light))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// The checkbox's 44 pt target, previewing the check while pressed.
private struct CheckboxButtonStyle: ButtonStyle {
    let priority: TaskPriority
    let isDone: Bool

    func makeBody(configuration: Configuration) -> some View {
        PriorityCheckbox(priority: priority, isDone: isDone, isPressed: configuration.isPressed)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}
