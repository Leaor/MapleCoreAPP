import Foundation

// MARK: - Status

/// Job status shared by stop rows, map pins and pills. Always rendered as colour + icon + label.
public enum StopStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending, enRoute, inProgress, done, delayed, skipped, urgent

    public var label: String {
        switch self {
        case .pending: "Pending"
        case .enRoute: "En route"
        case .inProgress: "In progress"
        case .done: "Completed"
        case .delayed: "Delayed"
        case .skipped: "Skipped"
        case .urgent: "Urgent"
        }
    }

    /// SF Symbol name. Lives in the kit so status rendering is consistent everywhere.
    public var symbol: String {
        switch self {
        case .pending: "clock"
        case .enRoute: "car.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        case .delayed: "exclamationmark.triangle.fill"
        case .skipped: "forward.end.fill"
        case .urgent: "bolt.fill"
        }
    }

    public var isFinished: Bool { self == .done || self == .skipped }
}

public enum Priority: String, Codable, CaseIterable, Hashable, Sendable {
    case low, normal, high
    public var label: String { rawValue.capitalized }
}

public enum ServiceType: String, Codable, CaseIterable, Hashable, Sendable {
    case lawnCare, fallCleanup, snowPlowing, salting, landscaping, construction

    public var label: String {
        switch self {
        case .lawnCare: "Lawn care"
        case .fallCleanup: "Fall cleanup"
        case .snowPlowing: "Snow plowing"
        case .salting: "Salting"
        case .landscaping: "Landscaping"
        case .construction: "Construction"
        }
    }
}

public enum ServiceFrequency: String, Codable, CaseIterable, Hashable, Sendable {
    case weekly, biweekly, monthly, seasonal, onCall

    public var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Bi-weekly"
        case .monthly: "Monthly"
        case .seasonal: "Seasonal"
        case .onCall: "On call"
        }
    }
}

public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
    public var label: String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue - 1]
    }
    public var initial: String { String(label.prefix(1)) }
}

// MARK: - Properties & customers

public enum PropertyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case commercial, residential, condo, retail

    public var label: String { rawValue.capitalized }
    /// Commercial-style kinds are grouped under "Commercial" in the list filter.
    public var isCommercial: Bool { self != .residential }
}

public struct SiteMeasurements: Codable, Hashable, Sendable {
    public var lawnSqM: Int
    public var gardenBedsSqM: Int
    public var parkingSqM: Int
    public var walkwaysM: Int

    public init(lawnSqM: Int = 0, gardenBedsSqM: Int = 0, parkingSqM: Int = 0, walkwaysM: Int = 0) {
        self.lawnSqM = lawnSqM
        self.gardenBedsSqM = gardenBedsSqM
        self.parkingSqM = parkingSqM
        self.walkwaysM = walkwaysM
    }
}

public struct Property: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var address: String
    public var city: String
    public var kind: PropertyKind
    /// Short descriptor shown under the name, e.g. "Condo", "30 units · Condo corp."
    public var descriptor: String
    public var customerID: Customer.ID?
    public var services: [ServiceType]
    public var primaryService: String
    public var frequency: ServiceFrequency
    public var preferredDay: Weekday
    public var assignedCrewID: Crew.ID?
    /// Crew-only access instructions. Never shown to the customer.
    public var accessNotes: String
    public var notes: String
    public var notesUpdatedBy: String
    public var notesUpdatedAt: Date?
    public var measurements: SiteMeasurements
    public var equipment: [String]
    public var contractStart: Date?
    public var contractEnd: Date?
    public var openIssues: Int
    public var latitude: Double
    public var longitude: Double

    public init(id: ID, name: String, address: String, city: String, kind: PropertyKind, descriptor: String, customerID: Customer.ID?, services: [ServiceType], primaryService: String, frequency: ServiceFrequency, preferredDay: Weekday, assignedCrewID: Crew.ID?, accessNotes: String, notes: String = "", notesUpdatedBy: String = "", notesUpdatedAt: Date? = nil, measurements: SiteMeasurements = .init(), equipment: [String] = [], contractStart: Date? = nil, contractEnd: Date? = nil, openIssues: Int = 0, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.kind = kind
        self.descriptor = descriptor
        self.customerID = customerID
        self.services = services
        self.primaryService = primaryService
        self.frequency = frequency
        self.preferredDay = preferredDay
        self.assignedCrewID = assignedCrewID
        self.accessNotes = accessNotes
        self.notes = notes
        self.notesUpdatedBy = notesUpdatedBy
        self.notesUpdatedAt = notesUpdatedAt
        self.measurements = measurements
        self.equipment = equipment
        self.contractStart = contractStart
        self.contractEnd = contractEnd
        self.openIssues = openIssues
        self.latitude = latitude
        self.longitude = longitude
    }

    public var hasSnowContract: Bool { services.contains(.snowPlowing) || services.contains(.salting) }
    public var isContractActive: Bool {
        guard let start = contractStart, let end = contractEnd else { return false }
        let now = Date()
        return start <= now && now <= end
    }
}

