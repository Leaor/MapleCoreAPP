import Foundation

/// Visit lifecycle shared by the visit cover, the Live Activity and supervisor review.
/// notStarted → travelling → arrived → working ⇄ paused → completed → reviewed
public enum VisitState: String, Codable, CaseIterable, Hashable, Sendable {
    case notStarted, travelling, arrived, working, paused, completed, reviewed

    public var label: String {
        switch self {
        case .notStarted: "Scheduled"
        case .travelling: "En route"
        case .arrived: "On site"
        case .working: "Working"
        case .paused: "Paused"
        case .completed: "Submitted"
        case .reviewed: "Approved"
        }
    }
}

public enum PauseReason: String, Codable, CaseIterable, Hashable, Sendable {
    case `break`, weather, equipment
    public var label: String { rawValue.capitalized }
}

public struct VisitPause: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date?
    public var reason: PauseReason

    public init(start: Date, end: Date? = nil, reason: PauseReason) {
        self.start = start
        self.end = end
        self.reason = reason
    }

    public func duration(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

public enum VisitError: Error, Equatable, Sendable {
    case invalidTransition(from: VisitState, action: String)
    case needsBeforePhotos(have: Int, need: Int)
    case needsAfterPhotos(have: Int, need: Int)
    case skipNeedsReason

    public var message: String {
        switch self {
        case let .invalidTransition(from, action): "Can't \(action) while the visit is \(from.label.lowercased())."
        case let .needsBeforePhotos(have, need): "Take \(need - have) more before photo\(need - have == 1 ? "" : "s") to start work."
        case let .needsAfterPhotos(have, need): "Take \(need - have) more after photo\(need - have == 1 ? "" : "s") to finish."
        case .skipNeedsReason: "Choose a reason for skipping this stop."
        }
    }
}

/// The visit currently in progress on this iPhone. Elapsed time is always derived from stored
/// dates so the timer survives the app being backgrounded or killed.
public struct VisitSession: Codable, Hashable, Sendable, Identifiable {
    public static let requiredBeforePhotos = 3
    public static let requiredAfterPhotos = 3

    public var id: String
    public var routeID: Route.ID
    public var stopID: RouteStop.ID
    public var propertyID: Property.ID
    public var propertyName: String
    public var stopNumber: Int
    public var stopCount: Int
    public var serviceName: String
    public var estimateMinutes: Int
    public var requiredAngles: [String]

    public private(set) var state: VisitState
    public private(set) var travelStartedAt: Date?
    public private(set) var arrivedAt: Date?
    public private(set) var workStartedAt: Date?
    public private(set) var completedAt: Date?
    public private(set) var pauses: [VisitPause]
    public var photos: [VisitPhoto]
    public var tasks: [VisitTask]
    public var notes: String
    public var issue: String?
    public var skipReason: String?

    public init(id: String = UUID().uuidString, routeID: Route.ID, stopID: RouteStop.ID, propertyID: Property.ID, propertyName: String, stopNumber: Int, stopCount: Int, serviceName: String, estimateMinutes: Int, requiredAngles: [String] = ["Front beds", "Parking lot", "Side gate"], tasks: [VisitTask] = [], state: VisitState = .notStarted) {
        self.id = id
        self.routeID = routeID
        self.stopID = stopID
        self.propertyID = propertyID
        self.propertyName = propertyName
        self.stopNumber = stopNumber
        self.stopCount = stopCount
        self.serviceName = serviceName
        self.estimateMinutes = estimateMinutes
        self.requiredAngles = requiredAngles
        self.state = state
        self.pauses = []
        self.photos = []
        self.tasks = tasks
        self.notes = ""
    }

    // MARK: Derived

    public func photos(_ kind: PhotoKind) -> [VisitPhoto] { photos.filter { $0.kind == kind } }
    public var beforeCount: Int { photos(.before).count }
    public var afterCount: Int { photos(.after).count }
    public var canStartWork: Bool { (state == .arrived) && beforeCount >= Self.requiredBeforePhotos }
    public var canComplete: Bool { (state == .working || state == .paused) && afterCount >= Self.requiredAfterPhotos }
    public var isTimerRunning: Bool { state == .working }
    public var isActive: Bool { [.arrived, .working, .paused].contains(state) }
    public var currentPause: VisitPause? { pauses.last.flatMap { $0.end == nil ? $0 : nil } }

    /// The next required angle without a photo of the given kind, if any.
    public func nextAngle(for kind: PhotoKind) -> String? {
        let taken = Set(photos(kind).map(\.angle))
        return requiredAngles.first { !taken.contains($0) }
    }

    /// The matching before photo for an angle — used as the onion-skin overlay in After mode.
    public func beforePhoto(forAngle angle: String) -> VisitPhoto? {
        photos(.before).first { $0.angle == angle }
    }

    public func pausedDuration(at now: Date) -> TimeInterval {
        pauses.reduce(0) { $0 + $1.duration(at: now) }
    }

    /// now − workStart − Σ pauses. Frozen at completion.
    public func workingElapsed(at now: Date) -> TimeInterval {
        guard let start = workStartedAt else { return 0 }
        let end = completedAt ?? now
        let paused = pauses.reduce(0) { $0 + $1.duration(at: end) }
        return max(0, end.timeIntervalSince(start) - paused)
    }

    public func onSiteElapsed(at now: Date) -> TimeInterval {
        guard let arrivedAt else { return 0 }
        return max(0, (completedAt ?? now).timeIntervalSince(arrivedAt))
    }

    public var completedTaskCount: Int { tasks.filter(\.isDone).count }

    // MARK: Transitions

    public mutating func startTravel(at now: Date) throws {
        guard state == .notStarted else { throw VisitError.invalidTransition(from: state, action: "start travel") }
        travelStartedAt = now
        state = .travelling
    }

    public mutating func arrive(at now: Date) throws {
        guard state == .notStarted || state == .travelling else { throw VisitError.invalidTransition(from: state, action: "arrive") }
        arrivedAt = now
        state = .arrived
    }

    public mutating func startWork(at now: Date) throws {
        guard state == .arrived else { throw VisitError.invalidTransition(from: state, action: "start work") }
        guard beforeCount >= Self.requiredBeforePhotos else {
            throw VisitError.needsBeforePhotos(have: beforeCount, need: Self.requiredBeforePhotos)
        }
        workStartedAt = now
        state = .working
    }

    public mutating func pause(at now: Date, reason: PauseReason = .break) throws {
        guard state == .working else { throw VisitError.invalidTransition(from: state, action: "pause") }
        pauses.append(VisitPause(start: now, reason: reason))
        state = .paused
    }

    public mutating func resume(at now: Date) throws {
        guard state == .paused, let index = pauses.indices.last, pauses[index].end == nil else {
            throw VisitError.invalidTransition(from: state, action: "resume")
        }
        pauses[index].end = now
        state = .working
    }

    public mutating func complete(at now: Date) throws {
        guard state == .working || state == .paused else { throw VisitError.invalidTransition(from: state, action: "complete") }
        guard afterCount >= Self.requiredAfterPhotos else {
            throw VisitError.needsAfterPhotos(have: afterCount, need: Self.requiredAfterPhotos)
        }
        if state == .paused, let index = pauses.indices.last { pauses[index].end = now }
        completedAt = now
        state = .completed
    }

    public mutating func markReviewed() throws {
        guard state == .completed else { throw VisitError.invalidTransition(from: state, action: "approve") }
        state = .reviewed
    }

    // MARK: Photos & tasks

    @discardableResult
    public mutating func addPhoto(kind: PhotoKind, angle: String? = nil, at now: Date, source: PhotoSource = .inAppCamera, localFileName: String? = nil) -> VisitPhoto {
        let resolvedAngle = angle ?? nextAngle(for: kind) ?? "Extra"
        let photo = VisitPhoto(
            id: UUID().uuidString,
            kind: kind,
            angle: resolvedAngle,
            capturedAt: now,
            source: source,
            localFileName: localFileName,
            upload: .savedOnDevice,
            swatch: photos.count % 6
        )
        photos.append(photo)
        return photo
    }

    public mutating func removePhoto(id: VisitPhoto.ID) {
        photos.removeAll { $0.id == id }
    }

    public mutating func setCaption(_ caption: String, forPhoto id: VisitPhoto.ID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].caption = caption
    }

    public mutating func toggleTask(id: VisitTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
    }
}
