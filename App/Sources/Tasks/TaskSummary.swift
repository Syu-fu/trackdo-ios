import SwiftUI
import TrackdoKit

/// What a task carries beyond its title, in one dense line for its row:
/// due date, subtask progress, schedule, tags and a note mark, most telling
/// first since the line truncates. Words are kept few: priority shows only
/// as the checkbox's color, and a due date is just the date, colored when
/// it is today or past. The line is read as one sentence that does say all
/// of it, priority included.
struct TaskSummary {
    let item: TaskItem
    let today: CalendarDay

    /// One `Text` so the line truncates as a whole; `nil` when there is
    /// nothing to show.
    var text: Text? {
        let parts = parts.compactMap(\.text)
        guard let first = parts.first else {
            return nil
        }
        return parts.dropFirst().reduce(first) { line, part in
            Text("\(line)  \(part)")
        }
    }

    var spoken: String {
        parts.map(\.spoken).joined(separator: ", ")
    }

    private struct Part {
        /// `nil` for what the row shows some other way.
        let text: Text?
        let spoken: String
    }

    private var parts: [Part] {
        [priority, due, subtasks, scheduled, tags, note].compactMap(\.self)
    }

    private var priority: Part? {
        guard item.priority != .none else {
            return nil
        }
        return Part(text: nil, spoken: String(localized: "Priority: \(String(localized: item.priority.label))"))
    }

    private var due: Part? {
        guard let due = item.due, let status = DueStatus(due: due, isDone: item.isDone, today: today) else {
            return nil
        }
        let date = due.date().formatted(.dateTime.month(.defaultDigits).day())
        return switch status {
        case .overdue: part("calendar", date, spoken: String(localized: "Overdue \(date)"), color: DadsColor.red900)
        case .today: part("calendar", String(localized: "Today"), spoken: String(localized: "Due today"), color: DadsColor.success2)
        case .upcoming: part("calendar", date, spoken: String(localized: "Due \(date)"))
        }
    }

    private var scheduled: Part? {
        guard let scheduledAt = item.scheduledAt else {
            return nil
        }
        let date = scheduledAt.formatted(.dateTime.month(.defaultDigits).day().hour().minute())
        let spoken = scheduledAt.formatted(date: .abbreviated, time: .shortened)
        return part("clock", date, spoken: String(localized: "Planned for \(spoken)"))
    }

    private var subtasks: Part? {
        guard item.subtaskCount > 0 else {
            return nil
        }
        return part(
            "checklist",
            "\(item.doneSubtaskCount)/\(item.subtaskCount)",
            spoken: String(localized: "\(item.doneSubtaskCount) of \(item.subtaskCount) subtasks done")
        )
    }

    private var tags: Part? {
        guard !item.tags.isEmpty else {
            return nil
        }
        let names = item.tags.map(\.name).formatted(.list(type: .and, width: .narrow))
        return part("tag", names, spoken: String(localized: "Tags: \(names)"))
    }

    private var note: Part? {
        guard item.note != nil else {
            return nil
        }
        return Part(text: Text(Image(systemName: "note.text")), spoken: String(localized: "Has a note"))
    }

    private func part(_ symbol: String, _ label: String, spoken: String? = nil, color: Color = DadsColor.gray700) -> Part {
        Part(
            text: Text("\(Image(systemName: symbol)) \(label)").foregroundStyle(color),
            spoken: spoken ?? label
        )
    }
}

extension TaskPriority {
    var label: LocalizedStringResource {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}
