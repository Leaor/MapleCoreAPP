import SwiftUI
import MapleCoreKit

/// Field Profile: shift, location sharing, availability, history, uploads and settings.
struct FieldProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview

    private var actions: FieldActions { FieldActions(store: store, model: model, toasts: toasts) }

    var body: some View {
        List {
            Section {
                ProfileHeader()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Space.s, leading: 0, bottom: Space.s, trailing: 0))
            }
            Section {
                ProfileShiftSection(actions: actions)
            }
            .listRowBackground(Palette.surface)

            LocationSharingSection(actions: actions)

            Section {
                NavigationLink(value: AppDestination.availability) {
                    LabeledContent("Availability", value: store.fieldAvailabilitySummary)
                }
                NavigationLink(value: AppDestination.shiftHistory) {
                    Text("Shift history")
                }
                NavigationLink(value: AppDestination.syncQueue) {
                    LabeledContent {
                        uploadsStatus
                    } label: {
                        Text("Uploads")
                    }
                }
                NavigationLink(value: AppDestination.settings) {
                    Text("Settings")
                }
            }
            .listRowBackground(Palette.surface)

            if store.account?.hasMultipleRoles == true && !isRolePreview && !store.isReadOnly {
                Section {
                    Button {
                        model.resetNavigation()
                        store.choose(role: .admin)
                    } label: {
                        Label("Switch to Admin", systemImage: "arrow.left.arrow.right")
                            .foregroundStyle(Palette.redText)
                            .frame(minHeight: Hit.min)
                    }
                } footer: {
                    Text("Your field work stays saved on this iPhone.")
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var uploadsStatus: some View {
        let waiting = store.fieldWaitingUploadCount
        let needsYou = store.attentionOutbox.count
        let text: String
        let tone: Tone
        let symbol: String
        if needsYou > 0 {
            text = "\(needsYou) need you"; tone = .red; symbol = "exclamationmark.circle"
        } else if waiting > 0 {
            text = "\(waiting) waiting"; tone = store.isOnline ? .blue : .amber; symbol = "clock.arrow.circlepath"
        } else {
            text = "All uploaded"; tone = .green; symbol = "checkmark.circle.fill"
        }
        return Label(text, systemImage: symbol)
            .foregroundStyle(tone.foreground)
    }
}

// MARK: - Header

private struct ProfileHeader: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let member = store.fieldMember
        HStack(spacing: Space.m + 2) {
            Avatar(initials: member?.initials ?? store.account?.initials ?? "?", size: 60, tone: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(member?.name ?? store.account?.displayName ?? "Crew member")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(roleLine(member))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func roleLine(_ member: StaffMember?) -> String {
        let title = member?.jobTitle ?? store.account?.jobTitle ?? ""
        let crew = store.fieldCrew?.name
        return [title, crew].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Shift

private struct ProfileShiftSection: View {
    @Environment(AppStore.self) private var store
    var actions: FieldActions
    @State private var confirmEnd = false

    var body: some View {
        if let shift = store.activeFieldShift {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("On shift").font(.body.weight(.semibold))
                    Spacer(minLength: Space.s)
                    TimelineView(.everyMinute) { context in
                        let interval = max(0, context.date.timeIntervalSince(shift.startedAt))
                        Text(clock(interval))
                            .font(.title2.weight(.bold))
                            .numeric()
                            .accessibilityLabel(Fmt.spokenDuration(interval))
                    }
                }
                Text(detail(shift))
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                Button("End Shift") { confirmEnd = true }
                    .buttonStyle(.mc(.ink, glove: true))
                    .disabled(store.activeVisit != nil)
                if store.activeVisit != nil {
                    Text("Finish your visit before ending your shift.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .padding(.vertical, Space.s)
            .confirmationDialog("End your shift?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End Shift", role: .destructive) { actions.endShift() }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text("Your hours are saved and location sharing stops.")
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Not on shift").font(.body.weight(.semibold))
                Text("Location sharing only runs while you're on shift.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                Button {
                    actions.startShift()
                } label: {
                    Label("Start Shift", systemImage: "play.fill")
                }
                .buttonStyle(.mc(.primary, glove: true))
            }
            .padding(.vertical, Space.s)
        }
    }

    /// "2:38" hours:minutes.
    private func clock(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func detail(_ shift: Shift) -> String {
        var parts = ["Started \(Fmt.time(shift.startedAt))"]
        parts.append("\(Fmt.plural(store.fieldVisitsCompletedToday, "visit")) completed")
        if shift.breaks > 0 {
            parts.append("\(Fmt.plural(shift.breaks, "break")) (\(Fmt.duration(minutes: shift.breakMinutes)))")
        } else {
            parts.append("No breaks")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Location sharing

private struct LocationSharingSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview
    var actions: FieldActions

    private var isPreview: Bool { isRolePreview || store.isReadOnly }

    var body: some View {
        Section {
            Toggle(isOn: sharingBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share while on shift")
                    TimelineView(.everyMinute) { context in
                        Text(status(at: context.date))
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
            .tint(Palette.green)
            .disabled(isPreview)
            .frame(minHeight: Hit.min)

            TimelineView(.everyMinute) { context in
                if isPaused(at: context.date) {
                    Button("Resume Sharing Now") {
                        guard !actions.blockedByPreview() else { return }
                        store.setLocationSharing(true)
                        Haptics.success()
                        toasts.show("Location sharing resumed")
                    }
                    .foregroundStyle(Palette.redText)
                    .frame(minHeight: Hit.min)
                } else {
                    Button("Pause for 30 minutes") {
                        guard !actions.blockedByPreview() else { return }
                        store.pauseLocationSharing()
                        Haptics.success()
                        let until = store.locationSharing.pausedUntil.map { Fmt.time($0) } ?? ""
                        toasts.show("Paused until \(until)", symbol: "pause.circle.fill", tone: .amber)
                    }
                    .foregroundStyle(store.locationSharing.enabled ? Palette.redText : Palette.ink3)
                    .disabled(!store.locationSharing.enabled)
                    .frame(minHeight: Hit.min)
                }
            }
        } header: {
            Text("Location sharing")
        } footer: {
            Text(isPreview
                 ? "Preview only — location settings belong to the crew member."
                 : "Your manager sees your last location only while sharing is on. You can still check in by tapping Arrived.")
        }
        .listRowBackground(Palette.surface)
    }

    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { store.locationSharing.enabled },
            set: { newValue in
                guard !actions.blockedByPreview() else { return }
                store.setLocationSharing(newValue)
            }
        )
    }

    private func isPaused(at date: Date) -> Bool {
        guard store.locationSharing.enabled, let until = store.locationSharing.pausedUntil else { return false }
        return until > date
    }

    private func status(at date: Date) -> String {
        let sharing = store.locationSharing
        guard sharing.enabled else { return "Off · your manager can't see your location" }
        if let until = sharing.pausedUntil, until > date { return "Paused until \(Fmt.time(until))" }
        if store.activeFieldShift == nil { return "Starts when you start your shift" }
        return "Sharing now · stops when you end your shift"
    }
}

#Preview("Profile") {
    NavigationStack {
        FieldProfileView().appDestinations()
    }
    .previewEnvironment(role: .field)
}
