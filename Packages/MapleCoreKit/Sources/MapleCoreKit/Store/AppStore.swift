import Foundation
import Observation

/// Single source of truth for the app. Local-first: every write updates state on this iPhone,
/// queues an outbox item for the server and saves a snapshot. Views read from here.
///
/// Phase 1 has no live backend. `syncPending()` simulates the server with `SyncMode.demo`
/// and the UI says so on the Sync & Uploads screen.
@MainActor
@Observable
public final class AppStore {
    public enum SyncMode: Sendable { case demo, disabled }

    // MARK: Session
    public var account: Account?
    public var activeRole: AppRole?
    /// Admin "Preview Field Mode": every write becomes a no-op.
    public var isPreviewingRole = false
    public var previewStaffID: StaffMember.ID?

    // MARK: Data
    public var staff: [StaffMember]
    public var crews: [Crew]
    public var customers: [Customer]
    public var properties: [Property]
    public var routes: [Route]
    public var visitRecords: [VisitRecord]
    public var documents: [PropertyDocument]
    public var threads: [MessageThread]
    public var quotes: [Quote]
    public var invoices: [Invoice]
    public var snowEvent: SnowEvent?
    public var weather: Weather
    public var outbox: [OutboxItem]
    public var conflicts: [SyncConflict]
    public var analytics: [AnalyticsRange: AnalyticsSnapshot]

    // MARK: Device state
    public var settings: AppSettings { didSet { persist() } }
    public var notificationPrefs: NotificationPreferences { didSet { persist() } }
    public var locationSharing: LocationSharing
    public var shift: Shift?
    public var activeVisit: VisitSession?
    public var hasCompletedPermissions: Bool
    public var isOnline = true { didSet { if isOnline && !oldValue { scheduleSync() } } }
    public private(set) var lastSyncedAt: Date?

    // MARK: Infrastructure
    @ObservationIgnored public var clock: @Sendable () -> Date
    @ObservationIgnored private let persistence: SnapshotStoring?
    @ObservationIgnored public var syncMode: SyncMode
    @ObservationIgnored public var syncStepDelay: Duration = .milliseconds(700)
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoring = false

    public init(fixtures: Fixtures = Fixtures(), persistence: SnapshotStoring? = nil, syncMode: SyncMode = .demo, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        self.persistence = persistence
        self.syncMode = syncMode
        staff = fixtures.staff
        crews = fixtures.crews
        customers = fixtures.customers
        properties = fixtures.properties
        routes = fixtures.routes
        visitRecords = fixtures.visitRecords
        documents = fixtures.documents
        threads = fixtures.threads
        quotes = fixtures.quotes
        invoices = fixtures.invoices
        snowEvent = fixtures.snowEvent
        weather = fixtures.weather
        outbox = fixtures.outbox
        conflicts = fixtures.conflicts
        analytics = fixtures.analytics
        settings = AppSettings()
        notificationPrefs = NotificationPreferences()
        locationSharing = LocationSharing()
        hasCompletedPermissions = false
        lastSyncedAt = fixtures.now

        if let snapshot = try? persistence?.load() {
            restore(snapshot)
        }
    }

    public var now: Date { clock() }

    /// True when writes should be ignored (role preview).
    public var isReadOnly: Bool { isPreviewingRole }

    // MARK: - Snapshot

    public func snapshot() -> Snapshot {
        Snapshot(version: Snapshot.currentVersion, savedAt: now, account: account, activeRole: activeRole, staff: staff, crews: crews, customers: customers, properties: properties, routes: routes, visitRecords: visitRecords, documents: documents, threads: threads, quotes: quotes, invoices: invoices, snowEvent: snowEvent, weather: weather, outbox: outbox, conflicts: conflicts, settings: settings, notificationPrefs: notificationPrefs, locationSharing: locationSharing, shift: shift, activeVisit: activeVisit, hasCompletedPermissions: hasCompletedPermissions)
    }

    public func restore(_ s: Snapshot) {
        isRestoring = true
        defer { isRestoring = false }
        account = s.account
        activeRole = s.activeRole
        staff = s.staff
        crews = s.crews
        customers = s.customers
        properties = s.properties
        routes = s.routes
        visitRecords = s.visitRecords
        documents = s.documents
        threads = s.threads
        quotes = s.quotes
        invoices = s.invoices
        snowEvent = s.snowEvent
        weather = s.weather
        outbox = s.outbox
        conflicts = s.conflicts
        settings = s.settings
        notificationPrefs = s.notificationPrefs
        locationSharing = s.locationSharing
        shift = s.shift
        activeVisit = s.activeVisit
        hasCompletedPermissions = s.hasCompletedPermissions
    }

    /// Saves the snapshot. JSON encoding is cheap at this size; the write happens off the main actor.
    public func persist() {
        guard !isRestoring, let persistence else { return }
        let snap = snapshot()
        Task.detached(priority: .utility) {
            try? persistence.save(snap)
        }
    }

    /// Restores fixture data and signs out. Used by Sign Out and "Reset demo data".
    public func resetToFixtures() {
        let f = Fixtures(now: now)
        restore(Snapshot(version: Snapshot.currentVersion, savedAt: now, account: nil, activeRole: nil, staff: f.staff, crews: f.crews, customers: f.customers, properties: f.properties, routes: f.routes, visitRecords: f.visitRecords, documents: f.documents, threads: f.threads, quotes: f.quotes, invoices: f.invoices, snowEvent: f.snowEvent, weather: f.weather, outbox: f.outbox, conflicts: f.conflicts, settings: settings, notificationPrefs: notificationPrefs, locationSharing: LocationSharing(), shift: nil, activeVisit: nil, hasCompletedPermissions: hasCompletedPermissions))
        analytics = f.analytics
        try? persistence?.clear()
    }

