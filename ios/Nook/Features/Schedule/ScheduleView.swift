import SwiftUI
import NookCore

/// Calendar, trips and anniversaries (spec section 3.3).
enum ScheduleSegment: String, CaseIterable, Hashable {
    case calendar, trips, anniversaries

    var title: LocalizedStringKey {
        switch self {
        case .calendar: "Calendar"
        case .trips: "Trips"
        case .anniversaries: "Anniversaries"
        }
    }
}

struct ScheduleView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            ScheduleContent(now: context.date)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ScheduleContent: View {
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        let today = LocalDate.today(in: store.timeZone, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Schedule") {
                    CircleIconButton(symbol: "bell", label: "Notifications") {
                        router.present(.notifications)
                    }
                    AddMenuButton(primary: primaryAction)
                }
                PillSegmentedControl(options: ScheduleSegment.allCases, selection: $router.scheduleSegment) { $0.title }
                    .padding(.horizontal, Metrics.screenPadding)
                Group {
                    switch router.scheduleSegment {
                    case .calendar:
                        CalendarSection(today: today, now: now)
                    case .trips:
                        TripsSection(today: today)
                    case .anniversaries:
                        AnniversariesSection(today: today)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .padding(.top, 8)
            .padding(.bottom, Metrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { StatusBarScrim() }
        .accessibilityIdentifier("screen.schedule")
    }

    private var primaryAction: QuickAction {
        switch router.scheduleSegment {
        case .calendar: .event
        case .trips: .trip
        case .anniversaries: .anniversary
        }
    }
}

// MARK: - Calendar

private struct CalendarSection: View {
    let today: LocalDate
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let week = router.selectedDay.isoWeek
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            WeekHeader(week: week, isCurrentWeek: week.contains(today)) { offset in
                withAnimation(.snappy) {
                    router.shiftSelectedDay(by: offset * 7)
                }
            } onToday: {
                withAnimation(.snappy) {
                    router.selectedDay = today
                }
            }
            WeekStrip(days: week, selected: router.selectedDay, today: today, eventDays: store.eventDays(in: week)) { day in
                router.selectedDay = day
            }
            DayTimeline(day: router.selectedDay, today: today, now: now)
        }
    }
}

private struct WeekHeader: View {
    let week: [LocalDate]
    let isCurrentWeek: Bool
    let onMove: (Int) -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: DateText.range(week))
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !isCurrentWeek {
                    Button("Back to this week", action: onToday)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            ArrowButton(symbol: "chevron.left", label: "Previous week") {
                onMove(-1)
            }
            ArrowButton(symbol: "chevron.right", label: "Next week") {
                onMove(1)
            }
        }
    }
}

private struct ArrowButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }
}

private struct WeekStrip: View {
    let days: [LocalDate]
    let selected: LocalDate
    let today: LocalDate
    let eventDays: Set<LocalDate>
    let onSelect: (LocalDate) -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isSelected = day == selected
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        onSelect(day)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(day.noon, format: .dateTime.weekday(.abbreviated))
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                        Text(verbatim: "\(day.day)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(isSelected || day == today ? Theme.accent : Theme.textPrimary)
                        Circle()
                            .fill(eventDays.contains(day) ? (isSelected ? Theme.accent : Theme.primary) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.primarySoft)
                                .matchedGeometryEffect(id: "selectedDay", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day.noon, format: .dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .card(padding: 0)
    }
}

private struct DayTimeline: View {
    let day: LocalDate
    let today: LocalDate
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let events = store.events(on: day)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Group {
                    if day == today {
                        Text("Today")
                    } else {
                        Text(day.noon, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    }
                }
                .font(NookFont.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(events.count) events")
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if events.isEmpty {
                VStack(spacing: 4) {
                    EmptyStateView(symbol: "calendar", title: "No events", message: "Tap + to plan something.")
                    Button("Add Event") {
                        router.present(.newEvent(day))
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(
                            event: event,
                            isFirst: index == 0,
                            isLast: index == events.count - 1,
                            isPast: !event.isAllDay && event.effectiveEnd <= now
                        ) {
                            router.present(event.recurrence != nil ? .editOccurrence(event.id, event.start) : .editEvent(event.id))
                        }
                    }
                }
            }
        }
        .card()
    }
}

private struct TimelineRow: View {
    let event: ScheduleEvent
    let isFirst: Bool
    let isLast: Bool
    let isPast: Bool
    let action: () -> Void

