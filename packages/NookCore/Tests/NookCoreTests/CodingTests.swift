import Foundation
import Testing
@testable import NookCore

struct CodingTests {
    @Test func base64URLUsesTheURLSafeAlphabetWithoutPadding() {
        #expect(Base64URL.encode(Data([0xFB, 0xFF])) == "-_8")
        #expect(Base64URL.encode(Data("hello".utf8)) == "aGVsbG8")
        #expect(Base64URL.encode(Data()) == "")
        #expect(Base64URL.decode("-_8") == Data([0xFB, 0xFF]))
        #expect(Base64URL.decode("aGVsbG8") == Data("hello".utf8))
    }

    @Test(arguments: ["a", "aGVsbG8=", "+/8", "aGV sbG8", "aGVsbG8\n"])
    func base64URLRejects(text: String) {
        #expect(Base64URL.decode(text) == nil)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 31, 32, 33, 255])
    func base64URLRoundTrips(length: Int) {
        var generator = SplitMix64(seed: UInt64(length))
        let bytes = Data((0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        #expect(Base64URL.decode(Base64URL.encode(bytes)) == bytes)
    }

    @Test func rfc3339WritesUTCWithMilliseconds() {
        #expect(RFC3339.string(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        #expect(RFC3339.string(from: Date(timeIntervalSince1970: 1_793_721_600.25)) == "2026-11-03T16:00:00.250Z")
    }

    @Test func rfc3339ReadsWithAndWithoutFractions() {
        #expect(RFC3339.date(from: "2026-11-03T16:00:00.250Z") == Date(timeIntervalSince1970: 1_793_721_600.25))
        #expect(RFC3339.date(from: "2026-11-03T16:00:00Z") == Date(timeIntervalSince1970: 1_793_721_600))
        #expect(RFC3339.date(from: "2026-11-04") == nil)
        #expect(RFC3339.date(from: "yesterday") == nil)
    }

    @Test func nookJSONSortsKeysAndWritesRFC3339Dates() throws {
        struct Sample: Codable, Equatable {
            var zeta: Int
            var alpha: Date
            var link: String
        }
        let sample = Sample(zeta: 1, alpha: Date(timeIntervalSince1970: 0), link: "https://example.com/a")
        let json = try Fixtures.jsonText(sample)
        #expect(json == #"{"alpha":"1970-01-01T00:00:00.000Z","link":"https://example.com/a","zeta":1}"#)
        #expect(try Fixtures.decode(Sample.self, from: json) == sample)
    }
}
