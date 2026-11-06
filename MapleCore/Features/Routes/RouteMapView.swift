import SwiftUI
import MapKit
import MapleCoreKit

/// Route map (upper ~45%) with numbered stop pins, plus the route header and stop list below.
struct RouteMapView: View {
    let routeID: Route.ID

    @Environment(AppStore.self) private var store

    var body: some View {
        if let route = store.route(routeID) {
            RouteMapScreen(route: route)
        } else {
            MissingRecordView(title: "Route not available")
        }
    }
}

// MARK: - Map data

private struct RouteStopItem: Identifiable {
    let id: RouteStop.ID
    let number: Int
    let stop: RouteStop
    let name: String
    let isNext: Bool
    let coordinate: CLLocationCoordinate2D?
}

private struct RouteStopPin: Identifiable {
    let id: RouteStop.ID
    let number: Int
    let status: StopStatus
    let name: String
    let isNext: Bool
    let coordinate: CLLocationCoordinate2D
}

private struct RouteLineSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let isTravelled: Bool
}

private struct RouteVehiclePin: Identifiable {
    let id: String
    let label: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Screen

private struct RouteMapScreen: View {
    let route: Route

    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .automatic
    @State private var showsCompleted = false
    @State private var editingDraft: Route?
    @State private var crewSheet: RouteSheetItem?

    private var canPlan: Bool { store.capabilities.contains(.routePlanning) }

    private var items: [RouteStopItem] {
        let nextID = route.inProgressStop == nil ? route.nextStop?.id : nil
        return route.stops.enumerated().map { index, stop in
            let property = store.property(stop.propertyID)
            return RouteStopItem(
                id: stop.id,
                number: index + 1,
                stop: stop,
                name: property?.name ?? "Unknown property",
                isNext: stop.id == nextID,
                coordinate: property.map { RoutesGeo.coordinate($0) }
            )
        }
    }

    var body: some View {
        let items = self.items
        GeometryReader { geo in
            VStack(spacing: 0) {
                mapView(items)
                    .frame(height: max(220, geo.size.height * 0.45))
                ScrollView {
                    panel(items)
                        .padding(Space.l)
                }
                .background(Palette.background)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withMotion { position = .automatic }
                } label: {
                    Image(systemName: "scope")
                }
                .accessibilityLabel("Fit route")
            }
        }
        .fullScreenCover(item: $editingDraft) { draft in
            RoutePlannerView(draft: draft)
        }
        .sheet(item: $crewSheet) { item in
            CrewAssignSheet(routeID: item.id)
        }
    }

    // MARK: Map

    private func pins(_ items: [RouteStopItem]) -> [RouteStopPin] {
        items.compactMap { item -> RouteStopPin? in
            guard let coordinate = item.coordinate else { return nil }
            return RouteStopPin(id: item.id, number: item.number, status: item.stop.status, name: item.name, isNext: item.isNext, coordinate: coordinate)
        }
    }

    /// Travelled line runs through finished/in-progress stops; the remaining line continues from the last of them.
    private func segments(_ items: [RouteStopItem]) -> [RouteLineSegment] {
        let coords: [CLLocationCoordinate2D] = items.compactMap { $0.coordinate }
        let activeStatuses: [Bool] = items.filter { $0.coordinate != nil }.map { $0.stop.status.isFinished || $0.stop.status == .inProgress }
        guard coords.count > 1 else { return [] }
        let lastActive = activeStatuses.lastIndex(of: true)
        var result: [RouteLineSegment] = []
        if let lastActive, lastActive > 0 {
            result.append(RouteLineSegment(id: "travelled", coordinates: Array(coords[0...lastActive]), isTravelled: true))
        }
        let remainingStart = lastActive ?? 0
        if remainingStart < coords.count - 1 {
            result.append(RouteLineSegment(id: "remaining", coordinates: Array(coords[remainingStart...]), isTravelled: false))
        }
        return result
    }

    /// The crew vehicle is shown only when the lead is sharing live location, placed at the property they report.
    private var vehicles: [RouteVehiclePin] {
        guard let crew = store.crew(route.crewID), let lead = store.member(crew.leadID) else { return [] }
        guard case let .live(place, updatedAt) = lead.location else { return [] }
        guard let property = store.properties.first(where: { $0.name == place }) else { return [] }
        let label = "\(crew.name) · updated \(Fmt.ago(updatedAt, now: store.now))"
        return [RouteVehiclePin(id: crew.id, label: label, coordinate: RoutesGeo.coordinate(property))]
    }

