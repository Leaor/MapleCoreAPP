import SwiftUI
import MapleCoreKit

/// Admin "More" tab: account, business, team & operations, and app settings.
/// Rows are gated by capabilities so managers and supervisors only see what they can use.
struct MoreView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            accountSection
            if store.capabilities.contains(.finance) {
                businessSection
            }
            teamSection
            settingsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            NavigationLink(value: AppDestination.settings) {
                HStack(spacing: Space.m) {
                    Text(store.account?.initials ?? "–")
                        .font(.headline)
                        .foregroundStyle(Palette.background)
                        .frame(width: 52, height: 52)
                        .background(Palette.ink, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.account?.displayName ?? "Signed out")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(accountDetail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                    }
                }
                .padding(.vertical, Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens Settings")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var accountDetail: String {
        guard let account = store.account else { return "" }
        var parts = [account.jobTitle]
        if let role = store.activeRole { parts.append(role.title) }
        parts.append(account.company)
        return parts.joined(separator: " · ")
    }

    private var businessSection: some View {
        Section("Business") {
            NavigationLink(value: AppDestination.quotes) {
                MoreRow(title: "Quotes", symbol: "doc.text") {
                    let count = store.quotesAwaitingCount
                    if count > 0 { Pill(text: "\(count) awaiting", tone: .blue) }
                }
            }
            NavigationLink(value: AppDestination.invoices) {
                MoreRow(title: "Invoices", symbol: "dollarsign.circle") {
                    let count = store.overdueInvoices.count
                    if count > 0 { Pill(text: "\(count) overdue", tone: .red, symbol: "exclamationmark.circle") }
                }
            }
            if store.capabilities.contains(.analytics) {
                NavigationLink(value: AppDestination.analytics) {
                    MoreRow(title: "Analytics", symbol: "chart.bar") { EmptyView() }
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var teamSection: some View {
        Section("Team & operations") {
            NavigationLink(value: AppDestination.staff) {
                MoreRow(title: "Team & Crews", symbol: "person.3") { EmptyView() }
            }
            if store.capabilities.contains(.snowDispatch) {
                NavigationLink(value: AppDestination.snowOps) {
                    MoreRow(title: "Snow Operations", symbol: "snowflake") {
                        if store.snowEvent != nil { Pill(text: "Live", tone: .red, symbol: "dot.radiowaves.left.and.right") }
                    }
                }
            }
            NavigationLink(value: AppDestination.syncQueue) {
                MoreRow(title: "Sync & Uploads", symbol: "arrow.triangle.2.circlepath") {
                    let status = store.syncStatusSummary
                    Text(status.text)
                        .font(.subheadline)
                        .foregroundStyle(status.tone == .green ? Palette.ink2 : status.tone.foreground)
                }
            }
            Button {
                store.beginRolePreview()
                model.isFieldPreviewPresented = true
            } label: {
                MoreRow(title: "Preview Field Mode", symbol: "eye") {
                    Text("Read-only")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .accessibilityHint("Shows the crew app as Daniel sees it. Nothing you do there is saved.")
        }
        .listRowBackground(Palette.surface)
    }

    private var settingsSection: some View {
        Section {
            NavigationLink(value: AppDestination.settings) {
                MoreRow(title: "Settings", symbol: "gearshape") { EmptyView() }
            }
            NavigationLink(value: AppDestination.notificationPrefs) {
                MoreRow(title: "Notifications", symbol: "bell") { EmptyView() }
            }
            if store.capabilities.contains(.customerMessaging) {
                NavigationLink(value: AppDestination.pushTemplates) {
                    MoreRow(title: "Notification templates", symbol: "app.badge") { EmptyView() }
                }
            }
        }
        .listRowBackground(Palette.surface)
    }
}

/// Icon tile + title + trailing accessory, used by More and Settings rows.
struct MoreRow<Accessory: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .frame(width: 30, height: 30)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Space.s)
            accessory()
        }
        .frame(minHeight: Hit.min)
        .accessibilityElement(children: .combine)
    }
}

#Preview("More") {
    NavigationStack {
        MoreView().appDestinations()
    }
    .previewEnvironment()
}
