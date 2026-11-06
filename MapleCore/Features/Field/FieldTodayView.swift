import SwiftUI
import MapleCoreKit

/// Field Today: greeting + sync chip, shift, the next stop (or the running visit), notes and route progress.
struct FieldTodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts

    private var actions: FieldActions { FieldActions(store: store, model: model, toasts: toasts) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m + 2) {
                FieldTodayHeader()
                FieldShiftCard(actions: actions)
                content
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Today")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.syncPending() }
        .motionAnimation(value: store.activeVisit?.id)
    }

    @ViewBuilder
    private var content: some View {
        if let route = store.fieldRoute {
            routeContent(route)
        } else if let finished = store.fieldFinishedRouteToday {
            RouteDoneCard(route: finished)
        } else {
            noRoute
        }
    }

    @ViewBuilder
    private func routeContent(_ route: Route) -> some View {
        if let session = store.activeVisit {
            ActiveVisitCard(session: session) { model.isVisitPresented = true }
        } else if let next = store.fieldCurrentStop(in: route) {
            let property = store.property(next.propertyID)
            NextStopCard(
                route: route,
                stop: next,
                property: property,
                now: store.now,
                onNavigate: { if let property { FieldMaps.openDirections(to: property) } },
                onArrive: { actions.arrive(routeID: route.id, stopID: next.id) }
            )
            BeforeYouStartCard(stop: next, property: property)
        }
        RouteProgressCard(route: route, finish: store.projectedFinish(for: route)) {
            model.open(FieldTab.route)
        }
    }

    private var noRoute: some View {
        EmptyStateView(
            symbol: "map",
            title: "No route assigned yet",
            message: "Your manager hasn't published today's route. We'll notify you the moment it's ready."
        ) {
            Button("Message Manager") { actions.messageManager() }
                .buttonStyle(.mc(.secondary, glove: true))
                .frame(maxWidth: 320)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Header

private struct FieldTodayHeader: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.longDay(store.now))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                Text("Hi, \(store.fieldMember?.firstName ?? store.account?.firstName ?? "there")")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: Space.s)
            FieldSyncChip()
        }
        .padding(.top, Space.s)
    }
}

// MARK: - Shift

/// Compact shift card: live duration and End Shift, or Start Shift when off shift.
struct FieldShiftCard: View {
    @Environment(AppStore.self) private var store
    var actions: FieldActions
    @State private var confirmEnd = false

    var body: some View {
        if let shift = store.activeFieldShift {
            onShift(shift)
        } else {
            offShift
        }
    }

    private func onShift(_ shift: Shift) -> some View {
        HStack(spacing: Space.m) {
            Circle().fill(Palette.green).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                ShiftDurationText(startedAt: shift.startedAt, prefix: "On shift · ")
                    .font(.subheadline.weight(.semibold))
                Text(shiftDetail(shift))
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.s)
            Button("End Shift") { confirmEnd = true }
                .buttonStyle(.mc(.secondary, compact: true))
                .fixedSize()
                .disabled(store.activeVisit != nil)
                .accessibilityHint(store.activeVisit != nil ? "Finish your visit before ending your shift" : "Asks for confirmation")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .confirmationDialog("End your shift?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Shift", role: .destructive) { actions.endShift() }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("Your hours are saved and location sharing stops.")
        }
    }

    private var offShift: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Circle().fill(Palette.ink3).frame(width: 10, height: 10).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not on shift").font(.subheadline.weight(.semibold))
                    Text(offShiftDetail)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                actions.startShift()
            } label: {
                Label("Start Shift", systemImage: "play.fill")
            }
            .buttonStyle(.mc(.primary, glove: true))
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func shiftDetail(_ shift: Shift) -> String {
        var parts = ["Started \(Fmt.time(shift.startedAt))"]
        if let crew = store.fieldCrew { parts.append(crew.name) }
        let truck = shift.truck.isEmpty ? (store.fieldCrew?.truck ?? "") : shift.truck
        if !truck.isEmpty { parts.append(truck) }
        return parts.joined(separator: " · ")
    }

    private var offShiftDetail: String {
        var parts: [String] = []
        if let crew = store.fieldCrew { parts.append(crew.name) }
        if let truck = store.fieldCrew?.truck, !truck.isEmpty { parts.append(truck) }
        return parts.isEmpty ? "Start your shift when you're ready to work." : parts.joined(separator: " · ")
    }
}

// MARK: - Cards

/// Amber "Before you start" card: access notes and tasks added today.
private struct BeforeYouStartCard: View {
    var stop: RouteStop
    var property: Property?

    private var added: [VisitTask] { stop.tasks.filter(\.addedToday) }
    private var access: String { property?.accessNotes ?? "" }

    var body: some View {
        if !access.isEmpty || !added.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Before you start", systemImage: "exclamationmark.triangle")
                    .fieldCaption(Palette.amber)
                if !access.isEmpty {
                    Text(access).font(.body)
                }
                ForEach(added) { task in
                    Text("Added today: \(task.title)").font(.body)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.amberSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

/// "5 of 9 stops done · Finish ~2:15 PM" with the segmented bar. Opens the Route tab.
private struct RouteProgressCard: View {
    var route: Route
    var finish: Date
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Space.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: Space.s)
                        finishText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        finishText
                    }
                }
                RouteProgressBar(stops: route.stops)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(route.name): \(route.finishedCount) of \(route.stops.count) stops done. Finish around \(Fmt.time(finish))")
        .accessibilityHint("Opens your route")
    }

    private var title: some View {
        Text("\(route.finishedCount) of \(route.stops.count) stops done")
            .font(.headline)
            .foregroundStyle(Palette.ink)
    }

    private var finishText: some View {
        Text("Finish ~\(Fmt.time(finish))")
            .font(.footnote)
            .foregroundStyle(Palette.ink2)
    }
}

/// Shown after the crew finishes today's route.
private struct RouteDoneCard: View {
    var route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label("Route complete", systemImage: "checkmark.circle.fill")
                .fieldCaption(Palette.green)
            Text(route.name).font(.title2.weight(.bold))
            Text(detail).font(.subheadline).foregroundStyle(Palette.ink2)
            RouteProgressBar(stops: route.stops)
        }
        .padding(Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var text = "All \(route.stops.count) stops finished"
        if let finished = route.finishedAt { text += " · \(Fmt.time(finished))" }
        return text + ". Reports are with the office for review."
    }
}

#if DEBUG
#Preview("Today") {
    NavigationStack {
        FieldTodayView().appDestinations()
    }
    .previewEnvironment(role: .field)
}
#endif
