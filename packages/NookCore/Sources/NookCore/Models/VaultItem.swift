import Foundation

public enum VaultCategory: String, Codable, CaseIterable, Sendable {
    case account
    case card
    case other
}

/// What the vault list shows about an entry. Secret storage arrives with the encrypted vault in
/// P3, so this type deliberately has no password or card-number field.
public struct VaultItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    /// Login name or a masked identifier such as "***** 4589".
    public var subtitle: String
    public var category: VaultCategory
    /// SF Symbols name chosen for the entry.
    public var icon: String
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        subtitle: String,
        category: VaultCategory,
        icon: String,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.icon = icon
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case subtitle
        case category
        case icon
        case isFavorite = "favorite"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
