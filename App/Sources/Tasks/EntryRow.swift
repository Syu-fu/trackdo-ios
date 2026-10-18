import SwiftUI
import TrackdoKit

/// What an entry row asks the detail screen to do.
enum EntryRowAction {
    case edit
    case delete
}

/// One time entry in the DADS resource list style: the time range, its
/// duration, chip labels for its state and a More menu that mirrors the
/// swipe actions.
struct EntryRow: View {
    let model: TaskDetailModel
    let entry: EntryItem
    let onAction: (EntryRowAction) -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: entry.timeRange)
                    .dadsFont(.std16B170)
                    .foregroundStyle(DadsColor.gray900)
                    .accessibilityLabel(Text(verbatim: entry.spokenTimeRange))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let ms = model.durationMs(of: entry, at: context.date)
                    Text(verbatim: ElapsedTime.clock(ms))
                        .dadsFont(.dns16N130)
                        .monospacedDigit()
                        .foregroundStyle(DadsColor.gray800)
                        .accessibilityLabel(Text(verbatim: ElapsedTime.spoken(ms)))
                }
                marks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            moreMenu
        }
        .padding(.vertical, 16)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    @ViewBuilder private var marks: some View {
        if entry.isRunning || entry.needsAttention || entry.isStopDerived {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        if entry.isRunning {
            DadsChipLabel(title: "Running", symbol: "timer", tone: .blue)
        }
        if entry.needsAttention {
            DadsChipLabel(title: "Needs Fixing", symbol: "exclamationmark.triangle.fill", tone: .red)
        }
        if entry.isStopDerived {
            DadsChipLabel(title: "Stopped Automatically", symbol: "stop.circle", tone: .gray)
        }
    }

    private var moreMenu: some View {
        Menu {
            if entry.startedAt != nil {
                Button("Edit Times", systemImage: "pencil") { onAction(.edit) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { onAction(.delete) }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundStyle(DadsColor.gray800)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("More for \(entry.spokenTimeRange)"))
    }
}
