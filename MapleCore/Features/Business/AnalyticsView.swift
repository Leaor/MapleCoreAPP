import SwiftUI
import Charts
import MapleCoreKit

/// Operational analytics: KPIs with deltas, visits chart and a by-crew table.
struct AnalyticsView: View {
    var body: some View {
        BizCapabilityGate(capability: .analytics, title: "Analytics aren't available", message: "Operational analytics are visible to owners and managers.") {
            AnalyticsContent()
        }
        .navigationTitle("Analytics")
    }
}

private struct AnalyticsContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var range: AnalyticsRange = .week

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Picker("Range", selection: $range) {
                    ForEach(AnalyticsRange.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: range)

                if let snapshot = store.analytics[range] {
                    kpiGrid(snapshot)
                    AnalyticsChartCard(snapshot: snapshot, range: range)
                    crewTable(snapshot)
                } else {
                    EmptyStateView(symbol: "chart.bar", title: "No figures yet", message: "Figures appear once visits are completed in this period.")
                }

                Text("Figures from preview fixtures")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
            }
            .padding(Space.l)
            .motionAnimation(value: range)
        }
        .screenBackground()
    }

    // MARK: KPIs

    private var priorLabel: String {
        switch range {
        case .week: "prior 7 days"
        case .month: "prior month"
        case .season: "last season"
        }
    }

    private func kpiGrid(_ s: AnalyticsSnapshot) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Space.m) {
            AnalyticsKPI(title: "Visits completed", value: Fmt.number(s.visitsCompleted),
                         delta: percentDelta(s.visitsChange, suffix: "vs \(priorLabel)", higherIsBetter: true))
            AnalyticsKPI(title: "Arrived on time", value: Fmt.percent(s.onTimeRate),
                         delta: pointDelta(s.onTimeChange))
            AnalyticsKPI(title: "Time vs estimate", value: "\(s.minutesVsEstimate >= 0 ? "+" : "")\(s.minutesVsEstimate) min",
                         delta: minuteDelta(s.minutesVsEstimateChange))
            AnalyticsKPI(title: "Billed", value: Fmt.moneyWhole(s.billed),
                         delta: percentDelta(s.billedChange, suffix: "", higherIsBetter: true))
        }
    }

    private func percentDelta(_ change: Double, suffix: String, higherIsBetter: Bool) -> AnalyticsDelta {
        let pct = Int((abs(change) * 100).rounded())
        guard pct > 0 else { return AnalyticsDelta(text: "Same as \(priorLabel)", spoken: "Same as \(priorLabel)", direction: .flat, tone: .neutral) }
        let up = change > 0
        let text = "\(pct)%\(suffix.isEmpty ? "" : " \(suffix)")"
        return AnalyticsDelta(text: text, spoken: "\(up ? "Up" : "Down") \(pct) percent \(suffix)", direction: up ? .up : .down,
                              tone: up == higherIsBetter ? .green : .amber)
    }

    private func pointDelta(_ change: Double) -> AnalyticsDelta {
        let points = Int((abs(change) * 100).rounded())
        guard points > 0 else { return AnalyticsDelta(text: "Same as \(priorLabel)", spoken: "Same as \(priorLabel)", direction: .flat, tone: .neutral) }
        let up = change > 0
        return AnalyticsDelta(text: "\(points) pt vs \(priorLabel)", spoken: "\(up ? "Up" : "Down") \(points) points versus \(priorLabel)",
                              direction: up ? .up : .down, tone: up ? .green : .amber)
    }

    private func minuteDelta(_ change: Int) -> AnalyticsDelta {
        guard change != 0 else { return AnalyticsDelta(text: "Same as \(priorLabel)", spoken: "Same as \(priorLabel)", direction: .flat, tone: .neutral) }
        let up = change > 0
        return AnalyticsDelta(text: "\(abs(change)) min per visit", spoken: "\(up ? "Up" : "Down") \(abs(change)) minutes per visit",
                              direction: up ? .up : .down, tone: up ? .amber : .green)
    }

    // MARK: Crew table

    private func crewTable(_ s: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("By crew")
            VStack(spacing: 0) {
                HStack {
                    Text("Crew").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Visits").frame(minWidth: 56, alignment: .trailing)
                    Text("On time").frame(minWidth: 72, alignment: .trailing)
                    Spacer().frame(width: 14)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .padding(.vertical, Space.s)
                .accessibilityHidden(true)
                Divider()
                ForEach(s.crews) { row in
                    NavigationLink(value: AppDestination.crews) {
                        AnalyticsCrewRow(row: row)
                    }
                    .buttonStyle(.plain)
                    if row.id != s.crews.last?.id { Divider() }
                }
            }
            .padding(.horizontal, Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

struct AnalyticsDelta {
    enum Direction { case up, down, flat }
    var text: String
    var spoken: String
    var direction: Direction
    var tone: Tone
}

/// KPI tile: title, big value, coloured delta with arrow + text.
private struct AnalyticsKPI: View {
    let title: String
    let value: String
    let delta: AnalyticsDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
            Text(value)
                .font(.title2.weight(.bold))
                .numeric()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if delta.direction != .flat {
                    Text(delta.direction == .up ? "▲" : "▼")
                }
                Text(delta.text)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(delta.tone.foreground)
        }
        .padding(Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityValue(delta.spoken)
    }
}

/// Visits per period, latest bar in red.
private struct AnalyticsChartCard: View {
    let snapshot: AnalyticsSnapshot
    let range: AnalyticsRange

    private var title: String {
        switch range {
        case .week: "Visits per day"
        case .month: "Visits per week"
        case .season: "Visits per month"
        }
    }

    private var caption: String {
        switch range {
        case .week: "Today in red"
        case .month: "This week in red"
        case .season: "This month in red"
        }
    }

    private func label(at index: Int) -> String {
        snapshot.dayLabels.indices.contains(index) ? snapshot.dayLabels[index] : ""
    }

    private var summary: String {
        snapshot.dailyVisits.enumerated().map { index, value in
            "\(label(at: index)) \(value)"
        }
        .joined(separator: ", ")
    }

    var body: some View {
        let values = snapshot.dailyVisits
        let lastIndex = values.count - 1
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(caption).font(.footnote).foregroundStyle(Palette.ink3)
            }
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    BarMark(
                        x: .value("Period", String(index)),
                        y: .value("Visits", value)
                    )
                    .foregroundStyle(index == lastIndex ? Palette.red : Palette.ink)
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 2) {
                        Text("\(value)")
                            .font(.caption2)
                            .numeric()
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
            .chartXAxis {
                AxisMarks { axisValue in
                    AxisValueLabel {
                        Text(label(at: Int(axisValue.as(String.self) ?? "") ?? -1))
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(summary)
        }
        .cardStyle()
    }
}

/// One crew row: visits and on-time rate (amber below 90%).
private struct AnalyticsCrewRow: View {
    let row: AnalyticsSnapshot.CrewRow

    var body: some View {
        let isLow = row.onTimeRate < 0.9
        HStack {
            Text(row.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.number(row.visits))
                .numeric()
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 56, alignment: .trailing)
            HStack(spacing: 3) {
                if isLow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(Fmt.percent(row.onTimeRate)).numeric()
            }
            .foregroundStyle(isLow ? Palette.amber : Palette.ink)
            .frame(minWidth: 72, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .frame(width: 14)
                .accessibilityHidden(true)
        }
        .font(.body)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.visits) visits, \(Fmt.percent(row.onTimeRate)) on time\(isLow ? ", below target" : "")")
    }
}

#Preview("Analytics") {
    NavigationStack {
        AnalyticsView().appDestinations()
    }
    .previewEnvironment()
}
