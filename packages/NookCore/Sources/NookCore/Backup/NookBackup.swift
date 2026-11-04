import Foundation

/// A plain JSON export of the user's records (spec §13.5.1 local backup). The vault is left out:
/// its secrets may only leave the device in the encrypted format that arrives with P3.
public struct NookBackup: Codable, Equatable, Sendable {
    public static let format = "nook.backup"
    public static let currentVersion = 1

    public enum ReadError: Error, Equatable {
        case notANookBackup
        case unsupportedVersion(Int)
    }

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var notes: [Note]
    public var events: [ScheduleEvent]
    public var trips: [TripPlan]
    public var anniversaries: [Anniversary]
    public var ledger: [LedgerEntry]

    public init(
        exportedAt: Date = Date(),
        notes: [Note] = [],
        events: [ScheduleEvent] = [],
        trips: [TripPlan] = [],
        anniversaries: [Anniversary] = [],
        ledger: [LedgerEntry] = []
    ) {
        self.format = NookBackup.format
        self.version = NookBackup.currentVersion
        self.exportedAt = exportedAt
        self.notes = notes
        self.events = events
        self.trips = trips
        self.anniversaries = anniversaries
        self.ledger = ledger
    }

    public func encoded() throws -> Data {
        let encoder = NookJSON.makeEncoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        return try encoder.encode(self)
    }

    /// Reads a backup, checking that it is one and that this version of Nook understands it.
    public static func decode(_ data: Data) throws -> NookBackup {
        struct Header: Decodable {
            var format: String?
            var version: Int?
        }
        let decoder = NookJSON.makeDecoder()
        let header = try? decoder.decode(Header.self, from: data)
        guard let header, header.format == NookBackup.format, let version = header.version else {
            throw ReadError.notANookBackup
        }
        guard version == currentVersion else {
            throw ReadError.unsupportedVersion(version)
        }
        return try decoder.decode(NookBackup.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case format
        case version
        case exportedAt = "exported_at"
        case notes
        case events
        case trips = "plans"
        case anniversaries
        case ledger = "transactions"
    }
}
