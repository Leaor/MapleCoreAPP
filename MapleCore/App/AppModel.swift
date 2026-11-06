import SwiftUI
import Network
import MapleCoreKit

enum AdminTab: Hashable, CaseIterable {
    case today, routes, properties, inbox, more
}

enum FieldTab: Hashable, CaseIterable {
    /// `.camera` is not a real destination: selecting it opens the visit cover.
    case today, route, camera, messages, profile
}

/// App-level UI state: tab selection, one navigation path per tab, the visit cover and
/// Admin "Preview Field Mode". Domain data lives in `AppStore`.
@MainActor
@Observable
final class AppModel {
    var adminTab: AdminTab = .today
    var fieldTab: FieldTab = .today
    var adminPaths: [AdminTab: [AppDestination]] = [:]
    var fieldPaths: [FieldTab: [AppDestination]] = [:]

    /// Full-screen visit flow (field). Minimizing it never stops the timer.
    var isVisitPresented = false
    /// Admin previewing the Field shell.
    var isFieldPreviewPresented = false
    /// Demo-only switch to exercise offline behaviour without disabling the radio.
    var simulateOffline = false {
        didSet { applyConnectivity() }
    }
    private(set) var networkReachable = true

    /// The Camera tab asks before arriving, so a stray tap never marks a stop In Progress.
    struct ArrivalPrompt: Identifiable, Equatable {
        let routeID: Route.ID
        let stopID: RouteStop.ID
        let propertyName: String
        var id: RouteStop.ID { stopID }
    }
    var pendingArrival: ArrivalPrompt?

    let store: AppStore
    let auth: any AuthService
    let toasts = ToastCenter()
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var intentObserver: NSObjectProtocol?

    init(store: AppStore, auth: any AuthService = MockAuthService()) {
        self.store = store
        self.auth = auth
        // Called on the monitor's queue: hop to the main actor before touching state.
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let reachable = path.status == .satisfied
            guard let model = self else { return }
            Task { @MainActor in
                model.networkReachable = reachable
                model.applyConnectivity()
            }
        }
        monitor.start(queue: DispatchQueue(label: "maplecore.network"))

        // Live Activity buttons run as App Intents in this process, possibly before any view exists
        // (background launch), so the model — created at launch — handles them.
        intentObserver = NotificationCenter.default.addObserver(forName: .visitIntent, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[VisitIntentAction.userInfoKey] as? String
            MainActor.assumeIsolated {
                guard let raw, let action = VisitIntentAction(rawValue: raw) else { return }
                self?.handle(action)
            }
        }
    }

    func handle(_ action: VisitIntentAction) {
        switch action {
        case .pause: try? store.updateVisit { s, now in try s.pause(at: now) }
        case .resume: try? store.updateVisit { s, now in try s.resume(at: now) }
        case .afterPhotos: if store.activeVisit != nil { isVisitPresented = true }
        }
    }

    private func applyConnectivity() {
        store.isOnline = networkReachable && !simulateOffline
    }

    // MARK: Navigation

    func adminPath(_ tab: AdminTab) -> Binding<[AppDestination]> {
        Binding(get: { self.adminPaths[tab] ?? [] }, set: { self.adminPaths[tab] = $0 })
    }

    func fieldPath(_ tab: FieldTab) -> Binding<[AppDestination]> {
        Binding(get: { self.fieldPaths[tab] ?? [] }, set: { self.fieldPaths[tab] = $0 })
    }

    /// Pushes onto the visible tab's stack.
    func push(_ destination: AppDestination) {
        if store.activeRole == .field || isFieldPreviewPresented {
            fieldPaths[fieldTab, default: []].append(destination)
        } else {
            adminPaths[adminTab, default: []].append(destination)
        }
    }

    /// Switches admin tab and optionally pushes a destination there (e.g. Today → Inbox thread).
    func open(_ tab: AdminTab, then destination: AppDestination? = nil) {
        adminTab = tab
        if let destination { adminPaths[tab] = [destination] }
    }

    func open(_ tab: FieldTab, then destination: AppDestination? = nil) {
        guard tab != .camera else { presentVisit(); return }
        fieldTab = tab
        if let destination { fieldPaths[tab] = [destination] }
    }

    func popToRoot() {
        if store.activeRole == .field || isFieldPreviewPresented {
            fieldPaths[fieldTab] = []
        } else {
            adminPaths[adminTab] = []
        }
    }

    // MARK: Visit

    /// Opens the visit cover. With no active visit, asks to arrive at the crew's next stop first.
    func presentVisit() {
        if store.activeVisit != nil {
            isVisitPresented = true
            return
        }
        guard let route = store.fieldRoute, let next = route.nextStop else {
            toasts.show("No stop to start right now", symbol: "info.circle", tone: .blue)
            return
        }
        if store.isReadOnly {
            toasts.show("Preview only — visits can't be started", symbol: "eye", tone: .blue)
            return
        }
        pendingArrival = ArrivalPrompt(routeID: route.id, stopID: next.id, propertyName: store.property(next.propertyID)?.name ?? "the next stop")
    }

    /// Confirms the Camera-tab arrival prompt: marks arrival and opens the visit.
    func confirmArrival() {
        guard let prompt = pendingArrival else { return }
        pendingArrival = nil
        guard store.arrive(routeID: prompt.routeID, stopID: prompt.stopID) != nil else {
            toasts.show("Finish the visit in progress first", symbol: "info.circle", tone: .blue)
            return
        }
        Haptics.impact(.medium)
        isVisitPresented = true
    }

    func resetNavigation() {
        adminPaths = [:]
        fieldPaths = [:]
        adminTab = .today
        fieldTab = .today
        isVisitPresented = false
        isFieldPreviewPresented = false
    }

    // MARK: Deep links

    /// maplecore://visit opens the active visit (from the Live Activity).
    func handle(url: URL) {
        guard url.scheme == "maplecore" else { return }
        switch url.host() {
        case "visit":
            if store.activeVisit != nil { isVisitPresented = true }
        case "inbox":
            open(.inbox)
        default:
            break
        }
    }
}
