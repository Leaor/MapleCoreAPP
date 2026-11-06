import Foundation
import MapleCoreKit

/// Read-only helpers for Field Mode. Built only on AppStore's public API; mutations stay in the store.
@MainActor
extension AppStore {
    /// The field user (or the staff member being previewed).
    var fieldMember: StaffMember? { member(fieldStaffID) }

    /// The field user's crew.
    var fieldCrew: Crew? { crew(crewID(forStaff: fieldStaffID)) }

    /// The field user's shift, only while it is running.
    var activeFieldShift: Shift? {
        guard let shift = currentShift, shift.isActive else { return nil }
        return shift
    }

    /// Today's routes for the field user's crew, including finished ones.
    var fieldTodayRoutes: [Route] {
        guard let crewID = fieldCrew?.id else { return [] }
        return todayRoutes.filter { $0.crewID == crewID }
    }

    /// A route the crew already finished today (shown instead of "No route assigned yet").
    var fieldFinishedRouteToday: Route? {
        fieldTodayRoutes.first { $0.state == .completed }
    }

    /// Completed routes for the field user's crew, newest first.
    var fieldPastRoutes: [Route] {
        guard let crewID = fieldCrew?.id else { return [] }
        return routes
            .filter { $0.crewID == crewID && $0.state == .completed }
            .sorted { ($0.finishedAt ?? $0.date) > ($1.finishedAt ?? $1.date) }
    }

    /// Visits the crew completed today across its routes.
    var fieldVisitsCompletedToday: Int {
        fieldTodayRoutes.reduce(0) { $0 + $1.completedCount }
    }

    /// Items still waiting in the outbox, including ones that need attention.
    var fieldWaitingUploadCount: Int { pendingOutbox.count + attentionOutbox.count }

    /// The stop the crew should work next: the one in progress, else the next unstarted stop.
    func fieldCurrentStop(in route: Route) -> RouteStop? {
        route.inProgressStop ?? route.nextStop
    }

    /// 1-based stop number in route order.
    func stopNumber(_ stopID: RouteStop.ID, in route: Route) -> Int {
        (route.index(of: stopID) ?? 0) + 1
    }

    /// Projected finish: the last unfinished stop's ETA plus its job length.
    func projectedFinish(for route: Route) -> Date {
        if route.state == .completed, let finished = route.finishedAt { return finished }
        let remaining = route.stops.filter { !$0.status.isFinished }
        if let last = remaining.last, let eta = last.eta {
            return eta.addingTimeInterval(TimeInterval(last.estimatedMinutes * 60))
        }
        return route.estimatedEnd
    }

    /// The manager the field user messages ("Message Manager", availability requests).
    var fieldManager: StaffMember? { member(Fixtures.ID.michael) }

    /// The field-visible direct thread with the manager. The fixture thread is titled with the first
    /// name, so match on name or authorship before asking the store to create a new direct thread.
    func fieldManagerThreadID() -> MessageThread.ID? {
        guard let manager = fieldManager else { return nil }
        let existing = threads.first { thread in
            thread.kind == .direct && thread.visibleToField && (
                thread.title == manager.name ||
                thread.title == manager.firstName ||
                thread.messages.contains { $0.authorID == manager.id }
            )
        }
        if let existing { return existing.id }
        return directThread(with: manager.id)
    }

    /// Days the field user is marked off this week, e.g. "Off Sun".
    var fieldAvailabilitySummary: String {
        guard let availability = fieldMember?.availability, availability.count == 7 else { return "Not set" }
        let off = availability.enumerated().compactMap { index, isOn in
            isOn ? nil : Weekday(rawValue: index + 1).map { String($0.label.prefix(3)) }
        }
        if off.isEmpty { return "All week" }
        if off.count == 7 { return "Off all week" }
        return "Off " + off.joined(separator: ", ")
    }
}
