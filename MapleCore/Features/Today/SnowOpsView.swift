import SwiftUI
import Charts
import MapleCoreKit

/// Live snow event: accumulation, short-range rate, progress and the plow routes out now.
struct SnowOpsView: View {
    @Environment(AppStore.self) private var store
    @State private var showDispatch = false

    var body: some View {
        Group {
            if let event = store.snowEvent {
                content(event)
            } else {
                ScrollView {
                    EmptyStateView(symbol: "snowflake",
                                   title: "No active snow event",
                                   message: "When accumulation reaches a contract trigger, the event and its plow routes show up here. Outlook: \(store.weather.outlook).")
                }
                .screenBackground()
            }
        }
        .navigationTitle("Snow Operations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDispatch) {
            SnowDispatchSheet()
        }
    }

    private func content(_ event: SnowEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                SnowConditionsCard(event: event)
                SnowProgressSection(event: event)
                SnowRoutesSection(title: "Active plow routes", routes: event.activeRoutes, emptyText: "No plow routes dispatched yet.")
                if !event.pendingRoutes.isEmpty {
                    SnowRoutesSection(title: "Not dispatched", routes: event.pendingRoutes, emptyText: "")
                }
                dispatchButton(event)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.l)
        }
        .screenBackground()
        .refreshable { store.scheduleSync() }
    }

    @ViewBuilder
    private func dispatchButton(_ event: SnowEvent) -> some View {
        let dispatchable = event.pendingRoutes.filter { !$0.isBelowTrigger }
        if store.capabilities.contains(.snowDispatch) {
            VStack(spacing: Space.s) {
                Button {
                    showDispatch = true
                } label: {
                    Label("Dispatch More Crews", systemImage: "snowflake")
                }
                .buttonStyle(.mc(.primary))
                .disabled(dispatchable.isEmpty)
                if dispatchable.isEmpty {
                    Text("Every route that has reached its trigger is already out.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            NoticeCard(symbol: "lock", text: "Dispatching crews needs an admin or manager.", tone: .neutral)
        }
    }
}

// MARK: - Conditions

private struct SnowConditionsCard: View {
    var event: SnowEvent

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Label("Event #\(event.number) · live since \(Fmt.time(event.startedAt)) \(Fmt.shortDate(event.startedAt))", systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.redText)
                Spacer(minLength: Space.s)
                Pill(text: "Preview data", tone: .neutral)
            }
            HStack(alignment: .bottom, spacing: Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(event.groundCm) cm")
                        .font(.largeTitle.weight(.bold))
                        .numeric()
                    Text("on the ground · \(event.temperatureC)° \(event.condition)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Space.s)
                SnowRateChart(rates: event.hourlyRate)
                    .frame(width: 128, height: 64)
            }
            Text(event.forecast)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            if !event.warning.isEmpty {
                NoticeCard(symbol: "exclamationmark.triangle.fill", text: event.warning, tone: .amber)
            }
        }
        .cardStyle()
    }
}

private struct SnowRateChart: View {
    var rates: [Double]

    private struct Point: Identifiable {
        let id: Int
        let rate: Double
    }

    private var points: [Point] { rates.enumerated().map { Point(id: $0.offset, rate: $0.element) } }
    private var peak: Double { rates.max() ?? 0 }

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Hour", point.id), y: .value("cm per hour", point.rate))
                .foregroundStyle(point.rate == peak ? Palette.blue : Palette.blue.opacity(0.45))
                .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let first = rates.first, let last = rates.last else { return "No snowfall rate data" }
        return String(format: "Snowfall rate per hour: %.1f centimetres now, peaking at %.1f, easing to %.1f", first, peak, last)
    }
}

// MARK: - Progress

private struct SnowProgressSection: View {
    var event: SnowEvent

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Progress")
            VStack(alignment: .leading, spacing: Space.l) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.l) { metrics }
                    VStack(alignment: .leading, spacing: Space.l) { metrics }
                }
                Divider()
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Salt: \(formatTonnes(event.saltUsedTonnes)) of \(formatTonnes(event.saltTotalTonnes)) used")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    ProgressView(value: min(event.saltUsedTonnes, event.saltTotalTonnes), total: max(event.saltTotalTonnes, 0.1))
                        .tint(Palette.amber)
                }
                .accessibilityElement(children: .combine)
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var metrics: some View {
        ProgressMetric(title: "Priority commercial", done: event.priorityDone, total: event.priorityTotal, caption: "Due clear by \(event.priorityDeadline)", tint: Palette.red)
        ProgressMetric(title: "All properties", done: event.allDone, total: event.allTotal, caption: "\(event.allTotal - event.allDone) still to clear", tint: Palette.blue)
    }

    private func formatTonnes(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f t", value) : String(format: "%.1f t", value)
    }
}

private struct ProgressMetric: View {
    var title: String
    var done: Int
    var total: Int
    var caption: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
            Text("\(done) / \(total)").font(.title2.weight(.bold)).numeric()
            ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
                .tint(tint)
            Text(caption).font(.caption).foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Routes

private struct SnowRoutesSection: View {
    var title: String
    var routes: [SnowRoute]
    var emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title)
            if routes.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .cardStyle()
            } else {
                CardList(data: routes, inset: 0) { route in
                    SnowRouteRow(route: route)
                }
            }
        }
    }
}

private struct SnowRouteRow: View {
    @Environment(AppStore.self) private var store
    var route: SnowRoute

    private var detail: String {
        let crewName = store.crew(route.crewID)?.name ?? "No crew"
        var parts = [crewName]
        if route.isDispatched {
            parts.append("\(route.completed) of \(route.propertyCount)")
        } else {
            parts.append("\(route.propertyCount) \(route.unitLabel)")
            parts.append("est. \(Fmt.duration(minutes: route.estimatedMinutes))")
        }
        if !route.workDetail.isEmpty { parts.append(route.workDetail) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(route.code) · \(route.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                statusPill
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
            if route.isDispatched {
                ProgressView(value: Double(min(route.completed, route.propertyCount)), total: Double(max(route.propertyCount, 1)))
                    .tint(route.behindMinutes > 0 ? Palette.amber : Palette.green)
            }
        }
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusPill: some View {
        if !route.isDispatched {
            if route.isBelowTrigger {
                Pill(text: "Below trigger", tone: .neutral, symbol: "thermometer.snowflake")
            } else {
                Pill(text: "Ready", tone: .neutral, symbol: "clock")
            }
        } else if route.behindMinutes > 0 {
            Pill(text: "\(route.behindMinutes) min behind", tone: .amber, symbol: StopStatus.delayed.symbol)
        } else {
            Pill(text: "On track", tone: .green, symbol: "checkmark")
        }
    }
}

#Preview("Snow Ops") {
    NavigationStack {
        SnowOpsView()
    }
    .previewEnvironment()
}