public struct Contact: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var detail: String
    public var phone: String?
    public var email: String?
    public var isPrimary: Bool

    public init(id: ID, name: String, detail: String, phone: String? = nil, email: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.name = name
        self.detail = detail
        self.phone = phone
        self.email = email
        self.isPrimary = isPrimary
    }
}

public struct Customer: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var initials: String
    public var isCommercial: Bool
    public var customerSince: Int
    public var contacts: [Contact]

    public init(id: ID, name: String, initials: String, isCommercial: Bool, customerSince: Int, contacts: [Contact]) {
        self.id = id
        self.name = name
        self.initials = initials
        self.isCommercial = isCommercial
        self.customerSince = customerSince
        self.contacts = contacts
    }

    public var primaryContact: Contact? { contacts.first(where: \.isPrimary) ?? contacts.first }
}

public enum DocumentKind: String, Codable, Hashable, Sendable {
    case pdf, quote, report
    public var badge: String {
        switch self {
        case .pdf: "PDF"
        case .quote: "QTE"
        case .report: "RPT"
        }
    }
}

public struct PropertyDocument: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var propertyID: Property.ID
    public var title: String
    public var detail: String
    public var kind: DocumentKind
    public var tag: String?
    public var isFeatured: Bool
    public var quoteID: Quote.ID?
    public var visitID: VisitRecord.ID?

    public init(id: ID, propertyID: Property.ID, title: String, detail: String, kind: DocumentKind, tag: String? = nil, isFeatured: Bool = false, quoteID: Quote.ID? = nil, visitID: VisitRecord.ID? = nil) {
        self.id = id
        self.propertyID = propertyID
        self.title = title
        self.detail = detail
        self.kind = kind
        self.tag = tag
        self.isFeatured = isFeatured
        self.quoteID = quoteID
        self.visitID = visitID
    }
}

// MARK: - People

public enum LocationShare: Codable, Hashable, Sendable {
    /// Live location, shared during an active shift.
    case live(place: String, updatedAt: Date)
    /// Sharing on but the last fix is stale.
    case lastReported(at: Date)
    /// The person has not shared location. Never guess a position.
    case notShared(lastArrival: Date?)
}

public struct StaffMember: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var initials: String
    public var jobTitle: String
    public var crewID: Crew.ID?
    public var isLead: Bool
    public var phone: String
    public var email: String
    public var startYear: Int
    public var onDutySince: Date?
    public var shiftStartsAt: Date?
    public var location: LocationShare
    /// Monday-first availability for the current week.
    public var availability: [Bool]
    public var visitsThisWeek: Int
    public var onTimeRate: Double
    public var photoProofRate: Double
    public var lastShift: String

    public init(id: ID, name: String, initials: String, jobTitle: String, crewID: Crew.ID?, isLead: Bool, phone: String, email: String, startYear: Int, onDutySince: Date?, shiftStartsAt: Date? = nil, location: LocationShare, availability: [Bool], visitsThisWeek: Int, onTimeRate: Double, photoProofRate: Double, lastShift: String) {
        self.id = id
        self.name = name
        self.initials = initials
        self.jobTitle = jobTitle
        self.crewID = crewID
        self.isLead = isLead
        self.phone = phone
        self.email = email
        self.startYear = startYear
        self.onDutySince = onDutySince
        self.shiftStartsAt = shiftStartsAt
        self.location = location
        self.availability = availability
        self.visitsThisWeek = visitsThisWeek
        self.onTimeRate = onTimeRate
        self.photoProofRate = photoProofRate
        self.lastShift = lastShift
    }

    public var isOnDuty: Bool { onDutySince != nil }
    public var firstName: String { String(name.split(separator: " ").first ?? Substring(name)) }
    public var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1, let last = parts.last?.first else { return name }
        return "\(parts[0]) \(last)."
    }
}

public struct Crew: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var letter: String
    public var leadID: StaffMember.ID
    public var memberIDs: [StaffMember.ID]
    public var truck: String
    public var isSnowReady: Bool
    /// Days the crew lead has marked the crew off.
    public var offDays: [Weekday]

    public init(id: ID, name: String, letter: String, leadID: StaffMember.ID, memberIDs: [StaffMember.ID], truck: String, isSnowReady: Bool = false, offDays: [Weekday] = []) {
        self.id = id
        self.name = name
        self.letter = letter
        self.leadID = leadID
        self.memberIDs = memberIDs
        self.truck = truck
        self.isSnowReady = isSnowReady
        self.offDays = offDays
    }
}

