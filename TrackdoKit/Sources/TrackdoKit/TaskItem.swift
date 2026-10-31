import Foundation
import TrackdoFFI

/// A task as the screens show it.
public struct TaskItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// `nil` until the task's title arrives from the server.
    public let title: String?
    public let isDone: Bool
    public let isRunning: Bool
    /// Time spent at the last reload.
    public let totalMs: UInt64
    public let priority: TaskPriority
    /// `nil` while the task has no note.
    public let note: String?
    public let due: CalendarDay?
    public let scheduledAt: Date?
    /// `nil` at the top level.
    public let parentId: String?
    /// By name.
    public let tags: [TagItem]
    /// Direct subtasks, and how many of them are done.
    public let subtaskCount: Int
    public let doneSubtaskCount: Int

    init(_ record: TaskRecord, among records: [TaskRecord] = []) {
        id = record.id
        title = record.title
        isDone = record.isDone
        isRunning = record.isInProgress
        totalMs = record.totalMs
        priority = TaskPriority(record.priority)
        note = record.note
        due = record.due.map(CalendarDay.init)
        scheduledAt = record.scheduledAtMs.map(Date.init(unixMs:))
        parentId = record.parentId
        tags = record.tags.map(TagItem.init)
        let subtasks = records.filter { $0.parentId == record.id }
        subtaskCount = subtasks.count
        doneSubtaskCount = subtasks.count(where: \.isDone)
    }
}

/// Ordered from least to most urgent.
public enum TaskPriority: Comparable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high

    init(_ priority: Priority) {
        switch priority {
        case .none: self = .none
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        }
    }

    var ffi: Priority {
        switch self {
        case .none: .none
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

/// A tag that is not deleted.
public struct TagItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    init(_ record: TagRecord) {
        id = record.id
        name = record.name
    }

    /// Which of `count` colors this tag wears. Tags carry no color of their
    /// own, so it comes from the id: the same on every device and kept
    /// through renames. FNV-1a, since `hashValue` changes between launches.
    public func colorIndex(among count: Int) -> Int {
        let hash = id.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }
}

/// A day without a time zone: a task due on the 31st stays due on the 31st
/// wherever the device is.
public struct CalendarDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    init(_ date: CalendarDate) {
        self.init(year: Int(date.year), month: Int(date.month), day: Int(date.day))
    }

    /// The start of the day in `calendar`.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    var ffi: CalendarDate {
        CalendarDate(year: UInt16(clamping: year), month: UInt8(clamping: month), day: UInt8(clamping: day))
    }
}

/// How a due date stands against today.
public enum DueStatus: Equatable, Sendable {
    case overdue
    case today
    /// Neither overdue nor due today; a done task is never overdue.
    case upcoming

    /// `nil` without a due date.
    public init?(due: CalendarDay?, isDone: Bool, today: CalendarDay) {
        guard let due else {
            return nil
        }
        switch due {
        case _ where isDone: self = .upcoming
        case ..<today: self = .overdue
        case today: self = .today
        default: self = .upcoming
        }
    }
}
