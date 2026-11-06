import SwiftUI
import MapKit
import MapleCoreKit

/// Shared field actions so Today, Route and Stop behave identically (preview no-ops, haptics, toasts).
@MainActor
struct FieldActions {
    let store: AppStore
    let model: AppModel
    let toasts: ToastCenter

    /// In Admin "Preview Field Mode" every write is a no-op: say so instead of silently doing nothing.
    func blockedByPreview() -> Bool {
        guard store.isReadOnly else { return false }
        toasts.show("Preview only — nothing is saved", symbol: "eye", tone: .blue)
        return true
    }

    /// Marks arrival at a stop and opens the visit cover.
    func arrive(routeID: Route.ID, stopID: RouteStop.ID) {
        if let active = store.activeVisit {
            if active.stopID == stopID {
                model.isVisitPresented = true
            } else {
                Haptics.warning()
                toasts.show("Finish your visit at \(active.propertyName) first", symbol: "exclamationmark.circle", tone: .amber)
            }
            return
        }
        if blockedByPreview() { return }
        guard store.arrive(routeID: routeID, stopID: stopID) != nil else {
            toasts.show("This stop isn't available on this iPhone", symbol: "exclamationmark.circle", tone: .amber)
            return
        }
        Haptics.impact(.medium)
        model.isVisitPresented = true
    }

    /// "On My Way": marks the stop en route.
    func beginTravel(routeID: Route.ID, stopID: RouteStop.ID) {
        if blockedByPreview() { return }
        store.beginTravel(routeID: routeID, stopID: stopID)
        Haptics.impact(.light)
    }

    func startShift() {
        if blockedByPreview() { return }
        store.startShift(truck: store.fieldCrew?.truck ?? "")
        Haptics.success()
        toasts.show(store.isOnline ? "Shift started" : "Shift started · saved on this iPhone")
    }

    func endShift() {
        if blockedByPreview() { return }
        let worked = store.activeFieldShift.map { store.now.timeIntervalSince($0.startedAt) } ?? 0
        store.endShift()
        Haptics.success()
        toasts.show("Shift ended · \(Fmt.shiftDuration(worked))")
    }

    /// Opens (or starts) the direct thread with the manager and pushes it.
    func messageManager() {
        guard let id = store.fieldManagerThreadID() else {
            if !blockedByPreview() {
                toasts.show("Couldn't open a conversation with your manager", symbol: "exclamationmark.circle", tone: .amber)
            }
            return
        }
        model.push(.thread(id))
    }

    /// Opens the crew thread ("Office").
    func messageOffice(crewID: Crew.ID?) {
        if let crewID, let thread = store.crewThread(for: crewID) {
            model.push(.thread(thread.id))
        } else {
            messageManager()
        }
    }
}

/// Apple Maps hand-off. Directions use the property's stored coordinates.
@MainActor
enum FieldMaps {
    static func openDirections(to property: Property) {
        let coordinate = CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = property.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// "Synced" / "3 waiting" / "Offline" chip that opens Sync & Uploads.
struct FieldSyncChip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationLink(value: AppDestination.syncQueue) {
            Pill(text: text, tone: tone, symbol: symbol)
                .frame(minHeight: Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync status: \(text)")
        .accessibilityHint("Opens Sync and Uploads")
    }

    private var waiting: Int { store.fieldWaitingUploadCount }

    private var text: String {
        if !store.isOnline { return waiting > 0 ? "Offline · \(waiting) waiting" : "Offline" }
        if !store.attentionOutbox.isEmpty { return "\(store.attentionOutbox.count) need you" }
        if waiting > 0 { return "\(waiting) waiting" }
        return "Synced"
    }

    private var tone: Tone {
        if !store.isOnline { return .amber }
        if !store.attentionOutbox.isEmpty { return .red }
        return waiting > 0 ? .blue : .green
    }

    private var symbol: String {
        if !store.isOnline { return "wifi.slash" }
        if !store.attentionOutbox.isEmpty { return "exclamationmark.circle" }
        return waiting > 0 ? "arrow.triangle.2.circlepath" : "checkmark"
    }
}

/// Live "2 h 38 m" shift duration, refreshed every minute.
struct ShiftDurationText: View {
    var startedAt: Date
    var prefix: String = ""

    var body: some View {
        TimelineView(.everyMinute) { context in
            let interval = max(0, context.date.timeIntervalSince(startedAt))
            Text(prefix + Fmt.shiftDuration(interval))
                .numeric()
                .accessibilityLabel(prefix + Fmt.spokenDuration(interval))
        }
    }
}

/// Live visit working timer, refreshed every second.
struct VisitElapsedText: View {
    var session: VisitSession
    var baseSize: CGFloat = 44

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.workingElapsed(at: context.date)
            TimerText(text: Fmt.timer(elapsed), baseSize: baseSize)
                .accessibilityLabel("Working time \(Fmt.spokenDuration(elapsed))")
        }
    }
}

/// Formatting helpers for stop lines.
enum FieldText {
    /// "ETA 9:40 · 8 min" (minutes away only while it's in the future).
    static func eta(_ stop: RouteStop, now: Date) -> String? {
        guard let eta = stop.eta else { return nil }
        let minutes = Int((eta.timeIntervalSince(now) / 60).rounded())
        if minutes > 0 && minutes < 120 { return "ETA \(Fmt.clock(eta)) · \(minutes) min" }
        return "ETA \(Fmt.clock(eta))"
    }

    /// Line under a remaining stop: "ETA 10:45 · 1 h 10 min job".
    static func remainingDetail(_ stop: RouteStop) -> String {
        var parts: [String] = []
        if stop.status == .delayed { parts.append("Delayed") }
        if let eta = stop.eta { parts.append("ETA \(Fmt.clock(eta))") }
        parts.append("\(Fmt.duration(minutes: stop.estimatedMinutes)) job")
        return parts.joined(separator: " · ")
    }

    /// Line under a finished stop: "Done 9:12 · 32 min" or "Skipped · Gate locked".
    static func finishedDetail(_ stop: RouteStop) -> String {
        if stop.status == .skipped { return "Skipped" + (stop.skipReason.map { " · \($0)" } ?? "") }
        var parts = ["Done"]
        if let completed = stop.completedAt { parts = ["Done \(Fmt.clock(completed))"] }
        if let actual = stop.actualMinutes { parts.append(Fmt.duration(minutes: actual)) }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// Uppercase caption like `captionStyle()` but in a given colour (captionStyle fixes ink3).
    func fieldCaption(_ color: Color) -> some View {
        font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.3)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}
