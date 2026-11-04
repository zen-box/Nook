import Foundation
import NookCore

#if DEBUG
/// Demo content for UI tests (launch argument `-uiTesting`); never shown in normal use. Every
/// date is relative to `now`, so the screens match the reference design on any day: two events
/// today, the Japan trip note and $1,280.50 spent this month.
struct SampleData {
    var notes: [Note]
    var events: [ScheduleEvent]
    var trips: [TripPlan]
    var anniversaries: [Anniversary]
    var ledger: [LedgerEntry]

    static func make(now: Date = Date(), timeZone: TimeZone = .current) -> SampleData {
        let today = LocalDate.today(in: timeZone, now: now)

        func at(_ day: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
            day.date(hour: hour, minute: minute, in: timeZone)
        }

        func daysAgo(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            at(today.adding(days: -days), hour, minute)
        }

        let tripNoteID = UUIDv7.make(timestamp: daysAgo(10, 20))
        let trip = TripPlan(
            title: "Japan Trip",
            destination: "Tokyo, Japan",
            startDate: today,
            endDate: today.adding(days: 6),
            summary: "Mt. Fuji day trip, temples in Kyoto and a food tour in Tokyo.",
            noteID: tripNoteID,
            createdAt: daysAgo(10, 20)
        )

        return SampleData(
            notes: makeNotes(tripNoteID: tripNoteID, daysAgo: daysAgo),
            events: makeEvents(today: today, trip: trip, at: at, daysAgo: daysAgo, timeZone: timeZone),
            trips: [trip],
            anniversaries: makeAnniversaries(today: today, daysAgo: daysAgo),
            ledger: makeLedger(today: today, now: now, at: at)
        )
    }

    private static func makeNotes(tripNoteID: UUID, daysAgo: (Int, Int, Int) -> Date) -> [Note] {
        [
            Note(
                id: tripNoteID,
                title: "Trip Plan – Japan",
                body: "Tokyo → Hakone → Kyoto\n\nDay 1  Arrive in Tokyo, evening walk in Shibuya\nDay 2  Mt. Fuji day trip\nDay 3  City tour and Tsukiji market",
                category: .travel,
                tags: ["japan"],
                isPinned: true,
                checklist: [
                    ChecklistItem(text: "Book flights", isDone: true),
                    ChecklistItem(text: "Reserve hotels"),
                    ChecklistItem(text: "Plan daily itinerary"),
                    ChecklistItem(text: "Prepare travel documents"),
                ],
                createdAt: daysAgo(10, 20, 0),
                updatedAt: daysAgo(2, 9, 41)
            ),
            Note(
                title: "Project Ideas",
                body: "New features for the organizer app: smart reminders, shared lists and a weekly review.\n\n- Widgets for today's agenda\n- Natural language quick add\n- Receipt scanning",
                category: .work,
                tags: ["roadmap"],
                createdAt: daysAgo(12, 10, 0),
                updatedAt: daysAgo(4, 18, 5)
            ),
            Note(
                title: "Reading List",
                body: "Books, articles, and resources to read this season.\n\n- The Design of Everyday Things\n- Deep Work\n- Atomic Habits",
                category: .life,
                createdAt: daysAgo(20, 21, 0),
                updatedAt: daysAgo(6, 22, 10)
            ),
            Note(
                title: "Grocery List",
                category: .life,
                checklist: [
                    ChecklistItem(text: "Milk"),
                    ChecklistItem(text: "Eggs", isDone: true),
                    ChecklistItem(text: "Avocados"),
                    ChecklistItem(text: "Coffee beans"),
                ],
                createdAt: daysAgo(8, 19, 0),
                updatedAt: daysAgo(8, 19, 30)
            ),
            Note(
                title: "Meeting Notes",
                body: "Q4 planning: finalize scope, align on milestones and share the launch checklist.",
                category: .work,
                createdAt: daysAgo(11, 15, 0),
                updatedAt: daysAgo(11, 16, 0)
            ),
        ]
    }

