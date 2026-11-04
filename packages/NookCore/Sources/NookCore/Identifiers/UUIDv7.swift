import Foundation

/// UUID version 7 (RFC 9562): a 48-bit Unix timestamp in milliseconds followed by random bits,
/// so record ids sort roughly by creation time (spec §6.1).
public enum UUIDv7 {
    private static let maxMilliseconds: UInt64 = 0xFFFF_FFFF_FFFF

    public static func make(timestamp: Date = Date()) -> UUID {
        var generator = SystemRandomNumberGenerator()
        return make(timestamp: timestamp, using: &generator)
    }

    public static func make<G: RandomNumberGenerator>(timestamp: Date, using generator: inout G) -> UUID {
        let milliseconds = clampedMilliseconds(timestamp)
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> UInt64(8 * (5 - index)))
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70  // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 9562 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// The version nibble of any UUID: 4 for random UUIDs, 7 for ids made here.
    public static func version(of uuid: UUID) -> Int {
        Int(uuid.uuid.6 >> 4)
    }

    /// The creation time embedded in a version 7 UUID, or nil for other versions.
    public static func timestamp(of uuid: UUID) -> Date? {
        guard version(of: uuid) == 7 else { return nil }
        let u = uuid.uuid
        let milliseconds = [u.0, u.1, u.2, u.3, u.4, u.5].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func clampedMilliseconds(_ date: Date) -> UInt64 {
        let value = (date.timeIntervalSince1970 * 1000).rounded(.down)
        if value <= 0 { return 0 }
        if value >= Double(maxMilliseconds) { return maxMilliseconds }
        return UInt64(value)
    }
}
