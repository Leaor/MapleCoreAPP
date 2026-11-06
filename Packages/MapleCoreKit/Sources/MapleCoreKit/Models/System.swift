import Foundation

// MARK: - Snow

public struct SnowRoute: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var code: String
    public var name: String
    public var crewID: Crew.ID?
    public var propertyCount: Int
    public var completed: Int
    public var estimatedMinutes: Int
    public var behindMinutes: Int
    public var isDispatched: Bool
    /// True when these contracts have a higher trigger than the current accumulation.
    public var isBelowTrigger: Bool
    public var unitLabel: String
    public var workDetail: String

    public init(id: ID, code: String, name: String, crewID: Crew.ID?, propertyCount: Int, completed: Int = 0, estimatedMinutes: Int, behindMinutes: Int = 0, isDispatched: Bool, isBelowTrigger: Bool = false, unitLabel: String = "properties", workDetail: String = "") {
        self.id = id
        self.code = code
        self.name = name
        self.crewID = crewID
        self.propertyCount = propertyCount
        self.completed = completed
        self.estimatedMinutes = estimatedMinutes
        self.behindMinutes = behindMinutes
        self.isDispatched = isDispatched
        self.isBelowTrigger = isBelowTrigger
        self.unitLabel = unitLabel
        self.workDetail = workDetail
    }
}

public struct SnowEvent: Codable, Hashable, Sendable {
    public var number: Int
    public var startedAt: Date
    public var groundCm: Int
    public var temperatureC: Int
    public var condition: String
    /// Snowfall cm/h for the next hours, used for the small rate chart.
    public var hourlyRate: [Double]
    public var forecast: String
    public var warning: String
    public var priorityDone: Int
    public var priorityTotal: Int
    public var priorityDeadline: String
    public var allDone: Int
    public var allTotal: Int
    public var saltUsedTonnes: Double
    public var saltTotalTonnes: Double
    public var triggerCm: Int
    public var triggerReachedAt: Date
    public var newlyTriggeredCount: Int
    public var routes: [SnowRoute]

    public init(number: Int, startedAt: Date, groundCm: Int, temperatureC: Int, condition: String, hourlyRate: [Double], forecast: String, warning: String, priorityDone: Int, priorityTotal: Int, priorityDeadline: String, allDone: Int, allTotal: Int, saltUsedTonnes: Double, saltTotalTonnes: Double, triggerCm: Int, triggerReachedAt: Date, newlyTriggeredCount: Int, routes: [SnowRoute]) {
        self.number = number
        self.startedAt = startedAt
        self.groundCm = groundCm
        self.temperatureC = temperatureC
        self.condition = condition
        self.hourlyRate = hourlyRate
        self.forecast = forecast
        self.warning = warning
        self.priorityDone = priorityDone
        self.priorityTotal = priorityTotal
        self.priorityDeadline = priorityDeadline
        self.allDone = allDone
        self.allTotal = allTotal
        self.saltUsedTonnes = saltUsedTonnes
        self.saltTotalTonnes = saltTotalTonnes
        self.triggerCm = triggerCm
        self.triggerReachedAt = triggerReachedAt
        self.newlyTriggeredCount = newlyTriggeredCount
        self.routes = routes
    }

    public var activeRoutes: [SnowRoute] { routes.filter(\.isDispatched) }
    public var pendingRoutes: [SnowRoute] { routes.filter { !$0.isDispatched } }
}

// MARK: - Offline outbox & sync

public enum OutboxKind: String, Codable, Hashable, Sendable {
    case visitUpdate, photoUpload, note, message
}

public enum OutboxState: Codable, Hashable, Sendable {
    case queued
    case sending(progress: Double)
    case sent
    case failed(attempts: Int)
    case needsAttention
}

public struct OutboxItem: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var kind: OutboxKind
    public var title: String
    public var detail: String
    public var createdAt: Date
    public var state: OutboxState
    /// For photo batches: how many of `total` have uploaded.
    public var completedUnits: Int
    public var totalUnits: Int
    public var byteCount: Int
    public var conflictID: SyncConflict.ID?

    public init(id: ID, kind: OutboxKind, title: String, detail: String, createdAt: Date, state: OutboxState = .queued, completedUnits: Int = 0, totalUnits: Int = 1, byteCount: Int = 0, conflictID: SyncConflict.ID? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.state = state
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.byteCount = byteCount
        self.conflictID = conflictID
    }

    public var isPending: Bool {
        switch state {
        case .queued, .sending: true
        default: false
        }
    }

    public var needsAttention: Bool {
        switch state {
        case .failed, .needsAttention: true
        default: false
        }
    }
}

public struct ConflictVersion: Codable, Hashable, Sendable {
    public var text: String
    public var editedAt: Date
    public var editedBy: String

    public init(text: String, editedAt: Date, editedBy: String) {
        self.text = text
        self.editedAt = editedAt
        self.editedBy = editedBy
    }
}

public enum ConflictResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case mine, office, keepBoth
}