    private static func makeEvents(
        today: LocalDate,
        trip: TripPlan,
        at: (LocalDate, Int, Int) -> Date,
        daysAgo: (Int, Int, Int) -> Date,
        timeZone: TimeZone
    ) -> [ScheduleEvent] {
        let tomorrow = today.adding(days: 1)
        let inTwoDays = today.adding(days: 2)
        let tourDay = today.adding(days: 3)
        return [
            ScheduleEvent(
                title: "Team Meeting",
                start: at(today, 10, 0),
                end: at(today, 11, 0),
                location: "Room 3A",
                notes: "Weekly sync on the organizer roadmap.",
                category: .work,
                reminderMinutes: 10,
                createdAt: daysAgo(6, 9, 0)
            ),
            ScheduleEvent(
                title: "Flight to Tokyo",
                start: at(today, 14, 30),
                end: at(today, 18, 45),
                location: "Terminal 2 · Gate 32",
                category: .travel,
                reminderMinutes: 120,
                planID: trip.id,
                createdAt: daysAgo(10, 20, 0)
            ),
            ScheduleEvent(
                title: "Design Review",
                start: daysAgo(1, 16, 0),
                end: daysAgo(1, 17, 0),
                location: "Studio",
                category: .work,
                createdAt: daysAgo(5, 9, 0)
            ),
            ScheduleEvent(
                title: "Dentist",
                start: at(tomorrow, 9, 30),
                end: at(tomorrow, 10, 15),
                category: .health,
                reminderMinutes: 60,
                createdAt: daysAgo(8, 9, 0)
            ),
            ScheduleEvent(
                title: "Dinner with Mia",
                start: at(inTwoDays, 19, 0),
                end: at(inTwoDays, 21, 0),
                location: "Ginza",
                category: .personal,
                planID: trip.id,
                createdAt: daysAgo(3, 9, 0)
            ),
            ScheduleEvent(
                title: "Tokyo City Tour",
                start: tourDay.startDate(in: timeZone),
                end: tourDay.adding(days: 1).startDate(in: timeZone),
                isAllDay: true,
                category: .travel,
                planID: trip.id,
                createdAt: daysAgo(9, 9, 0)
            ),
        ]
    }

    private static func makeAnniversaries(today: LocalDate, daysAgo: (Int, Int, Int) -> Date) -> [Anniversary] {
        [
            Anniversary(
                title: "Mom's Birthday",
                date: today.adding(days: 12).sameDay(inYear: 1968),
                kind: .birthday,
                createdAt: daysAgo(200, 9, 0)
            ),
            Anniversary(
                title: "Wedding Anniversary",
                date: today.adding(days: 47).sameDay(inYear: 2019),
                kind: .anniversary,
                createdAt: daysAgo(180, 9, 0)
            ),
            Anniversary(
                title: "Started Nook",
                date: today.adding(days: -120),
                repeatRule: .never,
                kind: .project,
                notes: "The first sketch of the organizer.",
                createdAt: daysAgo(120, 9, 0)
            ),
            Anniversary(
                title: "Leo's Birthday",
                date: LocalDate(year: 2000, month: 2, day: 29) ?? today,
                kind: .birthday,
                notes: "Born on a leap day; celebrated on Feb 28 in other years.",
                createdAt: daysAgo(90, 9, 0)
            ),
        ]
    }

    private struct Spend {
        let title: String
        let category: LedgerCategory
        let cents: Int64
        let daysAgo: Int
        let hour: Int
        let minute: Int
    }

