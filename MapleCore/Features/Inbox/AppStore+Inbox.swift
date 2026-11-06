import Foundation
import MapleCoreKit

/// Read-only helpers for the Inbox screens. Only public AppStore API is used.
extension AppStore {
    /// The person reading threads: the preview subject in Field preview, else the signed-in user.
    var inboxViewerID: StaffMember.ID? { fieldStaffID }

    /// True when threads are shown in the Field shell (or the admin's Field preview).
    var inboxIsFieldContext: Bool { activeRole == .field || isPreviewingRole }

    /// One-line preview for an inbox row: "You: …", "Marco: …", "Photo · …".
    func inboxPreview(for thread: MessageThread) -> String {
        guard let message = thread.lastMessage else { return "No messages yet" }
        var body = message.text
        if message.attachments.contains(where: { $0.kind == .photo }) {
            body = body.isEmpty ? "Photo" : "Photo · \(body)"
        } else if let first = message.attachments.first, body.isEmpty {
            body = first.name
        }
        if message.isSystemEvent { return body }
        if message.isMine(inboxViewerID) { return "You: \(body)" }
        switch thread.kind {
        case .crew, .announcement, .property:
            return "\(message.authorName.split(separator: " ").first.map(String.init) ?? message.authorName): \(body)"
        case .customer, .direct:
            return body
        }
    }

    /// "Seen by 9 of 11" for announcement rows.
    func inboxSeenText(for thread: MessageThread) -> String? {
        guard thread.kind == .announcement, let message = thread.lastMessage else { return nil }
        if case let .seenBy(who) = message.delivery { return "Seen by \(who)" }
        return nil
    }

    /// Text used by inbox search: people, property, message text.
    func inboxSearchText(for thread: MessageThread) -> String {
        var parts = [thread.title, thread.subtitle]
        if let property = property(thread.propertyID) { parts.append(property.name); parts.append(property.address) }
        if let customer = customer(thread.customerID) { parts.append(customer.name) }
        parts.append(contentsOf: thread.messages.map(\.text))
        parts.append(contentsOf: thread.messages.map(\.authorName))
        return parts.joined(separator: " ")
    }

    /// The broadcast thread, if one exists.
    var inboxAnnouncementThread: MessageThread? { threads.first { $0.kind == .announcement } }
}
