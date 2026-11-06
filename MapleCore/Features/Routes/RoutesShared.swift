import SwiftUI
import MapKit
import MapleCoreKit

// Small helpers shared by the Routes screens. Names are prefixed to stay clear of other feature folders.

/// Identifiable wrapper so a route ID can drive `.sheet(item:)`.
struct RouteSheetItem: Identifiable, Hashable {
    let id: Route.ID
}

/// Routes grouped under one calendar day.
struct RoutesDayGroup: Identifiable {
    let id: Date
    let routes: [Route]
}

/// A route paired with display data for a status pill.
struct RouteStateBadge: Hashable {
    var text: String
    var tone: Tone
    var symbol: String
}

extension Route {
    /// The status shown on route cards: Done 7:58 · Needs crew · Delayed 20 min · In progress · Starts 11:00.
    func stateBadge() -> RouteStateBadge {
        if state == .completed {
            let text = finishedAt.map { "Done \(Fmt.clock($0))" } ?? "Done"
            return RouteStateBadge(text: text, tone: .green, symbol: "checkmark.circle.fill")
        }
        if crewID == nil {
            return RouteStateBadge(text: "Needs crew", tone: .red, symbol: "person.crop.circle.badge.exclamationmark")
        }
        if state == .draft {
            return RouteStateBadge(text: "Draft", tone: .neutral, symbol: "pencil")
        }
        if isDelayed {
            return RouteStateBadge(text: "Delayed \(delayMinutes) min", tone: .amber, symbol: "exclamationmark.triangle.fill")
        }
        if state == .inProgress {
            return RouteStateBadge(text: "In progress", tone: .blue, symbol: "circle.lefthalf.filled")
        }
        return RouteStateBadge(text: "Starts \(Fmt.clock(startTime))", tone: .neutral, symbol: "clock")
    }

    /// Estimated end including the current delay.
    var projectedEnd: Date {
        estimatedEnd.addingTimeInterval(TimeInterval(delayMinutes * 60))
    }

    /// Minutes from start to finish, when finished.
    var elapsedMinutes: Int? {
        guard let finishedAt else { return nil }
        return max(0, Int(finishedAt.timeIntervalSince(startTime) / 60))
    }

    /// History status: Complete · N skipped · Ran late.
    func historyBadge() -> RouteStateBadge {
        if skippedCount > 0 {
            return RouteStateBadge(text: "\(skippedCount) skipped", tone: .amber, symbol: "forward.end.fill")
        }
        if delayMinutes > 0 {
            return RouteStateBadge(text: "Ran late", tone: .amber, symbol: "clock.badge.exclamationmark")
        }
        if state == .completed {
            return RouteStateBadge(text: "Complete", tone: .green, symbol: "checkmark.circle.fill")
        }
        return stateBadge()
    }

    /// True when the route had something worth a second look.
    var hasHistoryIssue: Bool {
        skippedCount > 0 || delayMinutes > 0 || !issuesReported.isEmpty
    }
}

/// Status pill for a route. Colour + icon + text.
struct RouteStatePill: View {
    var badge: RouteStateBadge

    var body: some View {
        Pill(text: badge.text, tone: badge.tone, symbol: badge.symbol)
            .accessibilityLabel("Status: \(badge.text)")
    }
}