// MARK: - Routes

public struct VisitTask: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var title: String
    public var isDone: Bool
    public var addedToday: Bool

    public init(id: ID, title: String, isDone: Bool = false, addedToday: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.addedToday = addedToday
    }
}

public struct RouteStop: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var propertyID: Property.ID
    public var serviceName: String
    public var estimatedMinutes: Int
    public var eta: Date?
    public var status: StopStatus
    public var priority: Priority
    public var tasks: [VisitTask]
    public var completedAt: Date?
    public var actualMinutes: Int?
    public var startedAt: Date?
    public var skipReason: String?
    public var delayMinutes: Int

    public init(id: ID, propertyID: Property.ID, serviceName: String, estimatedMinutes: Int, eta: Date? = nil, status: StopStatus = .pending, priority: Priority = .normal, tasks: [VisitTask] = [], completedAt: Date? = nil, actualMinutes: Int? = nil, startedAt: Date? = nil, skipReason: String? = nil, delayMinutes: Int = 0) {
        self.id = id
        self.propertyID = propertyID
        self.serviceName = serviceName
        self.estimatedMinutes = estimatedMinutes
        self.eta = eta
        self.status = status
        self.priority = priority
        self.tasks = tasks
        self.completedAt = completedAt
        self.actualMinutes = actualMinutes
        self.startedAt = startedAt
        self.skipReason = skipReason
        self.delayMinutes = delayMinutes
    }
}

public enum RouteState: String, Codable, Hashable, Sendable {
    case draft, scheduled, inProgress, completed
}

public struct Route: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var serviceSummary: String
    public var date: Date
    public var startTime: Date
    public var crewID: Crew.ID?
    public var stops: [RouteStop]
    public var state: RouteState
    public var delayMinutes: Int
    public var driveMinutes: Int
    public var distanceKm: Int
    public var finishedAt: Date?
    public var issuesReported: [String]
    public var reviewedCount: Int
    public var photoCount: Int
    public var plannedMinutes: Int?

    public init(id: ID, name: String, serviceSummary: String, date: Date, startTime: Date, crewID: Crew.ID?, stops: [RouteStop], state: RouteState, delayMinutes: Int = 0, driveMinutes: Int = 0, distanceKm: Int = 0, finishedAt: Date? = nil, issuesReported: [String] = [], reviewedCount: Int = 0, photoCount: Int = 0, plannedMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.serviceSummary = serviceSummary
        self.date = date
        self.startTime = startTime
        self.crewID = crewID
        self.stops = stops
        self.state = state
        self.delayMinutes = delayMinutes
        self.driveMinutes = driveMinutes
        self.distanceKm = distanceKm
        self.finishedAt = finishedAt
        self.issuesReported = issuesReported
        self.reviewedCount = reviewedCount
        self.photoCount = photoCount
        self.plannedMinutes = plannedMinutes
    }

    public var completedCount: Int { stops.filter { $0.status == .done }.count }
    public var skippedCount: Int { stops.filter { $0.status == .skipped }.count }
    public var finishedCount: Int { stops.filter { $0.status.isFinished }.count }
    public var inProgressStop: RouteStop? { stops.first { $0.status == .inProgress } }
    /// The next stop the crew has not started, in route order.
    public var nextStop: RouteStop? { stops.first { $0.status == .pending || $0.status == .enRoute || $0.status == .delayed } }
    public var workMinutes: Int { stops.reduce(0) { $0 + $1.estimatedMinutes } }
    public var actualWorkMinutes: Int { stops.reduce(0) { $0 + ($1.actualMinutes ?? 0) } }
    public var estimatedEnd: Date { startTime.addingTimeInterval(TimeInterval((workMinutes + driveMinutes) * 60)) }
    public var isDelayed: Bool { delayMinutes > 0 && state == .inProgress }
    public var needsCrew: Bool { crewID == nil && state != .completed }
    public func index(of stopID: RouteStop.ID) -> Int? { stops.firstIndex { $0.id == stopID } }
}

// MARK: - Visits, photos & reviews

public enum PhotoKind: String, Codable, CaseIterable, Hashable, Sendable {
    case before, work, after
    public var label: String { rawValue.capitalized }
}

public enum PhotoSource: String, Codable, Hashable, Sendable {
    case inAppCamera, imported
}

public enum UploadState: Codable, Hashable, Sendable {
    case savedOnDevice
    case uploading(progress: Double)
    case uploaded
    case failed(attempts: Int)
}

