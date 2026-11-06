import Foundation
#if canImport(AppIntents)
import AppIntents

/// Live Activity "Pause" button. Runs in the app process; `FieldShell` applies it to the active visit.
struct PauseVisitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause visit"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .visitIntent,
            object: nil,
            userInfo: [VisitIntentAction.userInfoKey: VisitIntentAction.pause.rawValue]
        )
        return .result()
    }
}

/// Live Activity "Resume" button.
struct ResumeVisitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume visit"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .visitIntent,
            object: nil,
            userInfo: [VisitIntentAction.userInfoKey: VisitIntentAction.resume.rawValue]
        )
        return .result()
    }
}
#endif
