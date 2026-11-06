import Foundation
import MapleCoreKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Mirrors the active visit into a Live Activity (Lock Screen + Dynamic Island).
/// `FieldShell` calls `sync(_:)` on launch and whenever `store.activeVisit` changes; the controller
/// only talks to ActivityKit when the visible content actually changes.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private init() {}

    #if canImport(ActivityKit)
    private var activity: Activity<VisitActivityAttributes>?
    private var lastState: VisitActivityAttributes.ContentState?
    #endif

    func sync(_ session: VisitSession?) {
        #if canImport(ActivityKit)
        guard let session, session.isActive else {
            endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = Self.contentState(for: session)

        // Re-attach to an activity that survived an app relaunch.
        if activity == nil {
            activity = Activity<VisitActivityAttributes>.activities.first { $0.attributes.visitID == session.id }
            lastState = activity?.content.state
        }

        // A different visit: end whatever is showing before starting the new one.
        if let current = activity, current.attributes.visitID != session.id {
            endAll()
        }

        if let current = activity {
            guard state != lastState else { return }
            lastState = state
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await current.update(content) }
        } else {
            let attributes = VisitActivityAttributes(
                visitID: session.id,
                propertyName: session.propertyName,
                stopNumber: session.stopNumber,
                stopCount: session.stopCount,
                estimateMinutes: session.estimateMinutes
            )
            do {
                activity = try Activity<VisitActivityAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                lastState = state
            } catch {
                // Live Activities are a convenience; the visit itself is unaffected.
                activity = nil
                lastState = nil
            }
        }
        #endif
    }

    #if canImport(ActivityKit)
    private func endAll() {
        let running = Activity<VisitActivityAttributes>.activities
        activity = nil
        lastState = nil
        guard !running.isEmpty else { return }
        Task {
            for item in running {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func contentState(for session: VisitSession) -> VisitActivityAttributes.ContentState {
        let finishedPauses = session.pauses.filter { $0.end != nil }
        let pausedTotal = finishedPauses.reduce(0) { total, pause in
            total + pause.duration(at: pause.end ?? pause.start)
        }
        return VisitActivityAttributes.ContentState(
            stateLabel: session.state.label,
            isPaused: session.state == .paused,
            workStartedAt: session.workStartedAt,
            pausedTotal: pausedTotal,
            pausedAt: session.currentPause?.start
        )
    }
    #endif
}
