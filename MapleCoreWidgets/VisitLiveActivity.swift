import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// Brand colours kept local: the design-system `Palette` lives in the app target.
private enum WidgetColor {
    static let red = Color(red: 0.84, green: 0.16, blue: 0.16)
    static let blue = Color(red: 0.35, green: 0.66, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.30)
}

private let visitURL = URL(string: "maplecore://visit")

/// Lock Screen + Dynamic Island for the active visit (LiveActivity board).
/// The working timer counts on-device with `Text(timerInterval:)`; paused shows a frozen value.
struct VisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitActivityAttributes.self) { context in
            VisitLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(visitURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        MapleMark(size: 26)
                        Text(context.state.stateLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(context.state.isPaused ? WidgetColor.amber : WidgetColor.blue)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VisitTimerLabel(state: context.state, showsHours: true)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.propertyName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(detailLine(context.attributes, context.state))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VisitActionButtons(state: context.state)
                }
            } compactLeading: {
                MapleMark(size: 20)
            } compactTrailing: {
                VisitTimerLabel(state: context.state, showsHours: false)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.isPaused ? WidgetColor.amber : .white)
                    .frame(maxWidth: 52)
            } minimal: {
                MapleMark(size: 20)
            }
            .widgetURL(visitURL)
            .keylineTint(WidgetColor.red)
        }
    }

    private func detailLine(_ attributes: VisitActivityAttributes, _ state: VisitActivityAttributes.ContentState) -> String {
        var parts: [String] = []
        if let start = state.workStartedAt {
            parts.append("Started \(start.formatted(date: .omitted, time: .shortened))")
        }
        let pausedMinutes = Int(state.pausedTotal / 60)
        if pausedMinutes > 0 { parts.append("paused \(pausedMinutes) min") }
        parts.append("est. \(attributes.estimateMinutes) min")
        return parts.joined(separator: " · ")
    }
}

/// Lock Screen presentation.
struct VisitLockScreenView: View {
    let attributes: VisitActivityAttributes
    let state: VisitActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                MapleMark(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.propertyName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(state.stateLabel) · stop \(attributes.stopNumber) of \(attributes.stopCount)")
                        .font(.caption)
                        .foregroundStyle(state.isPaused ? WidgetColor.amber : Color.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                VisitTimerLabel(state: state, showsHours: false)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            VisitActionButtons(state: state)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// Working time: live count-up while working, frozen while paused, a prompt before work starts.
struct VisitTimerLabel: View {
    let state: VisitActivityAttributes.ContentState
    var showsHours: Bool

    var body: some View {
        Group {
            if state.isPaused {
                Text(Self.format(state.frozenElapsed))
            } else if let start = state.adjustedStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: showsHours)
            } else {
                Text("On site")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Pause / Resume (App Intents, run in the app) and After Photos (opens the visit).
struct VisitActionButtons: View {
    let state: VisitActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            if state.workStartedAt != nil {
                if state.isPaused {
                    Button(intent: ResumeVisitIntent()) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .tint(WidgetColor.blue)
                } else {
                    Button(intent: PauseVisitIntent()) {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .tint(.white.opacity(0.25))
                }
            }
            if let visitURL {
                Link(destination: visitURL) {
                    Label(state.workStartedAt == nil ? "Open Visit" : "After Photos", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(WidgetColor.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.semibold))
    }
}

/// Small red rounded square with a leaf — the MapleCore mark.
struct MapleMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(WidgetColor.red, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Lock Screen", as: .content, using: VisitActivityAttributes(visitID: "preview", propertyName: "Islington Medical", stopNumber: 6, stopCount: 9, estimateMinutes: 45)) {
    VisitLiveActivity()
} contentStates: {
    VisitActivityAttributes.ContentState(stateLabel: "Working", isPaused: false, workStartedAt: Date().addingTimeInterval(-2538), pausedTotal: 240, pausedAt: nil)
    VisitActivityAttributes.ContentState(stateLabel: "Paused", isPaused: true, workStartedAt: Date().addingTimeInterval(-2538), pausedTotal: 0, pausedAt: Date().addingTimeInterval(-60))
}
