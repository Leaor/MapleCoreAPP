import SwiftUI
import MapleCoreKit

/// Team directory: on duty / off duty, honest location states, quick message.
struct StaffDirectoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @State private var showsInvite = false

    private var people: [StaffMember] {
        store.staff.filter { $0.id != store.account?.staffID }
    }

    var body: some View {
        let people = self.people
        let onDuty = people.filter(\.isOnDuty).sorted(by: Self.order)
        let offDuty = people.filter { !$0.isOnDuty }.sorted(by: Self.order)
        List {
            Section {
                Picker("Team view", selection: teamViewBinding) {
                    Text("People").tag(0)
                    Text("Crews").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if people.isEmpty {
                EmptyStateView(symbol: "person.2", title: "No team members yet", message: "Invite your crew so they can see routes and send visit reports.")
                    .listRowBackground(Color.clear)
            }
            if !onDuty.isEmpty {
                Section("On duty · \(onDuty.count)") {
                    ForEach(onDuty) { person in row(person) }
                }
            }
            if !offDuty.isEmpty {
                Section("Off duty · \(offDuty.count)") {
                    ForEach(offDuty) { person in row(person) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Team")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.capabilities.contains(.staffManagement) {
                    Button {
                        showsInvite = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Invite team member")
                    .disabled(store.isReadOnly)
                }
            }
        }
        .sheet(isPresented: $showsInvite) {
            InviteStaffSheet()
        }
    }

    /// Selecting "Crews" pushes Crew Management; this screen always shows People.
    private var teamViewBinding: Binding<Int> {
        Binding(get: { 0 }, set: { value in
            if value == 1 { model.push(.crews) }
        })
    }

    private static func order(_ lhs: StaffMember, _ rhs: StaffMember) -> Bool {
        let l = lhs.crewID ?? "~", r = rhs.crewID ?? "~"
        if l != r { return l < r }
        if lhs.isLead != rhs.isLead { return lhs.isLead }
        return lhs.name < rhs.name
    }

    private func row(_ person: StaffMember) -> some View {
        HStack(spacing: Space.s) {
            NavigationLink(value: AppDestination.employee(person.id)) {
                BizStaffRow(person: person, showsLocation: store.capabilities.contains(.staffLocation))
            }
            Button {
                message(person)
            } label: {
                Image(systemName: "message")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.redText)
                    .frame(width: Hit.min, height: Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Message \(person.firstName)")
        }
    }

    private func message(_ person: StaffMember) {
        if let id = store.directThread(with: person.id) {
            model.push(.thread(id))
        } else {
            toasts.show("Preview only — new conversations can't be started", symbol: "eye", tone: .blue)
        }
    }
}

/// Avatar, name, role · crew, and location line.
struct BizStaffRow: View {
    @Environment(AppStore.self) private var store
    let person: StaffMember
    var showsLocation = true

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Avatar(initials: person.initials, size: 40, tone: person.isOnDuty ? .green : .neutral)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(roleLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                if person.isOnDuty && showsLocation {
                    BizStaffLocationLine(location: person.location, now: store.now)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var roleLine: String {
        var parts: [String] = []
        if person.isLead { parts.append(person.jobTitle) }
        if let crew = store.crew(person.crewID)?.name { parts.append(crew) } else if !person.isLead { parts.append(person.jobTitle) }
        if !person.isOnDuty, let starts = person.shiftStartsAt, starts > store.now { parts.append("starts \(Fmt.clock(starts))") }
        return parts.joined(separator: " · ")
    }
}

/// Three distinct location states. Never guesses a position.
struct BizStaffLocationLine: View {
    let location: LocationShare
    let now: Date

    var body: some View {
        switch location {
        case let .live(place, updatedAt):
            Label {
                Text("Live · \(place) · \(Fmt.ago(updatedAt, now: now))")
            } icon: {
                Image(systemName: "location.fill")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.blue)
        case let .lastReported(at):
            Label("Last reported \(Fmt.ago(at, now: now))", systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
        case let .notShared(lastArrival):
            Label(lastArrival.map { "Location not shared · last arrival \(Fmt.clock($0))" } ?? "Location not shared", systemImage: "location.slash")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }
}

/// Invite a team member: name, email, phone, crew.
private struct InviteStaffSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var crewID: Crew.ID?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool {
        !trimmedName.isEmpty && (!email.trimmingCharacters(in: .whitespaces).isEmpty || !phone.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Mobile phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } footer: {
                    Text("They get a sign-in code by email or text. Add an email or a phone number.")
                }
                Section {
                    Picker("Crew", selection: $crewID) {
                        Text("No crew yet").tag(Crew.ID?.none)
                        ForEach(store.crews) { crew in
                            Text(crew.name).tag(Crew.ID?.some(crew.id))
                        }
                    }
                }
            }
            .navigationTitle("Invite Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { invite() }
                        .disabled(!isValid || store.isReadOnly)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!trimmedName.isEmpty)
    }

    private func invite() {
        store.addStaff(name: trimmedName, email: email.trimmingCharacters(in: .whitespaces), phone: phone.trimmingCharacters(in: .whitespaces), crewID: crewID)
        Haptics.success()
        toasts.show(store.isOnline ? "Invite queued for \(trimmedName)" : "Invite saved on this iPhone · sends automatically")
        dismiss()
    }
}

#Preview("Team") {
    NavigationStack {
        StaffDirectoryView().appDestinations()
    }
    .previewEnvironment()
}
