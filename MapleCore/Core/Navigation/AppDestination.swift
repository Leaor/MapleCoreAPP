import SwiftUI
import MapleCoreKit

/// Every pushed screen. Each tab owns a NavigationStack bound to `[AppDestination]`, so tabs keep their
/// own back stack and scroll position. Sheets and covers are presented locally by the screen that owns them.
enum AppDestination: Hashable {
    // Routes
    case route(Route.ID)
    case routeHistory
    case stop(Route.ID, RouteStop.ID)
    case routeSummary(Route.ID)
    // Properties
    case property(Property.ID)
    case visitHistory(Property.ID)
    case gallery(Property.ID)
    case photoCompare(VisitRecord.ID)
    case customer(Customer.ID)
    case documents(Property.ID)
    // Inbox
    case thread(MessageThread.ID)
    case attachments(MessageThread.ID)
    case pushTemplates
    // Business & team
    case quotes
    case invoices
    case invoice(Invoice.ID)
    case analytics
    case staff
    case crews
    case employee(StaffMember.ID)
    // Snow & review
    case snowOps
    case review(VisitRecord.ID)
    // System
    case settings
    case notificationPrefs
    case syncQueue
    // Field
    case fieldStop(Route.ID, RouteStop.ID)
    case shiftHistory
    case availability
}

/// Maps a destination to its screen. Feature folders implement these views.
struct DestinationView: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case let .route(id): RouteMapView(routeID: id)
        case .routeHistory: RouteHistoryView()
        case let .stop(routeID, stopID): StopDetailView(routeID: routeID, stopID: stopID)
        case let .routeSummary(id): RouteSummaryView(routeID: id)
        case let .property(id): PropertyDetailView(propertyID: id)
        case let .visitHistory(id): VisitHistoryView(propertyID: id)
        case let .gallery(id): PropertyGalleryView(propertyID: id)
        case let .photoCompare(id): PhotoCompareView(visitID: id)
        case let .customer(id): CustomerDetailView(customerID: id)
        case let .documents(id): DocumentsView(propertyID: id)
        case let .thread(id): ConversationView(threadID: id)
        case let .attachments(id): AttachmentsView(threadID: id)
        case .pushTemplates: PushNotificationsPreviewView()
        case .quotes: QuotesView()
        case .invoices: InvoicesView()
        case let .invoice(id): InvoiceDetailView(invoiceID: id)
        case .analytics: AnalyticsView()
        case .staff: StaffDirectoryView()
        case .crews: CrewManagementView()
        case let .employee(id): EmployeeProfileView(staffID: id)
        case .snowOps: SnowOpsView()
        case let .review(id): SupervisorReviewView(visitID: id)
        case .settings: SettingsView()
        case .notificationPrefs: NotificationPrefsView()
        case .syncQueue: SyncQueueView()
        case let .fieldStop(routeID, stopID): FieldStopView(routeID: routeID, stopID: stopID)
        case .shiftHistory: ShiftHistoryView()
        case .availability: AvailabilityView()
        }
    }
}

extension View {
    /// Registers `AppDestination` on a NavigationStack root.
    func appDestinations() -> some View {
        navigationDestination(for: AppDestination.self) { DestinationView(destination: $0) }
    }
}

/// Shown when a destination's record no longer exists (deleted, or a stale deep link).
struct MissingRecordView: View {
    var title = "Not available"
    var message = "This item was removed or hasn't synced to this iPhone yet."

    var body: some View {
        EmptyStateView(symbol: "questionmark.folder", title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
    }
}
