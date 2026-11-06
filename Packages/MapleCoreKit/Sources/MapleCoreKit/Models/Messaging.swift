import Foundation

public enum ThreadKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Customer conversation. Customer-visible by default; internal notes allowed.
    case customer
    /// Crew group thread. Internal only.
    case crew
    /// One-to-one staff thread. Internal only.
    case direct
    /// Broadcast to all crews.
    case announcement
    /// Property thread for internal notes. Composer defaults to Internal.
    case property

    public var isInternalOnly: Bool { self != .customer }
}

public enum MessageVisibility: String, Codable, Hashable, Sendable {
    case customer, `internal`
}

public enum AttachmentKind: String, Codable, Hashable, Sendable {
    case photo, file, visitReport, quote
}

public struct Attachment: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var kind: AttachmentKind
    public var name: String
    public var detail: String
    public var swatch: Int
    public var upload: UploadState

    public init(id: ID, kind: AttachmentKind, name: String, detail: String = "", swatch: Int = 0, upload: UploadState = .uploaded) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.swatch = swatch
        self.upload = upload
    }
}

public enum DeliveryState: Codable, Hashable, Sendable {
    /// Saved on this iPhone, waiting in the outbox.
    case queued
    case sent
    case read(at: Date)
    case seenBy(String)
}

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var authorName: String
    public var authorInitials: String
    /// Staff author. nil for customer messages.
    public var authorID: StaffMember.ID?
    public var text: String
    public var sentAt: Date
    public var visibility: MessageVisibility
    public var attachments: [Attachment]
    /// A system line such as "Daniel started visit · Humber Bay Towers".
    public var isSystemEvent: Bool
    public var propertyTag: String?
    public var delivery: DeliveryState

    public func isMine(_ viewer: StaffMember.ID?) -> Bool { viewer != nil && authorID == viewer }

    public init(id: ID, authorName: String, authorInitials: String, authorID: StaffMember.ID?, text: String, sentAt: Date, visibility: MessageVisibility, attachments: [Attachment] = [], isSystemEvent: Bool = false, propertyTag: String? = nil, delivery: DeliveryState = .sent) {
        self.id = id
        self.authorName = authorName
        self.authorInitials = authorInitials
        self.authorID = authorID
        self.text = text
        self.sentAt = sentAt
        self.visibility = visibility
        self.attachments = attachments
        self.isSystemEvent = isSystemEvent
        self.propertyTag = propertyTag
        self.delivery = delivery
    }
}

public struct MessageThread: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var kind: ThreadKind
    public var title: String
    public var initials: String
    public var subtitle: String
    public var customerID: Customer.ID?
    public var propertyID: Property.ID?
    public var crewID: Crew.ID?
    public var unreadCount: Int
    public var isUrgent: Bool
    public var messages: [Message]
    /// Quick replies offered above the composer.
    public var quickReplies: [String]
    /// Which app shell sees the thread.
    public var visibleToField: Bool
    public var visibleToAdmin: Bool

    public init(id: ID, kind: ThreadKind, title: String, initials: String, subtitle: String, customerID: Customer.ID? = nil, propertyID: Property.ID? = nil, crewID: Crew.ID? = nil, unreadCount: Int = 0, isUrgent: Bool = false, messages: [Message], quickReplies: [String] = [], visibleToField: Bool = false, visibleToAdmin: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.initials = initials
        self.subtitle = subtitle
        self.customerID = customerID
        self.propertyID = propertyID
        self.crewID = crewID
        self.unreadCount = unreadCount
        self.isUrgent = isUrgent
        self.messages = messages
        self.quickReplies = quickReplies
        self.visibleToField = visibleToField
        self.visibleToAdmin = visibleToAdmin
    }

    public var lastMessage: Message? { messages.last }
    public var lastActivity: Date { messages.last?.sentAt ?? .distantPast }
    public var allAttachments: [Attachment] { messages.flatMap(\.attachments) }
}

/// Inbox filter segments.
public enum InboxFilter: String, CaseIterable, Hashable, Sendable {
    case all, customers, crew, announcements

    public var label: String { rawValue.capitalized }

    public func includes(_ thread: MessageThread) -> Bool {
        switch self {
        case .all: true
        case .customers: thread.kind == .customer
        case .crew: thread.kind == .crew || thread.kind == .direct || thread.kind == .property
        case .announcements: thread.kind == .announcement
        }
    }
}
