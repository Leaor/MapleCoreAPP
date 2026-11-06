import SwiftUI
import UserNotifications
import CoreLocation
import MapleCoreKit

// MARK: - Account loading

/// "Getting your day ready": a short checklist while the session is set up on this iPhone.
struct AccountLoadingView: View {
    let account: Account
    var onDone: () -> Void

    @State private var completed = 0

    private let steps = [
        "Role and permissions confirmed",
        "Loading today's route",
        "Saving property notes for offline use"
    ]

    var body: some View {
        VStack(spacing: Space.xxl) {
            Spacer(minLength: Space.xxl)
            BrandMarkImage(size: 56)
            VStack(spacing: Space.s) {
                Text("Getting your day ready")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Signed in as \(account.displayName) · \(account.company)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    stepRow(index: index, title: title)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            ProgressView(value: Double(completed), total: Double(steps.count))
                .tint(Palette.red)
                .accessibilityLabel("Setup progress")
            Spacer(minLength: Space.xxl)
        }
        .padding(.horizontal, Space.xxl)
        .task {
            for index in 1...steps.count {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                withMotion { completed = index }
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }

    private func stepRow(index: Int, title: String) -> some View {
        HStack(spacing: Space.m) {
            Group {
                if index < completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                } else if index == completed {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(Palette.ink3)
                }
            }
            .font(.title3)
            .frame(width: 28)
            .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(index <= completed ? Palette.ink : Palette.ink3)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
        .accessibilityValue(index < completed ? "Done" : (index == completed ? "In progress" : "Waiting"))
    }
}

// MARK: - Role selection

/// Only shown for accounts that hold both an admin-shell role and Field.
struct RoleSelectionView: View {
    var onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @State private var selection: AppRole?

    private var adminRole: AppRole {
        store.account?.roles.first(where: \.usesAdminShell) ?? .admin
    }

    private var chosen: AppRole { selection ?? adminRole }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                OnboardingHeading(title: "How are you working today?", message: "Your account has both roles. Switch any time from Settings.")
                    .padding(.bottom, Space.s)
                RoleCard(title: adminRole.title,
                         detail: "Routes, crews, properties, quotes, invoices and the inbox.",
                         symbol: "building.2",
                         isSelected: chosen == adminRole) { selection = adminRole }
                RoleCard(title: AppRole.field.title,
                         detail: "Today's route, visits, proof-of-work photos and crew messages.",
                         symbol: "point.topleft.down.to.point.bottomright.curvepath",
                         isSelected: chosen == .field) { selection = .field }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxxl)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue as \(chosen.title)") {
                store.choose(role: chosen)
                Haptics.selection()
                onContinue()
            }
            .buttonStyle(.mc(.primary))
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.l)
            .padding(.top, Space.s)
            .background(Palette.background)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct RoleCard: View {
    var title: String
    var detail: String
    var symbol: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Palette.redText : Palette.ink2)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Palette.redSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.red : Palette.ink3)
                    .accessibilityHidden(true)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Palette.red : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Notifications pre-prompt

/// Explains notifications before the system prompt so the one-time question lands well.
struct NotificationsPermissionView: View {
    var onDone: () -> Void

    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(spacing: Space.s) {
                    ExampleNotification(symbol: "snowflake", title: "Snow event — dispatch at 4:00 AM", detail: "Route S2 · 12 commercial lots")
                    ExampleNotification(symbol: "arrow.triangle.swap", title: "Route changed by Michael", detail: "Riverwood Townhomes moved to stop 2")
                        .opacity(0.8)
                }
                .padding(.vertical, Space.l)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Example notifications: a snow dispatch and a route change")

                OnboardingHeading(title: "Don't miss a dispatch", message: "Get route changes, snow callouts and messages from your manager. You choose which ones in Settings.")
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.s) {
                Button(action: request) {
                    Text("Turn On Notifications")
                }
                .buttonStyle(.mc(.primary))
                .disabled(isRequesting)
                Button("Not Now", action: onDone)
                    .buttonStyle(.mc(.secondary))
                    .disabled(isRequesting)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.l)
            .padding(.top, Space.s)
            .background(Palette.background)
        }
    }

    private func request() {
        isRequesting = true
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            isRequesting = false
            onDone()
        }
    }
}

private struct ExampleNotification: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Palette.red, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
            Text("now").font(.caption).foregroundStyle(Palette.ink3)
        }
        .padding(Space.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Location explanation (Field)

/// Field only. Explains when location is shared, then asks for When-In-Use access.
struct LocationPermissionView: View {
    var onDone: () -> Void

    @State private var requester: LocationPermissionRequester?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                LocationIllustration()
                Text("Location, only while you work")
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.m) {
                    reason("location.fill", "Shows your ETA and confirms arrival at each property.")
                    reason("clock", "Shared only after you start a shift, and stops when you end it.")
                    reason("pause.circle", "Pause sharing any time from Profile. The app still works — you tap Arrived yourself.")
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.s) {
                Button("Continue", action: request)
                    .buttonStyle(.mc(.primary))
                    .disabled(requester != nil)
                Button("Not Now", action: onDone)
                    .buttonStyle(.mc(.secondary))
                    .disabled(requester != nil)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.l)
            .padding(.top, Space.s)
            .background(Palette.background)
        }
    }

    private func reason(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func request() {
        let requester = LocationPermissionRequester()
        self.requester = requester
        Task {
            await requester.request()
            onDone()
        }
    }
}

private struct LocationIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface2)
            Path { path in
                path.move(to: CGPoint(x: 30, y: 130))
                path.addCurve(to: CGPoint(x: 230, y: 50), control1: CGPoint(x: 110, y: 140), control2: CGPoint(x: 150, y: 40))
            }
            .stroke(Palette.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 8]))
            Circle()
                .fill(Palette.blue)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .position(x: 30, y: 130)
            StopNumberBadge(number: 3, status: .pending, isNext: true)
                .position(x: 236, y: 48)
        }
        .frame(width: 280, height: 160)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// Holds the location manager until the user answers the system prompt (the prompt disappears if
/// the manager is released), then resumes.
@MainActor
final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.handleChange()
        }
    }

    private func handleChange() {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume()
        continuation = nil
    }
}

#Preview("Role") {
    RoleSelectionView(onContinue: {})
        .previewEnvironment()
}

#Preview("Notifications") {
    NotificationsPermissionView(onDone: {})
        .previewEnvironment()
}

#Preview("Location") {
    LocationPermissionView(onDone: {})
        .previewEnvironment(role: .field)
}
