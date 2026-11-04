import Foundation

/// Kinds of synced records (spec §6.1 `type`).
public enum RecordType: String, Codable, CaseIterable, Sendable {
    case note
    case vaultItem = "vault_item"
    case event
    case plan
    case anniversary
    case transaction
    case account
    case budget
    case subscription
    case file
    case tag
    case category
}

/// The unit the sync server stores (spec §6.1). The business record is encrypted on the device
/// into `ciphertext`; the server only ever sees this metadata. Sync itself arrives after P0.
public struct RecordEnvelope: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: RecordType
    /// Revision of the record, increased by every change.
    public var rev: Int64
    /// Position in the server's change feed; nil until the server has accepted the change.
    public var seq: Int64?
    /// Which data key encrypted `ciphertext`.
    public var keyVersion: Int
    public var nonce: Data
    public var ciphertext: Data
    /// Tombstone: the record was deleted.
    public var deleted: Bool
    public var updatedByDevice: UUID?
    public var serverUpdatedAt: Date?

    public init(
        id: UUID,
        type: RecordType,
        rev: Int64,
        seq: Int64? = nil,
        keyVersion: Int,
        nonce: Data,
        ciphertext: Data,
        deleted: Bool = false,
        updatedByDevice: UUID? = nil,
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.rev = rev
        self.seq = seq
        self.keyVersion = keyVersion
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.deleted = deleted
        self.updatedByDevice = updatedByDevice
        self.serverUpdatedAt = serverUpdatedAt
    }
}

/// Wire format: lowercase UUIDs, unpadded Base64URL bytes and RFC 3339 times, whatever the
/// encoder's own strategies are.
extension RecordEnvelope: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case rev
        case seq
        case keyVersion = "key_version"
        case nonce
        case ciphertext
        case deleted
        case updatedByDevice = "updated_by_device"
        case serverUpdatedAt = "server_updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeUUID(forKey: .id),
            type: try container.decode(RecordType.self, forKey: .type),
            rev: try container.decode(Int64.self, forKey: .rev),
            seq: try container.decodeIfPresent(Int64.self, forKey: .seq),
            keyVersion: try container.decode(Int.self, forKey: .keyVersion),
            nonce: try container.decodeBase64URL(forKey: .nonce),
            ciphertext: try container.decodeBase64URL(forKey: .ciphertext),
            deleted: try container.decode(Bool.self, forKey: .deleted),
            updatedByDevice: try container.decodeUUIDIfPresent(forKey: .updatedByDevice),
            serverUpdatedAt: try container.decodeRFC3339IfPresent(forKey: .serverUpdatedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(rev, forKey: .rev)
        try container.encodeIfPresent(seq, forKey: .seq)
        try container.encode(keyVersion, forKey: .keyVersion)
        try container.encode(Base64URL.encode(nonce), forKey: .nonce)
        try container.encode(Base64URL.encode(ciphertext), forKey: .ciphertext)
        try container.encode(deleted, forKey: .deleted)
        try container.encodeIfPresent(updatedByDevice?.uuidString.lowercased(), forKey: .updatedByDevice)
        try container.encodeIfPresent(serverUpdatedAt.map(RFC3339.string(from:)), forKey: .serverUpdatedAt)
    }
}

fileprivate extension KeyedDecodingContainer {
    func decodeUUID(forKey key: Key) throws -> UUID {
        guard let value = try decodeUUIDIfPresent(forKey: key) else {
            throw DecodingError.valueNotFound(UUID.self, .init(codingPath: codingPath + [key], debugDescription: "Missing UUID"))
        }
        return value
    }

    /// Nil when the key is missing or null.
    func decodeUUIDIfPresent(forKey key: Key) throws -> UUID? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let value = UUID(uuidString: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid UUID \(text)")
        }
        return value
    }

    func decodeBase64URL(forKey key: Key) throws -> Data {
        let text = try decode(String.self, forKey: key)
        guard let value = Base64URL.decode(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid Base64URL")
        }
        return value
    }

    func decodeRFC3339IfPresent(forKey key: Key) throws -> Date? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let value = RFC3339.date(from: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid RFC 3339 time \(text)")
        }
        return value
    }
}
