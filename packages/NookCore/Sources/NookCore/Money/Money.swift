import Foundation

/// An amount of money in integer minor units (cents), so sums never pick up floating-point error.
/// Encoded as {"amount_minor": 128050, "currency": "USD"}.
public struct Money: Hashable, Sendable {
    public var minorUnits: Int64
    public var currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
    }

    public static func zero(_ currencyCode: String) -> Money {
        Money(minorUnits: 0, currencyCode: currencyCode)
    }

    public var isZero: Bool { minorUnits == 0 }

    /// Digits after the decimal point for an ISO 4217 currency (JPY 0, USD 2, KWD 3).
    public static func minorUnitDigits(for currencyCode: String) -> Int {
        switch currencyCode.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF":
            return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        default:
            return 2
        }
    }

    public var minorUnitDigits: Int { Money.minorUnitDigits(for: currencyCode) }

    public var decimalValue: Decimal {
        Decimal(sign: minorUnits < 0 ? .minus : .plus, exponent: -minorUnitDigits, significand: Decimal(minorUnits.magnitude))
    }

    /// Localized text with the narrow currency symbol, e.g. "$1,280.50" (not "US$1,280.50").
    public func formatted(locale: Locale = .current) -> String {
        decimalValue.formatted(.currency(code: currencyCode).presentation(.narrow).locale(locale))
    }

    /// Parses typed input such as "1,280.50", "12.5" or "-3". Returns nil for malformed input
    /// or for more fraction digits than the currency allows.
    public static func parse(_ text: String, currencyCode: String, decimalSeparator: String = ".") -> Money? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var negative = false
        if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }
        let grouping: Set<Character> = decimalSeparator == "," ? [".", " ", "\u{00A0}", "'"] : [",", " ", "\u{00A0}", "'"]
        body.removeAll { grouping.contains($0) }

        let pieces = body.components(separatedBy: decimalSeparator)
        guard pieces.count <= 2 else { return nil }
        let integerPart = pieces[0]
        let fractionPart = pieces.count == 2 ? pieces[1] : ""
        let digits = minorUnitDigits(for: currencyCode)
        guard !(integerPart.isEmpty && fractionPart.isEmpty),
              isASCIIDigits(integerPart), isASCIIDigits(fractionPart),
              integerPart.count <= 15, fractionPart.count <= digits else { return nil }

        let whole = Int64(integerPart.isEmpty ? "0" : integerPart) ?? 0
        let paddedFraction = fractionPart + String(repeating: "0", count: digits - fractionPart.count)
        let fraction = Int64(paddedFraction.isEmpty ? "0" : paddedFraction) ?? 0
        var scale: Int64 = 1
        for _ in 0..<digits { scale *= 10 }
        let total = whole * scale + fraction
        return Money(minorUnits: negative ? -total : total, currencyCode: currencyCode)
    }

    private static func isASCIIDigits(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

extension Money {
    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Cannot add \(lhs.currencyCode) and \(rhs.currencyCode)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currencyCode: lhs.currencyCode)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Cannot subtract \(rhs.currencyCode) from \(lhs.currencyCode)")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currencyCode: lhs.currencyCode)
    }

    public static func += (lhs: inout Money, rhs: Money) {
        lhs = lhs + rhs
    }
}

extension Money: Codable {
    enum CodingKeys: String, CodingKey {
        case minorUnits = "amount_minor"
        case currencyCode = "currency"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minorUnits: try container.decode(Int64.self, forKey: .minorUnits),
            currencyCode: try container.decode(String.self, forKey: .currencyCode)
        )
    }
}
