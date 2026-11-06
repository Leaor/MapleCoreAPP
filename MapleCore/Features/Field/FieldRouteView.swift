import SwiftUI
import MapKit
import MapleCoreKit

/// Field "My Route": map with numbered stops on top, then the next stop, remaining stops and
/// completed stops (collapsed).
struct FieldRouteView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts

    private var actions: FieldActions { FieldActions(store: store, model: model, toasts: toasts) }

    var body: some View {
        Group {
            if let route = store.fieldRoute {
                FieldRouteContent(route: route, actions: actions)
            } else {
                emptyState
            }
        }
        .navigationTitle("My Route")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var emptyState: some View {
        ScrollView {
            if let finished = store.fieldFinishedRouteToday {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "\(finished.name) is done",
                    message: "All \(finished.stops.count) stops are finished. Nice work."
                ) {
                    NavigationLink(value: AppDestination.shiftHistory) {
                        Text("Shift History")
                    }
                    .buttonStyle(.mc(.secondary, glove: true))
                    .frame(maxWidth: 320)
                }
            } else {
                EmptyStateView(
                    symbol: "map",
                    title: "No route assigned yet",
                    message: "Your manager hasn't published today's route. We'll notify you the moment it's ready."
                ) {
                    Button("Message Manager") { actions.messageManager() }
                        .buttonStyle(.mc(.secondary, glove: true))
                        .frame(maxWidth: 320)
                }
            }
        }
        .screenBackground()
    }
}

// MARK: - Content

