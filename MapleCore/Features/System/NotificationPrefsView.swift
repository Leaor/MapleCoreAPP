import SwiftUI
import UIKit
import UserNotifications
import MapleCoreKit

/// Which notifications this person gets, the daily summary time and quiet hours.
/// Rows a role can't use (customer messages, review) are hidden for Field.
struct NotificationPrefsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.isRolePreview) private var isRolePreview
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var systemStatus: UNAuthorizationStatus?

    private var isField: Bool { store.activeRole == .field || isRolePreview }

    var body: some View {
        @Bindable var store = store
        List {
            if systemStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Label("Notifications are off for MapleCore", systemImage: "bell.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.amber)
                        Text("These choices apply once you allow notifications in iPhone Settings.")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: Hit.min)
                    }
                    .padding(.vertical, Space.xs)
                }
                .listRowBackground(Palette.surface)
            }

            Section("Dispatch & routes") {
                Toggle(isOn: $store.notificationPrefs.snowDispatch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snow dispatch")
                        Text("Time sensitive").font(.caption).foregroundStyle(Palette.redText)
                    }
                }
                Toggle("Route changes", isOn: $store.notificationPrefs.routeChanges)
                Toggle("Crew running late", isOn: $store.notificationPrefs.crewRunningLate)
            }
            .listRowBackground(Palette.surface)

            Section("Messages") {
                if !isField {
                    Toggle("Customer messages", isOn: $store.notificationPrefs.customerMessages)
                }
                Toggle("Crew messages", isOn: $store.notificationPrefs.crewMessages)
                Toggle(isOn: $store.notificationPrefs.urgentOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Urgent requests only")
                        Text("Mutes routine messages; urgent ones still come through.")
                            .font(.caption)
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
            .listRowBackground(Palette.surface)

            if !isField && store.capabilities.contains(.visitReview) {
                Section("Review") {
                    Toggle("Visits ready for review", isOn: $store.notificationPrefs.visitsReadyForReview)
                }
                .listRowBackground(Palette.surface)
            }

            Section("Daily summary") {
                Toggle("Daily summary", isOn: $store.notificationPrefs.dailySummary)
                if store.notificationPrefs.dailySummary {
                    HourPicker(title: "Time", hour: $store.notificationPrefs.dailySummaryHour)
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                Toggle("Quiet hours", isOn: $store.notificationPrefs.quietHoursEnabled)
                if store.notificationPrefs.quietHoursEnabled {
                    HourPicker(title: "From", hour: $store.notificationPrefs.quietStartHour)
                    HourPicker(title: "To", hour: $store.notificationPrefs.quietEndHour)
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Snow dispatch still reaches you during quiet hours. Focus modes on your iPhone are respected for everything else.")
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .motionAnimation(value: store.notificationPrefs)
        .task { await refreshSystemStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from iPhone Settings: pick up a changed permission.
            if phase == .active { Task { await refreshSystemStatus() } }
        }
    }

    private func refreshSystemStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        systemStatus = status
    }
}

/// Hour-of-day menu picker ("6:00 PM").
private struct HourPicker: View {
    var title: String
    @Binding var hour: Int

    var body: some View {
        Picker(title, selection: $hour) {
            ForEach(0..<24, id: \.self) { value in
                Text(Self.label(for: value)).tag(value)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: Hit.min)
    }

    static func label(for hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return Fmt.time(date)
    }
}

#Preview("Notification Preferences") {
    NavigationStack {
        NotificationPrefsView()
    }
    .previewEnvironment()
}
