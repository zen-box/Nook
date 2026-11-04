import SwiftUI
import NookCore

struct HomeView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HomeContent(now: context.date)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HomeContent: View {
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let today = LocalDate.today(in: store.timeZone, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Today", subtitle: Greeting(now: now).text) {
                    CircleIconButton(
                        symbol: "bell",
                        label: "Notifications",
                        showsBadge: !store.reminders(now: now).isEmpty
                    ) {
                        router.present(.notifications)
                    }
                    AvatarButton {
                        router.present(.settings)
                    }
                }
                DatePill(day: router.selectedDay) {
                    router.present(.pickDay)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 2)
                VStack(spacing: Metrics.sectionSpacing) {
                    UpcomingCard(day: router.selectedDay, today: today, now: now)
                    if let note = store.recentNote {
                        RecentNoteCard(note: note)
                    }
                    MonthExpenseCard(today: today)
                    VaultSummaryCard()
                    TodosCard()
                    AnniversaryCard(today: today)
                    QuickAddCard()
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .padding(.top, 8)
            .padding(.bottom, Metrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack(alignment: .top) {
                Theme.background
                MistyBackground()
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { StatusBarScrim() }
        .accessibilityIdentifier("screen.home")
    }
}

// MARK: - Header pieces

private struct AvatarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "A")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xFFD9C2), Color(hex: 0xF7B39A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .shadow(color: Theme.shadow, radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Profile and settings"))
    }
}

private struct DatePill: View {
    let day: LocalDate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accent)
                Text(day.noon, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(.subheadline, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Theme.surface.opacity(0.9), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
            .shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(Text("Choose a day"))
    }
}

// MARK: - Cards

private struct UpcomingCard: View {
    let day: LocalDate
    let today: LocalDate
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let events = store.events(on: day)
        Button {
            router.showSchedule()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "calendar", pastel: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upcoming")
                            .font(NookFont.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        subtitle(count: events.count)
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Chevron()
                }
                if events.isEmpty {
                    Text("Nothing planned. Enjoy the free time.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(events.prefix(3))) { event in
                            UpcomingRow(event: event, isPast: !event.isAllDay && event.effectiveEnd <= now)
                        }
                    }
                }
            }
            .card(fill: LinearGradient(colors: [Theme.primarySoft, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("home.upcoming")
    }

    @ViewBuilder
    private func subtitle(count: Int) -> some View {
        if day == today {
            Text("\(count) events today")
        } else {
            Text("\(count) events")
        }
    }
}

private struct UpcomingRow: View {
    let event: ScheduleEvent
    let isPast: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.category.pastel.base)
                .frame(width: 8, height: 8)
            Group {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(verbatim: TimeText.time(event.start))
                }
            }
            .font(.system(.subheadline, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            Text(verbatim: "•")
                .foregroundStyle(Theme.textTertiary)
            Text(event.title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if event.category == .travel {
                Image(systemName: "airplane")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Pastel.peach.strong)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(isPast ? 0.55 : 1)
    }
}

private struct RecentNoteCard: View {
    let note: Note

    var body: some View {
        NavigationLink(value: AppRoute.note(note.id)) {
            HStack(spacing: 12) {
                IconTile(symbol: "note.text", pastel: .peach)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Note")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(note.displayTitle)
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Chevron()
            }
            .card()
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("home.recentNote")
    }
}

private struct MonthExpenseCard: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let total = store.monthToDate(today: today).current
        let series = store.monthSeries(today: today).map { Double($0.total.minorUnits) }
        Button {
            router.select(.finance)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "wallet.bifold", pastel: .mint)
                    Text("Expenses (This Month)")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Chevron()
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: total.formatted())
                            .font(NookFont.amount)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Budget \(store.monthlyBudget.formatted())")
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    MiniBars(values: series)
                        .frame(width: 118, height: 46)
                }
            }
            .card()
        }
        .buttonStyle(.pressable)
    }
}

/// The seven small rising bars on the expenses card.
private struct MiniBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(values.count, 1)
            let spacing: CGFloat = 6
            let barWidth = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 2)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(values.indices, id: \.self) { index in
                    let ratio = values[index] / maxValue
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(index == values.count - 1 ? Pastel.mint.strong : Pastel.mint.base.opacity(0.3 + 0.5 * ratio))
                        .frame(width: barWidth, height: max(proxy.size.height * ratio, 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .accessibilityHidden(true)
    }
}

private struct VaultSummaryCard: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.select(.vault)
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "lock", pastel: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Vault")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(store.vaultItems.count) accounts · \(store.vaultCategoryCount) categories")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Chevron()
            }
            .card()
        }
        .buttonStyle(.pressable)
    }
}

private struct TodosCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let todos = store.openTodos(limit: 3)
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(symbol: "checklist", pastel: .violet)
                    Text("To-dos")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(store.openTodoCount) open")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        Button {
                            withAnimation(.snappy) {
                                store.toggleChecklistItem(todo.item.id, in: todo.noteID)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.textTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(todo.item.text)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(todo.noteTitle)
                                        .font(NookFont.micro)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Marks the item as done"))
                    }
                }
            }
            .card()
        }
    }
}

private struct AnniversaryCard: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let next = store.nextAnniversary(today: today) {
            Button {
                router.showSchedule(segment: .anniversaries)
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: next.anniversary.kind.symbol, pastel: next.anniversary.kind.pastel)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.anniversary.title)
                            .font(NookFont.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(next.date.noon, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    CountdownLabel(days: next.days)
                }
                .card()
            }
            .buttonStyle(.pressable)
        }
    }
}

struct CountdownLabel: View {
    let days: Int

    var body: some View {
        Group {
            if days == 0 {
                Text("Today")
            } else {
                Text("In \(days) days")
            }
        }
        .font(.system(.footnote, weight: .semibold))
        .foregroundStyle(Pastel.rose.strong)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Pastel.rose.soft, in: Capsule())
    }
}

private struct QuickAddCard: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Add")
                .font(NookFont.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                QuickAddButton(title: "Note", symbol: "square.and.pencil", pastel: .peach) {
                    router.perform(.note, store: store)
                }
                QuickAddButton(title: "Event", symbol: "calendar.badge.plus", pastel: .blue) {
                    router.perform(.event, store: store)
                }
                QuickAddButton(title: "Expense", symbol: "creditcard", pastel: .mint) {
                    router.perform(.expense, store: store)
                }
                QuickAddButton(title: "Account", symbol: "key", pastel: .violet) {
                    router.perform(.account, store: store)
                }
            }
        }
        .card()
    }
}

private struct QuickAddButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let pastel: Pastel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconTile(symbol: symbol, pastel: pastel, size: 46)
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
    }
}
