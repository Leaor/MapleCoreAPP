import Foundation
import MapleCoreKit

extension AppStore {
    /// Runs a visit transition through `updateVisit` and returns the user-facing error, if any,
    /// so screens can show it inline instead of failing silently.
    @discardableResult
    func visitAction(_ body: (inout VisitSession, Date) throws -> Void) -> String? {
        do {
            try updateVisit(body)
            return nil
        } catch let error as VisitError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    /// The most recent outbox item for a submitted visit (the times/notes report).
    func visitOutboxItem(propertyName: String) -> OutboxItem? {
        outbox.last { $0.kind == .visitUpdate && $0.title == "Visit · \(propertyName)" }
    }

    /// The most recent photo batch for a submitted visit.
    func visitPhotoOutboxItem(propertyName: String) -> OutboxItem? {
        outbox.last { $0.kind == .photoUpload && $0.detail == propertyName }
    }
}
