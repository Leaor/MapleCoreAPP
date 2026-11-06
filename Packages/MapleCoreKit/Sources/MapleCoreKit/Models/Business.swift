import Foundation

/// Ontario HST. Open question in the handoff: confirm per division and exemptions.
public enum Tax {
    public static let hstRate: Decimal = 0.13
    public static let label = "HST 13%"

    public static func hst(on subtotal: Decimal) -> Decimal {
        (subtotal * hstRate).rounded(scale: 2)
    }
}

public extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}

public enum Division: String, Codable, CaseIterable, Hashable, Sendable {
    case lawnCare, construction
    public var label: String { self == .lawnCare ? "LawnCare" : "Construction" }
    public var companyName: String { self == .lawnCare ? "MapleCore LawnCare" : "MapleCore Construction" }
}

public struct LineItem: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var title: String
    public var detail: String
    public var quantity: Int
    public var unitPrice: Decimal
    public var unit: String
    /// Optional items are shown but excluded from the total.
    public var isOptional: Bool

    public init(id: ID, title: String, detail: String = "", quantity: Int = 1, unitPrice: Decimal, unit: String = "", isOptional: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.isOptional = isOptional
    }

    public var total: Decimal { unitPrice * Decimal(quantity) }
}

public struct Totals: Hashable, Sendable {
    public var subtotal: Decimal
    public var tax: Decimal
    public var total: Decimal

    public init(items: [LineItem]) {
        subtotal = items.filter { !$0.isOptional }.reduce(Decimal(0)) { $0 + $1.total }
        tax = Tax.hst(on: subtotal)
        total = subtotal + tax
    }
}

public enum QuoteStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft, sent, viewed, approved, declined

    public var label: String {
        switch self {
        case .draft: "Draft"
        case .sent: "Sent · not opened"
        case .viewed: "Viewed · awaiting"
        case .approved: "Approved"
        case .declined: "Declined"
        }
    }

    public var isOpen: Bool { self == .sent || self == .viewed }
}

public enum QuoteFilter: String, CaseIterable, Hashable, Sendable {
    case open, approved, declined, drafts
    public var label: String { rawValue.capitalized }

    public func includes(_ quote: Quote) -> Bool {
        switch self {
        case .open: quote.status.isOpen
        case .approved: quote.status == .approved
        case .declined: quote.status == .declined
        case .drafts: quote.status == .draft
        }
    }
}

public struct Quote: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var number: String
    public var customerID: Customer.ID?
    public var propertyID: Property.ID?
    public var title: String
    public var division: Division
    public var status: QuoteStatus
    public var sentAt: Date?
    public var expiresAt: Date?
    public var approvedAt: Date?
    public var lineItems: [LineItem]
    public var updatedAt: Date

    public init(id: ID, number: String, customerID: Customer.ID?, propertyID: Property.ID?, title: String, division: Division, status: QuoteStatus, sentAt: Date? = nil, expiresAt: Date? = nil, approvedAt: Date? = nil, lineItems: [LineItem], updatedAt: Date = Date()) {
        self.id = id
        self.number = number
        self.customerID = customerID
        self.propertyID = propertyID
        self.title = title
        self.division = division
        self.status = status
        self.sentAt = sentAt
        self.expiresAt = expiresAt
        self.approvedAt = approvedAt
        self.lineItems = lineItems
        self.updatedAt = updatedAt
    }

    public var totals: Totals { Totals(items: lineItems) }
}

public enum InvoiceStatus: String, Codable, Hashable, Sendable {
    case draft, sent, viewed, paid
}

public struct Payment: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var amount: Decimal
    public var method: String
    public var receivedAt: Date
    public var reference: String

    public init(id: ID, amount: Decimal, method: String, receivedAt: Date, reference: String = "") {
        self.id = id
        self.amount = amount
        self.method = method
        self.receivedAt = receivedAt
        self.reference = reference
    }
}

public struct Invoice: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = String
    public var id: ID
    public var number: String
    public var customerID: Customer.ID?
    public var billToName: String
    public var propertyID: Property.ID?
    public var title: String
    public var issuedAt: Date
    public var sentAt: Date?
    public var viewedAt: Date?
    public var dueDate: Date
    public var lineItems: [LineItem]
    public var payments: [Payment]
    public var reviewedVisitCount: Int
    public var paymentTerms: String
    public var remindersSent: Int

    public init(id: ID, number: String, customerID: Customer.ID?, billToName: String, propertyID: Property.ID?, title: String, issuedAt: Date, sentAt: Date? = nil, viewedAt: Date? = nil, dueDate: Date, lineItems: [LineItem], payments: [Payment] = [], reviewedVisitCount: Int = 0, paymentTerms: String = "e-Transfer or cheque", remindersSent: Int = 0) {
        self.id = id
        self.number = number
        self.customerID = customerID
        self.billToName = billToName
        self.propertyID = propertyID
        self.title = title
        self.issuedAt = issuedAt
        self.sentAt = sentAt
        self.viewedAt = viewedAt
        self.dueDate = dueDate
        self.lineItems = lineItems
        self.payments = payments
        self.reviewedVisitCount = reviewedVisitCount
        self.paymentTerms = paymentTerms
        self.remindersSent = remindersSent
    }

    public var totals: Totals { Totals(items: lineItems) }
    public var amountPaid: Decimal { payments.reduce(Decimal(0)) { $0 + $1.amount } }
    public var balance: Decimal { max(totals.total - amountPaid, 0) }
    public var isPaid: Bool { balance == 0 && !payments.isEmpty }
    public var paidAt: Date? { isPaid ? payments.map(\.receivedAt).max() : nil }

    public var status: InvoiceStatus {
        if isPaid { return .paid }
        if viewedAt != nil { return .viewed }
        if sentAt != nil { return .sent }
        return .draft
    }

    public func isOverdue(asOf now: Date) -> Bool {
        !isPaid && dueDate < Calendar.current.startOfDay(for: now)
    }

    public func daysOverdue(asOf now: Date) -> Int {
        guard isOverdue(asOf: now) else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: dueDate), to: Calendar.current.startOfDay(for: now)).day ?? 0
    }
}

public enum InvoiceFilter: String, CaseIterable, Hashable, Sendable {
    case all, unpaid, overdue, paid
    public var label: String { rawValue.capitalized }

    public func includes(_ invoice: Invoice, now: Date) -> Bool {
        switch self {
        case .all: true
        case .unpaid: !invoice.isPaid
        case .overdue: invoice.isOverdue(asOf: now)
        case .paid: invoice.isPaid
        }
    }
}
