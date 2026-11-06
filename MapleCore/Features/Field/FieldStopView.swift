import SwiftUI
import MapleCoreKit

/// Field stop detail: what to know before arriving. Read-only except "I've Arrived".
///
/// Arriving out of order is allowed (gates get locked, customers call) but always asks first,
/// so the next-stop rule is explicit rather than silently enforced.
struct FieldStopView: View {
    let routeID: Route.ID
    let stopID: RouteStop.ID

    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts

    @State private var confirmOutOfOrder = false

    private var actions: FieldActions { FieldActions(store: store, model: model, toasts: toasts) }

    var body: some View {
        if let route = store.route(routeID), let stop = route.stops.first(where: { $0.id == stopID }) {
            content(route: route, stop: stop, property: store.property(stop.propertyID))
        } else {
            MissingRecordView(title: "Stop not available", message: "This stop was removed from the route or hasn't synced to this iPhone yet.")
        }
    }

    private func content(route: Route, stop: RouteStop, property: Property?) -> some View {
        let number = store.stopNumber(stop.id, in: route)
        let current = store.fieldCurrentStop(in: route)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.m + 2) {
                StopTitleBlock(stop: stop, number: number, isNext: current?.id == stop.id, property: property)
                quickActions(route: route, property: property)
                AccessNotesCard(notes: property?.accessNotes ?? "")
                TaskPreviewList(tasks: stop.tasks)
                if let property {
                    LastFinishSection(propertyID: property.id)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .screenBackground()
        .navigationTitle("Stop \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(route: route, stop: stop, number: number, current: current)
        }
        .confirmationDialog("Arrive out of order?", isPresented: $confirmOutOfOrder, titleVisibility: .visible) {
            Button("Start Stop \(number) Now") { actions.arrive(routeID: route.id, stopID: stop.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let current {
                Text("Stop \(store.stopNumber(current.id, in: route)) · \(store.property(current.propertyID)?.name ?? "") is next on your route. The office will see that you changed the order.")
            } else {
                Text("The office will see that you changed the order.")
            }
        }
    }

    private func quickActions(route: Route, property: Property?) -> some View {
        HStack(spacing: Space.s + 2) {
            Button {
                if let property { FieldMaps.openDirections(to: property) }
            } label: {
                Label("Directions", systemImage: "location.north.line.fill")
            }
            .buttonStyle(.mc(.secondary, glove: true))
            .disabled(property == nil)
            .accessibilityHint("Opens driving directions in Apple Maps")

            Button {
                actions.messageOffice(crewID: route.crewID)
            } label: {
                Label("Office", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .buttonStyle(.mc(.secondary, glove: true))
            .accessibilityHint("Opens your crew conversation with the office")
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private func bottomBar(route: Route, stop: RouteStop, number: Int, current: RouteStop?) -> some View {
        let isTodaysRoute = store.fieldRoute?.id == route.id
        if stop.status.isFinished {
            BottomActionBar {
                Label(FieldText.finishedDetail(stop), systemImage: stop.status.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stop.status.tone.foreground)
                    .frame(maxWidth: .infinity, minHeight: Hit.min)
            }
        } else if let session = store.activeVisit, session.stopID == stop.id {
            BottomActionBar {
                Button("Return to Visit") { model.isVisitPresented = true }
                    .buttonStyle(.mc(.primary, glove: true))
            }
        } else if let session = store.activeVisit {
            BottomActionBar {
                hint("Finish your visit at \(session.propertyName) first.")
                Button("Return to Visit") { model.isVisitPresented = true }
                    .buttonStyle(.mc(.secondary, glove: true))
            }
        } else if !isTodaysRoute {
            BottomActionBar {
                hint("This stop isn't on today's route, so it can't be started from here.")
            }
        } else if current?.id == stop.id {
            BottomActionBar {
                Button("I've Arrived") { actions.arrive(routeID: route.id, stopID: stop.id) }
                    .buttonStyle(.mc(.primary, glove: true))
            }
        } else {
            BottomActionBar {
                hint("Not next — finish stop \(current.map { store.stopNumber($0.id, in: route) } ?? number) first, or start here out of order.")
                Button("Arrive Out of Order") {
                    if !actions.blockedByPreview() { confirmOutOfOrder = true }
                }
                .buttonStyle(.mc(.secondary, glove: true))
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sections

private struct StopTitleBlock: View {
    var stop: RouteStop
    var number: Int
    var isNext: Bool
    var property: Property?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { pills }
                VStack(alignment: .leading, spacing: Space.xs) { pills }
            }
            Text(property?.name ?? "Stop \(number)")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text([property?.address, property?.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(Palette.ink2)
            Text(stop.serviceName)
                .font(.subheadline)
                .foregroundStyle(Palette.ink3)
        }
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private var pills: some View {
        if isNext {
            Pill(text: "Stop \(number) · Next", tone: .red, symbol: "arrow.right.circle.fill")
        } else {
            Pill(text: "Stop \(number)", tone: .neutral)
        }
        if stop.status != .pending {
            StatusPill(status: stop.status)
        }
        Pill(text: "~\(Fmt.duration(minutes: stop.estimatedMinutes)) job", tone: .neutral, symbol: "clock")
        if stop.priority == .high {
            Pill(text: "High priority", tone: .red, symbol: "flag.fill")
        }
    }
}

private struct AccessNotesCard: View {
    var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Access & notes", systemImage: "key.fill")
                .fieldCaption(Palette.amber)
            Text(notes.isEmpty ? "No access notes for this property." : notes)
                .font(.body)
                .foregroundStyle(notes.isEmpty ? Palette.ink2 : Palette.ink)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amberSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Read-only checklist preview; tasks are checked off inside the visit.
private struct TaskPreviewList: View {
    var tasks: [VisitTask]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Today's tasks")
            if tasks.isEmpty {
                Text("No tasks listed for this stop.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .cardStyle()
            } else {
                CardList(data: tasks, inset: 36) { task in
                    TaskPreviewRow(task: task)
                }
                Text("You'll check these off during the visit.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

private struct TaskPreviewRow: View {
    var task: VisitTask

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isDone ? Palette.green : Palette.ink3)
                .accessibilityHidden(true)
            Text(task.title)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if task.addedToday {
                Pill(text: "Added today", tone: .blue)
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isDone ? "Done" : "Not done")
    }
}

/// After-photos from the last visit so the crew can match the finish.
private struct LastFinishSection: View {
    @Environment(AppStore.self) private var store
    var propertyID: Property.ID

    private var lastVisit: VisitRecord? {
        store.history(for: propertyID).first { $0.kind == .visit && !$0.photos(.after).isEmpty }
    }

    var body: some View {
        if let visit = lastVisit {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionHeader("Match last visit's finish")
                HStack(spacing: Space.s) {
                    ForEach(Array(visit.photos(.after).prefix(3))) { photo in
                        PhotoTile(photo: photo, cornerRadius: Radius.control + 2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    }
                }
                Text("After photos · \(Fmt.relativeDay(visit.date, now: store.now))\(visit.crewNames.isEmpty ? "" : " · \(visit.crewNames)")")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

#if DEBUG
#Preview("Stop · next") {
    NavigationStack {
        FieldStopView(routeID: Fixtures.ID.routeNorth, stopID: "north-6").appDestinations()
    }
    .previewEnvironment(role: .field)
}

#Preview("Stop · later") {
    NavigationStack {
        FieldStopView(routeID: Fixtures.ID.routeNorth, stopID: "north-8").appDestinations()
    }
    .previewEnvironment(role: .field)
}
#endif
