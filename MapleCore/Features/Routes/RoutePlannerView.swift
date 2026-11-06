import SwiftUI
import MapleCoreKit

/// Full-screen route planner: details, ordered stops, optimize, then assign a crew to publish.
struct RoutePlannerView: View {
    private let original: Route

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Route
    /// The last version saved (or the incoming one). Edits are compared against it.
    @State private var baseline: Route
    @State private var showsDiscard = false
    @State private var showsAddStops = false
    @State private var proposal: PlannerProposal?
    @State private var crewSheet: RouteSheetItem?
    @State private var didAssign = false
    @State private var notifyCrew = true
    @State private var published: PublishedRoute?

    init(draft: Route) {
        self.original = draft
        _draft = State(initialValue: draft)
        _baseline = State(initialValue: draft)
    }

    private var isExisting: Bool { store.route(original.id) != nil }
    private var hasEdits: Bool { draft != baseline }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && !draft.stops.isEmpty }
    private var canEdit: Bool { store.capabilities.contains(.routePlanning) && !store.isReadOnly }
    private var isDraftState: Bool { draft.state == .draft }

    var body: some View {
        NavigationStack {
            Group {
                if let published {
                    PublishedRouteView(info: published, onDone: { dismiss() }, onBuildAnother: buildAnother)
                } else {
                    form
                }
            }
            .navigationTitle(published == nil ? (isExisting ? "Edit Route" : "New Route") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if published == nil {
                        Button("Cancel") {
                            if hasEdits { showsDiscard = true } else { dismiss() }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if published == nil {
                        Button(isDraftState ? "Save Draft" : "Save") { save() }
                            .disabled(!isValid || !canEdit)
                    }
                }
            }
        }
        .toastOverlay()
        .interactiveDismissDisabled(hasEdits)
        .confirmationDialog("Discard changes to this route?", isPresented: $showsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $showsAddStops) {
            AddStopsSheet(existing: Set(draft.stops.map(\.propertyID))) { ids in
                addStops(ids)
            }
        }
        .sheet(item: $crewSheet, onDismiss: checkPublished) { item in
            CrewAssignSheet(routeID: item.id) { _, notify in
                didAssign = true
                notifyCrew = notify
            }
        }
    }

    // MARK: Form

    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.startTime },
            set: { newValue in
                draft.startTime = newValue
                draft.date = newValue
            }
        )
    }

    private var serviceOptions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let candidates: [String] = [draft.serviceSummary, "Leaf removal"] + ServiceType.allCases.map(\.label) + store.routes.map(\.serviceSummary)
        for option in candidates where !option.isEmpty && !seen.contains(option) {
            seen.insert(option)
            result.append(option)
        }
        return result
    }

    private var form: some View {
        List {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Kingsway Residential"))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                DatePicker("Date", selection: startBinding, displayedComponents: [.date, .hourAndMinute])
                Picker("Service", selection: $draft.serviceSummary) {
                    ForEach(serviceOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } footer: {
                if trimmedName.isEmpty {
                    Text("A name is required.")
                }
            }

            Section {
                if let proposal {
                    proposalBanner(proposal)
                }
                ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                    PlannerStopRow(number: index + 1, stop: stop, name: store.property(stop.propertyID)?.name ?? "Unknown property")
                        .contextMenu {
                            Button {
                                togglePriority(stop.id)
                            } label: {
                                Label(stop.priority == .high ? "Set Normal Priority" : "Mark High Priority", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                removeStop(stop.id)
                            } label: {
                                Label("Remove Stop", systemImage: "trash")
                            }
                        }
                }
                .onMove(perform: moveStops)
                .onDelete(perform: deleteStops)

                Button {
                    showsAddStops = true
                } label: {
                    Label(draft.stops.isEmpty ? "Add Properties" : "Add More Stops", systemImage: "plus.circle.fill")
                }
                .disabled(!canEdit)
            } header: {
                stopsHeader
            } footer: {
                if draft.stops.isEmpty {
                    Text("Add at least one stop. Drag to reorder; high-priority stops stay first when optimized.")
                } else {
                    Text("Drag to reorder. Touch and hold a stop to change its priority.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footerBar }
        .motionAnimation(value: proposal)
    }

    private var stopsHeader: some View {
        HStack {
            Text("Stops · \(draft.stops.count)")
            Spacer()
            Button("Optimize") { optimize() }
                .disabled(draft.stops.filter { !$0.status.isFinished }.count < 2 || !canEdit)
            Button("Add") { showsAddStops = true }
                .disabled(!canEdit)
                .padding(.leading, Space.m)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }

    private func proposalBanner(_ proposal: PlannerProposal) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Proposed order saves \(proposal.savedMinutes) min of driving. High-priority stops stay first.", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            HStack(spacing: Space.l) {
                Button("Apply") { applyProposal(proposal) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                Button("Not Now") { withMotion { self.proposal = nil } }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .tint(Palette.ink2)
            }
        }
        .padding(.vertical, Space.xs)
        .listRowBackground(Palette.blueSoft)
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    // MARK: Footer

    private var endTime: Date {
        draft.startTime.addingTimeInterval(TimeInterval((draft.workMinutes + draft.driveMinutes) * 60))
    }

    @ViewBuilder
    private var summaryItems: some View {
        summaryItem(Fmt.duration(minutes: draft.workMinutes), "work")
        summaryItem(Fmt.duration(minutes: draft.driveMinutes), "drive")
        summaryItem("\(draft.distanceKm) km", "distance")
        summaryItem("~\(Fmt.time(endTime))", "ends")
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .numeric()
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.ink3)
        }
        .accessibilityElement(children: .combine)
    }

    private var footerBar: some View {
        BottomActionBar {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.l) {
                    summaryItems
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    summaryItems
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                assignCrew()
            } label: {
                Text(draft.crewID == nil ? "Assign Crew" : "Change Crew")
            }
            .buttonStyle(.mc(.primary))
            .disabled(!isValid || !canEdit)
            if !canEdit {
                Text(store.isReadOnly ? "Preview only — changes aren't saved." : "Planning routes needs route-planning access.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            } else if !isValid {
                Text("Add a name and at least one stop to continue.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    // MARK: Stop edits

    private func afterStopsChanged() {
        proposal = nil
        let km = RoutesPlanning.pathKm(draft.stops, lookup: store.routesPropertyLookup)
        draft.distanceKm = Int(km.rounded())
        draft.driveMinutes = RoutesPlanning.driveMinutes(km: km)
    }

    private func moveStops(from source: IndexSet, to destination: Int) {
        draft.stops.move(fromOffsets: source, toOffset: destination)
        afterStopsChanged()
    }

    private func deleteStops(at offsets: IndexSet) {
        draft.stops.remove(atOffsets: offsets)
        afterStopsChanged()
    }

    private func removeStop(_ id: RouteStop.ID) {
        draft.stops.removeAll { $0.id == id }
        afterStopsChanged()
    }

    private func togglePriority(_ id: RouteStop.ID) {
        guard let i = draft.stops.firstIndex(where: { $0.id == id }) else { return }
        draft.stops[i].priority = draft.stops[i].priority == .high ? .normal : .high
        proposal = nil
    }

    private func addStops(_ ids: [Property.ID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            draft.stops.append(RouteStop(id: UUID().uuidString, propertyID: id, serviceName: draft.serviceSummary, estimatedMinutes: 30))
        }
        afterStopsChanged()
        Haptics.selection()
    }

    private func optimize() {
        let result = RoutesPlanning.proposal(for: draft.stops, lookup: store.routesPropertyLookup)
        let sameOrder = result.stops.map(\.id) == draft.stops.map(\.id)
        if sameOrder || result.savedMinutes == 0 {
            toasts.show("This order is already the shortest drive", symbol: "checkmark.circle", tone: .blue)
            return
        }
        withMotion {
            proposal = PlannerProposal(stopIDs: result.stops.map(\.id), savedMinutes: result.savedMinutes)
        }
    }

    private func applyProposal(_ proposal: PlannerProposal) {
        var reordered: [RouteStop] = []
        for id in proposal.stopIDs {
            if let stop = draft.stops.first(where: { $0.id == id }) { reordered.append(stop) }
        }
        // Keep any stop added after the proposal was made.
        for stop in draft.stops where !proposal.stopIDs.contains(stop.id) {
            reordered.append(stop)
        }
        withMotion {
            draft.stops = reordered
            afterStopsChanged()
        }
        Haptics.success()
        toasts.show("Stops reordered · saves about \(proposal.savedMinutes) min")
    }

    // MARK: Save & publish

    private func normalized() -> Route {
        var route = draft
        route.name = trimmedName
        route.date = route.startTime
        if route.plannedMinutes == nil || route.state == .draft {
            route.plannedMinutes = route.workMinutes + route.driveMinutes
        }
        return route
    }

    private func save() {
        guard isValid, canEdit else { return }
        let route = normalized()
        store.saveRoute(route)
        baseline = route
        draft = route
        Haptics.success()
        let what = route.state == .draft ? "Draft saved" : "Route saved"
        toasts.show(store.isOnline ? what : "\(what) on this iPhone · sends automatically", symbol: store.isOnline ? "checkmark.circle.fill" : "wifi.slash", tone: store.isOnline ? .green : .amber)
        dismiss()
    }

    private func assignCrew() {
        guard isValid, canEdit else { return }
        let route = normalized()
        store.saveRoute(route)
        baseline = route
        draft = route
        didAssign = false
        crewSheet = RouteSheetItem(id: route.id)
    }

    private func checkPublished() {
        guard didAssign, let saved = store.route(draft.id), let crew = store.crew(saved.crewID), saved.state != .draft else { return }
        draft = saved
        baseline = saved
        Haptics.success()
        withMotion {
            published = PublishedRoute(stopCount: saved.stops.count, crewName: crew.name, start: saved.startTime, notify: notifyCrew, queuedOffline: !store.isOnline)
        }
    }

    private func buildAnother() {
        let fresh = store.newRouteDraft(on: draft.date)
        draft = fresh
        baseline = fresh
        proposal = nil
        didAssign = false
        withMotion { published = nil }
    }
}

// MARK: - Models

private struct PlannerProposal: Hashable {
    let stopIDs: [RouteStop.ID]
    let savedMinutes: Int
}

private struct PublishedRoute: Hashable {
    let stopCount: Int
    let crewName: String
    let start: Date
    let notify: Bool
    let queuedOffline: Bool
}

// MARK: - Rows

private struct PlannerStopRow: View {
    let number: Int
    let stop: RouteStop
    let name: String

    var body: some View {
        HStack(spacing: Space.m) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .numeric()
                .foregroundStyle(Palette.ink)
                .frame(width: 32, height: 32)
                .background(Palette.surface2, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(Fmt.duration(minutes: stop.estimatedMinutes)) · \(stop.serviceName)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if stop.priority == .high {
                Pill(text: "High", tone: .red, symbol: "flag.fill")
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(number), \(name), \(Fmt.duration(minutes: stop.estimatedMinutes))\(stop.priority == .high ? ", high priority" : "")")
    }
}

// MARK: - Add stops

private struct AddStopsSheet: View {
    let existing: Set<Property.ID>
    var onAdd: ([Property.ID]) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: [Property.ID] = []

    private var filtered: [Property] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.properties }
        return store.properties.filter { p in
            p.name.lowercased().contains(q) || p.address.lowercased().contains(q) || p.city.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { property in
                row(property)
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matching properties", message: "Try a name, street or city.")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search properties")
            .navigationTitle("Add Stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Add" : "Add \(selection.count)") {
                        onAdd(selection)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!selection.isEmpty)
    }

    private func row(_ property: Property) -> some View {
        let isOnRoute = existing.contains(property.id)
        let isSelected = selection.contains(property.id)
        return Button {
            if let i = selection.firstIndex(of: property.id) {
                selection.remove(at: i)
            } else {
                selection.append(property.id)
            }
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: isSelected || isOnRoute ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOnRoute ? Palette.ink3 : (isSelected ? Palette.red : Palette.ink3))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(property.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("\(property.address) · \(property.kind.label)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: Space.s)
                if isOnRoute {
                    Pill(text: "On route", tone: .neutral)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOnRoute)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Published

private struct PublishedRouteView: View {
    let info: PublishedRoute
    var onDone: () -> Void
    var onBuildAnother: () -> Void

    @State private var appeared = false

    private var detail: String {
        let start = "starts \(Fmt.weekdayShort(info.start)) \(Fmt.time(info.start))"
        let crewPart: String
        if !info.notify {
            crewPart = "\(info.crewName) not notified"
        } else if info.queuedOffline {
            crewPart = "\(info.crewName) is notified once this iPhone is back online"
        } else {
            crewPart = "\(info.crewName) notified"
        }
        return "\(Fmt.plural(info.stopCount, "stop")) · \(crewPart) · \(start)"
    }

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Palette.green)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            VStack(spacing: Space.s) {
                Text("Route published")
                    .font(.title2.weight(.bold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            VStack(spacing: Space.s) {
                Button("Done", action: onDone)
                    .buttonStyle(.mc(.primary))
                Button("Build Another", action: onBuildAnother)
                    .buttonStyle(.mc(.secondary))
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear {
            withMotion(.spring(response: 0.35, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

#Preview("Route Planner") {
    RoutePlannerView(draft: Route(id: "preview-draft", name: "", serviceSummary: "Leaf removal", date: Date(), startTime: Date(), crewID: nil, stops: [], state: .draft))
        .previewEnvironment()
}
