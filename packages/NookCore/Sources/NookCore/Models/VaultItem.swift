import Foundation

public enum VaultCategory: String, Codable, CaseIterable, Sendable {
    case account
    case card
    case other
}

/// One labelled value of a vault entry, such as "Username" or "Password".
public struct VaultField: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    /// Hidden until revealed; copied to a clipboard entry that expires.
    public var isSecret: Bool

    public init(id: UUID = UUIDv7.make(), label: String, value: String = "", isSecret: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.isSecret = isSecret
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case value
        case isSecret = "secret"
    }
}

/// A vault entry (spec 6.2 `vault_item`). The app keeps it only in encrypted form on disk.
public struct VaultItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var category: VaultCategory
    /// SF Symbols name chosen for the entry.
    public var icon: String
    public var isFavorite: Bool
    public var url: String?
    public var notes: String
    public var fields: [VaultField]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        category: VaultCategory,
        icon: String,
        isFavorite: Bool = false,
        url: String? = nil,
        notes: String = "",
        fields: [VaultField] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.icon = icon
        self.isFavorite = isFavorite
        self.url = url
        self.notes = notes
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// The line under the name in lists: the last four digits of a card number, otherwise the
    /// first visible field (usually the login name).
    public var subtitle: String {
        if category == .card,
           let number = fields.first(where: { $0.isSecret && Self.digits(in: $0.value).count >= 12 }) {
            return "•••• " + String(Self.digits(in: number.value).suffix(4))
        }
        let visible = fields.first { !$0.isSecret && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        return visible?.value.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The first filled-in secret field, for one-tap copying.
    public var primarySecret: VaultField? {
        fields.first { $0.isSecret && !$0.value.isEmpty }
    }

    /// Whether the search text appears in the name, the visible fields, the address or the notes.
    /// Secret values are never searched.
    public func matches(_ search: String) -> Bool {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = ([title, url ?? "", notes] + fields.filter { !$0.isSecret }.flatMap { [$0.label, $0.value] })
            .joined(separator: "\n")
        return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static func digits(in text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case category
        case icon
        case isFavorite = "favorite"
        case url
        case notes
        case fields
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
