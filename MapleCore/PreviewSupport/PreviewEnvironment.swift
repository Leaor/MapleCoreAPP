import SwiftUI
import MapleCoreKit

#if DEBUG
@MainActor
enum PreviewModels {
    /// A fresh store signed in with the given role. Fixtures only; nothing is persisted.
    static func model(role: AppRole = .admin) -> AppModel {
        let store = AppStore(persistence: nil, syncMode: .disabled)
        let account = role == .field ? Fixtures.accounts[1] : Fixtures.accounts[0]
        store.signIn(account)
        store.choose(role: role == .field ? .field : .admin)
        store.completePermissions()
        return AppModel(store: store, auth: MockAuthService(latency: .zero))
    }
}

extension View {
    /// Injects AppModel, AppStore and ToastCenter for previews.
    func previewEnvironment(role: AppRole = .admin) -> some View {
        let model = PreviewModels.model(role: role)
        return self
            .environment(model)
            .environment(model.store)
            .environment(model.toasts)
            .tint(Palette.red)
    }
}
#endif
