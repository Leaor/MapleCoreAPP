import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
/// Live Activity for the visit in progress. Compiled into the app (which starts and updates it)
/// and the widget extension (which renders it). Elapsed time is derived from stored dates, so the
/// Lock Screen counts on its own with `Text(timerInterval:)` and never needs a push per second.
struct VisitActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "On site", "Working", "Paused".
        var stateLabel: String
        var isPaused: Bool
        /// When work started (device clock). Nil while the crew is taking before photos.
        var workStartedAt: Date?
        /// Total of finished pauses. The open pause (if any) starts at `pausedAt`.
        var pausedTotal: TimeInterval
        var pausedAt: Date?

        /// The date a count-up timer should start from so it shows working time only.
        var adjustedStart: Date? {
            workStartedAt.map { $0.addingTimeInterval(pausedTotal) }
        }

        /// Working time frozen at the moment the pause began.
        var frozenElapsed: TimeInterval {
            guard let start = workStartedAt else { return 0 }
            let end = pausedAt ?? Date()
            return max(0, end.timeIntervalSince(start) - pausedTotal)
        }
    }

    var visitID: String
    var propertyName: String
    var stopNumber: Int
    var stopCount: Int
    var estimateMinutes: Int

    init(visitID: String, propertyName: String, stopNumber: Int, stopCount: Int, estimateMinutes: Int) {
        self.visitID = visitID
        self.propertyName = propertyName
        self.stopNumber = stopNumber
        self.stopCount = stopCount
        self.estimateMinutes = estimateMinutes
    }
}
#endif
