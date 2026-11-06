import SwiftUI
import MapleCoreKit

/// Step 1 · Arrived (ActiveVisit board): what happens next, access notes, then the before camera.
struct VisitArrivedStep: View {
    @Environment(AppStore.self) private var store

    let session: VisitSession
    var go: (VisitScreen) -> Void
    var onSkip: () -> Void

    @State private var errorMessage: String?

    private var property: Property? { store.property(session.propertyID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                heading
                checklist
                accessNotes
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                if let errorMessage { VisitInlineError(message: errorMessage) }
                Button(action: start) {
                    Label("Start Visit · Before Photos", systemImage: "camera.fill")
                }
                .buttonStyle(.mc(.primary, glove: true))
                Button("Can't service this stop?", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Hit.min)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label {
                Text(arrivedLine)
            } icon: {
                Image(systemName: "mappin.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.green)
            Text(property?.name ?? session.propertyName)
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(session.serviceName) · about \(Fmt.duration(minutes: session.estimateMinutes))")
                .font(.body)
                .foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var arrivedLine: String {
        if let arrivedAt = session.arrivedAt {
            return "Arrived \(Fmt.time(arrivedAt)) · on site"
        }
        return "On site"
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            VisitChecklistRow(
                number: 1,
                title: "Before photos",
                detail: "At least \(VisitSession.requiredBeforePhotos) · \(session.requiredAngles.joined(separator: ", ").lowercased())",
                isDone: session.beforeCount >= VisitSession.requiredBeforePhotos
            )
            Divider().padding(.leading, 46)
            VisitChecklistRow(number: 2, title: "Do the work · timer runs", detail: taskDetail, isDone: false)
            Divider().padding(.leading, 46)
            VisitChecklistRow(number: 3, title: "After photos · same angles", detail: nil, isDone: false)
            Divider().padding(.leading, 46)
            VisitChecklistRow(number: 4, title: "Notes, review & submit", detail: nil, isDone: false)
        }
        .cardStyle(padding: Space.l)
    }

    private var taskDetail: String? {
        session.tasks.isEmpty ? nil : Fmt.plural(session.tasks.count, "task")
    }

    @ViewBuilder
    private var accessNotes: some View {
        if let notes = property?.accessNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Access notes").captionStyle()
                NoticeCard(symbol: "exclamationmark.triangle.fill", text: notes, tone: .amber)
            }
        }
    }

    private func start() {
        if session.state == .notStarted || session.state == .travelling {
            errorMessage = store.visitAction { s, now in try s.arrive(at: now) }
            if errorMessage != nil { Haptics.error(); return }
        }
        errorMessage = nil
        Haptics.selection()
        go(.camera(.before))
    }
}

/// Numbered step row used on the Arrived checklist.
struct VisitChecklistRow: View {
    var number: Int
    var title: String
    var detail: String?
    var isDone: Bool

    var body: some View {
        HStack(spacing: Space.m + 2) {
            ZStack {
                Circle().fill(isDone ? Palette.greenSoft : Palette.surface2)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.green)
                } else {
                    Text("\(number)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title)\(detail.map { ", \($0)" } ?? "")\(isDone ? ", done" : "")")
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost()
        .previewEnvironment(role: .field)
}
#endif