    private func mapView(_ items: [RouteStopItem]) -> some View {
        let pins = self.pins(items)
        let lines = segments(items)
        let vehicles = self.vehicles
        let routeID = route.id
        return Map(position: $position) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(line.isTravelled ? Palette.green : Palette.ink3,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: line.isTravelled ? [] : [6, 6]))
            }
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                    Button {
                        model.push(.stop(routeID, pin.id))
                    } label: {
                        StopNumberBadge(number: pin.number, status: pin.status, isNext: pin.isNext)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .floatingShadow()
                            .frame(minWidth: Hit.min, minHeight: Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop \(pin.number), \(pin.name)\(pin.isNext ? ", next" : ""), \(pin.status.label)")
                }
            }
            ForEach(vehicles) { vehicle in
                Annotation(vehicle.label, coordinate: vehicle.coordinate, anchor: .bottom) {
                    VStack(spacing: 2) {
                        Image(systemName: "truck.box.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Palette.blue, in: Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Text(vehicle.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.bar, in: Capsule())
                    }
                    .floatingShadow()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Crew vehicle, live location, \(vehicle.label)")
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted))
        .annotationTitles(.hidden)
    }

    // MARK: Panel

    private func panel(_ items: [RouteStopItem]) -> some View {
        let finished = items.filter { $0.stop.status.isFinished }
        let upcoming = items.filter { !$0.stop.status.isFinished }
        return VStack(alignment: .leading, spacing: Space.l) {
            header
            actions
            if !finished.isEmpty {
                completedSection(finished)
            }
            if upcoming.isEmpty {
                NoticeCard(symbol: "checkmark.circle.fill", text: "Every stop on this route is finished.", tone: .green)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionHeader("Upcoming")
                    CardList(data: upcoming, inset: 52) { item in
                        stopLink(item)
                    }
                }
            }
        }
    }

    private var header: some View {
        let badge: RouteStateBadge = (route.state == .inProgress && !route.isDelayed)
            ? RouteStateBadge(text: "On time", tone: .green, symbol: "checkmark")
            : route.stateBadge()
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(route.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                RouteStatePill(badge: badge)
            }
            Text("\(store.routesCrewLine(route.crewID)) · \(route.completedCount) of \(route.stops.count) done")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var crewThreadID: MessageThread.ID? {
        guard let crewID = route.crewID else { return nil }
        return store.crewThread(for: crewID)?.id
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            editingDraft = route
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.mc(.secondary, compact: true))
        .disabled(!canPlan || route.state == .completed)

        Button {
            crewSheet = RouteSheetItem(id: route.id)
        } label: {
            Label("Crew", systemImage: "person.2")
        }
        .buttonStyle(.mc(.secondary, compact: true))
        .disabled(!canPlan || route.state == .completed)

        if let threadID = crewThreadID {
            NavigationLink(value: AppDestination.thread(threadID)) {
                Label("Message", systemImage: "bubble.left")
            }
            .buttonStyle(.mc(.secondary, compact: true))
        } else {
            Button {} label: {
                Label("Message", systemImage: "bubble.left")
            }
            .buttonStyle(.mc(.secondary, compact: true))
            .disabled(true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { actionButtons }
                VStack(spacing: Space.s) { actionButtons }
            }
            if crewThreadID == nil {
                Text(route.crewID == nil ? "Assign a crew to message them." : "This crew has no group thread yet.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            } else if !canPlan {
                Text("Editing routes needs route-planning access.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    private func completedSection(_ finished: [RouteStopItem]) -> some View {
        let skipped = finished.filter { $0.stop.status == .skipped }.count
        let title = skipped == 0
            ? "\(Fmt.plural(finished.count, "stop")) completed"
            : "\(Fmt.plural(finished.count, "stop")) finished · \(skipped) skipped"
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion { showsCompleted.toggle() }
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.green)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.s)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                        .rotationEffect(.degrees(showsCompleted ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsCompleted ? "Expanded" : "Collapsed")

            if showsCompleted {
                ForEach(finished) { item in
                    Divider()
                    stopLink(item)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func stopLink(_ item: RouteStopItem) -> some View {
        NavigationLink(value: AppDestination.stop(route.id, item.id)) {
            StopRow(
                number: item.number,
                title: item.name,
                detail: RoutesText.stopDetail(item.stop, isNext: item.isNext, now: store.now),
                status: item.stop.status,
                isNext: item.isNext,
                trailing: item.stop.priority == .high && !item.stop.status.isFinished ? "High" : nil
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Route Map") {
    NavigationStack {
        RouteMapView(routeID: Fixtures.ID.routeNorth)
            .appDestinations()
    }
    .previewEnvironment()
}
