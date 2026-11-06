import SwiftUI
import MapleCoreKit

/// Crew cards with today's status, members, route progress and truck.
struct CrewManagementView: View {
    @Environment(AppStore.self) private var store
    @State private var showsNewCrew = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                if store.crews.isEmpty {
                    EmptyStateView(symbol: "person.3", title: "No crews yet", message: "Group your team into crews so routes can be assigned.")
                }
                ForEach(store.crews) { crew in
                    CrewCardLink(crew: crew)
                }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle("Crews")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.capabilities.contains(.staffManagement) {
                    Button {
                        showsNewCrew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New crew")
                    .disabled(store.isReadOnly)
                }
            }
        }
        .sheet(isPresented: $showsNewCrew) {
            NewCrewSheet()
        }
    }
}

/// Wraps a crew card in a link to today's route (live) or its summary (finished).
private struct CrewCardLink: View {
    @Environment(AppStore.self) private var store
    let crew: Crew

    var body: some View {
        let route = store.bizTodayRoute(forCrew: crew.id)
        if let route {
            NavigationLink(value: route.state == .completed ? AppDestination.routeSummary(route.id) : AppDestination.route(route.id)) {
                CrewCard(crew: crew, route: route, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(route.state == .completed ? "Opens the route summary" : "Opens the route map")
        } else {
            CrewCard(crew: crew, route: nil, showsChevron: false)
        }
    }
}

private struct CrewCard: View {
    @Environment(AppStore.self) private var store
    let crew: Crew
    let route: Route?
    let showsChevron: Bool

    var body: some View {
        let status = store.bizCrewStatus(crew)
        let members = store.members(of: crew)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                CrewBadge(letter: crew.letter, size: 40)
                Text(crew.name)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                Pill(text: status.text, tone: status.tone, symbol: status.symbol)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: Space.s) {
                AvatarStack(initials: members.map(\.initials))
                Text(memberLine(members))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            if let route {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("\(route.name) · \(route.finishedCount)/\(route.stops.count)")
                            .font(.subheadline.weight(.semibold))
                            .numeric()
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.s)
                        Label(crew.truck, systemImage: "truck.box")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                    RouteProgressBar(stops: route.stops)
                }
            } else {
                Label(crew.truck, systemImage: "truck.box")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func memberLine(_ members: [StaffMember]) -> String {
        var names = members.map { $0.id == crew.leadID ? "\($0.firstName) (lead)" : $0.firstName }
        if names.isEmpty { names = ["No members"] }
        var line = names.joined(separator: ", ")
        if crew.isSnowReady { line += " · snow-ready" }
        return line
    }
}

/// New crew: lead, members, truck.
private struct NewCrewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var leadID: StaffMember.ID?
    @State private var memberIDs: Set<StaffMember.ID> = []
    @State private var truck = ""

    private var candidates: [StaffMember] {
        store.staff.filter { $0.id != store.account?.staffID }.sorted { $0.name < $1.name }
    }

    private var isValid: Bool { leadID != nil && !truck.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Crew lead", selection: $leadID) {
                        Text("Choose…").tag(StaffMember.ID?.none)
                        ForEach(candidates) { person in
                            Text(person.name).tag(StaffMember.ID?.some(person.id))
                        }
                    }
                    TextField("Truck, e.g. Truck 5", text: $truck)
                }
                Section {
                    ForEach(candidates.filter { $0.id != leadID }) { person in
                        Button {
                            toggle(person.id)
                        } label: {
                            HStack(spacing: Space.m) {
                                Avatar(initials: person.initials, size: 32)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(person.name).foregroundStyle(Palette.ink)
                                    Text(store.crew(person.crewID).map { "Now in \($0.name)" } ?? "No crew")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.ink2)
                                }
                                Spacer()
                                Image(systemName: memberIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(memberIDs.contains(person.id) ? Palette.red : Palette.ink3)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(memberIDs.contains(person.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Members")
                } footer: {
                    Text("People already on a crew move to the new crew.")
                }
            }
            .navigationTitle("New Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!isValid || store.isReadOnly)
                }
            }
            .sensoryFeedback(.selection, trigger: memberIDs)
        }
        .interactiveDismissDisabled(leadID != nil || !memberIDs.isEmpty)
    }

    private func toggle(_ id: StaffMember.ID) {
        if memberIDs.contains(id) { memberIDs.remove(id) } else { memberIDs.insert(id) }
    }

    private func create() {
        guard let leadID else { return }
        store.createCrew(leadID: leadID, memberIDs: Array(memberIDs.subtracting([leadID])), truck: truck.trimmingCharacters(in: .whitespaces))
        Haptics.success()
        toasts.show("Crew created")
        dismiss()
    }
}

#Preview("Crews") {
    NavigationStack {
        CrewManagementView().appDestinations()
    }
    .previewEnvironment()
}
