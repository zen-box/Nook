import Foundation

public struct TransportDetails: Hashable, Codable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable { case train, flight, other }
    public var kind: Kind
    public var number: String
    public var departure: String
    public var arrival: String
    public var departureTimeZone: String
    public var arrivalTimeZone: String
    public var terminal: String
    public var gate: String
    public var platform: String
    public var carriage: String
    public var seat: String
    public var boardingAt: Date?

    public init(kind: Kind = .train, number: String = "", departure: String = "", arrival: String = "",
                departureTimeZone: String = TimeZone.current.identifier, arrivalTimeZone: String = TimeZone.current.identifier,
                terminal: String = "", gate: String = "", platform: String = "", carriage: String = "", seat: String = "", boardingAt: Date? = nil) {
        self.kind = kind; self.number = number; self.departure = departure; self.arrival = arrival
        self.departureTimeZone = departureTimeZone; self.arrivalTimeZone = arrivalTimeZone
        self.terminal = terminal; self.gate = gate; self.platform = platform; self.carriage = carriage
        self.seat = seat; self.boardingAt = boardingAt
    }
}