    // MARK: - Session

    public func signIn(_ account: Account) {
        self.account = account
        activeRole = account.hasMultipleRoles ? nil : account.roles.first
        persist()
    }

    public func choose(role: AppRole) {
        guard account?.roles.contains(role) == true || role == .admin && account?.roles.contains(where: \.usesAdminShell) == true else { return }
        activeRole = role
        persist()
    }

    public func signOut() {
        account = nil
        activeRole = nil
        shift = nil
        activeVisit = nil
        isPreviewingRole = false
        persist()
    }

    public var capabilities: Capabilities {
        guard let account else { return [] }
        if activeRole == .field { return [] }
        return account.roles.reduce(into: Capabilities()) { $0.formUnion($1.capabilities) }
    }

    /// The staff member whose field view is shown: the preview subject, or the signed-in user.
    public var fieldStaffID: StaffMember.ID? { isPreviewingRole ? previewStaffID : account?.staffID }

    public func beginRolePreview(as staffID: StaffMember.ID = Fixtures.ID.daniel) {
        previewStaffID = staffID
        isPreviewingRole = true
    }

    public func endRolePreview() {
        isPreviewingRole = false
        previewStaffID = nil
    }

    // MARK: - Lookups

    public func property(_ id: Property.ID?) -> Property? { id.flatMap { id in properties.first { $0.id == id } } }
    public func customer(_ id: Customer.ID?) -> Customer? { id.flatMap { id in customers.first { $0.id == id } } }
    public func crew(_ id: Crew.ID?) -> Crew? { id.flatMap { id in crews.first { $0.id == id } } }
    public func member(_ id: StaffMember.ID?) -> StaffMember? { id.flatMap { id in staff.first { $0.id == id } } }
    public func route(_ id: Route.ID?) -> Route? { id.flatMap { id in routes.first { $0.id == id } } }
    public func thread(_ id: MessageThread.ID?) -> MessageThread? { id.flatMap { id in threads.first { $0.id == id } } }
    public func quote(_ id: Quote.ID?) -> Quote? { id.flatMap { id in quotes.first { $0.id == id } } }
    public func invoice(_ id: Invoice.ID?) -> Invoice? { id.flatMap { id in invoices.first { $0.id == id } } }
    public func visit(_ id: VisitRecord.ID?) -> VisitRecord? { id.flatMap { id in visitRecords.first { $0.id == id } } }
    public func conflict(_ id: SyncConflict.ID?) -> SyncConflict? { id.flatMap { id in conflicts.first { $0.id == id } } }
    public func stop(routeID: Route.ID, stopID: RouteStop.ID) -> RouteStop? { route(routeID)?.stops.first { $0.id == stopID } }

    public func members(of crew: Crew) -> [StaffMember] { crew.memberIDs.compactMap { member($0) } }
    public func crewMemberNames(_ crewID: Crew.ID?, short: Bool = true) -> String {
        guard let crew = crew(crewID) else { return "" }
        return members(of: crew).map { short ? $0.firstName : $0.shortName }.joined(separator: ", ")
    }

    public func properties(of customerID: Customer.ID) -> [Property] { properties.filter { $0.customerID == customerID } }
    public func documents(for propertyID: Property.ID) -> [PropertyDocument] { documents.filter { $0.propertyID == propertyID } }
    public func history(for propertyID: Property.ID) -> [VisitRecord] {
        visitRecords.filter { $0.propertyID == propertyID }.sorted { $0.date > $1.date }
    }
    public func invoices(for propertyID: Property.ID) -> [Invoice] {
        invoices.filter { $0.propertyID == propertyID }.sorted { $0.issuedAt > $1.issuedAt }
    }
    public func invoices(forCustomer customerID: Customer.ID) -> [Invoice] { invoices.filter { $0.customerID == customerID } }
    public func quotes(forCustomer customerID: Customer.ID) -> [Quote] { quotes.filter { $0.customerID == customerID } }
    public func customerThread(for propertyID: Property.ID) -> MessageThread? {
        threads.first { $0.kind == .customer && $0.propertyID == propertyID }
    }
    public func customerThread(forCustomer customerID: Customer.ID) -> MessageThread? {
        threads.first { $0.kind == .customer && $0.customerID == customerID }
    }
    public func crewThread(for crewID: Crew.ID) -> MessageThread? { threads.first { $0.kind == .crew && $0.crewID == crewID } }

    // MARK: - Today & routes

    private var calendar: Calendar { Calendar.current }

    public var todayRoutes: [Route] {
        routes.filter { calendar.isDate($0.date, inSameDayAs: now) }.sorted { lhs, rhs in
            func rank(_ r: Route) -> Int { r.state == .completed ? 2 : (r.state == .inProgress ? 0 : 1) }
            return rank(lhs) == rank(rhs) ? lhs.startTime < rhs.startTime : rank(lhs) < rank(rhs)
        }
    }

