import SwiftUI
import MapleCoreKit

// Bubbles from the Components board: customer-visible messages are solid bubbles, internal notes in a
// customer thread are dashed amber with a lock label, system events are small centred lines.

/// One message in a conversation, laid out for the viewer.
struct InboxMessageRow: View {
    @Environment(AppStore.self) private var store
    let message: Message
    let thread: MessageThread
    let isMine: Bool
    /// Show avatar + name above incoming messages in group threads.
    let showsAuthor: Bool
    /// Delivery line under the viewer's most recent message.
    let showsDelivery: Bool

    var body: some View {
        if message.isSystemEvent {
            InboxSystemEventLine(message: message)
        } else {
            VStack(alignment: isMine ? .trailing : .leading, spacing: Space.xs) {
                if showsAuthor && !isMine {
                    HStack(spacing: Space.s) {
                        Avatar(initials: message.authorInitials, size: 24)
                        Text(message.authorName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(.top, Space.xs)
                }
                bubble
                if let tag = message.propertyTag {
                    Pill(text: tag, tone: .neutral, symbol: "mappin.and.ellipse")
                        .accessibilityLabel("Property: \(tag)")
                }
                if showsDelivery {
                    InboxDeliveryLine(state: message.delivery)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let isInternalNote = thread.kind == .customer && message.visibility == .internal
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: Space.xxxl + Space.l) }
            VStack(alignment: .leading, spacing: Space.s) {
                if !message.attachments.isEmpty {
                    InboxMessageAttachments(message: message, onDark: isMine && !isInternalNote)
                }
                if isInternalNote {
                    InternalNoteBody(message: message)
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isMine ? Palette.background : Palette.ink)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, Space.m + 2)
            .padding(.vertical, Space.s + 2)
            .background {
                if isInternalNote {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.amberSoft)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isMine ? Palette.ink : Palette.surface)
                }
            }
            .overlay {
                if isInternalNote {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.amber, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(isInternalNote: isInternalNote))
            if !isMine { Spacer(minLength: Space.xxxl + Space.l) }
        }
    }

    private func accessibilityText(isInternalNote: Bool) -> String {
        var parts: [String] = []
        parts.append(isMine ? "You" : message.authorName)
        if isInternalNote { parts.append("Internal note, staff only") }
        if !message.text.isEmpty { parts.append(message.text) }
        let photos = message.attachments.filter { $0.kind == .photo }.count
        if photos > 0 { parts.append(Fmt.plural(photos, "photo")) }
        let files = message.attachments.count - photos
        if files > 0 { parts.append(Fmt.plural(files, "file")) }
        parts.append(Fmt.time(message.sentAt))
        return parts.joined(separator: ", ")
    }
}

/// Internal note content: lock label, text and author.
private struct InternalNoteBody: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label("Internal note · staff only", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.amber)
            if !message.text.isEmpty {
                Text("\(message.text) — \(message.authorName)")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
        }
    }
}

/// "Daniel started visit · Humber Bay Towers · 9:06"
struct InboxSystemEventLine: View {
    let message: Message

    var body: some View {
        Text("\(message.text) · \(Fmt.clock(message.sentAt))")
            .font(.caption)
            .foregroundStyle(Palette.ink3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
    }
}

/// Day separator: "Today 9:12 AM".
struct ConversationDaySeparator: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Delivery state of the viewer's latest message. Never claims a send that hasn't happened.
struct InboxDeliveryLine: View {
    let state: DeliveryState

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tone.foreground)
            .accessibilityLabel("Delivery: \(text)")
    }

    private var text: String {
        switch state {
        case .queued: "Saved on this iPhone · sends automatically"
        case .sent: "Sent"
        case let .read(at): "Read \(Fmt.clock(at))"
        case let .seenBy(who): "Seen by \(who)"
        }
    }

    private var symbol: String {
        switch state {
        case .queued: "clock.arrow.circlepath"
        case .sent: "checkmark"
        case .read, .seenBy: "eye"
        }
    }

    private var tone: Tone {
        switch state {
        case .queued: .amber
        default: .neutral
        }
    }
}

/// Photos and files attached to a message.
struct InboxMessageAttachments: View {
    let message: Message
    var onDark = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(message.attachments) { attachment in
                if attachment.kind == .photo {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        PhotoTile(photo: attachment.inboxPhoto(at: message.sentAt), cornerRadius: Radius.control)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .frame(maxWidth: 240)
                            .accessibilityLabel("Photo, \(attachment.inboxDisplayName)")
                        Text(attachment.inboxDisplayName)
                            .font(.caption)
                            .foregroundStyle(onDark ? Palette.background.opacity(0.8) : Palette.ink3)
                    }
                } else {
                    HStack(spacing: Space.s) {
                        Image(systemName: attachment.inboxSymbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(onDark ? Palette.background : Palette.redText)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(attachment.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(onDark ? Palette.background : Palette.ink)
                            if !attachment.detail.isEmpty {
                                Text(attachment.detail)
                                    .font(.caption)
                                    .foregroundStyle(onDark ? Palette.background.opacity(0.8) : Palette.ink3)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension Attachment {
    /// True when `name` is a file saved on this iPhone by `PhotoStorage`.
    var inboxIsLocalFile: Bool { kind == .photo && name.hasSuffix(".jpg") }

    /// Readable name: saved files show their detail ("Photo"), fixtures their name ("IMG_2041").
    var inboxDisplayName: String { inboxIsLocalFile ? (detail.isEmpty ? "Photo" : detail) : name }

    var inboxSymbol: String {
        switch kind {
        case .photo: "photo"
        case .file: "doc.fill"
        case .visitReport: "doc.text.fill"
        case .quote: "doc.plaintext.fill"
        }
    }

    /// Adapts an attachment for `PhotoTile`, which renders the saved image or a tinted placeholder.
    func inboxPhoto(at date: Date) -> VisitPhoto {
        VisitPhoto(id: id, kind: .work, angle: inboxDisplayName, capturedAt: date, localFileName: inboxIsLocalFile ? name : nil, upload: upload, swatch: swatch)
    }
}
