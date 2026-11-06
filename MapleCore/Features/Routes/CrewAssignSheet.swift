import SwiftUI
import MapleCoreKit

/// Assign a crew to a route. Presented as a sheet with medium/large detents.
struct CrewAssignSheet: View {
    let routeID: Route.ID
    /// Called after a crew is assigned, with the crew and whether "Notify crew" was on.
    var onAssigned: ((Crew.ID, Bool) -> Void)?

    init(routeID: Route.ID, onAssigned: ((Crew.ID, Bool) -> Void)? = nil) {
        self.routeID = routeID
        self.onAssigned = onAssigned
    }

    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            if let route = store.route(routeID) {
                CrewAssignContent(route: route, onAssigned: onAssigned)
            } else {
                MissingRecordView(title: "Route not available")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CrewAssignCloseButton()
                        }
                    }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CrewAssignCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Close") { dismiss() }
    }
}

private struct CrewAssignContent: View {
    enum Mode: String, CaseIterable, Identifiable {
        case crews = "Crews"
        case individuals = "Individuals"
        var id: String { rawValue }
    }

    let route: Route
    var onAssigned: ((Crew.ID, Bool) -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .crews
    @State private var selected: Crew.ID?
    @State private var didLoad = false
    @State private var notify = true

    private var canAssign: Bool { store.capabilities.contains(.routePlanning) && !store.isReadOnly }
    private var hasChange: Bool { selected != nil && selected != route.crewID }
    private var selectedCrew: Crew? { store.crew(selected) }
    private var isAlreadyAssigned: Bool { selected != nil && selected == route.crewID && route.state != .draft }

    private func availability(_ crew: Crew) -> AppStore.CrewAvailability {
        store.availability(of: crew.id, for: route)
    }

    private func rank(_ availability: AppStore.CrewAvailability) -> Int {
        switch availability {
        case .available: 0
        case .overlaps: 1
        case .off: 2
        }
    }

    private var sortedCrews: [Crew] {
        store.crews.sorted { lhs, rhs in
            let l = rank(availability(lhs))
            let r = rank(availability(rhs))
            return l == r ? lhs.name < rhs.name : l < r
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                routeHeader
                Picker("Assign by", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .crews:
                    crewList
                case .individuals:
                    individualsList
                }

                Toggle("Notify crew when published", isOn: $notify)
                    .tint(Palette.green)
                    .frame(minHeight: Hit.min)
                    .cardStyle(padding: Space.m)
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle("Assign Crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    assign()
                } label: {
                    Text(assignTitle)
                }
                .buttonStyle(.mc(.primary))
                .disabled(!canAssign || selected == nil || isAlreadyAssigned)
                if !canAssign {
                    Text(store.isReadOnly ? "Preview only — changes aren't saved." : "Assigning crews needs route-planning access.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                } else if isAlreadyAssigned {
                    Text("This crew is already on the route.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
        }
        .interactiveDismissDisabled(hasChange)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = route.crewID
        }
    }

    private var assignTitle: String {
        if let crew = selectedCrew { return "Assign \(crew.name)" }
        return "Choose a Crew"
    }

    // MARK: Header

    private var routeHeader: some View {
        let length = Fmt.duration(minutes: route.workMinutes + route.driveMinutes)
        return VStack(alignment: .leading, spacing: 4) {
            Text(route.name.isEmpty ? "Untitled route" : route.name)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("\(Fmt.shortDay(route.date)) · \(Fmt.time(route.startTime)) · \(Fmt.plural(route.stops.count, "stop")) · ~\(length)")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .numeric()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: Crews

    private var crewList: some View {
        VStack(spacing: Space.s) {
            ForEach(sortedCrews) { crew in
                crewRow(crew)
            }
            if let crew = selectedCrew, case let .overlaps(name, until) = availability(crew) {
                NoticeCard(symbol: "exclamationmark.triangle.fill", text: "\(crew.name) is on \(name) until ~\(Fmt.time(until)). This route will start after they finish, or adjust the start time.", tone: .amber)
            }
        }
    }

    private func crewRow(_ crew: Crew) -> some View {
        let state = availability(crew)
        let isOff = state == .off
        let isSelected = selected == crew.id
        let members = store.members(of: crew)
        return Button {
            selected = crew.id
        } label: {
            HStack(spacing: Space.m) {
                CrewBadge(letter: crew.letter)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Space.s) {
                        Text(crew.name)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        availabilityPill(state)
                    }
                    HStack(spacing: Space.s) {
                        AvatarStack(initials: members.map(\.initials), size: 24)
                        Text(detail(for: crew, members: members, state: state))
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.red : Palette.ink3)
                    .accessibilityHidden(true)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Palette.red : Color.clear, lineWidth: 2)
            )
            .opacity(isOff ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOff || !canAssign)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func detail(for crew: Crew, members: [StaffMember], state: AppStore.CrewAvailability) -> String {
        switch state {
        case .available:
            let names = members.map { $0.id == crew.leadID ? "\($0.shortName) (lead)" : $0.shortName }.joined(separator: ", ")
            return names.isEmpty ? crew.truck : "\(names) · \(crew.truck)"
        case let .overlaps(name, until):
            return "On \(name) until ~\(Fmt.time(until))"
        case .off:
            return "Unavailable — marked off by lead"
        }
    }

    @ViewBuilder
    private func availabilityPill(_ state: AppStore.CrewAvailability) -> some View {
        switch state {
        case .available:
            Pill(text: "Available", tone: .green, symbol: "checkmark")
        case let .overlaps(_, until):
            Pill(text: "Overlaps until \(Fmt.clock(until))", tone: .amber, symbol: "exclamationmark.triangle.fill")
        case .off:
            Pill(text: "Off \(route.date.formatted(.dateTime.weekday(.wide)))", tone: .neutral, symbol: "moon.zzz")
        }
    }

    // MARK: Individuals

    private var assignablePeople: [StaffMember] {
        store.staff.filter { $0.crewID != nil }.sorted { $0.name < $1.name }
    }

    private var individualsList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            NoticeCard(symbol: "info.circle", text: "Routes are assigned to a whole crew. Choosing a person assigns their crew.", tone: .blue)
            CardList(data: assignablePeople, inset: 52) { person in
                personRow(person)
            }
        }
    }

    private func personRow(_ person: StaffMember) -> some View {
        let crew = store.crew(person.crewID)
        let state: AppStore.CrewAvailability = crew.map { availability($0) } ?? .off
        let isSelected = crew != nil && selected == crew?.id
        return Button {
            if let crew { selected = crew.id }
        } label: {
            HStack(spacing: Space.m) {
                Avatar(initials: person.initials, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("\(crew?.name ?? "No crew")\(person.isLead ? " · lead" : "")")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: Space.s)
                availabilityPill(state)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.red : Palette.ink3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(crew == nil || state == .off || !canAssign)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Assign

    private func assign() {
        guard canAssign, let crewID = selected, let crew = store.crew(crewID) else { return }
        store.assignCrew(crewID, to: route.id)
        Haptics.success()
        if store.isOnline {
            toasts.show(notify ? "\(crew.name) assigned · notification queued" : "\(crew.name) assigned")
        } else {
            toasts.show("\(crew.name) assigned · saved on this iPhone, sends automatically", symbol: "wifi.slash", tone: .amber)
        }
        onAssigned?(crewID, notify)
        dismiss()
    }
}

#Preview("Crew Assign") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CrewAssignSheet(routeID: Fixtures.ID.routeSweep)
        }
        .previewEnvironment()
}
