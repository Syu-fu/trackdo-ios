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
