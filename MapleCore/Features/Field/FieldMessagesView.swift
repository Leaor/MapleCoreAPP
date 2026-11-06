import SwiftUI
import MapleCoreKit

/// Field Messages: pinned announcement, then crew, direct and property threads. Internal only.
struct FieldMessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var isComposing = false

    private var announcementThread: MessageThread? {
        store.fieldThreads
            .filter { $0.kind == .announcement && $0.lastMessage != nil }
            .max { $0.lastActivity < $1.lastActivity }
    }

    private var conversations: [MessageThread] {
        store.fieldThreads.filter { $0.kind != .announcement }
    }

    var body: some View {
        let announcement = announcementThread
        let threads = conversations
        List {
            if let announcement, let message = announcement.lastMessage {
                Section {
                    NavigationLink(value: AppDestination.thread(announcement.id)) {
                        AnnouncementRow(message: message, unread: announcement.unreadCount > 0)
                    }
                    .listRowBackground(Palette.ink)
                }
            }
            Section {
                if threads.isEmpty {
                    Text("No conversations yet. Crew and manager messages will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                        .listRowBackground(Palette.surface)
                } else {
                    ForEach(threads) { thread in
                        NavigationLink(value: AppDestination.thread(thread.id)) {
                            FieldThreadRow(thread: thread, now: store.now)
                        }
                        .listRowBackground(Palette.surface)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isRolePreview || store.isReadOnly {
                        toasts.show("Preview only — messages can't be sent", symbol: "eye", tone: .blue)
                    } else {
                        isComposing = true
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .sheet(isPresented: $isComposing) {
            NewMessageSheet(onOpen: { id in model.push(.thread(id)) })
        }
        .refreshable { await store.syncPending() }
    }
}

// MARK: - Rows

private struct AnnouncementRow: View {
    var message: Message
    var unread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "megaphone.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.background)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if unread {
                        Circle().fill(Palette.red).frame(width: 8, height: 8).accessibilityHidden(true)
                    }
                }
                Text("\(bodyText) — \(message.authorName)")
                    .font(.footnote)
                    .opacity(0.8)
            }
            .foregroundStyle(Palette.background)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Announcement\(unread ? ", unread" : ""): \(message.text) — \(message.authorName)")
    }

    /// First clause as a headline ("Snow watch tonight"), the rest as body.
    private var title: String {
        let parts = message.text.components(separatedBy: " — ")
        return parts.count > 1 ? parts[0] : "Announcement"
    }

    private var bodyText: String {
        let parts = message.text.components(separatedBy: " — ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " — ") : message.text
    }
}

private struct FieldThreadRow: View {
    @Environment(AppStore.self) private var store
    var thread: MessageThread
    var now: Date

    private var isUnread: Bool { thread.unreadCount > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Circle()
                .fill(isUnread ? Palette.red : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 16)
                .accessibilityHidden(true)
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.title)
                        .font(.body.weight(isUnread ? .bold : .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(Fmt.stamp(thread.lastActivity, now: now))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .numeric()
                }
                tag
                Text(preview)
                    .font(.subheadline.weight(isUnread ? .medium : .regular))
                    .foregroundStyle(isUnread ? Palette.ink : Palette.ink2)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var avatar: some View {
        switch thread.kind {
        case .crew:
            CrewBadge(letter: store.crew(thread.crewID)?.letter ?? thread.initials, size: 44)
        case .property:
            Image(systemName: "building.2.fill")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface2, in: Circle())
                .accessibilityHidden(true)
        default:
            Avatar(initials: thread.initials, size: 44, tone: .red)
        }
    }

    @ViewBuilder
    private var tag: some View {
        switch thread.kind {
        case .direct:
            if !thread.subtitle.isEmpty { Pill(text: thread.subtitle, tone: .neutral) }
        case .property:
            Pill(text: "Property notes · internal", tone: .amber, symbol: "lock.fill")
        default:
            EmptyView()
        }
    }

    private var preview: String {
        guard let last = thread.lastMessage else { return "No messages yet" }
        let text = last.text.isEmpty ? "\(Fmt.plural(last.attachments.count, "attachment"))" : last.text
        if thread.kind == .direct || last.isSystemEvent { return text }
        let isMine = last.isMine(store.fieldStaffID)
        return "\(isMine ? "You" : last.authorName): \(text)"
    }

    private var accessibilityText: String {
        var parts = [thread.title]
        if isUnread { parts.append("unread") }
        if thread.kind == .property { parts.append("property notes, internal") }
        if thread.kind == .direct && !thread.subtitle.isEmpty { parts.append(thread.subtitle) }
        parts.append(preview)
        parts.append(Fmt.stamp(thread.lastActivity, now: now))
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Messages") {
    NavigationStack {
        FieldMessagesView().appDestinations()
    }
    .previewEnvironment(role: .field)
}
#endif
