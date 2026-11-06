import SwiftUI
import PhotosUI
import MapleCoreKit

/// One conversation, shared by Admin (Inbox) and Field (Messages).
struct ConversationView: View {
    let threadID: MessageThread.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let thread = store.thread(threadID) {
            ConversationContent(thread: thread)
        } else {
            MissingRecordView(title: "Conversation not available")
        }
    }
}

private struct ConversationDayGroup: Identifiable {
    var id: Date
    var title: String
    var messages: [Message]
}

private struct ConversationContent: View {
    let thread: MessageThread

    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview
    @Environment(\.openURL) private var openURL

    @State private var draft = ""
    @State private var audience: MessageVisibility
    @State private var pendingAttachments: [Attachment] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var sentCount = 0
    @FocusState private var composerFocused: Bool

    init(thread: MessageThread) {
        self.thread = thread
        _audience = State(initialValue: thread.kind == .customer ? .customer : .internal)
    }

    // MARK: Derived

    private var viewer: StaffMember.ID? { store.inboxViewerID }
    private var isFieldContext: Bool { isRolePreview || store.inboxIsFieldContext }
    private var isPreviewOnly: Bool { isRolePreview || store.isReadOnly }

    private var dayGroups: [ConversationDayGroup] {
        let calendar = Calendar.current
        var groups: [ConversationDayGroup] = []
        for message in thread.messages {
            let day = calendar.startOfDay(for: message.sentAt)
            if let last = groups.indices.last, groups[last].id == day {
                groups[last].messages.append(message)
            } else {
                let title = "\(Fmt.relativeDay(message.sentAt, now: store.now)) \(Fmt.time(message.sentAt))"
                groups.append(ConversationDayGroup(id: day, title: title, messages: [message]))
            }
        }
        return groups
    }

    private var lastMineID: Message.ID? {
        thread.messages.last { $0.isMine(viewer) && !$0.isSystemEvent }?.id
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        !isPreviewOnly && !isSavingPhoto && (!trimmedDraft.isEmpty || !pendingAttachments.isEmpty)
    }

    private var headerDestination: AppDestination? {
        guard !isFieldContext else { return nil }
        switch thread.kind {
        case .customer:
            return thread.customerID.map { AppDestination.customer($0) }
        case .crew:
            return .crews
        case .property:
            return thread.propertyID.map { AppDestination.property($0) }
        case .direct:
            return store.staff.first { $0.name == thread.title }.map { AppDestination.employee($0.id) }
        case .announcement:
            return nil
        }
    }

    private var customerPhoneURL: URL? {
        guard thread.kind == .customer, !isFieldContext,
              let phone = store.customer(thread.customerID)?.primaryContact?.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(digits)")
    }

    // MARK: Body

