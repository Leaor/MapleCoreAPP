import Foundation
import MapleCoreKit

/// Read-only helpers for More, Settings and Sync & Uploads. Public AppStore API only.
extension AppStore {
    /// One-line sync status for rows like "Sync & Uploads  All synced".
    var syncStatusSummary: (text: String, tone: Tone) {
        let attention = attentionOutbox.count
        let pending = pendingOutbox.count
        if attention > 0 { return (text: "\(attention) need\(attention == 1 ? "s" : "") you", tone: .red) }
        if !isOnline { return (text: pending > 0 ? "Offline · \(pending) waiting" : "Offline", tone: .amber) }
        if pending > 0 { return (text: "Sending \(pending)…", tone: .blue) }
        return (text: "All synced", tone: .green)
    }

    /// Outbox items already delivered, newest first.
    var sentOutbox: [OutboxItem] {
        outbox.filter { $0.state == .sent }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Quotes sent or viewed but not yet answered.
    var quotesAwaitingCount: Int { quotes.filter { $0.status.isOpen }.count }
}
