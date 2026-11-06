import SwiftUI
import MapleCoreKit

/// The field user's crew's past routes. Each row expands inline to its stops and times; field users
/// never see the admin route summary (review data, issues).
struct ShiftHistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var expanded: Set<Route.ID> = []

    var body: some View {
        let routes = store.fieldPastRoutes
        Group {
            if routes.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "No past shifts yet",
                        message: "Finished routes for your crew will appear here."
                    )
                }
            } else {
                List {
                    Section {
                        ForEach(routes) { route in
                            DisclosureGroup(isExpanded: binding(for: route.id)) {
                                ForEach(route.stops) { stop in
                                    HistoryStopRow(
                                        number: store.stopNumber(stop.id, in: route),
                                        name: store.property(stop.propertyID)?.name ?? "Stop",
                                        stop: stop
                                    )
                                }
                            } label: {
                                ShiftHistoryRow(route: route, now: store.now)
                            }
                            .tint(Palette.ink2)
                            .listRowBackground(Palette.surface)
                        }
                    } footer: {
                        Text("Hours run from route start to the last stop finished.")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .screenBackground()
        .navigationTitle("Shift History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for id: Route.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct ShiftHistoryRow: View {
    var route: Route
    var now: Date

    private var hours: String {
        guard let finished = route.finishedAt else { return "—" }
        let minutes = Int(finished.timeIntervalSince(route.startTime) / 60)
        return Fmt.duration(minutes: max(0, minutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.relativeDay(route.date, now: now))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            Text(route.name)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { stats }
                VStack(alignment: .leading, spacing: 2) { stats }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink2)
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stats: some View {
        Text("\(route.completedCount) of \(route.stops.count) stops")
        if route.skippedCount > 0 {
            Text("· \(route.skippedCount) skipped").foregroundStyle(Palette.amber)
        }
        Text("· \(hours)").numeric()
    }
}

private struct HistoryStopRow: View {
    var number: Int
    var name: String
    var stop: RouteStop

    var body: some View {
        HStack(spacing: Space.m) {
            StopNumberBadge(number: number, status: stop.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stop.status == .skipped ? Palette.ink3 : Palette.ink)
                Text(FieldText.finishedDetail(stop))
                    .font(.footnote)
                    .foregroundStyle(stop.status == .skipped ? Palette.amber : Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(number), \(name), \(FieldText.finishedDetail(stop))")
    }
}

#if DEBUG
#Preview("Shift history") {
    NavigationStack {
        ShiftHistoryView()
    }
    .previewEnvironment(role: .field)
}
#endif
