import Foundation
import Testing
@testable import NookCore

struct RecordEnvelopeTests {
    private static let id = UUID(uuidString: "0190A5B2-C3D4-7E5F-8A6B-1C2D3E4F5A6B")!
    private static let device = UUID(uuidString: "0190A5B2-0000-7000-8000-00000000000D")!
    private static let required = #""id":"0190a5b2-c3d4-7e5f-8a6b-1c2d3e4f5a6b","type":"note","rev":1,"key_version":1,"deleted":false"#

    private func sample(seq: Int64? = 42, device: UUID? = RecordEnvelopeTests.device, serverUpdatedAt: Date? = Date(timeIntervalSince1970: 1_793_721_600.25)) -> RecordEnvelope {
        RecordEnvelope(
            id: Self.id, type: .vaultItem, rev: 3, seq: seq, keyVersion: 1,
            nonce: Data([0xFB, 0xFF, 0x00]), ciphertext: Data([0x01, 0x02, 0x03, 0x04]),
            updatedByDevice: device, serverUpdatedAt: serverUpdatedAt
        )
    }

    @Test func encodesTheWireFormat() throws {
        #expect(try Fixtures.jsonText(sample()) == """
            {"ciphertext":"AQIDBA","deleted":false,"id":"0190a5b2-c3d4-7e5f-8a6b-1c2d3e4f5a6b","key_version":1,\
            "nonce":"-_8A","rev":3,"seq":42,"server_updated_at":"2026-11-03T16:00:00.250Z","type":"vault_item",\
            "updated_by_device":"0190a5b2-0000-7000-8000-00000000000d"}
            """)
    }

    @Test func roundTrips() throws {
        let envelope = sample()
        #expect(try Fixtures.decode(RecordEnvelope.self, from: Fixtures.jsonText(envelope)) == envelope)
    }

    @Test func leavesOutUnsetFields() throws {
        let json = try Fixtures.jsonText(sample(seq: nil, device: nil, serverUpdatedAt: nil))
        #expect(!json.contains("seq"))
        #expect(!json.contains("updated_by_device"))
        #expect(!json.contains("server_updated_at"))
    }

    @Test func acceptsNullAndMissingOptionalFields() throws {
        let envelope = try Fixtures.decode(
            RecordEnvelope.self,
            from: "{" + Self.required + #","nonce":"AA","ciphertext":"","updated_by_device":null,"seq":null}"#
        )
        #expect(envelope.id == Self.id)
        #expect(envelope.seq == nil)
        #expect(envelope.updatedByDevice == nil)
        #expect(envelope.serverUpdatedAt == nil)
        #expect(envelope.nonce == Data([0x00]))
        #expect(envelope.ciphertext.isEmpty)
    }

    @Test(arguments: [
        #","nonce":"AA==","ciphertext":"AA""#,  // padded
        #","nonce":"a+b/","ciphertext":"AA""#,  // standard alphabet
        #","nonce":"AA","ciphertext":"A""#,  // impossible length
        #","nonce":"AA","ciphertext":"AA","updated_by_device":"device-1""#,
        #","nonce":"AA","ciphertext":"AA","server_updated_at":"2026-11-04""#,
    ])
    func rejectsMalformedFields(fields: String) {
        #expect(throws: DecodingError.self) {
            try Fixtures.decode(RecordEnvelope.self, from: "{" + Self.required + fields + "}")
        }
    }

    @Test func rejectsUnknownTypes() {
        let text = #"{"id":"0190a5b2-c3d4-7e5f-8a6b-1c2d3e4f5a6b","type":"mystery","rev":1,"key_version":1,"deleted":false,"nonce":"AA","ciphertext":"AA"}"#
        #expect(throws: DecodingError.self) {
            try Fixtures.decode(RecordEnvelope.self, from: text)
        }
    }
}
