import Foundation
import MapleCoreKit

/// Read-only helpers for Business & Team screens. Only public AppStore API is used.
extension AppStore {
    /// Today's route for a crew: the one in progress first, then scheduled, then completed.
    func bizTodayRoute(forCrew crewID: Crew.ID?) -> Route? {
        guard let crewID else { return nil }
        return todayRoutes.first { $0.crewID == crewID && $0.state != .draft }
    }

    /// Crew status for today, derived from today's routes.
    func bizCrewStatus(_ crew: Crew) -> (text: String, tone: Tone, symbol: String) {
        guard let route = bizTodayRoute(forCrew: crew.id) else {
            return ("No route today", .neutral, "moon.zzz")
        }
        switch route.state {
        case .completed:
            return ("Done \(Fmt.clock(route.finishedAt ?? route.estimatedEnd))", .green, "checkmark.circle.fill")
        case .inProgress:
            if route.delayMinutes > 0 { return ("Delayed \(route.delayMinutes) min", .amber, "exclamationmark.triangle.fill") }
            return ("Working", .blue, "circle.lefthalf.filled")
        case .scheduled, .draft:
            return ("Starts \(Fmt.clock(route.startTime))", .neutral, "clock")
        }
    }

    /// Sum of quote totals.
    func bizTotal(of quotes: [Quote]) -> Decimal {
        quotes.reduce(Decimal(0)) { $0 + $1.totals.total }
    }

    /// Quotes approved in the current calendar month.
    var bizQuotesApprovedThisMonth: [Quote] {
        let calendar = Calendar.current
        return quotes.filter { quote in
            guard quote.status == .approved, let approvedAt = quote.approvedAt else { return false }
            return calendar.isDate(approvedAt, equalTo: now, toGranularity: .month)
        }
    }

    /// Whole days between two dates, ignoring time of day.
    func bizDays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
