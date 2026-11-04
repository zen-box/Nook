import Foundation

public enum JSONValue: Hashable, Codable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), integer(Int64), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue? { object?[key] }
    public var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var int: Int? { if case .integer(let v) = self { Int(exactly: v) } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var foundation: Any {
        switch self {
        case .object(let v): v.mapValues(\.foundation)
        case .array(let v): v.map(\.foundation)
        case .string(let v): v
        case .integer(let v): v
        case .number(let v): v
        case .bool(let v): v
        case .null: NSNull()
        }
    }
    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try NookJSON.makeDecoder().decode(Self.self, from: NookJSON.makeEncoder().encode(value))
    }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try NookJSON.makeDecoder().decode(type, from: NookJSON.makeEncoder().encode(self))
    }
    public var json: String { (try? String(data: NookJSON.makeEncoder().encode(self), encoding: .utf8)) ?? "null" }
}