    var body: some View {
        let pastel = event.category.pastel
        HStack(alignment: .top, spacing: 12) {
            Group {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(verbatim: TimeText.time(event.start))
                }
            }
            .font(.system(.subheadline, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 52, alignment: .leading)
            .padding(.top, 13)
            Color.clear
                .frame(width: 10, height: 1)
            Button(action: action) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(NookFont.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !detail.isEmpty {
                            Text(verbatim: detail)
                                .font(NookFont.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if let transport = event.transport, !transport.readableSummary.isEmpty {
                            Text(verbatim: transport.readableSummary).font(NookFont.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: event.category.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pastel.strong)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(pastel.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(isPast ? 0.6 : 1)
            }
            .buttonStyle(.pressable)
        }
        .padding(.bottom, isLast ? 0 : 10)
        .background(alignment: .topLeading) {
            rail(color: pastel.base)
        }
    }

    /// The dot and the line joining this event to its neighbours.
    private func rail(color: Color) -> some View {
        ZStack(alignment: .top) {
            if !(isFirst && isLast) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1.5, height: isLast ? 21 : nil)
                    .frame(maxHeight: isLast ? nil : .infinity, alignment: .top)
                    .padding(.top, isFirst ? 21 : 0)
            }
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay { Circle().strokeBorder(Theme.surface, lineWidth: 2) }
                .padding(.top, 16)
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.leading, 64)
    }

    private var detail: String {
        var parts: [String] = []
        if !event.isAllDay, let end = event.end, end > event.start {
            parts.append(TimeText.range(event.start, end))
        }
        if let location = event.location, !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Trips

private struct TripsSection: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            if store.trips.isEmpty {
                VStack(spacing: 4) {
                    EmptyStateView(symbol: "airplane", title: "No trips yet", message: "Plan dates, places and events in one place.")
                    SoftButton(title: "New Trip", symbol: "plus") {
                        router.present(.newTrip)
                    }
                }
                .card()
            }
            ForEach(store.tripsByDate) { trip in
                TripCard(trip: trip, today: today)
            }
        }
    }
}

private struct TripCard: View {
    let trip: TripPlan
    let today: LocalDate
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let events = store.events(inTrip: trip)
        VStack(alignment: .leading, spacing: 14) {
            Button {
                router.present(.editTrip(trip.id))
            } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "airplane.departure", pastel: .blue, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title)
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: subtitle)
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                phaseLabel
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Pastel.blue.strong)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Pastel.blue.soft, in: Capsule())
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit trip"))
            ProgressCapsule(value: progress, pastel: .blue)
            if !trip.summary.isEmpty {
                Text(trip.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !events.isEmpty {
                VStack(spacing: 8) {
                    ForEach(events, id: \.displayID) { event in
                        Button {
                            router.present(event.recurrence != nil ? .editOccurrence(event.id, event.start) : .editEvent(event.id))
                        } label: {
                            TripEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                if let noteID = trip.noteID, store.note(id: noteID) != nil {
                    NavigationLink(value: AppRoute.note(noteID)) {
                        Label("Open Trip Plan", systemImage: "note.text")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                } else {
                    SoftButton(title: "Create Plan Note", symbol: "note.text.badge.plus") {
                        guard let note = store.createPlanNote(for: trip) else { return }
                        router.push(.note(note.id), in: .schedule)
                    }
                }
                SoftButton(title: "Add Event", symbol: "calendar.badge.plus") {
                    router.present(.newEvent(max(trip.startDate, today)))
                }
            }
        }
        .card()
    }

    private var subtitle: String {
        let range = DateText.range([trip.startDate, trip.endDate])
        guard let destination = trip.destination, !destination.isEmpty else { return range }
        return "\(destination) · \(range)"
    }

    private var progress: Double {
        switch trip.phase(on: today) {
        case .upcoming: 0
        case .finished: 1
        case .ongoing: Double(trip.dayNumber(of: today) ?? 1) / Double(max(trip.dayCount, 1))
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch trip.phase(on: today) {
        case .upcoming:
            Text("In \(today.days(to: trip.startDate)) days")
        case .ongoing:
            Text("Day \(trip.dayNumber(of: today) ?? 1) of \(trip.dayCount)")
        case .finished:
            Text("Finished")
        }
    }
}

private struct TripEventRow: View {
    let event: ScheduleEvent

    var body: some View {
        let day = LocalDate(event.start, timeZone: .current)
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(day.noon, format: .dateTime.weekday(.abbreviated))
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: "\(day.day)")
                    .font(.system(.subheadline, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 42, height: 44)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(NookFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text(verbatim: TimeText.range(event.start, event.end))
                    }
                }
                .font(NookFont.caption)
                .foregroundStyle(Theme.textSecondary)
                if let transport = event.transport, !transport.readableSummary.isEmpty {
                    Text(verbatim: transport.readableSummary).font(NookFont.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: event.category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(event.category.pastel.strong)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Anniversaries

private struct AnniversariesSection: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 12) {
            if store.anniversaries.isEmpty {
                VStack(spacing: 4) {
                    EmptyStateView(symbol: "gift", title: "No anniversaries yet", message: "Birthdays and special days, with a countdown.")
                    SoftButton(title: "New Anniversary", symbol: "plus") {
                        router.present(.newAnniversary)
                    }
                }
                .card()
            }
            ForEach(store.anniversariesByNextDate(today: today)) { anniversary in
                Button {
                    router.present(.editAnniversary(anniversary.id))
                } label: {
                    AnniversaryRow(anniversary: anniversary, today: today)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

private struct AnniversaryRow: View {
    let anniversary: Anniversary
    let today: LocalDate

    var body: some View {
        let status = anniversary.status(on: today)
        let shownDate = anniversary.nextOccurrence(onOrAfter: today) ?? anniversary.date
        HStack(spacing: 12) {
            IconTile(symbol: anniversary.kind.symbol, pastel: anniversary.kind.pastel, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(anniversary.title)
                    .font(NookFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text(shownDate.noon, format: .dateTime.month(.abbreviated).day().year())
                    yearsText(status)
                }
                .font(NookFont.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            StatusBadge(status: status)
        }
        .card()
    }

    @ViewBuilder
    private func yearsText(_ status: Anniversary.Status) -> some View {
        switch status {
        case .today(let years), .upcoming(_, let years):
            if years > 0 {
                Text(verbatim: "·")
                if anniversary.kind == .birthday {
                    Text("Turns \(years)")
                } else {
                    Text("\(years) years")
                }
            }
        case .elapsed:
            EmptyView()
        }
    }
}

private struct StatusBadge: View {
    let status: Anniversary.Status

    var body: some View {
        VStack(spacing: 0) {
            switch status {
            case .today:
                Text("Today")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Pastel.rose.strong)
            case .upcoming(let days, _):
                Text(verbatim: "\(days)")
                    .font(.system(.title2, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Group {
                    if days == 1 {
                        Text("day left")
                    } else {
                        Text("days left")
                    }
                }
                .font(NookFont.micro)
                .foregroundStyle(Theme.textSecondary)
            case .elapsed(let days):
                Text(verbatim: "\(days)")
                    .font(.system(.title2, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Group {
                    if days == 1 {
                        Text("day since")
                    } else {
                        Text("days since")
                    }
                }
                .font(NookFont.micro)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minWidth: 64)
        .padding(.vertical, 6)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
