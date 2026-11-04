import SwiftUI
import NookCore

struct AddTransactionView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LedgerKind = .expense
    @State private var amountText = ""
    @State private var category: LedgerCategory = .food
    @State private var title = ""
    @State private var date = Date()
    @FocusState private var amountFocused: Bool

    private var amount: Money? {
        Money.parse(amountText, currencyCode: store.currencyCode, decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }

    private var canSave: Bool {
        guard let amount else { return false }
        return amount.minorUnits > 0
    }

    private var categories: [LedgerCategory] {
        kind == .income ? LedgerCategory.incomeCases : LedgerCategory.expenseCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.sectionSpacing) {
                    PillSegmentedControl(options: [LedgerKind.expense, .income], selection: $kind) { $0.label }
                    amountCard
                    categoryGrid
                    detailsCard
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(kind == .income ? Text("Add Income") : Text("Add Expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { amountFocused = true }
        .onChange(of: kind) { _, newKind in
            category = newKind == .income ? .salary : .food
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private var amountCard: some View {
        VStack(spacing: 6) {
            Text("Amount")
                .font(NookFont.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: currencySymbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                TextField(text: $amountText, prompt: Text(verbatim: "0.00")) {
                    Text("Amount")
                }
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(kind == .income ? Pastel.mint.strong : Theme.textPrimary)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .fixedSize()
            }
            if !amountText.isEmpty && amount == nil {
                Text("Enter an amount like 12.50")
                    .font(NookFont.micro)
                    .foregroundStyle(Pastel.rose.strong)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = store.currencyCode
        return formatter.currencySymbol ?? "$"
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            ForEach(categories, id: \.self) { option in
                let isSelected = option == category
                Button {
                    category = option
                } label: {
                    VStack(spacing: 6) {
                        IconTile(symbol: option.symbol, pastel: option.pastel, size: 42)
                        Text(option.shortLabel)
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Theme.primarySoft : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.primary.opacity(0.5), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .card(padding: 12)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
                TextField("Description (optional)", text: $title)
                    .font(.subheadline)
            }
            .padding(.vertical, 14)
            Hairline()
            DatePicker(selection: $date, displayedComponents: [.date, .hourAndMinute]) {
                Label("Date", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 14)
        .card(padding: 0)
    }

    private func save() {
        guard let amount, amount.minorUnits > 0 else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addEntry(
            LedgerEntry(
                kind: kind,
                amount: amount,
                category: category,
                title: trimmed.isEmpty ? category.plainName : trimmed,
                occurredAt: date
            )
        )
        router.showToast(ToastMessage(text: kind == .income ? "Income added" : "Expense added"))
        dismiss()
    }
}
