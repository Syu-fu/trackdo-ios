import Foundation
import TrackdoKit

extension TitleIssue {
    var message: LocalizedStringResource {
        switch self {
        case .empty: "Enter a title."
        case .containsLineBreak: "Keep the title on one line."
        case let .tooLong(max): "Shorten the title to \(max) characters or fewer."
        }
    }
}

extension TaskListIssue {
    var title: LocalizedStringResource {
        switch self {
        case .taskGone: "The task was deleted on another device"
        case .failed: "The change could not be saved"
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .taskGone: "The list now shows the current tasks."
        case let .failed(reason): "Try again. If this keeps happening, restart the app. (\(reason))"
        }
    }
}

extension TaskItem {
    /// A task whose title has not arrived from the server yet.
    var displayTitle: String {
        title ?? String(localized: "Untitled task")
    }
}

extension RunningTimer {
    var displayTitle: String {
        title ?? String(localized: "Untitled task")
    }
}

extension EntryTimesIssue {
    var message: LocalizedStringResource {
        switch self {
        case .stopBeforeStart: "Set the end after the start."
        case .inFuture: "Set times that are not later than now."
        }
    }
}

extension EntryItem {
    /// "Oct 18, 9:00 – 10:30"; the end shows its date only when it differs.
    var timeRange: String {
        guard let startedAt else {
            return String(localized: "Start time not received yet")
        }
        let start = startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        guard let stoppedAt else {
            return isRunning ? String(localized: "\(start) – now") : start
        }
        let sameDay = Calendar.current.isDate(startedAt, inSameDayAs: stoppedAt)
        let end = sameDay
            ? stoppedAt.formatted(date: .omitted, time: .shortened)
            : stoppedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "\(start) – \(end)"
    }

    /// Read instead of the dash, which VoiceOver skips.
    var spokenTimeRange: String {
        guard let startedAt else {
            return timeRange
        }
        let start = startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let stoppedAt else {
            return isRunning ? String(localized: "From \(start), still running") : start
        }
        return String(localized: "From \(start) to \(stoppedAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
