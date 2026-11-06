import SwiftUI
import MapleCoreKit

/// Step 5 · Notes and review (VisitReview board): summary, work notes, issue, then Submit.
/// Submitting writes to this iPhone and the outbox; it never claims the office has it yet.
struct VisitReviewStep: View {
    @Environment(AppStore.self) private var store

    let session: VisitSession
    var go: (VisitScreen) -> Void
    var onReportIssue: () -> Void
    var onSubmitted: (VisitSubmittedResult) -> Void

    @State private var notes = ""
    @State private var didLoadNotes = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Review Visit")
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(session.propertyName) · Stop \(session.stopNumber)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                summary
                notesField
                issueButton
                if !store.isOnline {
                    NoticeCard(symbol: "wifi.slash", text: "No signal — this visit will send automatically", tone: .amber)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                if let errorMessage { VisitInlineError(message: errorMessage) }
                Button(action: submit) {
                    Label("Submit Visit", systemImage: "paperplane.fill")
                }
                .buttonStyle(.mc(.primary, glove: true))
                .disabled(isSubmitting)
            }
        }
        .onAppear {
            guard !didLoadNotes else { return }
            notes = session.notes
            didLoadNotes = true
        }
        .onDisappear(perform: saveNotes)
        .onChange(of: notesFocused) { _, focused in
            if !focused { saveNotes() }
        }
    }

    // MARK: Sections

    private var summary: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                summaryRow(
                    symbol: "clock",
                    title: "Time on site",
                    value: timeValue(at: context.date)
                )
            }
            Divider().padding(.leading, 52)
            Button {
                saveNotes()
                go(.compare)
            } label: {
                summaryRow(
                    symbol: "photo.on.rectangle",
                    title: "Photos",
                    value: "\(Fmt.plural(session.photos.count, "photo")) · \(session.beforeCount) before · \(session.afterCount) after",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the before and after compare")
            Divider().padding(.leading, 52)
            summaryRow(
                symbol: "checklist",
                title: "Tasks",
                value: "\(session.completedTaskCount) of \(session.tasks.count)"
            )
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func timeValue(at date: Date) -> String {
        let work = Int((session.workingElapsed(at: date) / 60).rounded())
        let paused = Int((session.pausedDuration(at: date) / 60).rounded())
        return "\(Fmt.duration(minutes: work)) work · \(Fmt.duration(minutes: paused)) paused"
    }

    private func summaryRow(symbol: String, title: String, value: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Palette.ink2)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Work notes").captionStyle()
            TextField("What was done, anything the office should know", text: $notes, axis: .vertical)
                .lineLimit(4...10)
                .focused($notesFocused)
                .padding(Space.m)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityLabel("Work notes")
            Text("Tip: use the microphone on the keyboard to dictate.")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
        }
    }

    private var issueButton: some View {
        Button(action: onReportIssue) {
            HStack(spacing: Space.m) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(Palette.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.issue == nil ? "Report an issue" : "Issue reported")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if let issue = session.issue {
                        Text(issue)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: Hit.glove)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func saveNotes() {
        guard didLoadNotes, notes != session.notes, store.activeVisit?.id == session.id else { return }
        let text = notes
        store.visitAction { s, _ in s.notes = text }
    }

    private func submit() {
        notesFocused = false
        saveNotes()
        let routeID = session.routeID
        let stopCount = session.stopCount
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let result = try store.submitVisit() else {
                errorMessage = "This visit can't be submitted from a preview."
                Haptics.error()
                return
            }
            errorMessage = nil
            Haptics.success()
            onSubmitted(VisitSubmittedResult(result: result, routeID: routeID, stopCount: stopCount))
        } catch let error as VisitError {
            errorMessage = error.message
            Haptics.error()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost(beforePhotos: 3, startWork: true)
        .previewEnvironment(role: .field)
}
#endif
