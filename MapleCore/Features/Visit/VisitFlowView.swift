import SwiftUI
import MapleCoreKit

/// Screens inside the visit cover. The step is driven by `VisitSession.state`, plus which photo
/// mode or review the crew is looking at.
enum VisitScreen: Hashable {
    case arrived
    case camera(PhotoKind, angle: String? = nil)
    case photo(VisitPhoto.ID)
    case timer
    case compare
    case review

    /// Where to land when the cover opens (or reopens after being minimized).
    static func initial(for session: VisitSession) -> VisitScreen {
        switch session.state {
        case .notStarted, .travelling, .arrived:
            return session.beforeCount > 0 ? .camera(.before) : .arrived
        case .working, .paused:
            return .timer
        case .completed, .reviewed:
            return .review
        }
    }
}

/// What the Submitted step shows. Kept in local state because `activeVisit` is nil after submit.
struct VisitSubmittedResult: Equatable {
    var result: AppStore.SubmittedVisit
    var routeID: Route.ID
    var stopCount: Int
}

/// The proof-of-work visit, presented as one full-screen cover by `FieldShell`:
/// arrived → before photos → work timer → after photos → compare → review → submitted.
/// Minimizing never stops the timer; elapsed time is derived from stored dates.
struct VisitFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts

    @State private var screen: VisitScreen?
    @State private var submitted: VisitSubmittedResult?
    @State private var camera = CameraController()
    @State private var isIssuePresented = false
    @State private var isSkipPresented = false
    @State private var isDiscardConfirming = false

    var body: some View {
        Group {
            if let submitted {
                VisitSubmittedStep(submitted: submitted)
            } else if let session = store.activeVisit {
                flow(session)
            } else {
                emptyState
            }
        }
        .sheet(isPresented: $isIssuePresented) {
            VisitIssueSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSkipPresented) {
            VisitSkipSheet(onSkip: skip)
                .presentationDetents([.large])
        }
        .confirmationDialog("Discard this visit?", isPresented: $isDiscardConfirming, titleVisibility: .visible) {
            Button("Discard Visit", role: .destructive, action: discard)
            Button("Keep Visit", role: .cancel) {}
        } message: {
            Text("Photos, times and notes for this visit are deleted from this iPhone. The stop goes back to pending.")
        }
    }

    // MARK: Flow

    @ViewBuilder
    private func flow(_ session: VisitSession) -> some View {
        let current = screen ?? VisitScreen.initial(for: session)
        ZStack {
            switch current {
            case let .camera(kind, angle):
                VisitCameraScreen(session: session, initialMode: kind, initialAngle: angle, camera: camera, go: go)
                    .transition(.opacity)
            case let .photo(id):
                VisitPhotoReviewScreen(session: session, photoID: id, go: go)
                    .transition(.opacity)
            default:
                VStack(spacing: 0) {
                    VisitHeader(
                        session: session,
                        step: stepIndex(current, session: session),
                        onReportIssue: { isIssuePresented = true },
                        onSkip: { isSkipPresented = true },
                        onDiscard: { isDiscardConfirming = true }
                    )
                    stepContent(current, session: session)
                }
                .background(Palette.background.ignoresSafeArea())
                .transition(.opacity)
            }
        }
        .motionAnimation(.easeInOut(duration: 0.2), value: current)
    }

    @ViewBuilder
    private func stepContent(_ current: VisitScreen, session: VisitSession) -> some View {
        switch current {
        case .timer:
            VisitTimerStep(session: session, go: go, onReportIssue: { isIssuePresented = true })
        case .compare:
            VisitCompareStep(session: session, go: go)
        case .review:
            VisitReviewStep(session: session, go: go, onReportIssue: { isIssuePresented = true }) { result in
                withMotion { submitted = result }
            }
        default:
            VisitArrivedStep(session: session, go: go, onSkip: { isSkipPresented = true })
        }
    }

    private func go(_ next: VisitScreen) {
        withMotion(.easeInOut(duration: 0.2)) { screen = next }
    }

    private func stepIndex(_ current: VisitScreen, session: VisitSession) -> Int {
        switch current {
        case .arrived: return 0
        case let .camera(kind, _): return Self.step(for: kind)
        case let .photo(id): return Self.step(for: session.photos.first { $0.id == id }?.kind ?? .before)
        case .timer: return 2
        case .compare: return 3
        case .review: return 4
        }
    }

    private static func step(for kind: PhotoKind) -> Int {
        switch kind {
        case .before: 1
        case .work: 2
        case .after: 3
        }
    }

    // MARK: Actions

    private func skip(reason: String) {
        guard let session = store.activeVisit else { return }
        for name in session.photos.compactMap(\.localFileName) { PhotoStorage.delete(name) }
        store.skipStop(routeID: session.routeID, stopID: session.stopID, reason: reason)
        isSkipPresented = false
        model.isVisitPresented = false
        toasts.show(store.isOnline ? "Stop skipped · sends automatically" : "Stop skipped · saved on this iPhone", symbol: "arrow.uturn.right.circle.fill", tone: .neutral)
    }

    private func discard() {
        guard let session = store.activeVisit else { return }
        for name in session.photos.compactMap(\.localFileName) { PhotoStorage.delete(name) }
        store.cancelActiveVisit()
        model.isVisitPresented = false
        toasts.show("Visit discarded", symbol: "trash", tone: .neutral)
    }

    private var emptyState: some View {
        EmptyStateView(symbol: "camera", title: "No active visit", message: "Start a visit from your next stop on the Route tab.") {
            Button("Close") { model.isVisitPresented = false }
                .buttonStyle(.mc(.secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

// MARK: - Header

/// Common header: minimize, "Visit · Stop N", demo connectivity chip, options menu and the step indicator.
struct VisitHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let session: VisitSession
    let step: Int
    var onReportIssue: () -> Void
    var onSkip: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Button {
                    model.isVisitPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.iconCircle)
                .accessibilityLabel("Minimize visit — timer keeps running")

                Text("Visit · Stop \(session.stopNumber)")
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                connectivityChip

                Menu {
                    Button(action: onReportIssue) {
                        Label("Report an issue", systemImage: "exclamationmark.bubble")
                    }
                    Button(action: onSkip) {
                        Label("Can't service this stop?", systemImage: "arrow.uturn.right")
                    }
                    Divider()
                    Button(role: .destructive, action: onDiscard) {
                        Label("Discard visit", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: Hit.min, height: Hit.min)
                        .background(Palette.surface2, in: Circle())
                }
                .accessibilityLabel("Visit options")
            }
            VisitStepIndicator(current: step)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
        .background(Palette.background)
    }

    /// Demo-only: flips `simulateOffline` so the offline copy can be exercised (FieldFlow prototype).
    private var connectivityChip: some View {
        Button {
            model.simulateOffline.toggle()
            Haptics.selection()
        } label: {
            Pill(
                text: store.isOnline ? "Online" : "Offline",
                tone: store.isOnline ? .green : .amber,
                symbol: store.isOnline ? "wifi" : "wifi.slash"
            )
            .frame(minHeight: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isOnline ? "Online" : "Offline")
        .accessibilityHint("Toggle connection for the demo")
    }
}

// MARK: - Shared bits

/// Inline error for a rejected visit transition (e.g. "Take 2 more before photos to start work.").
struct VisitInlineError: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.redText)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.redText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m)
        .background(Palette.redSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

#if DEBUG
/// Starts a visit at the crew's next stop so the cover has something to show in previews.
struct VisitFlowPreviewHost: View {
    @Environment(AppStore.self) private var store
    var beforePhotos = 0
    var startWork = false

    var body: some View {
        VisitFlowView()
            .task {
                guard store.activeVisit == nil, let route = store.fieldRoute, let next = route.nextStop else { return }
                store.arrive(routeID: route.id, stopID: next.id)
                for _ in 0..<beforePhotos {
                    store.visitAction { s, now in _ = s.addPhoto(kind: .before, at: now) }
                }
                if startWork {
                    store.visitAction { s, now in try s.startWork(at: now) }
                }
            }
    }
}

#Preview("Arrived") {
    VisitFlowPreviewHost()
        .previewEnvironment(role: .field)
}

#Preview("Working") {
    VisitFlowPreviewHost(beforePhotos: 3, startWork: true)
        .previewEnvironment(role: .field)
}

#Preview("No visit") {
    VisitFlowView()
        .previewEnvironment(role: .field)
}
#endif
