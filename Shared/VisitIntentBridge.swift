import Foundation

/// Actions the Live Activity buttons can request. App Intents run in the app process and post
/// `Notification.Name.visitIntent`; `FieldShell` applies them to the active visit.
/// Compiled into both the app and the widget extension.
enum VisitIntentAction: String, Sendable {
    case pause, resume, afterPhotos

    static let userInfoKey = "action"
}

extension Notification.Name {
    static let visitIntent = Notification.Name("com.maplecore.visitIntent")
}
