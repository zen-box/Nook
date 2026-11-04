import SwiftUI
import NookCore

enum FinancePeriod: String, CaseIterable, Hashable {
    case week, month

    var title: LocalizedStringKey {
        switch self {
        case .week: "This Week"
        case .month: "This Month"
        }
    }
}

/// The fifth tab. The reference has no mock for it, so it is built from the expense cards.
struct FinanceView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            FinanceContent(now: context.date)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FinanceContent: View {
    let now: Date
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var period: FinancePeriod = .week

    var body: some View {
        let today = LocalDate.today(in: store.timeZone, now: now)
        let days = period == .week ? today.isoWeek : store.monthDays(of: today)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Finance") {
                    AddMenuButton(primary: .expense)
                }
                PillSegmentedControl(options: FinancePeriod.allCases, selection: $period) { $0.title }
                    .padding(.horizontal, Metrics.screenPadding)
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    switch period {
                    case .week:
                        WeekExpenseCard(today: today, showsCategories: false)
                    case .month:
                        MonthSpendingCard(today: today)
                    }
                    BreakdownCard(interval: store.interval(for: days))
                    BudgetCard(today: today)
                    SectionHeader(title: "Recent Transactions", actionTitle: "View All") {
                        router.push(.transactions, in: .finance)
                    }
                    .padding(.top, 4)
                    if store.ledger.isEmpty {
                        EmptyStateView(symbol: "creditcard", title: "No transactions yet", message: "Tap + to add an expense.").card()
                    } else {
                        TransactionsCard(entries: Array(store.recentEntries.prefix(6)))
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
        .accessibilityIdentifier("screen.finance")
    }
}

private struct MonthSpendingCard: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store

    var body: some View {
        let total = store.monthToDate(today: today).current
        let average = Money(minorUnits: total.minorUnits / Int64(max(today.day, 1)), currencyCode: total.currencyCode)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expenses (This Month)")
                    .font(NookFont.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: total.formatted())
                    .font(NookFont.amount)
                    .foregroundStyle(Theme.textPrimary)
                Text("Daily average \(average.formatted())")
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            DailyBarChart(totals: store.dailyTotals(days: store.monthDays(of: today)), today: today, labels: .dayOfMonth)
                .frame(height: 128)
        }
        .card()
    }
}

private struct BreakdownCard: View {
    let interval: DateInterval
    @Environment(AppStore.self) private var store

    var body: some View {
        let shares = store.breakdown(in: interval)
        VStack(alignment: .leading, spacing: 16) {
            Text("Spending by Category")
                .font(NookFont.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            if shares.isEmpty {
                EmptyStateView(symbol: "chart.pie", title: "No spending yet")
            } else {
                HStack(alignment: .center, spacing: 18) {
                    DonutChart(shares: shares)
                        .frame(width: 136, height: 136)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(shares.prefix(5))) { share in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(share.category.pastel.base)
                                    .frame(width: 8, height: 8)
                                Text(share.category.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(verbatim: "\(share.percent)%")
                                    .font(.system(.footnote, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .card()
    }
}

private struct BudgetCard: View {
    let today: LocalDate
    @Environment(AppStore.self) private var store

    var body: some View {
        let spent = store.monthToDate(today: today).current
        let budget = store.monthlyBudget
        let ratio = budget.minorUnits > 0 ? Double(spent.minorUnits) / Double(budget.minorUnits) : 0
        let remaining = budget - spent
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "target", pastel: .violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Budget")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(spent.formatted()) of \(budget.formatted())")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Text(verbatim: ratio.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            ProgressCapsule(value: ratio, pastel: ratio > 0.9 ? .rose : .mint)
            Group {
                if remaining.minorUnits >= 0 {
                    Text("\(remaining.formatted()) left this month")
                } else {
                    Text("Over budget by \(Money(minorUnits: -remaining.minorUnits, currencyCode: remaining.currencyCode).formatted())")
                }
            }
            .font(NookFont.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

struct AllTransactionsView: View {
    @Environment(AppStore.self) private var store

    private struct DayGroup: Identifiable {
        let day: LocalDate
        let entries: [LedgerEntry]
        var id: LocalDate { day }
    }

    private var groups: [DayGroup] {
        let zone = store.timeZone
        let grouped = Dictionary(grouping: store.recentEntries) { LocalDate($0.occurredAt, timeZone: zone) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        TransactionRow(entry: entry)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteEntry(entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(group.day.noon, format: .dateTime.weekday(.wide).month(.wide).day())
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
