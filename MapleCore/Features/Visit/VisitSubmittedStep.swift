import SwiftUI
import MapleCoreKit

/// Visit submitted (VisitSubmitted board). The visit is stored on this iPhone; the sync card
/// reports the real outbox state and opens Sync & Uploads.
struct VisitSubmittedStep: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let submitted: VisitSubmittedResult

    @State private var showsCheck = false

    private var result: AppStore.SubmittedVisit { submitted.result }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                header
                syncCard
                Text("Everything is stored on this iPhone. It sends on its own — you don't need to keep the app open.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s)
                upNext
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xxxl)
            .padding(.bottom, Space.l)
        }
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                if result.nextStop != nil {
                    Button {
                        model.isVisitPresented = false
                        model.open(FieldTab.route)
                    } label: {
                        Label("Next Stop", systemImage: "arrow.right")
                    }
                    .buttonStyle(.mc(.primary, glove: true))
                }
                Button("Back to Today") {
                    model.isVisitPresented = false
                    model.open(FieldTab.today)
                }
                .buttonStyle(.mc(result.nextStop == nil ? .primary : .secondary, glove: true))
            }
        }
        .onAppear {
            if reduceMotion {
                showsCheck = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { showsCheck = true }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Palette.green, in: Circle())
                .scaleEffect(showsCheck ? 1 : 0.4)
                .opacity(showsCheck ? 1 : 0)
                .accessibilityHidden(true)
            Text("Visit saved")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("\(result.propertyName) · \(Fmt.duration(minutes: result.workMinutes)) · \(Fmt.plural(result.photoCount, "photo"))")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Sync

    private var outboxState: OutboxState {
        store.visitOutboxItem(propertyName: result.propertyName)?.state ?? .queued
    }

    private var syncTitle: String {
        switch outboxState {
        case .queued: return store.isOnline ? "Sending…" : "Waiting for signal to send"
        case .sending: return "Sending…"
        case .sent: return "Sent"
        case .failed: return "Couldn't send yet · retries automatically"
        case .needsAttention: return "Needs your attention"
        }
    }

    private var syncDetail: String {
        let photos = store.visitPhotoOutboxItem(propertyName: result.propertyName)
        guard result.photoCount > 0 else { return "Times, tasks and notes" }
        if let photos, photos.totalUnits > 0, case .sending = photos.state {
            return "Times, tasks, notes · photos \(photos.completedUnits) of \(photos.totalUnits)"
        }
        return "Times, tasks, notes · \(Fmt.plural(result.photoCount, "photo"))"
    }

    private var syncCard: some View {
        Button {
            model.isVisitPresented = false
            model.open(FieldTab.profile, then: .syncQueue)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: store.isOnline ? "arrow.up.circle" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(store.isOnline ? Palette.blue : Palette.amber)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(syncDetail)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: Space.s)
                SyncBadge(state: outboxState)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Sync & Uploads")
    }

    // MARK: Up next

    @ViewBuilder
    private var upNext: some View {
        if let next = result.nextStop {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Up next · \(result.nextStopNumber ?? 0) of \(submitted.stopCount)").captionStyle()
                HStack(spacing: Space.m) {
                    StopNumberBadge(number: result.nextStopNumber ?? 0, status: next.status, isNext: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.property(next.propertyID)?.name ?? "Next stop")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text("\(next.serviceName) · \(Fmt.duration(minutes: next.estimatedMinutes)) job")
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .cardStyle()
                .accessibilityElement(children: .combine)
            }
        } else {
            NoticeCard(symbol: "flag.checkered", text: "That was the last stop on this route.", tone: .green)
        }
    }
}

#if DEBUG
/// Runs a whole visit against the preview store so the Submitted step shows real data.
private struct VisitSubmittedPreviewHost: View {
    @Environment(AppStore.self) private var store
    @State private var submitted: VisitSubmittedResult?

    var body: some View {
        Group {
            if let submitted {
                VisitSubmittedStep(submitted: submitted)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let route = store.fieldRoute, let next = route.nextStop,
                  let session = store.arrive(routeID: route.id, stopID: next.id) else { return }
            for _ in 0..<3 { store.visitAction { s, now in _ = s.addPhoto(kind: .before, at: now) } }
            store.visitAction { s, now in try s.startWork(at: now) }
            for _ in 0..<3 { store.visitAction { s, now in _ = s.addPhoto(kind: .after, at: now) } }
            if let result = try? store.submitVisit() {
                submitted = VisitSubmittedResult(result: result, routeID: session.routeID, stopCount: session.stopCount)
            }
        }
    }
}

#Preview {
    VisitSubmittedPreviewHost()
        .previewEnvironment(role: .field)
}
#endif