    /// This month: 16 expenses totalling exactly $1,280.50, all on or before today. The last
    /// three days hold the reference week: Food $236.40, Travel $180.00, Shopping $89.80 and
    /// $74.00 other, with today the busiest day. Last month's entries give the comparisons.
    private static func makeLedger(today: LocalDate, now: Date, at: (LocalDate, Int, Int) -> Date) -> [LedgerEntry] {
        let thisMonth: [Spend] = [
            Spend(title: "Coffee & Croissant", category: .food, cents: 1_830, daysAgo: 0, hour: 8, minute: 15),
            Spend(title: "Travel Insurance", category: .travel, cents: 12_000, daysAgo: 0, hour: 9, minute: 5),
            Spend(title: "Airport Express", category: .travel, cents: 6_000, daysAgo: 0, hour: 11, minute: 40),
            Spend(title: "Phone Bill", category: .others, cents: 7_400, daysAgo: 0, hour: 7, minute: 30),
            Spend(title: "Groceries", category: .food, cents: 5_820, daysAgo: 1, hour: 18, minute: 20),
            Spend(title: "Ramen Lunch", category: .food, cents: 3_440, daysAgo: 1, hour: 12, minute: 30),
            Spend(title: "Travel Adapter", category: .shopping, cents: 3_490, daysAgo: 1, hour: 15, minute: 10),
            Spend(title: "Dinner with Friends", category: .food, cents: 12_550, daysAgo: 2, hour: 20, minute: 0),
            Spend(title: "Running Shoes", category: .shopping, cents: 5_490, daysAgo: 2, hour: 17, minute: 45),
            Spend(title: "Electricity Bill", category: .housing, cents: 8_640, daysAgo: 3, hour: 9, minute: 0),
            Spend(title: "Internet", category: .housing, cents: 4_990, daysAgo: 4, hour: 9, minute: 30),
            Spend(title: "Monthly Transit Pass", category: .transport, cents: 9_800, daysAgo: 5, hour: 8, minute: 0),
            Spend(title: "Concert Tickets", category: .entertainment, cents: 15_600, daysAgo: 6, hour: 21, minute: 0),
            Spend(title: "Gym Membership", category: .health, cents: 4_500, daysAgo: 8, hour: 7, minute: 0),
            Spend(title: "Running Jacket", category: .shopping, cents: 12_900, daysAgo: 10, hour: 16, minute: 0),
            Spend(title: "Weekly Groceries", category: .food, cents: 13_600, daysAgo: 12, hour: 11, minute: 0),
        ]
        /// (day of last month, title, category, cents). Days 26–28 sum to $634.80.
        let lastMonth: [(Int, String, LedgerCategory, Int64)] = [
            (2, "Electricity Bill", .housing, 7_960),
            (4, "Internet", .housing, 4_990),
            (5, "Groceries", .food, 9_230),
            (8, "Movie Night", .entertainment, 3_600),
            (11, "Gym Membership", .health, 4_500),
            (13, "Dinner Out", .food, 6_840),
            (15, "Monthly Transit Pass", .transport, 9_800),
            (18, "Books", .shopping, 4_250),
            (20, "Pharmacy", .health, 2_380),
            (22, "Weekend Brunch", .food, 5_420),
            (24, "Headphones", .shopping, 12_900),
            (26, "Flight Deposit", .travel, 32_000),
            (27, "Hotel Booking", .travel, 21_480),
            (28, "Groceries", .food, 10_000),
        ]

        let monthStart = today.startOfMonth
        func spentAt(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = max(today.adding(days: -daysAgo), monthStart)
            let date = at(day, hour, minute)
            return day == today ? min(date, now) : date
        }

        var entries = thisMonth.map { spend in
            LedgerEntry(
                amount: Money(minorUnits: spend.cents, currencyCode: "USD"),
                category: spend.category,
                title: spend.title,
                occurredAt: spentAt(spend.daysAgo, spend.hour, spend.minute),
                createdAt: spentAt(spend.daysAgo, spend.hour, spend.minute)
            )
        }
        let previousStart = monthStart.adding(months: -1)
        entries += lastMonth.map { day, title, category, cents in
            let date = at(previousStart.adding(days: day - 1), 12, 0)
            return LedgerEntry(
                amount: Money(minorUnits: cents, currencyCode: "USD"),
                category: category,
                title: title,
                occurredAt: date,
                createdAt: date
            )
        }
        let payday = spentAt(40, 9, 0)
        entries.append(
            LedgerEntry(
                kind: .income,
                amount: Money(minorUnits: 420_000, currencyCode: "USD"),
                category: .salary,
                title: "Salary",
                occurredAt: payday,
                createdAt: payday
            )
        )
        return entries
    }
}
#endif
