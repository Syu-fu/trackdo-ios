import SwiftUI
import TrackdoKit

/// The running timer above the list: which task and for how long, with a
/// Stop button. Time is updated every second but never announced.
struct RunningTimerBanner: View {
    let model: TaskListModel
    let timer: RunningTimer

    var body: some View {
        DadsNotificationBanner(kind: .info, title: "Timer running") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    DadsBannerDescription(verbatim: timer.displayTitle)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let ms = model.elapsedMs(of: timer, at: context.date)
                        Text(verbatim: ElapsedTime.clock(ms))
                            .dadsFont(.std24B150)
                            .monospacedDigit()
                            .foregroundStyle(DadsColor.gray900)
                            .accessibilityLabel(Text(verbatim: ElapsedTime.spoken(ms)))
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        Task { await model.stop() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.dads(.solidFill, size: .medium))
                    .accessibilityLabel(Text("Stop timer for \(timer.displayTitle)"))
                }
            }
        }
    }
}