    public var upcomingRoutes: [Route] {
        routes.filter { calendar.startOfDay(for: $0.date) > calendar.startOfDay(for: now) }.sorted { $0.startTime < $1.startTime }
    }

    /// Completed routes before today, newest day first.
    public var pastRoutesByDay: [(day: Date, routes: [Route])] {
        let past = routes.filter { calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: now) }
        let grouped = Dictionary(grouping: past) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.name < $1.name }) }
    }

    public struct TodayStats: Sendable, Equatable {
        public var scheduled: Int
        public var completed: Int
        public var inProgress: Int
        public var delayed: Int
        public var pending: Int
        public var crewsActive: Int
        public var crewsTotal: Int
    }

    public var todayStats: TodayStats {
        let stops = todayRoutes.flatMap(\.stops)
        let done = stops.filter { $0.status == .done }.count
        let inProgress = stops.filter { $0.status == .inProgress || $0.status == .enRoute }.count + (activeVisit != nil && !isPreviewingRole ? 0 : 0)
        let delayed = stops.filter { $0.status == .delayed }.count
        let activeCrews = Set(todayRoutes.filter { $0.state == .inProgress }.compactMap(\.crewID)).count
        let workingNow = staff.filter(\.isOnDuty).compactMap(\.crewID)
        return TodayStats(scheduled: stops.count, completed: done, inProgress: inProgress, delayed: delayed, pending: stops.count - done - stops.filter { $0.status == .skipped }.count, crewsActive: max(activeCrews, Set(workingNow).count), crewsTotal: crews.count + 1)
    }

    public var reviewQueue: [VisitRecord] {
        visitRecords.filter { $0.kind == .visit && $0.review == .awaiting }.sorted { $0.date > $1.date }
    }

    public var urgentThreads: [MessageThread] { threads.filter { $0.isUrgent && $0.visibleToAdmin } }

    public func unreadCount(forField: Bool) -> Int {
        threads.filter { forField ? $0.visibleToField : $0.visibleToAdmin }.reduce(0) { $0 + $1.unreadCount }
    }

    /// One line describing what's happening at a property today, e.g. "Next today 9:40".
    public func todayStatus(for propertyID: Property.ID) -> (text: String, status: StopStatus)? {
        for route in todayRoutes {
            guard let stop = route.stops.first(where: { $0.propertyID == propertyID }) else { continue }
            switch stop.status {
            case .done: return ("Done today", .done)
            case .inProgress: return ("\(crew(route.crewID)?.name ?? "Crew") on site", .inProgress)
            case .delayed: return ("Delayed · \(Fmt.clock(stop.eta ?? now))", .delayed)
            case .skipped: return ("Skipped today", .skipped)
            default:
                if let eta = stop.eta { return ("Today \(Fmt.clock(eta))", route.nextStop?.id == stop.id ? .enRoute : .pending) }
            }
        }
        if let route = upcomingRoutes.first(where: { $0.stops.contains { $0.propertyID == propertyID } }) {
            return (Fmt.relativeDay(route.date, now: now), .pending)
        }
        return nil
    }

    // MARK: - Field view helpers

    public func crewID(forStaff staffID: StaffMember.ID?) -> Crew.ID? { member(staffID)?.crewID }

    /// Today's route for the field user's crew.
    public var fieldRoute: Route? {
        guard let crewID = crewID(forStaff: fieldStaffID) else { return nil }
        return todayRoutes.first { $0.crewID == crewID && $0.state != .completed && $0.state != .draft }
    }

    public var fieldThreads: [MessageThread] {
        let crewID = crewID(forStaff: fieldStaffID)
        return threads.filter { $0.visibleToField && ($0.kind != .crew || $0.crewID == crewID) }.sorted { $0.lastActivity > $1.lastActivity }
    }

    public var adminThreads: [MessageThread] {
        threads.filter(\.visibleToAdmin).sorted { lhs, rhs in
            if lhs.isUrgent != rhs.isUrgent { return lhs.isUrgent }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    // MARK: - Mutation helpers

    private func mutate(_ body: () -> Void) {
        guard !isReadOnly else { return }
        body()
        persist()
    }

    private func enqueue(_ kind: OutboxKind, title: String, detail: String, units: Int = 1, bytes: Int = 0) {
        outbox.append(OutboxItem(id: UUID().uuidString, kind: kind, title: title, detail: detail, createdAt: now, state: .queued, totalUnits: units, byteCount: bytes))
        scheduleSync()
    }

    private func updateRoute(_ id: Route.ID, _ body: (inout Route) -> Void) {
        guard let i = routes.firstIndex(where: { $0.id == id }) else { return }
        body(&routes[i])
    }

    // MARK: - Properties

    public func addProperty(_ property: Property) {
        mutate {
            properties.insert(property, at: 0)
            enqueue(.note, title: "New property · \(property.name)", detail: property.address)
        }
    }

    public func updateProperty(_ property: Property) {
        mutate {
            guard let i = properties.firstIndex(where: { $0.id == property.id }) else { return }
            properties[i] = property
            enqueue(.note, title: "Property · \(property.name)", detail: "Details updated")
        }
    }

    public func addPropertyNote(_ text: String, propertyID: Property.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate {
            let author = account?.firstName ?? "You"
            visitRecords.append(VisitRecord(id: UUID().uuidString, propertyID: propertyID, kind: .note, title: "Note added", detail: "“\(trimmed)” — \(author)", date: now))
            enqueue(.note, title: "Note · \(property(propertyID)?.name ?? "Property")", detail: "“\(trimmed)”")
        }
    }

    public func reportIssue(_ text: String, propertyID: Property.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate {
            visitRecords.append(VisitRecord(id: UUID().uuidString, propertyID: propertyID, kind: .issue, title: "Issue reported", detail: trimmed, date: now, review: .awaiting))
            if let i = properties.firstIndex(where: { $0.id == propertyID }) { properties[i].openIssues += 1 }
            enqueue(.note, title: "Issue · \(property(propertyID)?.name ?? "Property")", detail: trimmed)
        }
    }

    // MARK: - Routes

    public func saveRoute(_ route: Route) {
        mutate {
            if let i = routes.firstIndex(where: { $0.id == route.id }) { routes[i] = route } else { routes.append(route) }
            enqueue(.visitUpdate, title: "Route · \(route.name)", detail: route.state == .draft ? "Draft saved" : "Route updated")
        }
    }

    public func assignCrew(_ crewID: Crew.ID, to routeID: Route.ID, publish: Bool = true) {
        mutate {
            updateRoute(routeID) { r in
                r.crewID = crewID
                if publish && r.state == .draft { r.state = .scheduled }
            }
            enqueue(.visitUpdate, title: "Crew assigned · \(route(routeID)?.name ?? "Route")", detail: crew(crewID)?.name ?? "")
        }
    }

    public func moveStops(routeID: Route.ID, from source: IndexSet, to destination: Int) {
        mutate {
            updateRoute(routeID) { r in
                let moving = source.sorted().map { r.stops[$0] }
                for index in source.sorted(by: >) { r.stops.remove(at: index) }
                let adjusted = destination - source.filter { $0 < destination }.count
                r.stops.insert(contentsOf: moving, at: min(max(adjusted, 0), r.stops.count))
            }
        }
    }

    public func setPriority(_ priority: Priority, routeID: Route.ID, stopID: RouteStop.ID) {
        mutate {
            updateRoute(routeID) { r in
                guard let i = r.index(of: stopID) else { return }
                r.stops[i].priority = priority
            }
        }
    }

    public func removeStop(routeID: Route.ID, stopID: RouteStop.ID) {
        mutate { updateRoute(routeID) { $0.stops.removeAll { $0.id == stopID } } }
    }

    public func skipStop(routeID: Route.ID, stopID: RouteStop.ID, reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate {
            updateRoute(routeID) { r in
                guard let i = r.index(of: stopID) else { return }
                r.stops[i].status = .skipped
                r.stops[i].skipReason = trimmed
            }
            if let s = stop(routeID: routeID, stopID: stopID) {
                visitRecords.append(VisitRecord(id: UUID().uuidString, propertyID: s.propertyID, kind: .skipped, title: s.serviceName, detail: trimmed, date: now))
            }
            if activeVisit?.stopID == stopID { activeVisit = nil }
            enqueue(.visitUpdate, title: "Stop skipped · \(property(stop(routeID: routeID, stopID: stopID)?.propertyID)?.name ?? "Stop")", detail: trimmed)
        }
    }

    /// Orders unfinished stops: high priority first, then nearest-neighbour by distance from the last finished stop.
    /// Returns the estimated driving minutes saved (straight-line approximation at 30 km/h).
    public func proposedOrder(for routeID: Route.ID) -> (stops: [RouteStop], savedMinutes: Int)? {
        guard let route = route(routeID) else { return nil }
        let finished = route.stops.filter { $0.status.isFinished || $0.status == .inProgress }
        var remaining = route.stops.filter { !($0.status.isFinished || $0.status == .inProgress) }
        guard remaining.count > 1 else { return (route.stops, 0) }
        func coord(_ s: RouteStop) -> (Double, Double) {
            let p = property(s.propertyID)
            return (p?.latitude ?? 0, p?.longitude ?? 0)
        }
        func km(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
            let dLat = (a.0 - b.0) * 111, dLon = (a.1 - b.1) * 111 * cos(a.0 * .pi / 180)
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        func pathKm(_ stops: [RouteStop], from start: (Double, Double)?) -> Double {
            var total = 0.0
            var last = start
            for s in stops { if let l = last { total += km(l, coord(s)) }; last = coord(s) }
            return total
        }
        let start = finished.last.map(coord)
        let before = pathKm(remaining, from: start)
        var ordered = remaining.filter { $0.priority == .high }
        remaining.removeAll { $0.priority == .high }
        var cursor = ordered.last.map(coord) ?? start
        while !remaining.isEmpty {
            let index: Int
            if let c = cursor {
                index = remaining.indices.min { km(c, coord(remaining[$0])) < km(c, coord(remaining[$1])) }!
            } else { index = 0 }
            let next = remaining.remove(at: index)
            ordered.append(next)
            cursor = coord(next)
        }
        let after = pathKm(ordered, from: start)
        let saved = max(0, Int(((before - after) / 30 * 60).rounded()))
        return (finished + ordered, saved)
    }

    @discardableResult
    public func applyOptimizedOrder(routeID: Route.ID) -> Int {
        guard let proposal = proposedOrder(for: routeID) else { return 0 }
        mutate {
            updateRoute(routeID) { r in
                r.stops = proposal.stops
                r.driveMinutes = max(0, r.driveMinutes - proposal.savedMinutes)
            }
        }
        return proposal.savedMinutes
    }

    public func newRouteDraft(on date: Date) -> Route {
        let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        return Route(id: UUID().uuidString, name: "", serviceSummary: "Leaf removal", date: start, startTime: start, crewID: nil, stops: [], state: .draft)
    }

    /// Copies the most recent route for the same weekday a week earlier, if there is one.
    public func copyRoute(_ routeID: Route.ID, to date: Date) -> Route? {
        guard let source = route(routeID) else { return nil }
        let start = calendar.date(bySettingHour: calendar.component(.hour, from: source.startTime), minute: calendar.component(.minute, from: source.startTime), second: 0, of: date) ?? date
        let stops = source.stops.map { s in
            RouteStop(id: UUID().uuidString, propertyID: s.propertyID, serviceName: s.serviceName, estimatedMinutes: s.estimatedMinutes, priority: s.priority, tasks: s.tasks.map { VisitTask(id: UUID().uuidString, title: $0.title) })
        }
        return Route(id: UUID().uuidString, name: source.name, serviceSummary: source.serviceSummary, date: start, startTime: start, crewID: nil, stops: stops, state: .draft, driveMinutes: source.driveMinutes, distanceKm: source.distanceKm)
    }

    /// Crew availability for a given route date: off days and overlapping routes.
    public enum CrewAvailability: Equatable, Sendable {
        case available
        case overlaps(routeName: String, until: Date)
        case off
    }

    public func availability(of crewID: Crew.ID, for route: Route) -> CrewAvailability {
        guard let crew = crew(crewID) else { return .off }
        let weekdayIndex = (calendar.component(.weekday, from: route.date) + 5) % 7 + 1
        if let day = Weekday(rawValue: weekdayIndex), crew.offDays.contains(day) { return .off }
        let routeEnd = route.estimatedEnd
        if let clash = routes.first(where: { $0.id != route.id && $0.crewID == crewID && calendar.isDate($0.date, inSameDayAs: route.date) && $0.state != .completed && $0.startTime < routeEnd && $0.estimatedEnd > route.startTime }) {
            return .overlaps(routeName: clash.name, until: clash.estimatedEnd)
        }
        return .available
    }

    // MARK: - Visits (field)

    public func beginTravel(routeID: Route.ID, stopID: RouteStop.ID) {
        mutate {
            updateRoute(routeID) { r in
                guard let i = r.index(of: stopID) else { return }
                r.stops[i].status = .enRoute
            }
            enqueue(.visitUpdate, title: "On my way · \(property(stop(routeID: routeID, stopID: stopID)?.propertyID)?.name ?? "Stop")", detail: "Travel started \(Fmt.time(now))")
        }
    }

    /// Creates the active visit and marks arrival. Returns the session (also stored in `activeVisit`).
    @discardableResult
    public func arrive(routeID: Route.ID, stopID: RouteStop.ID) -> VisitSession? {
        if let activeVisit, activeVisit.stopID == stopID { return activeVisit }
        // Never replace a visit that is running at another stop.
        if let activeVisit, activeVisit.isActive { return nil }
        guard let route = route(routeID), let index = route.index(of: stopID), let property = property(route.stops[index].propertyID) else { return nil }
        let stop = route.stops[index]
        var session = VisitSession(routeID: routeID, stopID: stopID, propertyID: property.id, propertyName: property.name, stopNumber: index + 1, stopCount: route.stops.count, serviceName: stop.serviceName, estimateMinutes: stop.estimatedMinutes, tasks: stop.tasks)
        try? session.arrive(at: now)
        guard !isReadOnly else { return session }
        activeVisit = session
        updateRoute(routeID) { r in r.stops[index].status = .inProgress; r.stops[index].startedAt = now; r.state = .inProgress }
        enqueue(.visitUpdate, title: "Arrived · \(property.name)", detail: "Arrived \(Fmt.time(now))")
        persist()
        return session
    }

    /// Applies a visit transition using the store clock. Throws `VisitError` for the UI to show.
    public func updateVisit(_ body: (inout VisitSession, Date) throws -> Void) throws {
        guard !isReadOnly, var session = activeVisit else { return }
        try body(&session, now)
        activeVisit = session
        persist()
    }

    public struct SubmittedVisit: Sendable, Equatable {
        public var propertyName: String
        public var workMinutes: Int
        public var photoCount: Int
        public var queuedOffline: Bool
        public var nextStop: RouteStop?
        public var nextStopNumber: Int?
    }

    /// Completes (if needed) and submits the active visit as a report awaiting review.
    @discardableResult
    public func submitVisit() throws -> SubmittedVisit? {
        guard !isReadOnly, var session = activeVisit else { return nil }
        if session.state != .completed { try session.complete(at: now) }
        let workSeconds = session.workingElapsed(at: now)
        let pausedSeconds = session.pausedDuration(at: now)
        let crewID = route(session.routeID)?.crewID
        let record = VisitRecord(id: session.id, propertyID: session.propertyID, kind: .visit, title: session.serviceName, crewID: crewID, crewNames: crewMemberNames(crewID, short: false), date: session.arrivedAt ?? now, arrivedAt: session.arrivedAt, workStart: session.workStartedAt, workEnd: session.completedAt, workMinutes: Int((workSeconds / 60).rounded()), pausedMinutes: Int((pausedSeconds / 60).rounded()), estimateMinutes: session.estimateMinutes, receivedAt: isOnline ? now : nil, photos: session.photos, notes: session.notes, review: .awaiting, arrivalVerified: locationSharing.isSharing(at: now))
        visitRecords.append(record)
        if let issue = session.issue, !issue.isEmpty {
            visitRecords.append(VisitRecord(id: UUID().uuidString, propertyID: session.propertyID, kind: .issue, title: "Issue reported", detail: issue, crewID: crewID, date: now, review: .awaiting))
        }
        var nextStop: RouteStop?
        var nextNumber: Int?
        updateRoute(session.routeID) { r in
            guard let i = r.index(of: session.stopID) else { return }
            r.stops[i].status = .done
            r.stops[i].completedAt = now
            r.stops[i].actualMinutes = record.workMinutes
            r.stops[i].tasks = session.tasks
            r.photoCount += session.photos.count
            if let n = r.nextStop, let ni = r.index(of: n.id) { nextStop = n; nextNumber = ni + 1 }
            if r.stops.allSatisfy({ $0.status.isFinished }) { r.state = .completed; r.finishedAt = now }
        }
        enqueue(.visitUpdate, title: "Visit · \(session.propertyName)", detail: "Times, tasks, notes · saved \(Fmt.clock(now))")
        if !session.photos.isEmpty {
            enqueue(.photoUpload, title: "\(session.photos.count) photos", detail: session.propertyName, units: session.photos.count, bytes: session.photos.count * 2_600_000)
        }
        let result = SubmittedVisit(propertyName: session.propertyName, workMinutes: record.workMinutes, photoCount: session.photos.count, queuedOffline: !isOnline, nextStop: nextStop, nextStopNumber: nextNumber)
        activeVisit = nil
        persist()
        return result
    }

    /// Discards the active visit without submitting (e.g. started by mistake). The stop returns to pending.
    public func cancelActiveVisit() {
        guard let session = activeVisit else { return }
        mutate {
            updateRoute(session.routeID) { r in
                guard let i = r.index(of: session.stopID) else { return }
                r.stops[i].status = .pending
                r.stops[i].startedAt = nil
            }
            activeVisit = nil
        }
    }

    // MARK: - Review

    public func approveVisit(_ id: VisitRecord.ID) {
        mutate {
            guard let i = visitRecords.firstIndex(where: { $0.id == id }) else { return }
            visitRecords[i].review = .approved
            visitRecords[i].reviewedBy = account?.firstName
            visitRecords[i].reviewedAt = now
            enqueue(.visitUpdate, title: "Visit approved", detail: property(visitRecords[i].propertyID)?.name ?? "")
        }
    }

    public func requestChanges(_ id: VisitRecord.ID, note: String) {
        mutate {
            guard let i = visitRecords.firstIndex(where: { $0.id == id }) else { return }
            visitRecords[i].review = .changesRequested
            visitRecords[i].reviewedBy = account?.firstName
            visitRecords[i].reviewedAt = now
            enqueue(.visitUpdate, title: "Changes requested", detail: note)
        }
    }

    // MARK: - Messaging

    public func markRead(_ threadID: MessageThread.ID) {
        guard let i = threads.firstIndex(where: { $0.id == threadID }), threads[i].unreadCount > 0 else { return }
        mutate { threads[i].unreadCount = 0 }
    }

    public func send(_ text: String, to threadID: MessageThread.ID, visibility: MessageVisibility, attachments: [Attachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, let account else { return }
        mutate {
            guard let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
            let resolved: MessageVisibility = threads[i].kind.isInternalOnly ? .internal : visibility
            threads[i].messages.append(Message(id: UUID().uuidString, authorName: account.firstName, authorInitials: account.initials, authorID: account.staffID, text: trimmed, sentAt: now, visibility: resolved, attachments: attachments, delivery: .queued))
            threads[i].unreadCount = 0
            enqueue(.message, title: "Message · \(threads[i].title)", detail: trimmed.isEmpty ? "\(attachments.count) attachment(s)" : trimmed)
        }
    }

    /// Starts (or reuses) a direct thread with a staff member.
    @discardableResult
    public func directThread(with staffID: StaffMember.ID) -> MessageThread.ID? {
        guard let person = member(staffID) else { return nil }
        let viewerIsField = activeRole == .field || isPreviewingRole
        // Match on the person (name, first name or a message they wrote) and the side of the app that can see it.
        if let existing = threads.first(where: { t in
            t.kind == .direct && (viewerIsField ? t.visibleToField : t.visibleToAdmin) &&
            (t.title == person.name || t.title == person.firstName || t.messages.contains { $0.authorID == staffID })
        }) { return existing.id }
        guard !isReadOnly else { return nil }
        let thread = MessageThread(id: UUID().uuidString, kind: .direct, title: person.name, initials: person.initials, subtitle: person.jobTitle, crewID: person.crewID, messages: [], visibleToField: viewerIsField, visibleToAdmin: !viewerIsField)
        threads.append(thread)
        persist()
        return thread.id
    }

    public func postAnnouncement(_ text: String) {
        guard let id = threads.first(where: { $0.kind == .announcement })?.id else { return }
        send(text, to: id, visibility: .internal)
    }

    // MARK: - Quotes

    public func newQuoteDraft(customerID: Customer.ID? = nil, propertyID: Property.ID? = nil) -> Quote {
        let next = (quotes.compactMap { Int($0.number.dropFirst(2)) }.max() ?? 200) + 1
        return Quote(id: UUID().uuidString, number: "Q-\(next)", customerID: customerID, propertyID: propertyID, title: "", division: .lawnCare, status: .draft, lineItems: [], updatedAt: now)
    }

    public func saveQuote(_ quote: Quote) {
        mutate {
            var q = quote
            q.updatedAt = now
            if let i = quotes.firstIndex(where: { $0.id == q.id }) { quotes[i] = q } else { quotes.insert(q, at: 0) }
        }
    }

    public func sendQuote(_ quote: Quote) {
        mutate {
            var q = quote
            q.status = .sent
            q.sentAt = now
            q.expiresAt = calendar.date(byAdding: .day, value: 30, to: now)
            q.updatedAt = now
            if let i = quotes.firstIndex(where: { $0.id == q.id }) { quotes[i] = q } else { quotes.insert(q, at: 0) }
            enqueue(.message, title: "Quote \(q.number) sent", detail: customer(q.customerID)?.name ?? "")
        }
    }

    public func deleteQuote(_ id: Quote.ID) {
        mutate { quotes.removeAll { $0.id == id && $0.status == .draft } }
    }

    // MARK: - Invoices

    public func recordPayment(invoiceID: Invoice.ID, amount: Decimal, method: String, reference: String = "") {
        guard amount > 0 else { return }
        mutate {
            guard let i = invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
            invoices[i].payments.append(Payment(id: UUID().uuidString, amount: min(amount, invoices[i].balance), method: method, receivedAt: now, reference: reference))
            enqueue(.visitUpdate, title: "Payment · \(invoices[i].number)", detail: "\(Fmt.money(amount)) by \(method)")
        }
    }

    public func sendReminder(invoiceID: Invoice.ID) {
        mutate {
            guard let i = invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
            invoices[i].remindersSent += 1
            enqueue(.message, title: "Reminder · \(invoices[i].number)", detail: invoices[i].billToName)
        }
    }

    public func createInvoice(customerID: Customer.ID, propertyID: Property.ID?, title: String, items: [LineItem], dueInDays: Int = 30) -> Invoice.ID? {
        guard let customer = customer(customerID), !items.isEmpty else { return nil }
        let next = (invoices.compactMap { Int($0.number.dropFirst(4)) }.max() ?? 1000) + 1
        let invoice = Invoice(id: UUID().uuidString, number: "INV-\(next)", customerID: customerID, billToName: customer.name, propertyID: propertyID, title: title, issuedAt: now, sentAt: now, dueDate: calendar.date(byAdding: .day, value: dueInDays, to: now) ?? now, lineItems: items)
        guard !isReadOnly else { return nil }
        invoices.insert(invoice, at: 0)
        enqueue(.message, title: "Invoice \(invoice.number) sent", detail: customer.name)
        persist()
        return invoice.id
    }

    public var outstandingInvoices: [Invoice] { invoices.filter { !$0.isPaid } }
    public var overdueInvoices: [Invoice] { invoices.filter { $0.isOverdue(asOf: now) } }

    // MARK: - Staff & crews

    public func addStaff(name: String, email: String, phone: String, crewID: Crew.ID?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        mutate {
            let initials = trimmed.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            staff.append(StaffMember(id: UUID().uuidString, name: trimmed, initials: initials, jobTitle: "Crew member", crewID: crewID, isLead: false, phone: phone, email: email, startYear: calendar.component(.year, from: now), onDutySince: nil, location: .notShared(lastArrival: nil), availability: Array(repeating: true, count: 7), visitsThisWeek: 0, onTimeRate: 0, photoProofRate: 0, lastShift: "—"))
            if let crewID, let ci = crews.firstIndex(where: { $0.id == crewID }) { crews[ci].memberIDs.append(staff.last!.id) }
            enqueue(.note, title: "Invite · \(trimmed)", detail: email.isEmpty ? phone : email)
        }
    }

    public func createCrew(leadID: StaffMember.ID, memberIDs: [StaffMember.ID], truck: String) {
        mutate {
            let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
            let letter = letters.first { l in !crews.contains { $0.letter == l } } ?? "X"
            let crew = Crew(id: UUID().uuidString, name: "Crew \(letter)", letter: letter, leadID: leadID, memberIDs: Array(Set([leadID] + memberIDs)), truck: truck)
            crews.append(crew)
            for id in crew.memberIDs {
                if let i = staff.firstIndex(where: { $0.id == id }) {
                    let old = staff[i].crewID
                    staff[i].crewID = crew.id
                    staff[i].isLead = id == leadID
                    if let old, let oi = crews.firstIndex(where: { $0.id == old }) { crews[oi].memberIDs.removeAll { $0 == id } }
                }
            }
        }
    }

    // MARK: - Snow

    public func dispatchSnow(routeIDs: Set<SnowRoute.ID>, startAt: Date?, message: String) {
        mutate {
            guard var event = snowEvent else { return }
            for i in event.routes.indices where routeIDs.contains(event.routes[i].id) && !event.routes[i].isBelowTrigger {
                event.routes[i].isDispatched = true
            }
            snowEvent = event
            let names = event.routes.filter { routeIDs.contains($0.id) }.map(\.code).joined(separator: ", ")
            enqueue(.message, title: "Snow dispatch · \(names)", detail: startAt.map { "Start \(Fmt.time($0))" } ?? "Start now")
            if !message.trimmingCharacters(in: .whitespaces).isEmpty { postAnnouncement(message) }
        }
    }

    // MARK: - Shift & location

    public func startShift(truck: String) {
        mutate {
            shift = Shift(startedAt: now, truck: truck)
            if let id = account?.staffID, let i = staff.firstIndex(where: { $0.id == id }) { staff[i].onDutySince = now }
            enqueue(.visitUpdate, title: "Shift started", detail: Fmt.time(now))
        }
    }

    public func endShift() {
        mutate {
            shift?.endedAt = now
            if let id = account?.staffID, let i = staff.firstIndex(where: { $0.id == id }) { staff[i].onDutySince = nil }
            enqueue(.visitUpdate, title: "Shift ended", detail: Fmt.time(now))
        }
    }

    /// The field user's shift: their own, or a derived one for preview/fixtures.
    public var currentShift: Shift? {
        if let shift, !isPreviewingRole { return shift.isActive ? shift : nil }
        guard let member = member(fieldStaffID), let since = member.onDutySince else { return nil }
        return Shift(startedAt: since, breakMinutes: 15, breaks: 1, truck: crew(member.crewID)?.truck ?? "")
    }

    public func pauseLocationSharing(minutes: Int = 30) {
        mutate { locationSharing.pausedUntil = now.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    public func setLocationSharing(_ enabled: Bool) {
        mutate {
            locationSharing.enabled = enabled
            if enabled { locationSharing.pausedUntil = nil }
        }
    }

    public func completePermissions() {
        hasCompletedPermissions = true
        persist()
    }

    // MARK: - Sync

    public var pendingOutbox: [OutboxItem] { outbox.filter(\.isPending) }
    public var attentionOutbox: [OutboxItem] { outbox.filter(\.needsAttention) }
    public var isFullySynced: Bool { pendingOutbox.isEmpty && attentionOutbox.isEmpty }

    public func retry(_ itemID: OutboxItem.ID) {
        guard let i = outbox.firstIndex(where: { $0.id == itemID }) else { return }
        guard outbox[i].conflictID == nil else { return }
        outbox[i].state = .queued
        persist()
        scheduleSync()
    }

    public func sendNow() {
        for i in outbox.indices {
            if case .failed = outbox[i].state { outbox[i].state = .queued }
        }
        scheduleSync()
    }

    public func resolveConflict(_ id: SyncConflict.ID, with resolution: ConflictResolution) {
        guard let conflict = conflict(id) else { return }
        if let i = properties.firstIndex(where: { $0.id == conflict.propertyID }) {
            properties[i].accessNotes = conflict.resolvedText(resolution)
        }
        let unchosen = resolution == .mine ? conflict.office : (resolution == .office ? conflict.mine : nil)
        if let unchosen {
            visitRecords.append(VisitRecord(id: UUID().uuidString, propertyID: conflict.propertyID, kind: .note, title: "Earlier version kept in history", detail: "“\(unchosen.text)” — \(unchosen.editedBy)", date: now))
        }
        conflicts.removeAll { $0.id == id }
        if let i = outbox.firstIndex(where: { $0.conflictID == id }) {
            outbox[i].conflictID = nil
            outbox[i].state = .queued
            outbox[i].title = "Access notes · \(property(conflict.propertyID)?.name ?? "")"
            outbox[i].detail = resolution == .keepBoth ? "Both versions kept" : (resolution == .mine ? "Your version" : "Office version")
        }
        persist()
        scheduleSync()
    }

    public func clearSent() {
        outbox.removeAll { $0.state == .sent }
        persist()
    }

    public func scheduleSync() {
        guard syncMode == .demo, isOnline, syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.syncPending()
            self?.syncTask = nil
        }
    }

    /// Demo transport: walks queued items to `sent` while online. There is no server in Phase 1.
    public func syncPending() async {
        while isOnline, let i = outbox.firstIndex(where: { if case .queued = $0.state { return true }; return false }) {
            let id = outbox[i].id
            let units = max(outbox[i].totalUnits, 1)
            for step in outbox[i].completedUnits..<units {
                guard isOnline, let j = outbox.firstIndex(where: { $0.id == id }) else { return }
                outbox[j].state = .sending(progress: Double(step) / Double(units))
                try? await Task.sleep(for: syncStepDelay)
                guard isOnline, let k = outbox.firstIndex(where: { $0.id == id }) else {
                    if let k = outbox.firstIndex(where: { $0.id == id }) { outbox[k].state = .queued }
                    return
                }
                outbox[k].completedUnits = step + 1
            }
            guard let k = outbox.firstIndex(where: { $0.id == id }) else { continue }
            outbox[k].state = .sent
            markDelivered()
            lastSyncedAt = now
            persist()
        }
    }

    private func markDelivered() {
        for t in threads.indices {
            for m in threads[t].messages.indices where threads[t].messages[m].delivery == .queued {
                threads[t].messages[m].delivery = .sent
            }
        }
        for v in visitRecords.indices where visitRecords[v].receivedAt == nil && visitRecords[v].kind == .visit {
            visitRecords[v].receivedAt = now
            for p in visitRecords[v].photos.indices where visitRecords[v].photos[p].receivedAt == nil {
                visitRecords[v].photos[p].receivedAt = now
                visitRecords[v].photos[p].upload = .uploaded
            }
        }
    }
}
