import SwiftUI
import TrackdoKit

/// The running timer in the bottom toolbar, beside Add Task: which task and
/// for how long, with a Stop button. Stopping is frequent, so it sits within
/// the thumb's reach, and the bar is one line so the list keeps its room.
/// The task's name opens it. Time is updated every second but never
/// announced.
struct RunningTimerBar: View {
    let model: TaskListModel
    let timer: RunningTimer
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: timer.displayTitle)
                        .lineLimit(1)
                        .dadsFont(.dns14N130)
                        .foregroundStyle(DadsColor.gray800)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let ms = model.elapsedMs(of: timer, at: context.date)
                        Text(verbatim: ElapsedTime.clock(ms))
                            .dadsFont(.dns16B130)
                            .monospacedDigit()
                            .foregroundStyle(DadsColor.gray900)
                            .accessibilityLabel(Text(verbatim: ElapsedTime.spoken(ms)))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Timer running"))
            .accessibilityHint(Text("Shows its details."))
            Button {
                Task { await model.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.dads(.solidFill, size: .icon))
            .accessibilityLabel(Text("Stop timer for \(timer.displayTitle)"))
        }
        // Keeps the square Stop button inside the capsule's rounded end.
        .padding(.leading, 12)
        .padding(.trailing, 6)
    }
}