public struct VisitPhoto: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var kind: PhotoKind
    public var angle: String
    public var caption: String
    /// Device clock. Always labelled "iPhone clock" in the UI.
    public var capturedAt: Date
    /// Server time when the upload landed. The authoritative time; nil until uploaded.
    public var receivedAt: Date?
    public var source: PhotoSource
    /// File name inside the app's container, when a real image was captured. Fixture photos have none.
    public var localFileName: String?
    public var upload: UploadState
    /// Fixture tint index so mock photos render as distinct placeholders.
    public var swatch: Int

    public init(id: ID, kind: PhotoKind, angle: String, caption: String = "", capturedAt: Date, receivedAt: Date? = nil, source: PhotoSource = .inAppCamera, localFileName: String? = nil, upload: UploadState = .savedOnDevice, swatch: Int = 0) {
        self.id = id
        self.kind = kind
        self.angle = angle
        self.caption = caption
        self.capturedAt = capturedAt
        self.receivedAt = receivedAt
        self.source = source
        self.localFileName = localFileName
        self.upload = upload
        self.swatch = swatch
    }
}

public enum ReviewState: String, Codable, Hashable, Sendable {
    case awaiting, approved, changesRequested

    public var label: String {
        switch self {
        case .awaiting: "Awaiting review"
        case .approved: "Reviewed"
        case .changesRequested: "Changes requested"
        }
    }
}

public enum HistoryKind: String, Codable, Hashable, Sendable {
    case visit, issue, note, skipped
}

/// A completed visit report, issue, note or skipped visit on a property's timeline.
public struct VisitRecord: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var propertyID: Property.ID
    public var kind: HistoryKind
    public var title: String
    public var detail: String
    public var crewID: Crew.ID?
    public var crewNames: String
    public var date: Date
    public var arrivedAt: Date?
    public var workStart: Date?
    public var workEnd: Date?
    public var workMinutes: Int
    public var pausedMinutes: Int
    public var estimateMinutes: Int
    public var receivedAt: Date?
    public var photos: [VisitPhoto]
    public var notes: String
    public var review: ReviewState
    public var reviewedBy: String?
    public var reviewedAt: Date?
    public var resolvedAt: Date?
    public var arrivalVerified: Bool

    public init(id: ID, propertyID: Property.ID, kind: HistoryKind, title: String, detail: String = "", crewID: Crew.ID? = nil, crewNames: String = "", date: Date, arrivedAt: Date? = nil, workStart: Date? = nil, workEnd: Date? = nil, workMinutes: Int = 0, pausedMinutes: Int = 0, estimateMinutes: Int = 0, receivedAt: Date? = nil, photos: [VisitPhoto] = [], notes: String = "", review: ReviewState = .approved, reviewedBy: String? = nil, reviewedAt: Date? = nil, resolvedAt: Date? = nil, arrivalVerified: Bool = false) {
        self.id = id
        self.propertyID = propertyID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.crewID = crewID
        self.crewNames = crewNames
        self.date = date
        self.arrivedAt = arrivedAt
        self.workStart = workStart
        self.workEnd = workEnd
        self.workMinutes = workMinutes
        self.pausedMinutes = pausedMinutes
        self.estimateMinutes = estimateMinutes
        self.receivedAt = receivedAt
        self.photos = photos
        self.notes = notes
        self.review = review
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.resolvedAt = resolvedAt
        self.arrivalVerified = arrivalVerified
    }

    public var offlinePhotoCount: Int { photos.filter { $0.receivedAt == nil || $0.source == .imported }.count }
    public func photos(_ kind: PhotoKind) -> [VisitPhoto] { photos.filter { $0.kind == kind } }
}

// MARK: - Shift

public struct Shift: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var breakMinutes: Int
    public var breaks: Int
    public var truck: String

    public init(startedAt: Date, endedAt: Date? = nil, breakMinutes: Int = 0, breaks: Int = 0, truck: String) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.breakMinutes = breakMinutes
        self.breaks = breaks
        self.truck = truck
    }

    public var isActive: Bool { endedAt == nil }
}

public struct Weather: Codable, Hashable, Sendable {
    public var temperatureC: Int
    public var condition: String
    public var place: String
    public var lowC: Int
    public var outlook: String
    public var snowWatch: Bool

    public init(temperatureC: Int, condition: String, place: String, lowC: Int, outlook: String, snowWatch: Bool) {
        self.temperatureC = temperatureC
        self.condition = condition
        self.place = place
        self.lowC = lowC
        self.outlook = outlook
        self.snowWatch = snowWatch
    }
}
