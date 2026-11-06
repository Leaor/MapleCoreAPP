import SwiftUI
import MapleCoreKit

/// Supervisor review of one visit report: photos, verified times, crew notes, then approve or send back.
/// Approving advances to the next visit in the queue, or pops back when the queue is empty.
struct SupervisorReviewView: View {
    let visitID: VisitRecord.ID

    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var showRequestChanges = false

    var body: some View {
        if !store.capabilities.contains(.visitReview) {
            EmptyStateView(symbol: "lock", title: "Review isn't available", message: "Visit review is for supervisors, managers and admins.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
                .navigationTitle("Visit Report")
                .navigationBarTitleDisplayMode(.inline)
        } else if let visit = store.visit(visitID), let property = store.property(visit.propertyID) {
            content(visit: visit, property: property)
        } else {
            MissingRecordView()
                .navigationTitle("Visit Report")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        if let position = store.reviewQueuePosition(of: visitID) {
            return "Review · \(position.index) of \(position.total)"
        }
        return "Visit Report"
    }

    private func content(visit: VisitRecord, property: Property) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                ReviewHeader(visit: visit, property: property)
                ReviewPhotos(visit: visit)
                ReviewTimes(visit: visit)
                if visit.offlinePhotoCount > 0 {
                    NoticeCard(symbol: "iphone", text: offlineText(visit), tone: .amber)
                }
                if !visit.notes.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionHeader("Crew notes")
                        Text(visit.notes)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .cardStyle()
                    }
                }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if visit.review == .awaiting {
                BottomActionBar {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Space.m) { actionButtons(visit) }
                        VStack(spacing: Space.s) { actionButtons(visit) }
                    }
                }
            }
        }
        .sheet(isPresented: $showRequestChanges) {
            RequestChangesSheet(propertyName: property.name) { note in
                requestChanges(visit, note: note)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(_ visit: VisitRecord) -> some View {
        Button("Request Changes") { showRequestChanges = true }
            .buttonStyle(.mc(.secondary))
        Button("Approve Visit") { approve(visit) }
            .buttonStyle(.mc(.primary))
    }

    private func offlineText(_ visit: VisitRecord) -> String {
        let imported = visit.photos.filter { $0.source == .imported }.count
        let count = visit.offlinePhotoCount
        var text = "\(Fmt.plural(count, "photo")) \(count == 1 ? "was" : "were") taken offline or imported. Their capture times come from the iPhone's clock only and can't be independently confirmed."
        if imported > 0 { text += " \(Fmt.plural(imported, "photo")) came from the photo library." }
        return text
    }

    // MARK: Actions

    private func approve(_ visit: VisitRecord) {
        store.approveVisit(visit.id)
        Haptics.success()
        toasts.show(store.isOnline ? "Visit approved" : "Approved · saved on this iPhone, sends automatically")
        advance(from: visit.id)
    }

    private func requestChanges(_ visit: VisitRecord, note: String) {
        store.requestChanges(visit.id, note: note)
        Haptics.success()
        toasts.show(store.isOnline ? "Changes requested · crew will be notified" : "Saved on this iPhone · sends automatically", symbol: "arrow.uturn.backward.circle.fill", tone: .amber)
        advance(from: visit.id)
    }

    /// Replaces this screen with the next visit in the queue, or pops when the queue is done.
    private func advance(from visitID: VisitRecord.ID) {
        guard let next = store.nextReviewVisit(after: visitID) else {
            dismiss()
            return
        }
        var path = model.adminPaths[model.adminTab] ?? []
        if let last = path.last, case .review = last {
            path[path.count - 1] = .review(next.id)
            model.adminPaths[model.adminTab] = path
        } else {
            dismiss()
        }
    }
}

// MARK: - Sections

private struct ReviewHeader: View {
    @Environment(AppStore.self) private var store
    var visit: VisitRecord
    var property: Property

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            reviewPill
            Text(property.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [visit.title]
        if let crew = store.crew(visit.crewID) { parts.append(crew.name) }
        if !visit.crewNames.isEmpty { parts.append(visit.crewNames) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var reviewPill: some View {
        switch visit.review {
        case .awaiting:
            Pill(text: visit.review.label, tone: .blue, symbol: "hourglass")
        case .approved:
            Pill(text: reviewedText("Approved"), tone: .green, symbol: "checkmark.seal.fill")
        case .changesRequested:
            Pill(text: reviewedText("Changes requested"), tone: .amber, symbol: "arrow.uturn.backward")
        }
    }

    private func reviewedText(_ base: String) -> String {
        guard let by = visit.reviewedBy else { return base }
        if let at = visit.reviewedAt { return "\(base) by \(by) · \(Fmt.time(at))" }
        return "\(base) by \(by)"
    }
}

private struct ReviewPhotos: View {
    var visit: VisitRecord

    var body: some View {
        let before = visit.photos(.before).first
        let after = visit.photos(.after).first
        let shown = (before == nil ? 0 : 1) + (after == nil ? 0 : 1)
        let extra = max(visit.photos.count - shown, 0)
        if visit.photos.isEmpty {
            NoticeCard(symbol: "camera", text: "No photos were attached to this visit.", tone: .amber)
        } else {
            HStack(spacing: Space.s) {
                if before != nil || after != nil {
                    NavigationLink(value: AppDestination.photoCompare(visit.id)) {
                        HStack(spacing: Space.s) {
                            tile(before, label: "Before")
                            tile(after, label: "After")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Compare before and after photos")
                }
                if extra > 0 {
                    NavigationLink(value: AppDestination.gallery(visit.propertyID)) {
                        Text("+\(extra)\nphotos")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(extra) more photos, open gallery")
                }
            }
        }
    }

    private func tile(_ photo: VisitPhoto?, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            PhotoTile(photo: photo, swatch: label == "Before" ? 0 : 1, cornerRadius: Radius.control, maxPixel: 400)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
    }
}

private struct ReviewTimes: View {
    var visit: VisitRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(title: "Arrived", detail: visit.arrivalVerified ? "Within 30 m of property" : "Arrival not location-verified",
                value: visit.arrivedAt.map(Fmt.time) ?? "—",
                symbol: visit.arrivalVerified ? "location.fill" : "location.slash", tone: visit.arrivalVerified ? .green : .amber)
            Divider()
            row(title: "Worked \(Fmt.duration(minutes: visit.workMinutes))", detail: workDetail,
                value: Fmt.timer(TimeInterval(visit.workMinutes * 60)),
                symbol: "timer", tone: .blue)
            Divider()
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Received by MapleCore")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                TimeStampLabel(source: .server, date: visit.receivedAt, withSeconds: true)
            }
            .padding(.vertical, Space.m)
        }
        .padding(.horizontal, Space.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var workDetail: String {
        var parts: [String] = []
        if let start = visit.workStart, let end = visit.workEnd {
            parts.append("\(Fmt.clock(start))–\(Fmt.clock(end))")
        }
        if visit.pausedMinutes > 0 { parts.append("paused \(visit.pausedMinutes) min") }
        if visit.estimateMinutes > 0 { parts.append("est. \(visit.estimateMinutes)") }
        parts.append("iPhone clock")
        return parts.joined(separator: " · ")
    }

    private func row(title: String, detail: String, value: String, symbol: String, tone: Tone) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(tone.foreground)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.caption).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: Space.s)
            Text(value).font(.subheadline.weight(.semibold)).numeric().foregroundStyle(Palette.ink)
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Request changes

private struct RequestChangesSheet: View {
    var propertyName: String
    var onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var focused: Bool

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Tell the crew what to fix at \(propertyName). They'll see this with the visit report.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $note)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(Space.m)
                    .frame(minHeight: 140)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Note to crew, required")
                Text("A note is required.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .screenBackground()
            .navigationTitle("Request Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!trimmed.isEmpty)
    }
}

#Preview("Supervisor Review") {
    NavigationStack {
        SupervisorReviewView(visitID: "v-kingsway-today")
            .appDestinations()
    }
    .previewEnvironment()
}
