import SwiftUI
import MapleCoreKit

/// Completion summary for a route: stats, proof of work, issues, review progress and stop timeline.
struct RouteSummaryView: View {
    let routeID: Route.ID

    @Environment(AppStore.self) private var store

    var body: some View {
        if let route = store.route(routeID) {
            RouteSummaryScreen(route: route)
        } else {
            MissingRecordView(title: "Route not available")
        }
    }
}

private struct SummaryStat: Identifiable {
    let id: String
    let value: String
    let label: String
    let tone: Tone?
}

private struct RouteSummaryScreen: View {
    let route: Route

    @Environment(AppStore.self) private var store
    @State private var showsTimeline = false

    private var isComplete: Bool { route.state == .completed }
    private var canReview: Bool { store.capabilities.contains(.visitReview) }

    var body: some View {
        let records = store.routesVisitRecords(for: route)
        let pending = store.routesPendingReviews(for: route)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                statGrid
                proofOfWork(records)
                issuesCard
                reviewCard(pending)
                timelineSection
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle("Route Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: reportText, subject: Text("\(route.name) route report")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share route report")
            }
        }
    }

    // MARK: Header

    private var timeRange: String {
        if let finished = route.finishedAt {
            return "\(Fmt.clock(route.startTime))–\(Fmt.time(finished))"
        }
        return "Started \(Fmt.time(route.startTime))"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let crew = store.crew(route.crewID) { parts.append(crew.name) }
        parts.append(Fmt.longDay(route.date))
        parts.append(timeRange)
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "clock.fill")
                .font(.largeTitle)
                .foregroundStyle(isComplete ? Palette.green : Palette.blue)
                .accessibilityHidden(true)
            Text(isComplete ? "\(route.name) complete" : "\(route.name) · so far")
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .numeric()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Stats

    private var stats: [SummaryStat] {
        var result: [SummaryStat] = [
            SummaryStat(id: "stops", value: "\(route.completedCount) / \(route.stops.count)", label: "Stops completed", tone: nil)
        ]
        if let total = route.elapsedMinutes {
            let working = max(0, total - route.driveMinutes)
            result.append(SummaryStat(id: "work", value: Fmt.compactDuration(minutes: working), label: "Working time", tone: nil))
        } else {
            result.append(SummaryStat(id: "work", value: Fmt.compactDuration(minutes: route.actualWorkMinutes), label: "Working time so far", tone: nil))
        }
        result.append(SummaryStat(id: "drive", value: Fmt.compactDuration(minutes: route.driveMinutes), label: "Driving", tone: nil))
        let planned = route.plannedMinutes ?? (route.workMinutes + route.driveMinutes)
        if let total = route.elapsedMinutes {
            let delta = total - planned
            let value: String
            if delta == 0 {
                value = "On plan"
            } else if delta > 0 {
                value = "+\(Fmt.compactDuration(minutes: delta))"
            } else {
                value = "−\(Fmt.compactDuration(minutes: -delta))"
            }
            result.append(SummaryStat(id: "plan", value: value, label: "vs. plan (\(Fmt.compactDuration(minutes: planned)))", tone: delta > 0 ? .amber : .green))
        } else {
            result.append(SummaryStat(id: "plan", value: Fmt.compactDuration(minutes: planned), label: "Planned", tone: nil))
        }
        return result
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Space.m)], spacing: Space.m) {
            ForEach(stats) { stat in
                StatTile(value: stat.value, label: stat.label, tone: stat.tone)
                    .cardStyle()
            }
        }
    }

    // MARK: Proof, issues, review

    private func proofOfWork(_ records: [VisitRecord]) -> some View {
        let waiting = records.flatMap(\.photos).filter { $0.receivedAt == nil }.count
        let detail: String
        let tone: Tone
        if route.photoCount == 0 {
            detail = "No photos yet"
            tone = .neutral
        } else if waiting > 0 {
            detail = "\(Fmt.plural(route.photoCount, "photo")) · \(waiting) waiting to upload"
            tone = .amber
        } else {
            detail = "\(Fmt.plural(route.photoCount, "photo")) uploaded"
            tone = .green
        }
        return HStack(spacing: Space.m) {
            Image(systemName: "camera.fill")
                .foregroundStyle(tone.foreground)
                .frame(width: 36, height: 36)
                .background(tone.background, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Proof of work")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var issuesCard: some View {
        if route.issuesReported.isEmpty {
            NoticeCard(symbol: "checkmark.seal", text: "No issues reported", tone: .green)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                Label(Fmt.plural(route.issuesReported.count, "issue") + " reported", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Palette.amber)
                ForEach(route.issuesReported, id: \.self) { issue in
                    Text(issue)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .cardStyle()
            .accessibilityElement(children: .combine)
        }
    }

    private func reviewCard(_ pending: [VisitRecord]) -> some View {
        let total = max(route.completedCount, 1)
        let reviewed = min(route.reviewedCount, total)
        return VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("\(route.reviewedCount) of \(route.completedCount) visits reviewed")
                    .font(.headline)
                    .numeric()
                ProgressView(value: Double(reviewed), total: Double(total))
                    .tint(Palette.green)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)

            if let first = pending.first {
                if canReview {
                    NavigationLink(value: AppDestination.review(first.id)) {
                        Text("Review \(Fmt.plural(pending.count, "Visit"))")
                    }
                    .buttonStyle(.mc(.primary))
                } else {
                    Text("\(Fmt.plural(pending.count, "visit")) waiting for a supervisor.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            } else {
                Label("All reviewed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.green)
            }
        }
        .cardStyle()
    }

    // MARK: Timeline

    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for (index, stop) in route.stops.enumerated() {
            entries.append(TimelineEntry(number: index + 1, stop: stop))
        }
        return entries
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                withMotion { showsTimeline.toggle() }
            } label: {
                Label(showsTimeline ? "Hide Stop Timeline" : "View Stop Timeline", systemImage: "list.number")
            }
            .buttonStyle(.mc(.secondary))

            if showsTimeline {
                CardList(data: timelineEntries, inset: 52) { entry in
                    NavigationLink(value: AppDestination.stop(route.id, entry.id)) {
                        StopRow(
                            number: entry.number,
                            title: store.property(entry.stop.propertyID)?.name ?? "Unknown property",
                            detail: RoutesText.stopDetail(entry.stop, isNext: false, now: store.now),
                            status: entry.stop.status
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Report

    private var reportText: String {
        var lines: [String] = []
        lines.append("\(route.name) — \(isComplete ? "complete" : "in progress")")
        lines.append(subtitle)
        lines.append("")
        for stat in stats {
            lines.append("\(stat.label): \(stat.value)")
        }
        lines.append("Photos: \(route.photoCount)")
        lines.append("Visits reviewed: \(route.reviewedCount) of \(route.completedCount)")
        if !route.issuesReported.isEmpty {
            lines.append("")
            lines.append("Issues:")
            for issue in route.issuesReported { lines.append("• \(issue)") }
        }
        lines.append("")
        lines.append("Stops:")
        for (index, stop) in route.stops.enumerated() {
            let name = store.property(stop.propertyID)?.name ?? "Unknown property"
            lines.append("\(index + 1). \(name) — \(RoutesText.stopDetail(stop, isNext: false, now: store.now))")
        }
        return lines.joined(separator: "\n")
    }
}

private struct TimelineEntry: Identifiable {
    let number: Int
    let stop: RouteStop
    var id: RouteStop.ID { stop.id }
}

#Preview("Route Summary") {
    NavigationStack {
        RouteSummaryView(routeID: Fixtures.ID.routeEarly)
            .appDestinations()
    }
    .previewEnvironment()
}
