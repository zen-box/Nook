import Foundation
@testable import NookCore

/// A seeded generator, so ids made in tests are the same on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    /// A fixed UTC+8 zone, so results don't depend on the machine running the tests.
    static let plus8 = TimeZone(secondsFromGMT: 8 * 3600)!
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> LocalDate {
        guard let value = LocalDate(year: year, month: month, day: dayOfMonth) else {
            preconditionFailure("Invalid fixture date \(year)-\(month)-\(dayOfMonth)")
        }
        return value
    }

    /// `hour`:`minute` on the given day in UTC+8.
    static func time(_ year: Int, _ month: Int, _ dayOfMonth: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        day(year, month, dayOfMonth).date(hour: hour, minute: minute, in: plus8)
    }

    static func usd(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "USD")
    }

    static func expense(
        _ minorUnits: Int64,
        _ category: LedgerCategory,
        at date: Date,
        currency: String = "USD",
        kind: LedgerKind = .expense
    ) -> LedgerEntry {
        LedgerEntry(
            kind: kind,
            amount: Money(minorUnits: minorUnits, currencyCode: currency),
            category: category,
            title: category.rawValue,
            occurredAt: date,
            createdAt: date
        )
    }

    /// The value as compact NookJSON text (sorted keys), for checking field names.
    static func jsonText<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try NookJSON.makeEncoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try NookJSON.makeDecoder().decode(type, from: Data(text.utf8))
    }

    /// The keys of a JSON object.
    static func topLevelKeys(_ data: Data) throws -> Set<String> {
        Set(try JSONDecoder().decode([String: AnyJSON].self, from: data).keys)
    }

    /// Accepts any JSON value without looking at it.
    struct AnyJSON: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
