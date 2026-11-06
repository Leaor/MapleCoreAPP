import SwiftUI
import MapleCoreKit

/// Admin, manager and supervisor shell: Today · Routes · Properties · Inbox · More.
struct AdminShell: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.adminTab) {
            NavigationStack(path: model.adminPath(.today)) {
                AdminTodayView().appDestinations()
            }
            .tabItem { Label("Today", systemImage: "house") }
            .tag(AdminTab.today)

            NavigationStack(path: model.adminPath(.routes)) {
                RoutesListView().appDestinations()
            }
            .tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            .tag(AdminTab.routes)

            NavigationStack(path: model.adminPath(.properties)) {
                PropertyListView().appDestinations()
            }
            .tabItem { Label("Properties", systemImage: "building.2") }
            .tag(AdminTab.properties)

            NavigationStack(path: model.adminPath(.inbox)) {
                InboxView().appDestinations()
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .badge(store.unreadCount(forField: false))
            .tag(AdminTab.inbox)

            NavigationStack(path: model.adminPath(.more)) {
                MoreView().appDestinations()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(AdminTab.more)
        }
        .sensoryFeedback(.selection, trigger: model.adminTab)
        .connectivityBanner()
        .fullScreenCover(isPresented: $model.isFieldPreviewPresented, onDismiss: { store.endRolePreview() }) {
            FieldShell()
                .environment(\.isRolePreview, true)
                // Covers sit above RootView's overlay, so they host their own toast layer.
                .toastOverlay()
        }
    }
}

/// Field shell for crew members: Today · Route · Camera · Messages · Profile.
/// One-handed and glove-friendly; no finance or staff data.
struct FieldShell: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store
    @Environment(\.isRolePreview) private var isRolePreview

    /// Camera is a trigger, not a destination: it opens the visit cover and the tab selection stays put.
    private var selection: Binding<FieldTab> {
        Binding(
            get: { model.fieldTab },
            set: { tab in
                if tab == .camera { model.presentVisit() } else { model.fieldTab = tab }
            }
        )
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: selection) {
            NavigationStack(path: model.fieldPath(.today)) {
                FieldTodayView().appDestinations()
            }
            .tabItem { Label("Today", systemImage: "house") }
            .tag(FieldTab.today)

            NavigationStack(path: model.fieldPath(.route)) {
                FieldRouteView().appDestinations()
            }
            .tabItem { Label("Route", systemImage: "map") }
            .tag(FieldTab.route)

            Color.clear
                .tabItem { Label(store.activeVisit == nil ? "Camera" : "Visit", systemImage: "camera.fill") }
                .tag(FieldTab.camera)
                .accessibilityLabel(store.activeVisit == nil ? "Camera, start visit at next stop" : "Return to active visit")

            NavigationStack(path: model.fieldPath(.messages)) {
                FieldMessagesView().appDestinations()
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .badge(store.unreadCount(forField: true))
            .tag(FieldTab.messages)

            NavigationStack(path: model.fieldPath(.profile)) {
                FieldProfileView().appDestinations()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(FieldTab.profile)
        }
        .sensoryFeedback(.selection, trigger: model.fieldTab)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isRolePreview { RolePreviewBanner() }
        }
        .connectivityBanner()
        .fullScreenCover(isPresented: $model.isVisitPresented) {
            VisitFlowView()
        }
        .task { LiveActivityController.shared.sync(store.activeVisit) }
        .onChange(of: store.activeVisit) { _, session in
            LiveActivityController.shared.sync(session)
        }
        .confirmationDialog(
            "Arrive at \(model.pendingArrival?.propertyName ?? "the next stop")?",
            isPresented: Binding(get: { model.pendingArrival != nil }, set: { if !$0 { model.pendingArrival = nil } }),
            titleVisibility: .visible
        ) {
            Button("I've Arrived · Start Visit") { model.confirmArrival() }
            Button("Cancel", role: .cancel) { model.pendingArrival = nil }
        } message: {
            Text("This records your arrival time and starts the before-photo step.")
        }
    }
}

/// Blue banner shown while an admin previews the Field shell. Every write is a no-op.
struct RolePreviewBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "eye").accessibilityHidden(true)
            Text("Previewing Field Mode as \(store.member(store.previewStaffID)?.shortName ?? "crew")")
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: Space.s)
            Button("Exit") { model.isFieldPreviewPresented = false }
                .font(.footnote.weight(.bold))
                .frame(minWidth: Hit.min, minHeight: Hit.min)
                .accessibilityHint("Returns to Admin mode")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.l)
        .background(Palette.blue)
    }
}

/// Global connectivity banner shown under the status bar while offline.
struct ConnectivityBanner: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if !store.isOnline {
                OfflineBanner(pendingCount: store.pendingOutbox.count)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.xs)
                    .background(Palette.background)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .motionAnimation(value: store.isOnline)
    }
}

extension View {
    func connectivityBanner() -> some View { modifier(ConnectivityBanner()) }
}
