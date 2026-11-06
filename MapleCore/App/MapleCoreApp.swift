import SwiftUI
import MapleCoreKit

@main
struct MapleCoreApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("-uitest")
        // UI tests run against a fresh in-memory store and an instant demo sign-in.
        let store = AppStore(persistence: isUITest ? MemorySnapshotStore() : FileSnapshotStore.applicationSupport())
        if isUITest { store.syncStepDelay = .milliseconds(50) }
        _model = State(initialValue: AppModel(store: store, auth: MockAuthService(latency: isUITest ? .zero : .milliseconds(600))))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.toasts)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.store.persist() }
            if phase == .active { model.store.scheduleSync() }
        }
    }
}

/// Chooses onboarding or a role shell from the session state.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    private var isReady: Bool {
        store.account != nil && store.activeRole != nil && store.hasCompletedPermissions
    }

    var body: some View {
        Group {
            if isReady {
                if store.activeRole == .field {
                    FieldShell()
                } else {
                    AdminShell()
                }
            } else {
                OnboardingFlow()
            }
        }
        .transition(.opacity)
        .motionAnimation(.easeInOut(duration: 0.25), value: isReady)
        .motionAnimation(.easeInOut(duration: 0.25), value: store.activeRole)
        .tint(Palette.red)
        .environment(\.gloveMode, store.settings.gloveMode)
        .preferredColorScheme(colorScheme)
        .toastOverlay()
        .onAppear { Haptics.isEnabled = store.settings.haptics }
        .onChange(of: store.settings.haptics) { _, on in Haptics.isEnabled = on }
        .onChange(of: store.account) { _, account in
            if account == nil { model.resetNavigation() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
