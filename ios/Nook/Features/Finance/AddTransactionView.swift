import SwiftUI
import NookCore

/// Adds a new expense or income (`entryID` nil) or edits an existing one.
struct AddTransactionView: View {
    let entryID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LedgerKind = .expense
    @State private var amountText = ""
    @State private var currency = ""
    @State private var category: LedgerCategory = .food
    @State private var title = ""
    @State private var date = Date()
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private var amount: Money? {
        Money.parse(amountText, currencyCode: currency, decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }

    private var canSave: Bool {
        guard let amount else { return false }
        return amount.minorUnits > 0
    }

    private var categories: [LedgerCategory] {
        kind == .income ? LedgerCategory.incomeCases : LedgerCategory.expenseCases
    }

    private var titleText: Text {
        switch (entryID == nil, kind == .income) {
        case (true, true): Text("Add Income")
        case (true, false): Text("Add Expense")
        case (false, true): Text("Edit Income")
        case (false, false): Text("Edit Expense")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.sectionSpacing) {
                    PillSegmentedControl(options: [LedgerKind.expense, .income], selection: $kind) { $0.label }
                    amountCard
                    categoryGrid
                    detailsCard
                    if entryID != nil {
                        Button("Delete", role: .destructive) {
                            confirmDelete = true
                        }
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.top, 4)
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(titleText)
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
            .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entryID {
                        guard store.deleteEntry(entryID) else { return }
                    }
                    dismiss()
                }
            }
        }
        .onAppear { load() }
        .onChange(of: kind) { _, newKind in
            if !categories.contains(category) {
                category = newKind == .income ? .salary : .food
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        currency = store.currencyCode
        if let entryID, let entry = store.entry(id: entryID) {
            kind = entry.kind
            currency = entry.currencyCode
            category = entry.category
            title = entry.title
            date = entry.occurredAt
            amountText = entry.amount.decimalValue.formatted(
                .number.precision(.fractionLength(entry.amount.minorUnitDigits)).grouping(.never)
            )
        } else {
            amountFocused = true
        }
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
        formatter.currencyCode = currency.isEmpty ? store.currencyCode : currency
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
        let name = trimmed.isEmpty ? category.plainName : trimmed
        if let entryID, var entry = store.entry(id: entryID) {
            entry.kind = kind
            entry.amount = amount
            entry.category = category
            entry.title = name
            entry.occurredAt = date
            guard store.saveEntry(entry) else { return }
            router.showToast(ToastMessage(text: "Changes saved"))
        } else {
            guard store.saveEntry(LedgerEntry(kind: kind, amount: amount, category: category, title: name, occurredAt: date)) else { return }
            router.showToast(ToastMessage(text: kind == .income ? "Income added" : "Expense added"))
        }
        dismiss()
    }
}
