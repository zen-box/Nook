import SwiftUI
import NookCore

/// "Expenses (This Week)": total, change against the same days last week, daily bars and the
/// top categories. Shown on the Schedule and Finance tabs.
struct WeekExpenseCard: View {
    let today: LocalDate
    var showsCategories = true
    @Environment(AppStore.self) private var store

    var body: some View {
        let week = today.isoWeek
        let summary = store.weekToDate(today: today)
        let shares = store.breakdown(in: store.interval(for: week))
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expenses (This Week)")
                    .font(NookFont.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: summary.current.formatted())
                        .font(NookFont.amount)
                        .foregroundStyle(Theme.textPrimary)
                    if let change = summary.change {
                        ChangeBadge(change: change)
                    }
                }
            }
            DailyBarChart(totals: store.dailyTotals(days: week), today: today)
                .frame(height: 128)
            if showsCategories && !shares.isEmpty {
                Hairline()
                VStack(spacing: 12) {
                    ForEach(Array(shares.prefix(3))) { share in
                        CategoryShareRow(share: share)
                    }
                }
            }
        }
        .card()
        .accessibilityIdentifier("card.weekExpenses")
    }
}

struct CategoryShareRow: View {
    let share: CategoryShare

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: share.category.symbol, pastel: share.category.pastel, size: 34)
            Text(share.category.label)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: share.amount.formatted())
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: "\(share.percent)%")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Daily bars: today saturated mint, past days soft mint, future days a faint stub.
struct DailyBarChart: View {
    enum Labels {
        case weekday
        case dayOfMonth
    }

    let totals: [DailyTotal]
    let today: LocalDate
    var labels: Labels = .weekday

    var body: some View {
        let maxValue = max(totals.map(\.total.minorUnits).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: labels == .weekday ? 10 : 3) {
            ForEach(totals) { item in
                BarColumn(
                    ratio: CGFloat(item.total.minorUnits) / CGFloat(maxValue),
                    isToday: item.day == today,
                    isFuture: item.day > today,
                    label: label(for: item.day)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily spending chart"))
    }

    private func label(for day: LocalDate) -> String {
        switch labels {
        case .weekday:
            return day.noon.formatted(.dateTime.weekday(.abbreviated))
        case .dayOfMonth:
            return [1, 8, 15, 22, 29].contains(day.day) ? "\(day.day)" : " "
        }
    }
}

private struct BarColumn: View {
    let ratio: CGFloat
    let isToday: Bool
    let isFuture: Bool
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let height: CGFloat = isFuture || ratio <= 0 ? 6 : max(proxy.size.height * ratio, 8)
                RoundedRectangle(cornerRadius: min(proxy.size.width / 2, 8), style: .continuous)
                    .fill(fill)
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            Text(verbatim: label)
                .font(.system(.caption2, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private var fill: AnyShapeStyle {
        if isToday {
            return AnyShapeStyle(LinearGradient(colors: [Pastel.mint.base, Pastel.mint.strong], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(isFuture ? Theme.border : Pastel.mint.base.opacity(0.4))
    }
}

/// A ring split by category, with the total in the middle.
struct DonutChart: View {
    let shares: [CategoryShare]
    var lineWidth: CGFloat = 16

    private struct Segment: Identifiable {
        let id: LedgerCategory
        let start: Double
        let end: Double
        let color: Color
    }

    var body: some View {
        let sum = shares.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        let gap = shares.count > 1 ? 0.006 : 0
        ZStack {
            Circle()
                .stroke(Theme.surfaceMuted, lineWidth: lineWidth)
            ForEach(segments(total: Double(max(sum, 1)))) { segment in
                Circle()
                    .trim(from: segment.start + gap, to: max(segment.end - gap, segment.start + gap))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(verbatim: Money(minorUnits: sum, currencyCode: shares.first?.amount.currencyCode ?? "USD").formatted())
                    .font(.system(.subheadline, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Total")
                    .font(NookFont.micro)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, lineWidth)
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .combine)
    }

    private func segments(total: Double) -> [Segment] {
        var result: [Segment] = []
        var start = 0.0
        for share in shares {
            let end = start + Double(share.amount.minorUnits) / total
            result.append(Segment(id: share.category, start: start, end: end, color: share.category.pastel.base))
            start = end
        }
        return result
    }
}

struct TransactionRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: entry.category.symbol, pastel: entry.category.pastel)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(NookFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: amountText)
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(entry.kind == .income ? Pastel.mint.strong : Theme.textPrimary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let day = LocalDate(entry.occurredAt, timeZone: .current)
        let when = day == LocalDate.today() ? TimeText.time(entry.occurredAt) : DateText.monthDay(entry.occurredAt)
        return "\(entry.category.plainName) · \(when)"
    }

    private var amountText: String {
        switch entry.kind {
        case .expense: entry.signedAmount.formatted()
        case .income: "+" + entry.amount.formatted()
        case .transfer: entry.amount.formatted()
        }
    }
}

struct TransactionsCard: View {
    let entries: [LedgerEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                TransactionRow(entry: entry)
                if index < entries.count - 1 {
                    Hairline().padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .card(padding: 0)
    }
}
