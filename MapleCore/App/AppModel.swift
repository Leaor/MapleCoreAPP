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

    let store: AppStore
    let auth: any AuthService
    let toasts = ToastCenter()
    @ObservationIgnored private let monitor = NWPathMonitor()

    init(store: AppStore, auth: any AuthService = MockAuthService()) {
        self.store = store
        self.auth = auth
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in
                self?.networkReachable = reachable
                self?.applyConnectivity()
            }
        }
        monitor.start(queue: DispatchQueue(label: "maplecore.network"))
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

    /// Opens the visit cover. If no visit is active, starts one at the crew's next stop (arrive).
    func presentVisit() {
        if store.activeVisit == nil, let route = store.fieldRoute, let next = route.nextStop {
            if store.isReadOnly {
                toasts.show("Preview only — visits can't be started", symbol: "eye", tone: .blue)
                return
            }
            store.arrive(routeID: route.id, stopID: next.id)
            Haptics.impact(.medium)
        }
        guard store.activeVisit != nil else {
            toasts.show("No stop to start right now", symbol: "info.circle", tone: .blue)
            return
        }
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