/// Geography helpers. Uses each property's stored latitude/longitude.
enum RoutesGeo {
    static func coordinate(_ property: Property) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude)
    }

    /// Straight-line kilometres between two properties.
    static func km(_ a: Property, _ b: Property) -> Double {
        let dLat = (a.latitude - b.latitude) * 111
        let dLon = (a.longitude - b.longitude) * 111 * cos(a.latitude * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}

/// Local route planning maths for drafts that aren't saved yet. Mirrors `AppStore.proposedOrder(for:)`:
/// unfinished stops are ordered high priority first, then nearest neighbour; driving at ~30 km/h.
enum RoutesPlanning {
    static let averageKmh: Double = 30

    static func pathKm(_ stops: [RouteStop], lookup: [Property.ID: Property], from start: Property? = nil) -> Double {
        var total = 0.0
        var last = start
        for stop in stops {
            guard let p = lookup[stop.propertyID] else { continue }
            if let l = last { total += RoutesGeo.km(l, p) }
            last = p
        }
        return total
    }

    static func driveMinutes(km: Double) -> Int {
        Int((km / averageKmh * 60).rounded())
    }

    /// Proposed order and the driving minutes it saves. Finished and in-progress stops stay where they are.
    static func proposal(for stops: [RouteStop], lookup: [Property.ID: Property]) -> (stops: [RouteStop], savedMinutes: Int) {
        let fixed = stops.filter { $0.status.isFinished || $0.status == .inProgress }
        var remaining = stops.filter { !($0.status.isFinished || $0.status == .inProgress) }
        guard remaining.count > 1 else { return (stops, 0) }
        let start: Property? = fixed.last.flatMap { lookup[$0.propertyID] }
        let before = pathKm(remaining, lookup: lookup, from: start)

        var ordered = remaining.filter { $0.priority == .high }
        remaining.removeAll { $0.priority == .high }
        var cursor: Property? = ordered.last.flatMap { lookup[$0.propertyID] } ?? start
        while !remaining.isEmpty {
            var bestIndex = 0
            if let c = cursor {
                var bestDistance = Double.greatestFiniteMagnitude
                for (i, stop) in remaining.enumerated() {
                    guard let p = lookup[stop.propertyID] else { continue }
                    let d = RoutesGeo.km(c, p)
                    if d < bestDistance {
                        bestDistance = d
                        bestIndex = i
                    }
                }
            }
            let next = remaining.remove(at: bestIndex)
            ordered.append(next)
            cursor = lookup[next.propertyID]
        }
        let after = pathKm(ordered, lookup: lookup, from: start)
        let saved = max(0, Int(((before - after) / averageKmh * 60).rounded()))
        return (fixed + ordered, saved)
    }
}

/// One-line description of a stop for rows: "Next · ETA 9:40 · 45 min".
enum RoutesText {
    static func stopDetail(_ stop: RouteStop, isNext: Bool, now: Date) -> String {
        let length = Fmt.duration(minutes: stop.estimatedMinutes)
        switch stop.status {
        case .done:
            let at = stop.completedAt.map { "Done \(Fmt.clock($0))" } ?? "Done"
            if let actual = stop.actualMinutes { return "\(at) · \(Fmt.duration(minutes: actual))" }
            return at
        case .skipped:
            return "Skipped" + (stop.skipReason.map { " · \($0)" } ?? "")
        case .inProgress:
            let elapsed = stop.startedAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) } ?? 0
            return "In progress · \(elapsed) min of ~\(stop.estimatedMinutes)"
        case .enRoute:
            return "En route" + (stop.eta.map { " · ETA \(Fmt.clock($0))" } ?? "") + " · \(length)"
        case .delayed:
            let late = stop.delayMinutes > 0 ? " +\(stop.delayMinutes) min" : ""
            return "Delayed\(late)" + (stop.eta.map { " · ETA \(Fmt.clock($0))" } ?? "")
        case .pending, .urgent:
            let eta = stop.eta.map { "ETA \(Fmt.clock($0)) · " } ?? ""
            return (isNext ? "Next · " : "") + eta + length
        }
    }
}

/// Wrapping layout for chips (equipment, filters) so they reflow at large text sizes and narrow widths.
struct RoutesFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Plain chip used for equipment tags.
struct RoutesTagChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.surface2, in: Capsule())
    }
}

/// Toggle-style filter chip.
struct RoutesFilterChip: View {
    var title: String
    var isOn: Bool
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? Palette.background : Palette.ink)
            .background(isOn ? Palette.ink : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: isOn ? 0 : 1))
            .frame(minHeight: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
