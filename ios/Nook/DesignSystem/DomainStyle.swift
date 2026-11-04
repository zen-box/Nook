import SwiftUI
import NookCore

// Names, icons and colors for NookCore's categories. Kept in the app because they are UI.

extension NoteCategory {
    var label: LocalizedStringKey {
        switch self {
        case .work: "Work"
        case .travel: "Travel"
        case .life: "Life"
        case .personal: "Personal"
        }
    }

    var symbol: String {
        switch self {
        case .work: "lightbulb"
        case .travel: "airplane"
        case .life: "book"
        case .personal: "person"
        }
    }

    var pastel: Pastel {
        switch self {
        case .work: .peach
        case .travel: .blue
        case .life: .rose
        case .personal: .violet
        }
    }
}

extension EventCategory {
    var label: LocalizedStringKey {
        switch self {
        case .work: "Work"
        case .travel: "Travel"
        case .personal: "Personal"
        case .health: "Health"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .travel: "airplane"
        case .personal: "person"
        case .health: "heart"
        case .other: "calendar"
        }
    }

    var pastel: Pastel {
        switch self {
        case .work: .mint
        case .travel: .peach
        case .personal: .blue
        case .health: .rose
        case .other: .violet
        }
    }
}

extension LedgerCategory {
    var label: LocalizedStringKey {
        switch self {
        case .food: "Food & Dining"
        case .travel: "Travel"
        case .shopping: "Shopping"
        case .transport: "Transport"
        case .housing: "Housing"
        case .entertainment: "Entertainment"
        case .health: "Health"
        case .salary: "Salary"
        case .others: "Others"
        }
    }

    /// Fits under an icon in the category grid.
    var shortLabel: LocalizedStringKey {
        switch self {
        case .food: "Food"
        case .entertainment: "Fun"
        default: label
        }
    }

    /// For places that need a plain string, like the default title of a new entry.
    var plainName: String {
        switch self {
        case .food: String(localized: "Food & Dining")
        case .travel: String(localized: "Travel")
        case .shopping: String(localized: "Shopping")
        case .transport: String(localized: "Transport")
        case .housing: String(localized: "Housing")
        case .entertainment: String(localized: "Entertainment")
        case .health: String(localized: "Health")
        case .salary: String(localized: "Salary")
        case .others: String(localized: "Others")
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .travel: "airplane"
        case .shopping: "bag"
        case .transport: "tram"
        case .housing: "house"
        case .entertainment: "ticket"
        case .health: "cross.case"
        case .salary: "banknote"
        case .others: "square.grid.2x2"
        }
    }

    var pastel: Pastel {
        switch self {
        case .food: .peach
        case .travel: .blue
        case .shopping: .rose
        case .transport: .violet
        case .housing: .mint
        case .entertainment: .violet
        case .health: .rose
        case .salary: .mint
        case .others: .slate
        }
    }

    static var expenseCases: [LedgerCategory] {
        [.food, .travel, .shopping, .transport, .housing, .entertainment, .health, .others]
    }

    static var incomeCases: [LedgerCategory] { [.salary, .others] }
}

extension LedgerKind {
    var label: LocalizedStringKey {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        }
    }
}

extension VaultCategory {
    var label: LocalizedStringKey {
        switch self {
        case .account: "Accounts"
        case .card: "Cards"
        case .other: "Others"
        }
    }

    var singularLabel: LocalizedStringKey {
        switch self {
        case .account: "Account"
        case .card: "Card"
        case .other: "Other"
        }
    }

    var defaultIcon: String {
        switch self {
        case .account: "person.crop.circle"
        case .card: "creditcard"
        case .other: "key"
        }
    }

    /// Icons offered in the editor.
    var iconChoices: [String] {
        switch self {
        case .account:
            ["person.crop.circle", "envelope", "cloud", "building.columns", "briefcase", "cart", "play.rectangle", "gamecontroller", "message", "globe"]
        case .card:
            ["creditcard", "wallet.bifold", "banknote", "building.columns", "tram", "cart"]
        case .other:
            ["key", "wifi", "wifi.router", "person.text.rectangle", "house", "car", "doc.text", "lock"]
        }
    }

    /// Starting fields for a new entry, with labels in the current language.
    var templateFields: [VaultField] {
        switch self {
        case .account:
            [
                VaultField(label: String(localized: "Username")),
                VaultField(label: String(localized: "Password"), isSecret: true),
            ]
        case .card:
            [
                VaultField(label: String(localized: "Cardholder")),
                VaultField(label: String(localized: "Card Number"), isSecret: true),
                VaultField(label: String(localized: "Expiry")),
                VaultField(label: String(localized: "CVV"), isSecret: true),
            ]
        case .other:
            [
                VaultField(label: String(localized: "Detail")),
                VaultField(label: String(localized: "Password"), isSecret: true),
            ]
        }
    }

    var symbol: String {
        switch self {
        case .account: "person.crop.circle"
        case .card: "creditcard"
        case .other: "tray.full"
        }
    }

    var pastel: Pastel {
        switch self {
        case .account: .mint
        case .card: .peach
        case .other: .violet
        }
    }
}

extension VaultItem {
    var pastel: Pastel {
        switch icon {
        case "envelope", "creditcard", "wifi", "globe", "person.crop.circle": .blue
        case "cloud", "person.text.rectangle", "play.rectangle", "gamecontroller": .violet
        case "building.columns", "cart", "banknote", "car": .peach
        case "briefcase", "wallet.bifold", "house", "key": .mint
        case "person.2", "message", "lock": .rose
        default: .slate
        }
    }
}

extension AnniversaryKind {
    var label: LocalizedStringKey {
        switch self {
        case .birthday: "Birthday"
        case .anniversary: "Anniversary"
        case .personal: "Personal"
        case .project: "Project"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .birthday: "gift"
        case .anniversary: "heart"
        case .personal: "star"
        case .project: "flag"
        case .custom: "sparkles"
        }
    }

    var pastel: Pastel {
        switch self {
        case .birthday: .rose
        case .anniversary: .peach
        case .personal: .blue
        case .project: .mint
        case .custom: .violet
        }
    }
}

extension Note {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
    }

    var hasImage: Bool { attachments.contains { $0.kind == .image } }
}