    var body: some View {
        let groups = dayGroups
        let mineID = lastMineID
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s) {
                    ConversationContextBanner(thread: thread)
                        .padding(.bottom, Space.xs)
                    if thread.messages.isEmpty {
                        EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "No messages yet", message: "Say hello — messages you send are saved on this iPhone first.")
                    }
                    ForEach(groups) { group in
                        ConversationDaySeparator(text: group.title)
                        ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                            InboxMessageRow(
                                message: message,
                                thread: thread,
                                isMine: message.isMine(viewer),
                                showsAuthor: showsAuthor(message, previous: index > 0 ? group.messages[index - 1] : nil),
                                showsDelivery: message.id == mineID
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.messages.count) { _, _ in
                if let last = thread.messages.last?.id {
                    withMotion { proxy.scrollTo(last, anchor: .bottom) }
                }
                store.markRead(thread.id)
            }
            .onChange(of: composerFocused) { _, focused in
                guard focused, let last = thread.messages.last?.id else { return }
                withMotion { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { store.markRead(thread.id) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attach(item) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentCount)
    }

    private func showsAuthor(_ message: Message, previous: Message?) -> Bool {
        guard thread.kind != .customer, thread.kind != .direct else { return false }
        guard let previous, !previous.isSystemEvent else { return true }
        return previous.authorName != message.authorName
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                if let headerDestination { model.push(headerDestination) }
            } label: {
                VStack(spacing: 0) {
                    Text(thread.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(thread.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
                .frame(minHeight: Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(headerDestination == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint(headerDestination == nil ? "" : "Opens details")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let customerPhoneURL {
                Button {
                    openURL(customerPhoneURL)
                } label: {
                    Image(systemName: "phone")
                }
                .accessibilityLabel("Call \(thread.title)")
            }
            Menu {
                Button {
                    model.push(.attachments(thread.id))
                } label: {
                    Label("Attachments", systemImage: "paperclip")
                }
                if let propertyID = thread.propertyID, thread.kind != .property, store.property(propertyID) != nil {
                    Button {
                        model.push(.property(propertyID))
                    } label: {
                        Label("View Property", systemImage: "building.2")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: Composer

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: Space.s) {
            if isPreviewOnly {
                NoticeCard(symbol: "eye", text: "Preview only — messages can't be sent while previewing Field Mode.", tone: .blue)
            } else {
                if !thread.quickReplies.isEmpty && trimmedDraft.isEmpty {
                    quickReplies
                }
                if thread.kind == .customer {
                    audiencePicker
                }
                if !pendingAttachments.isEmpty || isSavingPhoto {
                    pendingStrip
                }
                inputRow
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var quickReplies: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(thread.quickReplies, id: \.self) { reply in
                    Button {
                        draft = reply
                        composerFocused = true
                    } label: {
                        Text(reply)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: 34)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
                            .frame(minHeight: Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Fills the message box")
                }
            }
        }
    }

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Picker("Who sees this message", selection: $audience) {
                Text("Customer").tag(MessageVisibility.customer)
                Text("Internal").tag(MessageVisibility.internal)
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: audience)
            if audience == .internal {
                Label("Staff only — the customer won't see this note", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.amber)
            }
        }
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(pendingAttachments) { attachment in
                    PhotoTile(photo: attachment.inboxPhoto(at: store.now), cornerRadius: Radius.control, maxPixel: 200)
                        .frame(width: 64, height: 64)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(attachment)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                                    .frame(width: Hit.min, height: Hit.min, alignment: .topTrailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo")
                        }
                }
                if isSavingPhoto {
                    ProgressView()
                        .frame(width: 64, height: 64)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityLabel("Saving photo")
                }
            }
        }
    }

    private var inputRow: some View {
        let isInternal = thread.kind.isInternalOnly || audience == .internal
        return HStack(alignment: .bottom, spacing: Space.s) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "paperclip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: Hit.min, height: Hit.min)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Attach photo")

            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.body)
                .focused($composerFocused)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 2)
                .frame(minHeight: Hit.min)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(thread.kind == .customer && isInternal ? Palette.amber : Palette.separator,
                                      style: StrokeStyle(lineWidth: 1, dash: thread.kind == .customer && isInternal ? [5, 4] : []))
                }
                .accessibilityLabel(placeholder)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(canSend ? Color.white : Palette.ink3)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Palette.red : Palette.surface2, in: Circle())
                    .frame(width: Hit.min, height: Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
    }

    private var placeholder: String {
        if thread.kind == .customer {
            return audience == .internal ? "Internal note — staff only" : "Message \(thread.title)"
        }
        return "Message \(thread.title)"
    }

    // MARK: Actions

    private func send() {
        guard canSend else { return }
        let visibility: MessageVisibility = thread.kind == .customer ? audience : .internal
        store.send(trimmedDraft, to: thread.id, visibility: visibility, attachments: pendingAttachments)
        draft = ""
        pendingAttachments = []
        sentCount += 1
        if !store.isOnline {
            toasts.show("Saved on this iPhone · sends automatically", symbol: "icloud.and.arrow.up", tone: .amber)
        }
    }

    private func remove(_ attachment: Attachment) {
        if attachment.inboxIsLocalFile { PhotoStorage.delete(attachment.name) }
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func attach(_ item: PhotosPickerItem) async {
        isSavingPhoto = true
        defer {
            isSavingPhoto = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            let fileName = try PhotoStorage.save(data: data)
            let attachment = Attachment(id: UUID().uuidString, kind: .photo, name: fileName, detail: "Photo",
                                        swatch: pendingAttachments.count, upload: .savedOnDevice)
            pendingAttachments.append(attachment)
        } catch {
            toasts.show("Couldn't attach that photo", symbol: "exclamationmark.triangle.fill", tone: .amber)
        }
    }
}

/// Banner under the header: linked property and who can see the thread.
private struct ConversationContextBanner: View {
    @Environment(AppStore.self) private var store
    let thread: MessageThread

    var body: some View {
        VStack(spacing: Space.s) {
            if thread.kind == .customer, let property = store.property(thread.propertyID) {
                NavigationLink(value: AppDestination.property(property.id)) {
                    HStack(spacing: Space.m) {
                        Image(systemName: "building.2.fill")
                            .font(.body)
                            .foregroundStyle(Palette.ink2)
                            .frame(width: 40, height: 40)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(property.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text(visitLine(for: property))
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                        }
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    .cardStyle(padding: Space.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the property")
            }
            if thread.kind == .customer {
                Label("Customer sees messages in this thread", systemImage: "eye")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.blue)
                    .frame(maxWidth: .infinity)
            } else {
                Label("Internal — customers never see this thread", systemImage: "lock.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.amber)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(Palette.amberSoft, in: Capsule())
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func visitLine(for property: Property) -> String {
        let crewName = store.crew(property.assignedCrewID)?.name
        if let status = store.todayStatus(for: property.id) {
            let base = status.status == .done || status.status == .skipped ? status.text : "Next visit \(status.text)"
            return [base, crewName].compactMap { $0 }.joined(separator: " · ")
        }
        return property.address
    }
}

#Preview("Customer thread") {
    NavigationStack {
        ConversationView(threadID: Fixtures.ID.threadSandra).appDestinations()
    }
    .previewEnvironment()
}

#Preview("Crew thread · field") {
    NavigationStack {
        ConversationView(threadID: Fixtures.ID.threadCrewA).appDestinations()
    }
    .previewEnvironment(role: .field)
}