public struct SyncConflict: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var propertyID: Property.ID
    public var fieldName: String
    public var mine: ConflictVersion
    public var office: ConflictVersion

    public init(id: ID, propertyID: Property.ID, fieldName: String, mine: ConflictVersion, office: ConflictVersion) {
        self.id = id
        self.propertyID = propertyID
        self.fieldName = fieldName
        self.mine = mine
        self.office = office
    }

    /// The text produced by a resolution. Keep both adds the device lines under the office version.
    public func resolvedText(_ resolution: ConflictResolution) -> String {
        switch resolution {
        case .mine: return mine.text
        case .office: return office.text
        case .keepBoth:
            let officeLines = Set(office.text.components(separatedBy: CharacterSet(charactersIn: ".\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            let extra = mine.text.components(separatedBy: CharacterSet(charactersIn: ".\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !officeLines.contains($0) }
            guard !extra.isEmpty else { return office.text }
            return office.text + "\n" + extra.map { $0 + "." }.joined(separator: " ")
        }
    }
}

// MARK: - Preferences

public enum Appearance: String, Codable, CaseIterable, Hashable, Sendable {
    case system, light, dark
    public var label: String { rawValue.capitalized }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var appearance: Appearance
    public var gloveMode: Bool
    public var haptics: Bool
    public var saveRoutesOffline: Bool
    public var uploadOnCellular: Bool
    public var faceIDEnabled: Bool

    public init(appearance: Appearance = .system, gloveMode: Bool = false, haptics: Bool = true, saveRoutesOffline: Bool = true, uploadOnCellular: Bool = false, faceIDEnabled: Bool = true) {
        self.appearance = appearance
        self.gloveMode = gloveMode
        self.haptics = haptics
        self.saveRoutesOffline = saveRoutesOffline
        self.uploadOnCellular = uploadOnCellular
        self.faceIDEnabled = faceIDEnabled
    }
}

public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var snowDispatch: Bool
    public var routeChanges: Bool
    public var crewRunningLate: Bool
    public var customerMessages: Bool
    public var crewMessages: Bool
    public var urgentOnly: Bool
    public var visitsReadyForReview: Bool
    public var dailySummary: Bool
    public var dailySummaryHour: Int
    public var quietHoursEnabled: Bool
    public var quietStartHour: Int
    public var quietEndHour: Int

    public init(snowDispatch: Bool = true, routeChanges: Bool = true, crewRunningLate: Bool = true, customerMessages: Bool = true, crewMessages: Bool = true, urgentOnly: Bool = false, visitsReadyForReview: Bool = true, dailySummary: Bool = true, dailySummaryHour: Int = 18, quietHoursEnabled: Bool = true, quietStartHour: Int = 21, quietEndHour: Int = 6) {
        self.snowDispatch = snowDispatch
        self.routeChanges = routeChanges
        self.crewRunningLate = crewRunningLate
        self.customerMessages = customerMessages
        self.crewMessages = crewMessages
        self.urgentOnly = urgentOnly
        self.visitsReadyForReview = visitsReadyForReview
        self.dailySummary = dailySummary
        self.dailySummaryHour = dailySummaryHour
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
    }
}

public struct LocationSharing: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var pausedUntil: Date?

    public init(enabled: Bool = true, pausedUntil: Date? = nil) {
        self.enabled = enabled
        self.pausedUntil = pausedUntil
    }

    public func isSharing(at now: Date) -> Bool {
        guard enabled else { return false }
        if let pausedUntil, pausedUntil > now { return false }
        return true
    }
}

/// Analytics figures. Computed from fixtures in Phase 1.
public struct AnalyticsSnapshot: Codable, Hashable, Sendable {
    public struct CrewRow: Codable, Hashable, Sendable, Identifiable {
        public var id: Crew.ID
        public var name: String
        public var visits: Int
        public var onTimeRate: Double
        public init(id: Crew.ID, name: String, visits: Int, onTimeRate: Double) {
            self.id = id
            self.name = name
            self.visits = visits
            self.onTimeRate = onTimeRate
        }
    }

    public var visitsCompleted: Int
    public var visitsChange: Double
    public var onTimeRate: Double
    public var onTimeChange: Double
    public var minutesVsEstimate: Int
    public var minutesVsEstimateChange: Int
    public var billed: Decimal
    public var billedChange: Double
    /// Oldest first; the last entry is today.
    public var dailyVisits: [Int]
    public var dayLabels: [String]
    public var crews: [CrewRow]

    public init(visitsCompleted: Int, visitsChange: Double, onTimeRate: Double, onTimeChange: Double, minutesVsEstimate: Int, minutesVsEstimateChange: Int, billed: Decimal, billedChange: Double, dailyVisits: [Int], dayLabels: [String], crews: [CrewRow]) {
        self.visitsCompleted = visitsCompleted
        self.visitsChange = visitsChange
        self.onTimeRate = onTimeRate
        self.onTimeChange = onTimeChange
        self.minutesVsEstimate = minutesVsEstimate
        self.minutesVsEstimateChange = minutesVsEstimateChange
        self.billed = billed
        self.billedChange = billedChange
        self.dailyVisits = dailyVisits
        self.dayLabels = dayLabels
        self.crews = crews
    }
}

public enum AnalyticsRange: String, CaseIterable, Hashable, Sendable {
    case week, month, season
    public var label: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Month"
        case .season: "Season"
        }
    }
}
