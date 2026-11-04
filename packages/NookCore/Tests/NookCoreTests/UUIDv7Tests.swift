import Foundation
import Testing
@testable import NookCore

struct UUIDv7Tests {
    @Test func setsVersionAndVariantBits() {
        var generator = SplitMix64(seed: 1)
        for _ in 0..<100 {
            let id = UUIDv7.make(timestamp: Date(timeIntervalSince1970: 1_793_721_600), using: &generator)
            #expect(UUIDv7.version(of: id) == 7)
            #expect(id.uuid.8 & 0xC0 == 0x80)
        }
    }

    @Test func embedsTheTimestamp() throws {
        let instant = Date(timeIntervalSince1970: 1_793_721_600.5)
        let embedded = try #require(UUIDv7.timestamp(of: UUIDv7.make(timestamp: instant)))
        #expect(embedded == instant)
    }

    @Test func clampsTimesBeforeTheEpoch() throws {
        let id = UUIDv7.make(timestamp: Date(timeIntervalSince1970: -5))
        #expect(id.uuidString.hasPrefix("00000000-0000-7"))
        #expect(try #require(UUIDv7.timestamp(of: id)) == Date(timeIntervalSince1970: 0))
    }

    @Test func otherVersionsHaveNoTimestamp() {
        let random = UUID()
        #expect(UUIDv7.version(of: random) == 4)
        #expect(UUIDv7.timestamp(of: random) == nil)
    }

    @Test func laterIdsSortAfterEarlierOnes() {
        var generator = SplitMix64(seed: 7)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ids = (0..<50).map { UUIDv7.make(timestamp: start.addingTimeInterval(Double($0)), using: &generator) }
        let strings = ids.map(\.uuidString)
        #expect(strings == strings.sorted())
    }

    @Test func seededGeneratorsMakeTheSameIds() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        let instant = Date(timeIntervalSince1970: 1_793_721_600)
        #expect(UUIDv7.make(timestamp: instant, using: &first) == UUIDv7.make(timestamp: instant, using: &second))
    }
}
