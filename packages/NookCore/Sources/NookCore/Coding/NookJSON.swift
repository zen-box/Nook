import Foundation

/// JSON coding shared by Nook payloads (spec §9): RFC 3339 UTC dates with milliseconds and
/// sorted keys, so the same value always encodes to the same bytes.
public enum NookJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.string(from: date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = RFC3339.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an RFC 3339 date, got \(text)")
            }
            return date
        }
        return decoder
    }
}

/// RFC 3339 timestamps in UTC, e.g. "2026-11-04T02:00:00.000Z".
public enum RFC3339 {
    public static func string(from date: Date) -> String {
        // Formatting a fractional Double directly can truncate 123 ms to 122 ms on a
        // subsequent decode/encode. Quantize once to the documented millisecond format.
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = floor(milliseconds / 1000)
        let fraction = Int(milliseconds - seconds * 1000)
        let base = Date.ISO8601FormatStyle().format(Date(timeIntervalSince1970: seconds))
        return String(base.dropLast()) + String(format: ".%03dZ", fraction)
    }

    /// Accepts timestamps with or without fractional seconds.
    public static func date(from text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }
}

/// Unpadded Base64URL (RFC 4648 §5), used for binary fields in API payloads.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        var text = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while text.hasSuffix("=") {
            text.removeLast()
        }
        return text
    }

    /// Returns nil for padding, characters outside the URL-safe alphabet, or an impossible length.
    public static func decode(_ text: String) -> Data? {
        let isURLSafe = text.utf8.allSatisfy { byte in
            (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45 || byte == 95
        }
        guard isURLSafe, text.utf8.count % 4 != 1 else { return nil }
        let base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4))
    }
}
