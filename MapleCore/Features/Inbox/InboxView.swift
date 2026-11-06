import SwiftUI
import MapleCoreKit

/// Admin Inbox tab root: customers, crews and announcements in one list.
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var filter: InboxFilter = .all
    @State private var query = ""
    @State private var compose: InboxComposeRequest?

    private var visibleThreads: [MessageThread] {
        let base = store.adminThreads.filter { filter.includes($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return base }
        return base.filter { store.inboxSearchText(for: $0).localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        let threads = visibleThreads
        List {
            Section {
                if threads.isEmpty {
                    emptyContent
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(threads) { thread in
                        NavigationLink(value: AppDestination.thread(thread.id)) {
                            InboxThreadRow(thread: thread)
                        }
                        .listRowBackground(Palette.surface)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if thread.unreadCount > 0 {
                                Button {
                                    withMotion { store.markRead(thread.id) }
                                } label: {
                                    Label("Mark Read", systemImage: "envelope.open")
                                }
                                .tint(Palette.blue)
                            }
                        }
                    }
                }
            } header: {
                FilterChips(options: InboxFilter.allCases, selection: $filter, label: { $0.label }, count: { unreadCount(for: $0) })
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Space.xs)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .motionAnimation(value: threads.map(\.id))
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search people, properties, messages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    compose = InboxComposeRequest(announcementOnly: false)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .sheet(item: $compose) { request in
            NewMessageSheet(onOpen: { id in
                model.push(.thread(id))
            }, announcementOnly: request.announcementOnly)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxxl)
        } else if filter == .all {
            EmptyStateView(symbol: "tray", title: "You're all caught up", message: "Customer requests, crew messages and announcements will appear here.") {
                Button("Send an Announcement") {
                    compose = InboxComposeRequest(announcementOnly: true)
                }
                .buttonStyle(.mc(.ink, compact: true))
                .frame(maxWidth: 280)
            }
        } else {
            EmptyStateView(symbol: "tray", title: "Nothing in \(filter.label)", message: "Threads appear here as soon as a message arrives.")
        }
    }

    private func unreadCount(for option: InboxFilter) -> Int? {
        let count = store.adminThreads.filter { option.includes($0) }.reduce(0) { $0 + $1.unreadCount }
        return count > 0 ? count : nil
    }
}

/// Which compose sheet to show from the Inbox.
struct InboxComposeRequest: Identifiable, Hashable {
    let id = UUID()
    var announcementOnly: Bool
}

/// One inbox row: avatar, title, time, tags, preview, unread state.
struct InboxThreadRow: View {
    @Environment(AppStore.self) private var store
    let thread: MessageThread

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            InboxThreadAvatar(thread: thread)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(thread.title)
                        .font(thread.unreadCount > 0 ? .headline : .body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text(Fmt.stamp(thread.lastActivity, now: store.now))
                        .font(.footnote)
                        .numeric()
                        .foregroundStyle(thread.unreadCount > 0 ? Palette.redText : Palette.ink3)
                }
                tags
                HStack(alignment: .top, spacing: Space.s) {
                    Text(store.inboxPreview(for: thread))
                        .font(.subheadline)
                        .foregroundStyle(thread.unreadCount > 0 ? Palette.ink : Palette.ink2)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption.weight(.bold))
                            .numeric()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Palette.red, in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
                if let seen = store.inboxSeenText(for: thread) {
                    Label(seen, systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var tags: some View {
        let propertyName = store.property(thread.propertyID)?.name
        if thread.isUrgent || thread.kind == .customer || thread.kind == .crew || thread.kind == .property {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xs) { tagContent(propertyName: propertyName) }
                VStack(alignment: .leading, spacing: Space.xs) { tagContent(propertyName: propertyName) }
            }
        }
    }

    @ViewBuilder
    private func tagContent(propertyName: String?) -> some View {
        if thread.isUrgent {
            Pill(text: "Urgent", tone: .red, symbol: "bolt.fill")
        } else if thread.kind == .customer {
            Pill(text: "Customer", tone: .blue, symbol: "person.fill")
        } else {
            Pill(text: "Internal", tone: .amber, symbol: "lock.fill")
        }
        if thread.kind == .customer, let propertyName {
            Text(propertyName)
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
        }
    }

    private var accessibilityText: String {
        var parts = [thread.title]
        if thread.isUrgent { parts.append("Urgent") }
        if thread.unreadCount > 0 { parts.append("\(thread.unreadCount) unread") }
        parts.append(store.inboxPreview(for: thread))
        parts.append(Fmt.stamp(thread.lastActivity, now: store.now))
        if let seen = store.inboxSeenText(for: thread) { parts.append(seen) }
        return parts.joined(separator: ", ")
    }
}

/// Avatar for a thread: crew letter badge for crews, megaphone for announcements, initials otherwise.
struct InboxThreadAvatar: View {
    @Environment(AppStore.self) private var store
    let thread: MessageThread
    var size: CGFloat = 44

    var body: some View {
        switch thread.kind {
        case .crew:
            CrewBadge(letter: store.crew(thread.crewID)?.letter ?? thread.initials, size: size)
        case .announcement:
            Image(systemName: "megaphone.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.redText)
                .frame(width: size, height: size)
                .background(Palette.redSoft, in: Circle())
                .accessibilityHidden(true)
        case .property:
            Image(systemName: "building.2.fill")
                .font(.body)
                .foregroundStyle(Palette.amber)
                .frame(width: size, height: size)
                .background(Palette.amberSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
        case .customer:
            Avatar(initials: thread.initials, size: size, tone: thread.isUrgent ? .red : .blue)
        case .direct:
            Avatar(initials: thread.initials, size: size)
        }
    }
}

#Preview("Inbox") {
    NavigationStack {
        InboxView().appDestinations()
    }
    .previewEnvironment()
}
