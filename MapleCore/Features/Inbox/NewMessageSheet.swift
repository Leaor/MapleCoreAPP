import SwiftUI
import MapleCoreKit

/// Picks (or starts) a thread: announcement, crew, staff or customer. Calls `onOpen` then dismisses.
/// In the Field shell only staff and crew options are offered.
struct NewMessageSheet: View {
    var onOpen: (MessageThread.ID) -> Void
    /// Opens straight into writing an announcement (Inbox empty state).
    var announcementOnly: Bool = false

    init(onOpen: @escaping (MessageThread.ID) -> Void, announcementOnly: Bool = false) {
        self.onOpen = onOpen
        self.announcementOnly = announcementOnly
    }

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var query = ""
    @State private var announcementText = ""
    @State private var isWritingAnnouncement = false

    private var isFieldContext: Bool { isRolePreview || store.inboxIsFieldContext }

    private var crews: [Crew] {
        let ownCrew = store.crewID(forStaff: store.inboxViewerID)
        return store.crews
            .filter { store.crewThread(for: $0.id) != nil }
            .filter { !isFieldContext || $0.id == ownCrew }
            .filter { matches($0.name + " " + store.crewMemberNames($0.id)) }
    }

    private var people: [StaffMember] {
        store.staff
            .filter { $0.id != store.inboxViewerID }
            .filter { matches($0.name + " " + $0.jobTitle) }
            .sorted { $0.name < $1.name }
    }

    private var customers: [Customer] {
        guard !isFieldContext else { return [] }
        return store.customers
            .filter { store.customerThread(forCustomer: $0.id) != nil }
            .filter { customer in
                let properties = store.properties(of: customer.id).map(\.name).joined(separator: " ")
                return matches(customer.name + " " + properties + " " + (customer.primaryContact?.name ?? ""))
            }
            .sorted { $0.name < $1.name }
    }

    private var showsAnnouncement: Bool {
        !isFieldContext && store.inboxAnnouncementThread != nil && matches("Announcement all crews")
    }

    var body: some View {
        NavigationStack {
            Group {
                if announcementOnly || isWritingAnnouncement {
                    announcementForm
                } else {
                    pickerList
                }
            }
            .navigationTitle(announcementOnly || isWritingAnnouncement ? "Announcement" : "New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!announcementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Picker

    private var pickerList: some View {
        List {
            if showsAnnouncement, let thread = store.inboxAnnouncementThread {
                Section {
                    Button {
                        open(thread.id)
                    } label: {
                        NewMessageOptionRow(title: "Announcement to all crews", subtitle: thread.subtitle) {
                            InboxThreadAvatar(thread: thread, size: 40)
                        }
                    }
                    Button {
                        withMotion { isWritingAnnouncement = true }
                    } label: {
                        Label("Write a new announcement", systemImage: "megaphone")
                            .frame(minHeight: Hit.min)
                    }
                }
            }
            if !crews.isEmpty {
                Section("Crews") {
                    ForEach(crews) { crew in
                        Button {
                            if let id = store.crewThread(for: crew.id)?.id { open(id) }
                        } label: {
                            NewMessageOptionRow(title: crew.name, subtitle: store.crewMemberNames(crew.id)) {
                                CrewBadge(letter: crew.letter, size: 40)
                            }
                        }
                    }
                }
            }
            if !people.isEmpty {
                Section("Team") {
                    ForEach(people) { person in
                        Button {
                            openDirect(with: person)
                        } label: {
                            NewMessageOptionRow(title: person.name, subtitle: subtitle(for: person)) {
                                Avatar(initials: person.initials, size: 40)
                            }
                        }
                    }
                }
            }
            if !customers.isEmpty {
                Section {
                    ForEach(customers) { customer in
                        Button {
                            if let id = store.customerThread(forCustomer: customer.id)?.id { open(id) }
                        } label: {
                            NewMessageOptionRow(title: customer.primaryContact?.name ?? customer.name, subtitle: customer.name) {
                                Avatar(initials: customer.initials, size: 40, tone: .blue)
                            }
                        }
                    }
                } header: {
                    Text("Customers")
                } footer: {
                    Text("Customers with an existing conversation. Customer messages are visible to the customer unless marked Internal.")
                }
            }
            if crews.isEmpty && people.isEmpty && customers.isEmpty && !showsAnnouncement {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: isFieldContext ? "Search team" : "Search people, crews, customers")
        .tint(Palette.ink)
    }

    private func subtitle(for person: StaffMember) -> String {
        let crew = store.crew(person.crewID)?.name
        return [person.jobTitle, crew].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Announcement

    private var announcementForm: some View {
        Form {
            Section {
                TextField("Message to all crews", text: $announcementText, axis: .vertical)
                    .lineLimit(4...10)
            } header: {
                Text("All crews")
            } footer: {
                Text(store.isOnline
                     ? "Everyone on a crew sees this in Messages. Read receipts appear under the announcement."
                     : "You're offline. The announcement is saved on this iPhone and sends automatically.")
            }
            Section {
                Button {
                    postAnnouncement()
                } label: {
                    Text("Send to All Crews")
                }
                .buttonStyle(.mc(.primary))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(announcementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isReadOnly)
            }
        }
    }

    // MARK: Actions

    private func open(_ id: MessageThread.ID) {
        onOpen(id)
        dismiss()
    }

    private func openDirect(with person: StaffMember) {
        if let id = store.directThread(with: person.id) {
            open(id)
        } else {
            toasts.show("Preview only — new conversations can't be started", symbol: "eye", tone: .blue)
        }
    }

    private func postAnnouncement() {
        guard let id = store.inboxAnnouncementThread?.id else { return }
        store.postAnnouncement(announcementText)
        Haptics.success()
        toasts.show(store.isOnline ? "Announcement queued to send" : "Saved on this iPhone · sends automatically")
        announcementText = ""
        open(id)
    }

    private func matches(_ text: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || text.localizedCaseInsensitiveContains(trimmed)
    }
}

/// Avatar + title + subtitle row used by the picker.
private struct NewMessageOptionRow<Leading: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Space.m) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("New message") {
    NewMessageSheet(onOpen: { _ in })
        .previewEnvironment()
}

#Preview("Announcement") {
    NewMessageSheet(onOpen: { _ in }, announcementOnly: true)
        .previewEnvironment()
}
