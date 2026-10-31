import Foundation
import Testing
@testable import TrackdoKit

@Suite struct TaskItemTests {
    let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    @Test func aDayIsTheOneTheDateFallsOnLocally() {
        // 2026-10-30 20:00 UTC is already the 31st in Tokyo.
        let date = Date(timeIntervalSince1970: 1_793_390_400)

        let day = CalendarDay(date, calendar: tokyo)

        #expect(day == CalendarDay(year: 2026, month: 10, day: 31))
        #expect(CalendarDay(day.date(in: tokyo), calendar: tokyo) == day)
    }

    @Test func daysAreOrderedByDate() {
        let days = [
            CalendarDay(year: 2026, month: 11, day: 1),
            CalendarDay(year: 2025, month: 12, day: 31),
            CalendarDay(year: 2026, month: 10, day: 31),
        ]

        #expect(days.sorted() == [days[1], days[2], days[0]])
    }

    @Test func daysCrossTheBindingsUnchanged() {
        let day = CalendarDay(year: 2026, month: 2, day: 28)

        #expect(CalendarDay(day.ffi) == day)
    }

    @Test func prioritiesCrossTheBindingsUnchanged() {
        for priority in TaskPriority.allCases {
            #expect(TaskPriority(priority.ffi) == priority)
        }
        #expect(TaskPriority.allCases.sorted() == [.none, .low, .medium, .high])
    }
}

extension TaskItemTests {
    @Test func dueStatusComparesWithToday() {
        let today = CalendarDay(year: 2026, month: 10, day: 25)

        #expect(DueStatus(due: CalendarDay(year: 2026, month: 10, day: 24), isDone: false, today: today) == .overdue)
        #expect(DueStatus(due: today, isDone: false, today: today) == .today)
        #expect(DueStatus(due: CalendarDay(year: 2026, month: 10, day: 26), isDone: false, today: today) == .upcoming)
        #expect(DueStatus(due: CalendarDay(year: 2026, month: 10, day: 24), isDone: true, today: today) == .upcoming)
        #expect(DueStatus(due: nil, isDone: false, today: today) == nil)
    }
}