private struct FieldRouteContent: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    var route: Route
    var actions: FieldActions

    @State private var showCompleted = false

    private var current: RouteStop? { store.fieldCurrentStop(in: route) }
    private var remaining: [RouteStop] {
        route.stops.filter { !$0.status.isFinished && $0.id != current?.id }
    }
    private var finished: [RouteStop] { route.stops.filter { $0.status.isFinished } }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                FieldRouteMap(route: route, nextStopID: current?.id)
                    .frame(height: max(220, geo.size.height * 0.4))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.m) {
                        header
                        if !store.isOnline {
                            NoticeCard(symbol: "externaldrive.badge.checkmark", text: savedCopyText, tone: .amber)
                        }
                        if let current {
                            currentCard(current)
                        }
                        if !remaining.isEmpty {
                            remainingList
                        }
                        if !finished.isEmpty {
                            completedGroup
                        }
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                }
                .refreshable { await store.syncPending() }
            }
        }
        .screenBackground()
    }

    private var savedCopyText: String {
        if let synced = store.lastSyncedAt {
            return "Showing route saved at \(Fmt.time(synced)). Changes arrive when you're back online."
        }
        return "Showing the route saved on this iPhone. Changes arrive when you're back online."
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(route.finishedCount) of \(route.stops.count) done · finish ~\(Fmt.time(store.projectedFinish(for: route)))")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if route.isDelayed {
                Pill(text: "Delayed \(route.delayMinutes) min", tone: .amber, symbol: StopStatus.delayed.symbol)
            } else {
                Pill(text: "On time", tone: .green, symbol: "checkmark")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Current / next stop

    @ViewBuilder
    private func currentCard(_ stop: RouteStop) -> some View {
        let number = store.stopNumber(stop.id, in: route)
        let property = store.property(stop.propertyID)
        VStack(alignment: .leading, spacing: Space.m) {
            NavigationLink(value: AppDestination.fieldStop(route.id, stop.id)) {
                HStack(spacing: Space.m) {
                    StopNumberBadge(number: number, status: stop.status, isNext: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(property?.name ?? "Stop \(number)")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(currentDetail(stop))
                            .font(.footnote)
                            .foregroundStyle(stop.status == .enRoute ? Palette.blue : Palette.ink2)
                    }
                    Spacer(minLength: Space.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens stop details")

            currentButtons(stop)
        }
        .padding(Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.red, lineWidth: 2)
        }
        .motionAnimation(value: stop.status)
    }

    private func currentDetail(_ stop: RouteStop) -> String {
        switch stop.status {
        case .inProgress: return "In progress · visit running"
        case .enRoute: return "En route" + (stop.eta.map { " · ETA \(Fmt.clock($0))" } ?? "")
        default: return "Next" + (FieldText.eta(stop, now: store.now).map { " · \($0)" } ?? "")
        }
    }

    @ViewBuilder
    private func currentButtons(_ stop: RouteStop) -> some View {
        if stop.status == .inProgress || store.activeVisit?.stopID == stop.id {
            Button("Return to Visit") { model.isVisitPresented = true }
                .buttonStyle(.mc(.primary, glove: true))
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s + 2) { travelButtons(stop) }
                VStack(spacing: Space.s + 2) { travelButtons(stop) }
            }
        }
    }

    @ViewBuilder
    private func travelButtons(_ stop: RouteStop) -> some View {
        if stop.status == .enRoute {
            Button {
                if let property = store.property(stop.propertyID) { FieldMaps.openDirections(to: property) }
            } label: {
                Label("Navigate", systemImage: "location.north.line.fill")
            }
            .buttonStyle(.mc(.secondary, glove: true))
            .accessibilityHint("Opens driving directions in Apple Maps")
        } else {
            Button {
                actions.beginTravel(routeID: route.id, stopID: stop.id)
            } label: {
                Label("On My Way", systemImage: "car.fill")
            }
            .buttonStyle(.mc(.secondary, glove: true))
            .accessibilityHint("Marks this stop en route")
        }
        Button("Arrived") { actions.arrive(routeID: route.id, stopID: stop.id) }
            .buttonStyle(.mc(.primary, glove: true))
            .accessibilityLabel("I've arrived")
    }

    // MARK: Lists

    private var remainingList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Up next")
            CardList(data: remaining, inset: 52) { stop in
                NavigationLink(value: AppDestination.fieldStop(route.id, stop.id)) {
                    StopRow(
                        number: store.stopNumber(stop.id, in: route),
                        title: store.property(stop.propertyID)?.name ?? "Stop",
                        detail: FieldText.remainingDetail(stop),
                        status: stop.status,
                        trailing: stop.priority == .high ? "High" : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var completedGroup: some View {
        DisclosureGroup(isExpanded: $showCompleted) {
            VStack(spacing: 0) {
                ForEach(finished) { stop in
                    NavigationLink(value: AppDestination.fieldStop(route.id, stop.id)) {
                        StopRow(
                            number: store.stopNumber(stop.id, in: route),
                            title: store.property(stop.propertyID)?.name ?? "Stop",
                            detail: FieldText.finishedDetail(stop),
                            status: stop.status
                        )
                    }
                    .buttonStyle(.plain)
                    if stop.id != finished.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.top, Space.s)
        } label: {
            Text("Completed · \(finished.count)")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .frame(minHeight: Hit.min)
        }
        .tint(Palette.ink2)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xs)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Map

private struct RouteMapPin: Identifiable {
    let id: RouteStop.ID
    let number: Int
    let name: String
    let coordinate: CLLocationCoordinate2D
    let status: StopStatus
    let isNext: Bool
}

/// Native MapKit map with numbered stop badges. The next stop is red; finished stops are green.
private struct FieldRouteMap: View {
    @Environment(AppStore.self) private var store
    var route: Route
    var nextStopID: RouteStop.ID?

    @State private var position: MapCameraPosition = .automatic

    private var pins: [RouteMapPin] {
        route.stops.enumerated().compactMap { index, stop in
            guard let property = store.property(stop.propertyID) else { return nil }
            return RouteMapPin(
                id: stop.id,
                number: index + 1,
                name: property.name,
                coordinate: CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude),
                status: stop.status,
                isNext: stop.id == nextStopID
            )
        }
    }

    var body: some View {
        let allPins = pins
        Map(position: $position) {
            MapPolyline(coordinates: allPins.map(\.coordinate))
                .stroke(Palette.blue.opacity(0.55), lineWidth: 4)
            ForEach(allPins) { pin in
                Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                    StopNumberBadge(number: pin.number, status: pin.status, isNext: pin.isNext)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .floatingShadow()
                        .accessibilityLabel("Stop \(pin.number), \(pin.name), \(pin.isNext ? "next" : pin.status.label)")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted))
        .mapControls {
            MapCompass()
        }
        .overlay(alignment: .topTrailing) {
            if let next = nextProperty {
                Button {
                    FieldMaps.openDirections(to: next)
                } label: {
                    Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Space.m + 2)
                        .frame(minHeight: Hit.min)
                        .foregroundStyle(Palette.ink)
                        .background(Palette.surface, in: Capsule())
                        .floatingShadow()
                }
                .buttonStyle(.plain)
                .padding(Space.l)
                .accessibilityHint("Driving directions to \(next.name) in Apple Maps")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route map")
    }

    private var nextProperty: Property? {
        guard let id = nextStopID, let stop = route.stops.first(where: { $0.id == id }) else { return nil }
        return store.property(stop.propertyID)
    }
}

#Preview("My Route") {
    NavigationStack {
        FieldRouteView().appDestinations()
    }
    .previewEnvironment(role: .field)
}
