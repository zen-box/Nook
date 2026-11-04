import Foundation
import Testing
@testable import NookCore

struct ScheduleQueryTests {
    private static let zone = Fixtures.plus8

    private func event(_ title: String, _ start: Date, end: Date? = nil, allDay: Bool = false) -> ScheduleEvent {
        ScheduleEvent(title: title, start: start, end: end, isAllDay: allDay, createdAt: start)
    }

    private func midnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Fixtures.day(year, month, day).startDate(in: Self.zone)
    }

    @Test func dayAgendaPutsAllDayEventsFirst() {
        let events = [
            event("Flight to Tokyo", Fixtures.time(2026, 11, 4, 14, 30), end: Fixtures.time(2026, 11, 4, 18, 45)),
            event("Team Meeting", Fixtures.time(2026, 11, 4, 10), end: Fixtures.time(2026, 11, 4, 11)),
            event("Holiday", midnight(2026, 11, 4), end: midnight(2026, 11, 5), allDay: true),
            event("Design Review", Fixtures.time(2026, 11, 3, 16), end: Fixtures.time(2026, 11, 3, 17)),
        ]
        let titles = ScheduleQuery.events(events, on: Fixtures.day(2026, 11, 4), timeZone: Self.zone).map(\.title)
        #expect(titles == ["Holiday", "Team Meeting", "Flight to Tokyo"])
    }

    @Test func eventsCrossingMidnightShowOnBothDays() {
        let party = event("Party", Fixtures.time(2026, 11, 4, 22), end: Fixtures.time(2026, 11, 5, 2))
        #expect(party.occurs(on: Fixtures.day(2026, 11, 4), timeZone: Self.zone))
        #expect(party.occurs(on: Fixtures.day(2026, 11, 5), timeZone: Self.zone))
        #expect(!party.occurs(on: Fixtures.day(2026, 11, 6), timeZone: Self.zone))
    }

    @Test func eventsEndingAtMidnightStayOnTheirDay() {
        let late = event("Late", Fixtures.time(2026, 11, 4, 22), end: midnight(2026, 11, 5))
        #expect(late.occurs(on: Fixtures.day(2026, 11, 4), timeZone: Self.zone))
        #expect(!late.occurs(on: Fixtures.day(2026, 11, 5), timeZone: Self.zone))
    }

    @Test func eventsWithoutDurationBelongToTheirStartDay() {
        let reminder = event("Reminder", midnight(2026, 11, 5))
        #expect(!reminder.occurs(on: Fixtures.day(2026, 11, 4), timeZone: Self.zone))
        #expect(reminder.occurs(on: Fixtures.day(2026, 11, 5), timeZone: Self.zone))
        let backwards = event("Backwards", Fixtures.time(2026, 11, 5, 9), end: Fixtures.time(2026, 11, 4, 9))
        #expect(backwards.effectiveEnd == backwards.start)
    }

    @Test func weekStripDotsFollowMultiDayEvents() {
        let trip = event("Tokyo", midnight(2026, 11, 4), end: midnight(2026, 11, 7), allDay: true)
        let days = ScheduleQuery.daysWithEvents([trip], in: Fixtures.day(2026, 11, 4).isoWeek, timeZone: Self.zone)
        #expect(days == [Fixtures.day(2026, 11, 4), Fixtures.day(2026, 11, 5), Fixtures.day(2026, 11, 6)])
    }

    @Test func upcomingSkipsFinishedEvents() {
        let now = Fixtures.time(2026, 11, 4, 10, 30)
        let events = [
            event("Flight", Fixtures.time(2026, 11, 4, 14, 30)),
            event("Meeting", Fixtures.time(2026, 11, 4, 10), end: Fixtures.time(2026, 11, 4, 11)),
            event("Breakfast", Fixtures.time(2026, 11, 4, 8), end: Fixtures.time(2026, 11, 4, 9)),
            event("Dentist", Fixtures.time(2026, 11, 5, 9, 30)),
            event("Starts now", now),
        ]
        #expect(ScheduleQuery.upcoming(events, after: now).map(\.title) == ["Meeting", "Starts now", "Flight", "Dentist"])
        #expect(ScheduleQuery.upcoming(events, after: now, limit: 2).map(\.title) == ["Meeting", "Starts now"])
    }
}
