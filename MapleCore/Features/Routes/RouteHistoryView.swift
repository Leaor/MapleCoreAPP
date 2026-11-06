import SwiftUI
import MapleCoreKit

/// Past routes grouped by day, searchable by route or crew.
struct RouteHistoryView: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            RouteHistoryContent(query: query)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Route History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Route or crew")
    }
}

/// Filter chips + day groups. Embedded in the Routes tab's History segment and in `RouteHistoryView`.
struct RouteHistoryContent: View {
    var query: String = ""

    @Environment(AppStore.self) private var store
    @State private var crewFilter: Crew.ID? = nil
    @State private var issuesOnly = false

    private var days: [RoutesDayGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.pastRoutesByDay.compactMap { entry -> RoutesDayGroup? in
            let routes = entry.routes.filter { matches($0, query: q) }
            return routes.isEmpty ? nil : RoutesDayGroup(id: entry.day, routes: routes)
        }
    }

    private func matches(_ route: Route, query q: String) -> Bool {
        if let crewFilter, route.crewID != crewFilter { return false }
        if issuesOnly && !route.hasHistoryIssue { return false }
        guard !q.isEmpty else { return true }
        if route.name.lowercased().contains(q) { return true }
        return store.routesCrewLine(route.crewID).lowercased().contains(q)
    }

    var body: some View {
        let days = self.days
        VStack(alignment: .leading, spacing: Space.l) {
            chips
            if days.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No matching routes",
                    message: query.isEmpty && crewFilter == nil && !issuesOnly
                        ? "Finished routes will appear here."
                        : "Try another crew, or turn off Issues only."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: Space.l) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionHeader(Fmt.longDay(day.id))
                            CardList(data: day.routes, inset: 0) { route in
                                NavigationLink(value: AppDestination.routeSummary(route.id)) {
                                    RouteHistoryRow(route: route)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
            }
        }
        .sensoryFeedback(.selection, trigger: crewFilter)
        .sensoryFeedback(.selection, trigger: issuesOnly)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                RoutesFilterChip(title: "All crews", isOn: crewFilter == nil) {
                    crewFilter = nil
                }
                ForEach(store.crews) { crew in
                    RoutesFilterChip(title: crew.name, isOn: crewFilter == crew.id) {
                        crewFilter = crewFilter == crew.id ? nil : crew.id
                    }
                }
                RoutesFilterChip(title: "Issues only", isOn: issuesOnly, symbol: "exclamationmark.triangle") {
                    issuesOnly.toggle()
                }
            }
            .padding(.horizontal, Space.l)
        }
    }
}

private struct RouteHistoryRow: View {
    let route: Route
    @Environment(AppStore.self) private var store

    private var detail: String {
        var parts: [String] = []
        if let crew = store.crew(route.crewID) { parts.append(crew.name) }
        parts.append("\(route.completedCount) of \(route.stops.count) stops")
        if let minutes = route.elapsedMinutes { parts.append(Fmt.duration(minutes: minutes)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .numeric()
            }
            Spacer(minLength: Space.s)
            RouteStatePill(badge: route.historyBadge())
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Route History") {
    NavigationStack {
        RouteHistoryView()
            .appDestinations()
    }
    .previewEnvironment()
}
