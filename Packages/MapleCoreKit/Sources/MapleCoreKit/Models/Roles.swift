import Foundation

/// A person's job role. One account can hold more than one (for example an owner who also works in the field).
public enum AppRole: String, Codable, CaseIterable, Hashable, Sendable {
    case admin, manager, supervisor, field

    public var title: String {
        switch self {
        case .admin: "Admin"
        case .manager: "Manager"
        case .supervisor: "Supervisor"
        case .field: "Field"
        }
    }

    /// True for roles that use the Admin shell (Today · Routes · Properties · Inbox · More).
    public var usesAdminShell: Bool { self != .field }

    public var capabilities: Capabilities {
        switch self {
        case .admin, .manager:
            [.finance, .routePlanning, .visitReview, .customerMessaging, .staffLocation, .analytics, .snowDispatch, .staffManagement]
        case .supervisor:
            [.routePlanning, .visitReview, .customerMessaging, .staffLocation]
        case .field:
            []
        }
    }
}

/// Views gate on capabilities, never on role names, so managers and supervisors get the right subset.
public struct Capabilities: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let finance = Capabilities(rawValue: 1 << 0)
    public static let routePlanning = Capabilities(rawValue: 1 << 1)
    public static let visitReview = Capabilities(rawValue: 1 << 2)
    public static let customerMessaging = Capabilities(rawValue: 1 << 3)
    public static let staffLocation = Capabilities(rawValue: 1 << 4)
    public static let analytics = Capabilities(rawValue: 1 << 5)
    public static let snowDispatch = Capabilities(rawValue: 1 << 6)
    public static let staffManagement = Capabilities(rawValue: 1 << 7)
}

/// A signed-in staff account.
public struct Account: Codable, Hashable, Sendable {
    public var staffID: StaffMember.ID
    public var displayName: String
    public var firstName: String
    public var initials: String
    public var login: String
    public var roles: [AppRole]
    public var jobTitle: String
    public var company: String

    public init(staffID: StaffMember.ID, displayName: String, firstName: String, initials: String, login: String, roles: [AppRole], jobTitle: String, company: String) {
        self.staffID = staffID
        self.displayName = displayName
        self.firstName = firstName
        self.initials = initials
        self.login = login
        self.roles = roles
        self.jobTitle = jobTitle
        self.company = company
    }

    public var hasMultipleRoles: Bool {
        Set(roles.map(\.usesAdminShell)).count > 1
    }
}
