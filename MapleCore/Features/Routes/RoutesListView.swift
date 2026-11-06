import SwiftUI
import MapKit
import MapleCoreKit

/// Routes tab root: Today · Upcoming · History.
struct RoutesListView: View {
    enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case upcoming = "Upcoming"
        case history = "History"
        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var range: Range = .today
    @State private var plannerDraft: Route?
    @State private var crewSheet: RouteSheetItem?
    @State private var showsMap = false

    private var canPlan: Bool { store.capabilities.contains(.routePlanning) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Picker("Route range", selection: $range) {
                    ForEach(Range.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.l)

                content
            }
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsMap = true
                } label: {
                    Image(systemName: "map")
                }
                .accessibilityLabel("Show all routes on map")
                .disabled(store.todayRoutes.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if canPlan {
                    Button {
                        plannerDraft = store.newRouteDraft(on: store.now)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New route")
                }
            }
        }
        .refreshable { store.scheduleSync() }
        .sensoryFeedback(.selection, trigger: range)
        .sheet(isPresented: $showsMap) {
            TodayRoutesMapSheet { id in
                showsMap = false
                model.push(.route(id))
            }
        }
        .sheet(item: $crewSheet) { item in
            CrewAssignSheet(routeID: item.id)
        }
        .fullScreenCover(item: $plannerDraft) { draft in
            RoutePlannerView(draft: draft)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch range {
        case .today:
            todayContent
        case .upcoming:
            upcomingContent
        case .history:
            VStack(alignment: .leading, spacing: Space.m) {
                NavigationLink(value: AppDestination.routeHistory) {
                    HStack {
                        Label("Search all route history", systemImage: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Hit.min)
                    .cardStyle(padding: Space.m)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Space.l)

                RouteHistoryContent(query: "")
            }
        }
    }

    // MARK: Today

    @ViewBuilder
    private var todayContent: some View {
        let routes = store.todayRoutes
        if routes.isEmpty {
            emptyToday
        } else {
            LazyVStack(spacing: Space.m) {
                ForEach(routes) { route in
                    RouteListCard(route: route, canAssign: canPlan) {
                        crewSheet = RouteSheetItem(id: route.id)
                    }
                }
            }
            .padding(.horizontal, Space.l)
        }
    }

    private var weekdayName: String {
        store.now.formatted(.dateTime.weekday(.wide))
    }

    private var emptyToday: some View {
        let weekday = weekdayName
        let lastSame = store.routesLastRoute(sameWeekdayAs: store.now)
        return EmptyStateView(
            symbol: "map",
            title: "No routes for \(weekday)",
            message: canPlan
                ? "Build a route from your properties, or copy last \(weekday)'s and adjust it."
                : "No routes are scheduled today. A manager or supervisor plans routes."
        ) {
            if canPlan {
                Button("Plan a Route") {
                    plannerDraft = store.newRouteDraft(on: store.now)
                }
                .buttonStyle(.mc(.primary))

                Button("Copy Last \(weekday)") {
                    guard let source = lastSame, let copy = store.copyRoute(source.id, to: store.now) else { return }
                    plannerDraft = copy
                }
                .buttonStyle(.mc(.secondary))
                .disabled(lastSame == nil)

                if lastSame == nil {
                    Text("There's no earlier \(weekday) route to copy yet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: Upcoming

    private var upcomingDays: [RoutesDayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.upcomingRoutes) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            RoutesDayGroup(id: day, routes: grouped[day] ?? [])
        }
    }

    @ViewBuilder
    private var upcomingContent: some View {
        let days = upcomingDays
        if days.isEmpty {
            EmptyStateView(symbol: "calendar", title: "No upcoming routes", message: "Routes planned for later days will appear here.") {
                if canPlan {
                    Button("Plan a Route") {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.now) ?? store.now
                        plannerDraft = store.newRouteDraft(on: tomorrow)
                    }
                    .buttonStyle(.mc(.primary))
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: Space.l) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionHeader(Fmt.relativeDay(day.id, now: store.now) == "Tomorrow" ? "Tomorrow · \(Fmt.shortDay(day.id))" : Fmt.longDay(day.id))
                        ForEach(day.routes) { route in
                            RouteListCard(route: route, canAssign: canPlan) {
                                crewSheet = RouteSheetItem(id: route.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
        }
    }
}

// MARK: - Route card

private struct RouteListCard: View {
    let route: Route
    var canAssign: Bool
    var onAssignCrew: () -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        if route.state == .completed {
            completedCard
        } else {
            fullCard
        }
    }

    private var completedCard: some View {
        NavigationLink(value: AppDestination.routeSummary(route.id)) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(completedDetail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: Space.s)
                RouteStatePill(badge: route.stateBadge())
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the route summary")
    }

    private var completedDetail: String {
        var parts = [Fmt.plural(route.stops.count, "stop")]
        if let crew = store.crew(route.crewID) { parts.append(crew.name) }
        return parts.joined(separator: " · ")
    }

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            NavigationLink(value: AppDestination.route(route.id)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text("\(route.serviceSummary) · \(Fmt.plural(route.stops.count, "stop"))")
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink2)
                        }
                        Spacer(minLength: Space.s)
                        RouteStatePill(badge: route.stateBadge())
                    }
                    RouteProgressBar(stops: route.stops)
                    if let crew = store.crew(route.crewID) {
                        crewLine(crew)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if route.needsCrew {
                if canAssign {
                    Button {
                        onAssignCrew()
                    } label: {
                        Label("Assign a crew", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.mc(.tinted, compact: true))
                } else {
                    Text("Waiting for a planner to assign a crew.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
        }
        .cardStyle()
    }

    private func crewLine(_ crew: Crew) -> some View {
        let initials = store.members(of: crew).map(\.initials)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                AvatarStack(initials: initials, size: 26)
                Text(crew.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                Text(timing)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .numeric()
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    AvatarStack(initials: initials, size: 26)
                    Text(crew.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                Text(timing)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .numeric()
            }
        }
    }

    private var timing: String {
        switch route.state {
        case .inProgress:
            let done = "Done ~\(Fmt.time(route.projectedEnd))"
            if let eta = (route.inProgressStop == nil ? route.nextStop?.eta : nil) {
                return "Next \(Fmt.clock(eta)) · \(done)"
            }
            return done
        case .completed:
            return route.finishedAt.map { "Done \(Fmt.time($0))" } ?? "Done"
        case .draft, .scheduled:
            return "Est. \(Fmt.duration(minutes: route.workMinutes))"
        }
    }
}

// MARK: - All routes map

private struct RoutesMapPin: Identifiable {
    let id: Route.ID
    let route: Route
    let coordinate: CLLocationCoordinate2D
    let place: String
    let letter: String
}

private struct TodayRoutesMapSheet: View {
    var onOpen: (Route.ID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    private var pins: [RoutesMapPin] {
        store.todayRoutes.compactMap { route -> RoutesMapPin? in
            guard let stop = route.inProgressStop ?? route.nextStop ?? route.stops.last,
                  let property = store.property(stop.propertyID) else { return nil }
            return RoutesMapPin(id: route.id, route: route, coordinate: RoutesGeo.coordinate(property), place: property.name, letter: store.crew(route.crewID)?.letter ?? "?")
        }
    }

    var body: some View {
        let pins = self.pins
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $position) {
                    ForEach(pins) { pin in
                        Annotation(pin.route.name, coordinate: pin.coordinate, anchor: .bottom) {
                            Button {
                                onOpen(pin.id)
                            } label: {
                                pinLabel(pin)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(pin.route.name), \(pin.route.stateBadge().text), at \(pin.place)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(emphasis: .muted))
                .frame(minHeight: 280)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pins) { pin in
                            Button {
                                onOpen(pin.id)
                            } label: {
                                HStack(spacing: Space.m) {
                                    CrewBadge(letter: pin.letter, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pin.route.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                        Text(pin.place).font(.subheadline).foregroundStyle(Palette.ink2)
                                    }
                                    Spacer(minLength: Space.s)
                                    RouteStatePill(badge: pin.route.stateBadge())
                                }
                                .frame(minHeight: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            Divider()
                        }
                        Text("Pins show each route's current or next stop.")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink3)
                            .padding(.vertical, Space.m)
                    }
                    .padding(.horizontal, Space.l)
                }
                .frame(maxHeight: 280)
                .background(Palette.background)
            }
            .navigationTitle("Today's Routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withMotion { position = .automatic }
                    } label: {
                        Image(systemName: "scope")
                    }
                    .accessibilityLabel("Fit all routes")
                }
            }
        }
    }

    private func pinLabel(_ pin: RoutesMapPin) -> some View {
        let badge = pin.route.stateBadge()
        return VStack(spacing: 2) {
            Text(pin.letter)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(badge.tone == .neutral ? Palette.ink : badge.tone.foreground, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(pin.route.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.bar, in: Capsule())
        }
        .floatingShadow()
        .frame(minWidth: Hit.min, minHeight: Hit.min)
    }
}

#Preview("Routes") {
    NavigationStack {
        RoutesListView()
            .appDestinations()
    }
    .previewEnvironment()
}
