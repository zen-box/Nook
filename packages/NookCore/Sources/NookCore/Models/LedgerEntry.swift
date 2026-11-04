import Foundation

public enum LedgerKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case transfer
}

/// Built-in categories. User-defined categories (spec §6.2 category records) come later.
public enum LedgerCategory: String, Codable, CaseIterable, Sendable {
    case food
    case travel
    case shopping
    case transport
    case housing
    case entertainment
    case health
    case salary
    case others
}

/// One money movement (spec §6.2 "transaction"; named so it doesn't clash with SwiftUI's Transaction).
public struct LedgerEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: LedgerKind
    /// Never negative: `kind` says which way the money moved.
    public var amountMinor: Int64
    public var currencyCode: String
    public var category: LedgerCategory
    public var title: String
    public var note: String
    public var occurredAt: Date
    public var accountID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        kind: LedgerKind = .expense,
        amount: Money,
        category: LedgerCategory,
        title: String,
        note: String = "",
        occurredAt: Date,
        accountID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        precondition(amount.minorUnits >= 0, "Ledger amounts are never negative; use kind for direction")
        self.id = id
        self.kind = kind
        self.amountMinor = amount.minorUnits
        self.currencyCode = amount.currencyCode
        self.category = category
        self.title = title
        self.note = note
        self.occurredAt = occurredAt
        self.accountID = accountID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var amount: Money {
        get { Money(minorUnits: amountMinor, currencyCode: currencyCode) }
        set {
            amountMinor = newValue.minorUnits
            currencyCode = newValue.currencyCode
        }
    }

    /// Negative for expenses, positive for income, zero for transfers between own accounts.
    public var signedAmount: Money {
        switch kind {
        case .expense: Money(minorUnits: -amountMinor, currencyCode: currencyCode)
        case .income: amount
        case .transfer: .zero(currencyCode)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
        case amountMinor = "amount_minor"
        case currencyCode = "currency"
        case category
        case title
        case note
        case occurredAt = "occurred_at"
        case accountID = "account_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
