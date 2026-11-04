import Foundation

/// The trip and its timed transport segment are saved in one existing record transaction.
/// Timed segments remain events so calendar, notifications, backups and sync use one source.
public enum TripJourneyPlan {
    public static func make(trip: TripPlan, previousTrip: TripPlan?, journey: ScheduleEvent?,
                            previousJourney: ScheduleEvent?, now: Date = Date()) throws -> AgentPlan {
        guard previousTrip == nil || previousTrip?.id == trip.id,
              previousJourney?.planID == nil || previousJourney?.planID == trip.id,
              previousJourney == nil || journey == nil || previousJourney?.id == journey?.id else {
            throw AgentPlanError.conflict
        }
        var saved = trip
        saved.updatedAt = now
        var segment = journey
        if var event = segment {
            guard let transport = event.transport,
                  let departureZone = TimeZone(identifier: transport.departureTimeZone),
                  let arrivalZone = TimeZone(identifier: transport.arrivalTimeZone) else {
                throw AgentPlanError.invalid("transport time zone")
            }
            if let boarding = transport.boardingAt, boarding > event.start { throw AgentPlanError.invalid("boarding time") }
            event.planID = saved.id; event.category = .travel; event.isAllDay = false; event.updatedAt = now
            saved.startDate = min(saved.startDate, LocalDate(event.start, timeZone: departureZone))
            saved.endDate = max(saved.endDate, LocalDate(event.end ?? event.start, timeZone: arrivalZone))
            try AgentPlanner.validate(try .from(event), kind: .event)
            segment = event
        }
        try AgentPlanner.validate(try .from(saved), kind: .trip)
        var mutations = [AgentMutation(kind: .trip, id: saved.id, before: try previousTrip.map { try JSONValue.from($0) }, after: try .from(saved))]
        if let segment {
            mutations.append(.init(kind: .event, id: segment.id, before: try previousJourney.map { try JSONValue.from($0) }, after: try .from(segment)))
        } else if let previousJourney {
            mutations.append(.init(kind: .event, id: previousJourney.id, before: try .from(previousJourney), after: nil))
        }
        return AgentPlan(summary: saved.title, mutations: mutations)
    }
}
