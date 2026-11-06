import SwiftUI
import MapleCoreKit

/// Step 3 · Work timer (VisitTimer / TimerStates boards). Elapsed time is derived from stored
/// dates every second, so it survives backgrounding, minimizing and relaunch.
struct VisitTimerStep: View {
    @Environment(AppStore.self) private var store

    let session: VisitSession
    var go: (VisitScreen) -> Void
    var onReportIssue: () -> Void

    @State private var isPauseReasonsPresented = false
    @State private var errorMessage: String?

    private var isPaused: Bool { session.state == .paused }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                heading
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VisitTimerFace(session: session, now: context.date)
                }
                tasks
                Button {
                    go(.camera(.work))
                } label: {
                    Label("Add work-in-progress photo", systemImage: "camera")
                }
                .buttonStyle(.mc(.secondary))
                .disabled(session.state != .working && session.state != .paused)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                if let errorMessage { VisitInlineError(message: errorMessage) }
                HStack(spacing: Space.s) {
                    pauseResumeButton
                    Button {
                        go(.camera(.after))
                    } label: {
                        Text("Work Done · After Photos")
                    }
                    .buttonStyle(.mc(.primary, glove: true))
                    .layoutPriority(1)
                }
            }
        }
        .confirmationDialog("Pause the work timer?", isPresented: $isPauseReasonsPresented, titleVisibility: .visible) {
            ForEach(PauseReason.allCases, id: \.self) { reason in
                Button(reason.label) { pause(reason) }
            }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("Paused time is recorded separately with the reason.")
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(store.property(session.propertyID)?.name ?? session.propertyName)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Stop \(session.stopNumber) · \(session.serviceName)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onReportIssue) {
                Image(systemName: session.issue == nil ? "exclamationmark.bubble" : "exclamationmark.bubble.fill")
            }
            .buttonStyle(.iconCircle)
            .accessibilityLabel(session.issue == nil ? "Report an issue" : "Edit reported issue")
        }
    }

    @ViewBuilder
    private var tasks: some View {
        if !session.tasks.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionHeader("Tasks · \(session.completedTaskCount) of \(session.tasks.count)")
                VStack(spacing: 0) {
                    ForEach(Array(session.tasks.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider().padding(.leading, 52) }
                        VisitTaskRow(task: task) {
                            store.visitAction { s, _ in s.toggleTask(id: task.id) }
                            Haptics.selection()
                        }
                    }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var pauseResumeButton: some View {
        if isPaused {
            Button(action: resume) {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(.mc(.ink, glove: true))
        } else {
            Button {
                isPauseReasonsPresented = true
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(.mc(.secondary, glove: true))
            .disabled(session.state != .working)
        }
    }

    private func pause(_ reason: PauseReason) {
        errorMessage = store.visitAction { s, now in try s.pause(at: now, reason: reason) }
        if errorMessage == nil { Haptics.impact(.light) } else { Haptics.error() }
    }

    private func resume() {
        errorMessage = store.visitAction { s, now in try s.resume(at: now) }
        if errorMessage == nil { Haptics.impact(.medium) } else { Haptics.error() }
    }
}

/// The state pill, big timer, provenance line and Working / Paused / Estimate figures.
struct VisitTimerFace: View {
    let session: VisitSession
    let now: Date

    private var working: TimeInterval { session.workingElapsed(at: now) }
    private var paused: TimeInterval { session.pausedDuration(at: now) }
    private var isPaused: Bool { session.state == .paused }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: Space.s) {
                statePill
                TimerText(text: Fmt.timer(working))
                    .foregroundStyle(isPaused ? Palette.ink2 : Palette.ink)
                    .accessibilityLabel("Elapsed working time \(Fmt.spokenDuration(working))")
                    .accessibilityAddTraits(.updatesFrequently)
                if let start = session.workStartedAt {
                    // VisitSession has no server-confirmed start yet, so the device clock is labelled as such.
                    Text("Started \(Fmt.time(start)) · iPhone clock")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .frame(maxWidth: .infinity)
            figures
        }
    }

    private var statePill: some View {
        ZStack {
            if isPaused {
                pill(text: "Paused \(Fmt.timer(session.currentPause?.duration(at: now) ?? 0))", symbol: "pause.fill", color: Palette.amber)
                    .transition(.opacity)
            } else {
                pill(text: session.state == .working ? "Working" : session.state.label, symbol: "circle.fill", color: Palette.blue)
                    .transition(.opacity)
            }
        }
        .motionAnimation(.easeInOut(duration: 0.25), value: isPaused)
    }

    private func pill(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.m)
        .frame(minHeight: 28)
        .background(color, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPaused ? "Paused" : text)
    }

    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { figureItems }
            VStack(alignment: .leading, spacing: Space.s) { figureItems }
        }
        .padding(.vertical, Space.m + 2)
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var figureItems: some View {
        figure("Working", Fmt.timer(working), spoken: Fmt.spokenDuration(working))
        figure("Paused", Fmt.timer(paused), spoken: Fmt.spokenDuration(paused))
        figure("Estimate", Fmt.timer(TimeInterval(session.estimateMinutes * 60)), spoken: Fmt.duration(minutes: session.estimateMinutes))
    }

    private func figure(_ title: String, _ value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(spoken)")
    }
}

/// Tappable checklist row for a visit task.
struct VisitTaskRow: View {
    let task: VisitTask
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.m) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Palette.green : Palette.ink3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.isDone ? Palette.ink2 : Palette.ink)
                    .strikethrough(task.isDone, color: Palette.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.addedToday {
                    Pill(text: "New today", tone: .blue)
                }
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: Hit.glove)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityValue(task.isDone ? "Done" : "Not done")
        .accessibilityHint("Double tap to toggle")
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost(beforePhotos: 3, startWork: true)
        .previewEnvironment(role: .field)
}
#endif
