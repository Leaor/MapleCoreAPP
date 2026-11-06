import Foundation
import MapleCoreKit

/// Read-only helpers for the Properties feature. Built on AppStore's public API only.
extension AppStore {
    /// The next unfinished stop at this property: today's routes first, then upcoming routes.
    func scheduledStop(forProperty propertyID: Property.ID) -> (route: Route, stop: RouteStop)? {
        for route in todayRoutes where route.state != .draft {
            if let stop = route.stops.first(where: { $0.propertyID == propertyID && !$0.status.isFinished }) {
                return (route, stop)
            }
        }
        for route in upcomingRoutes where route.state != .draft {
            if let stop = route.stops.first(where: { $0.propertyID == propertyID }) {
                return (route, stop)
            }
        }
        return nil
    }

    /// Today's route that includes this property (any stop status).
    func todayRoute(servingProperty propertyID: Property.ID) -> Route? {
        todayRoutes.first { route in route.state != .draft && route.stops.contains { $0.propertyID == propertyID } }
    }

    /// The field user's unfinished stop at this property, if it is on their route today.
    func fieldStop(atProperty propertyID: Property.ID) -> (route: Route, stop: RouteStop)? {
        guard let route = fieldRoute,
              let stop = route.stops.first(where: { $0.propertyID == propertyID && !$0.status.isFinished }) else { return nil }
        return (route, stop)
    }

    /// Matches property name, address, city or customer name.
    func searchProperties(matching query: String, in source: [Property]) -> [Property] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return source }
        return source.filter { p in
            p.name.localizedCaseInsensitiveContains(q)
                || p.address.localizedCaseInsensitiveContains(q)
                || p.city.localizedCaseInsensitiveContains(q)
                || (customer(p.customerID)?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// Most recent visit report at a property that has photos.
    func latestPhotoVisit(forProperty propertyID: Property.ID) -> VisitRecord? {
        history(for: propertyID).first { $0.kind == .visit && !$0.photos.isEmpty }
    }

    /// Before/after pairs matched by angle, in before-photo order.
    func photoPairs(for visit: VisitRecord) -> [PropertyPhotoPair] {
        let afters = visit.photos(.after)
        var used = Set<VisitPhoto.ID>()
        var pairs: [PropertyPhotoPair] = []
        for before in visit.photos(.before) {
            if let after = afters.first(where: { $0.angle == before.angle && !used.contains($0.id) }) {
                used.insert(after.id)
                pairs.append(PropertyPhotoPair(before: before, after: after))
            }
        }
        return pairs
    }

    /// Open (unpaid) balance across a customer's invoices.
    func balanceDue(forCustomer customerID: Customer.ID) -> Decimal {
        invoices(forCustomer: customerID).reduce(Decimal(0)) { $0 + $1.balance }
    }

    /// Customer-visible messages preview for a property: the last non-system message.
    func latestCustomerMessage(in thread: MessageThread) -> Message? {
        thread.messages.last { !$0.isSystemEvent }
    }
}

struct PropertyPhotoPair: Identifiable, Hashable {
    var before: VisitPhoto
    var after: VisitPhoto
    var id: String { before.id + "|" + after.id }
    var angle: String { before.angle }
}

extension Property {
    var fullAddress: String { city.isEmpty ? address : "\(address), \(city)" }
}

/// Small formatting helpers local to the Properties feature.
enum PropertyFormat {
    /// "May 1 – Apr 30, 2027"
    static func contractRange(_ start: Date?, _ end: Date?) -> String? {
        guard let start, let end else { return nil }
        var startStyle = Date.FormatStyle().month(.abbreviated).day()
        startStyle.locale = Fmt.locale
        var endStyle = Date.FormatStyle().month(.abbreviated).day().year()
        endStyle.locale = Fmt.locale
        let text = "\(start.formatted(startStyle)) – \(end.formatted(endStyle))"
        return text.replacingOccurrences(of: ".", with: "")
    }

    /// "1,150 m²"
    static func area(_ value: Int) -> String { "\(Fmt.number(value)) m²" }
    /// "140 m"
    static func length(_ value: Int) -> String { "\(Fmt.number(value)) m" }

    /// Day of month, two digits: "05", "19".
    static func dayNumber(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.day, from: date))
    }
}
