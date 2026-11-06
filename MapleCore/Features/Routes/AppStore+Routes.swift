import Foundation
import MapleCoreKit

/// Read-only helpers for the Routes screens. Uses only the store's public API.
extension AppStore {
    /// The most recent earlier route on the same weekday as `date` (for "Copy Last Tuesday").
    func routesLastRoute(sameWeekdayAs date: Date) -> Route? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: date)
        return routes
            .filter { $0.state != .draft && cal.startOfDay(for: $0.date) < day && cal.component(.weekday, from: $0.date) == weekday }
            .max { $0.date < $1.date }
    }

    /// Visit reports filed for a route: same day, same crew, one of the route's properties.
    func routesVisitRecords(for route: Route) -> [VisitRecord] {
        let cal = Calendar.current
        let propertyIDs = Set(route.stops.map(\.propertyID))
        return visitRecords.filter { record in
            record.kind == .visit
                && propertyIDs.contains(record.propertyID)
                && cal.isDate(record.date, inSameDayAs: route.date)
                && (route.crewID == nil || record.crewID == route.crewID)
        }
    }

    /// Reports from this route still waiting for a supervisor.
    func routesPendingReviews(for route: Route) -> [VisitRecord] {
        let ids = Set(routesVisitRecords(for: route).map(\.id))
        return reviewQueue.filter { ids.contains($0.id) }
    }

    /// Property lookup table for planning maths.
    var routesPropertyLookup: [Property.ID: Property] {
        Dictionary(properties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// "Crew A · Daniel R., Marco S."
    func routesCrewLine(_ crewID: Crew.ID?) -> String {
        guard let crew = crew(crewID) else { return "No crew yet" }
        let names = members(of: crew).map(\.shortName).joined(separator: ", ")
        return names.isEmpty ? crew.name : "\(crew.name) · \(names)"
    }
}
