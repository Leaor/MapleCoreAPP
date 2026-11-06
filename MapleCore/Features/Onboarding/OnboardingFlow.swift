import SwiftUI
import MapleCoreKit

/// Root of the signed-out experience: Splash → Sign in → Verify → Account loading →
/// Role (two-role accounts only) → Notifications → Location (Field only).
///
/// The flow resumes from the store's session state, so quitting half-way through never loses progress:
/// an account without a role resumes at the role step, a chosen role without permissions at notifications.
/// `RootView` swaps to the right shell as soon as `account`, `activeRole` and `hasCompletedPermissions` are set.
struct OnboardingFlow: View {
    enum Phase: Hashable {
        case splash
        case signIn
        case loading(Account)
        case role
        case notifications
        case location
    }

    @Environment(AppStore.self) private var store
    @State private var phase: Phase?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let phase {
                content(for: phase)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
            }
        }
        .motionAnimation(.easeInOut(duration: 0.3), value: phase)
        .onAppear {
            if phase == nil { phase = resumePhase }
        }
    }

    /// Where to pick up, derived from what the store already knows.
    private var resumePhase: Phase {
        guard store.account != nil else { return .splash }
        if store.activeRole == nil { return .role }
        return .notifications
    }

    @ViewBuilder
    private func content(for phase: Phase) -> some View {
        switch phase {
        case .splash:
            SplashView { self.phase = .signIn }
        case .signIn:
            SignInFlow { account in self.phase = .loading(account) }
        case let .loading(account):
            AccountLoadingView(account: account) { finishLoading(account) }
        case .role:
            RoleSelectionView { advanceAfterRole() }
        case .notifications:
            NotificationsPermissionView { advanceAfterNotifications() }
        case .location:
            LocationPermissionView { store.completePermissions() }
        }
    }

    // MARK: Step logic

    private func finishLoading(_ account: Account) {
        store.signIn(account)
        if store.activeRole == nil {
            phase = .role
        } else if !store.hasCompletedPermissions {
            phase = .notifications
        }
        // Otherwise RootView switches to the shell on its own.
    }

    private func advanceAfterRole() {
        if !store.hasCompletedPermissions { phase = .notifications }
    }

    private func advanceAfterNotifications() {
        if store.activeRole == .field {
            phase = .location
        } else {
            store.completePermissions()
        }
    }
}

// MARK: - Shared onboarding chrome

/// Brand mark used across onboarding. Uses the `BrandMark` asset.
struct BrandMarkImage: View {
    var size: CGFloat

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("MapleCore maple leaf")
    }
}

/// Large onboarding heading with an optional supporting paragraph.
struct OnboardingHeading: View {
    var title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Horizontal shake for rejected input. Callers skip it under Reduce Motion.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

#Preview("Onboarding · signed out") {
    let model = AppModel(store: AppStore(persistence: nil, syncMode: .disabled), auth: MockAuthService(latency: .zero))
    OnboardingFlow()
        .environment(model)
        .environment(model.store)
        .environment(model.toasts)
}
