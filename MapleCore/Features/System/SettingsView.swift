import SwiftUI
import MapleCoreKit

/// Account, display and offline settings. Shared by Admin (More) and Field (Profile);
/// admin-only rows are hidden in the Field role.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var confirmSignOut = false
    @State private var confirmReset = false

    private var isField: Bool { store.activeRole == .field || isRolePreview }

    var body: some View {
        List {
            accountSection(store: store)
            displaySection(store: store)
            dataSection(store: store)
            sessionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of MapleCore?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive, action: signOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(signOutMessage)
        }
        .confirmationDialog("Reset demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Demo Data", role: .destructive, action: resetDemoData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores the preview's sample routes, properties and messages, and signs you out. Changes you made in this preview are removed from this iPhone.")
        }
    }

    // MARK: Account

    private func accountSection(store: AppStore) -> some View {
        @Bindable var store = store
        return Section("Account") {
            if let account = store.account {
                KeyValueRow(label: "Role", value: roleText(account))
                if !isField {
                    KeyValueRow(label: "Company", value: account.company)
                }
                if account.hasMultipleRoles && !isRolePreview {
                    Button {
                        switchRole(account)
                    } label: {
                        Label(store.activeRole == .field ? "Switch to Admin" : "Switch to Field", systemImage: "arrow.left.arrow.right")
                    }
                    .frame(minHeight: Hit.min)
                }
            }
            Toggle(isOn: $store.settings.faceIDEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Face ID")
                    Text("Saved for this iPhone. The preview build doesn't lock the app yet.")
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .frame(minHeight: Hit.min)
        }
        .listRowBackground(Palette.surface)
    }

    private func roleText(_ account: Account) -> String {
        if let role = store.activeRole { return "\(account.jobTitle) · \(role.title)" }
        return account.jobTitle
    }

    // MARK: Display

    private func displaySection(store: AppStore) -> some View {
        @Bindable var store = store
        return Section {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Appearance")
                Picker("Appearance", selection: $store.settings.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, Space.xs)
            Toggle(isOn: $store.settings.gloveMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glove mode")
                    Text("Larger buttons, swipe-free actions")
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .frame(minHeight: Hit.min)
            Toggle("Haptics", isOn: $store.settings.haptics)
                .frame(minHeight: Hit.min)
        } header: {
            Text("Display")
        } footer: {
            Text("Text size follows your iPhone's Dynamic Type setting.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Data & offline

    private func dataSection(store: AppStore) -> some View {
        @Bindable var store = store
        return Section("Data & offline") {
            Toggle("Save today's routes offline", isOn: $store.settings.saveRoutesOffline)
                .frame(minHeight: Hit.min)
            Toggle("Upload photos on cellular", isOn: $store.settings.uploadOnCellular)
                .frame(minHeight: Hit.min)
            NavigationLink(value: AppDestination.syncQueue) {
                HStack {
                    Text("Sync & uploads")
                    Spacer(minLength: Space.s)
                    let status = store.syncStatusSummary
                    Text(status.text)
                        .foregroundStyle(status.tone == .green ? Palette.ink2 : status.tone.foreground)
                }
            }
            NavigationLink(value: AppDestination.notificationPrefs) {
                Text("Notifications")
            }
            if !isField && store.capabilities.contains(.customerMessaging) {
                NavigationLink(value: AppDestination.pushTemplates) {
                    Text("Notification templates")
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Session

    private var sessionSection: some View {
        Section {
            Button("Reset Demo Data") { confirmReset = true }
                .foregroundStyle(Palette.ink)
                .frame(minHeight: Hit.min)
                .disabled(isRolePreview)
            Button("Sign Out", role: .destructive) { confirmSignOut = true }
                .foregroundStyle(Palette.redText)
                .frame(minHeight: Hit.min)
                .disabled(isRolePreview)
        } footer: {
            VStack(alignment: .leading, spacing: Space.s) {
                if isRolePreview {
                    Text("You're previewing Field Mode. Exit the preview to sign out or reset data.")
                }
                Text("MapleCore Operations · Phase 1 preview")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Space.l)
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var signOutMessage: String {
        let pending = store.pendingOutbox.count + store.attentionOutbox.count
        if pending > 0 {
            return "\(Fmt.plural(pending, "item")) on this iPhone haven't been sent yet. Signing out keeps this preview's data on the iPhone, but check Sync & Uploads first."
        }
        return "You'll need a new code to sign back in."
    }

    // MARK: Actions

    private func switchRole(_ account: Account) {
        let target: AppRole = store.activeRole == .field ? (account.roles.first(where: \.usesAdminShell) ?? .admin) : .field
        store.choose(role: target)
        Haptics.selection()
    }

    private func signOut() {
        KeychainStore.delete(KeychainStore.sessionTokenKey)
        store.signOut()
    }

    private func resetDemoData() {
        KeychainStore.delete(KeychainStore.sessionTokenKey)
        store.resetToFixtures()
        toasts.show("Demo data restored", symbol: "arrow.counterclockwise.circle.fill", tone: .blue)
    }
}

#Preview("Settings · Admin") {
    NavigationStack {
        SettingsView().appDestinations()
    }
    .previewEnvironment()
}

#Preview("Settings · Field") {
    NavigationStack {
        SettingsView().appDestinations()
    }
    .previewEnvironment(role: .field)
}
