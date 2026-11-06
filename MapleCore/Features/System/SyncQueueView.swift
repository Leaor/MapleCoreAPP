import SwiftUI
import MapleCoreKit

/// Sync & Uploads: what's waiting on this iPhone, what needs a decision, and what was sent.
/// Phase 1 has no server, so the screen says that the transport is simulated.
struct SyncQueueView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts

    @State private var conflictToResolve: ConflictSelection?

    private struct ConflictSelection: Identifiable {
        let id: SyncConflict.ID
    }

    var body: some View {
        @Bindable var model = model
        let pending = store.pendingOutbox
        let attention = store.attentionOutbox
        let sent = store.sentOutbox

        List {
            Section {
                SyncStatusCard()
            }
            .listRowBackground(Palette.surface)

            if pending.isEmpty && attention.isEmpty {
                Section {
                    EmptyStateView(symbol: "checkmark.icloud", title: "Everything's sent", message: "Visits, photos and notes from this iPhone have all been delivered.")
                        .padding(.vertical, -Space.l)
                }
                .listRowBackground(Palette.surface)
            }

            if !pending.isEmpty {
                Section("Waiting to send · \(pending.count)") {
                    ForEach(pending) { item in
                        OutboxRow(item: item)
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !attention.isEmpty {
                Section("Needs attention · \(attention.count)") {
                    ForEach(attention) { item in
                        AttentionOutboxRow(item: item, onRetry: { retry(item) }, onResolve: { conflictID in
                            conflictToResolve = ConflictSelection(id: conflictID)
                        })
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !pending.isEmpty || !attention.isEmpty {
                Section {
                    Button {
                        store.sendNow()
                        Haptics.impact(.light)
                    } label: {
                        Label("Try Sending Now", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity, minHeight: Hit.min)
                    }
                    .disabled(!store.isOnline)
                } footer: {
                    if !store.isOnline {
                        Text("You're offline. Everything sends automatically when you reconnect.")
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !sent.isEmpty {
                Section {
                    ForEach(sent.prefix(10)) { item in
                        OutboxRow(item: item)
                    }
                } header: {
                    HStack {
                        Text("Recently sent")
                        Spacer()
                        Button("Clear") {
                            withMotion { store.clearSent() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .accessibilityLabel("Clear recently sent")
                    }
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                Toggle(isOn: $model.simulateOffline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simulate offline")
                        Text("Demo / testing control. Keeps work on this iPhone as if there were no signal.")
                            .font(.caption)
                            .foregroundStyle(Palette.ink2)
                    }
                }
                .frame(minHeight: Hit.min)
            } header: {
                Text("Testing")
            } footer: {
                Text("Demo server: in this preview build uploads are simulated on this iPhone; nothing is sent to MapleCore yet.")
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Sync & Uploads")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.sendNow() }
        .motionAnimation(value: store.outbox.count)
        .sheet(item: $conflictToResolve) { selection in
            SyncConflictSheet(conflictID: selection.id)
        }
    }

    private func retry(_ item: OutboxItem) {
        store.retry(item.id)
        Haptics.impact(.light)
        if !store.isOnline {
            toasts.show("Queued · sends when you're back online", symbol: "clock.arrow.circlepath", tone: .amber)
        }
    }
}

// MARK: - Status

private struct SyncStatusCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: store.isOnline ? "checkmark.icloud" : "wifi.slash")
                .font(.title2)
                .foregroundStyle(store.isOnline ? Palette.green : Palette.amber)
                .frame(width: 44, height: 44)
                .background(store.isOnline ? Palette.greenSoft : Palette.amberSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(store.isOnline ? "Online" : "You're offline")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let last = store.lastSyncedAt.map { "Last synced \(Fmt.time($0))." } ?? "Not synced yet."
        if store.isOnline {
            return store.pendingOutbox.isEmpty ? "\(last) New work sends as soon as it's saved." : "\(last) Sending what's waiting now."
        }
        return "\(last) Keep working — visits, photos and notes are safe on this iPhone and send automatically."
    }
}

// MARK: - Rows

private extension OutboxKind {
    var symbol: String {
        switch self {
        case .visitUpdate: "checklist"
        case .photoUpload: "photo.on.rectangle"
        case .note: "note.text"
        case .message: "bubble.left"
        }
    }
}

private struct OutboxRow: View {
    @Environment(AppStore.self) private var store
    var item: OutboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: Space.s)
                SyncBadge(state: item.state, completed: item.completedUnits, total: item.totalUnits)
            }
            if item.totalUnits > 1 && item.state != .sent {
                ProgressView(value: Double(min(item.completedUnits, item.totalUnits)), total: Double(item.totalUnits))
                    .tint(Palette.blue)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if !item.detail.isEmpty { parts.append(item.detail) }
        if item.byteCount > 0 { parts.append(Fmt.bytes(item.byteCount)) }
        if item.totalUnits > 1 { parts.append("\(item.completedUnits) of \(item.totalUnits) uploaded") }
        parts.append("saved \(Fmt.clock(item.createdAt))")
        return parts.joined(separator: " · ")
    }
}

private struct AttentionOutboxRow: View {
    var item: OutboxItem
    var onRetry: () -> Void
    var onResolve: (SyncConflict.ID) -> Void

    private var attempts: Int? {
        if case let .failed(count) = item.state { return count }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: item.conflictID == nil ? "exclamationmark.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(Palette.redText)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.s)
            if let conflictID = item.conflictID {
                Button("Resolve") { onResolve(conflictID) }
                    .buttonStyle(.mc(.tinted, compact: true))
                    .fixedSize()
                    .accessibilityHint("Choose which version of the notes to keep")
            } else {
                Button("Retry", action: onRetry)
                    .buttonStyle(.mc(.secondary, compact: true))
                    .fixedSize()
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var detail: String {
        if let attempts { return "\(item.detail) · tried \(Fmt.plural(attempts, "time"))" }
        return item.detail
    }
}

#Preview("Sync & Uploads") {
    NavigationStack {
        SyncQueueView()
    }
    .previewEnvironment()
}
