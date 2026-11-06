import SwiftUI
import MapleCoreKit

/// Two versions of a text field: this iPhone's offline edit and the office's edit.
/// The person picks one (or keeps both); the other stays in property history.
struct SyncConflictSheet: View {
    let conflictID: SyncConflict.ID

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var choice: ConflictResolution = .mine
    /// Kept so the sheet doesn't flash "Already resolved" while it dismisses after resolving.
    @State private var snapshot: SyncConflict?

    var body: some View {
        NavigationStack {
            Group {
                if let conflict = store.conflict(conflictID) ?? snapshot {
                    content(conflict)
                } else {
                    MissingRecordView(title: "Already resolved", message: "This conflict was resolved or is no longer on this iPhone.")
                }
            }
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if snapshot == nil { snapshot = store.conflict(conflictID) }
        }
    }

    private func content(_ conflict: SyncConflict) -> some View {
        let propertyName = store.property(conflict.propertyID)?.name ?? "this property"
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Two versions of these notes")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("You edited the \(conflict.fieldName) for \(propertyName) while offline. \(conflict.office.editedBy) changed them from the office before you reconnected.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConflictOptionCard(title: "Your version",
                                   meta: "\(Fmt.time(conflict.mine.editedAt)) · \(conflict.mine.editedBy)",
                                   text: conflict.mine.text,
                                   isSelected: choice == .mine) { choice = .mine }
                ConflictOptionCard(title: "Office version",
                                   meta: "\(Fmt.time(conflict.office.editedAt)) · \(conflict.office.editedBy)",
                                   text: conflict.office.text,
                                   isSelected: choice == .office) { choice = .office }
                ConflictOptionCard(title: "Keep both",
                                   meta: "Adds your lines under the office version. Nothing is lost.",
                                   text: conflict.resolvedText(.keepBoth),
                                   isSelected: choice == .keepBoth,
                                   isPreview: true) { choice = .keepBoth }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .sensoryFeedback(.selection, trigger: choice)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(primaryTitle) { resolve(conflict) }
                    .buttonStyle(.mc(.primary))
                Text("The version you don't choose stays in property history.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var primaryTitle: String {
        switch choice {
        case .mine: "Use My Version"
        case .office: "Use Office Version"
        case .keepBoth: "Keep Both"
        }
    }

    private func resolve(_ conflict: SyncConflict) {
        store.resolveConflict(conflict.id, with: choice)
        Haptics.success()
        let field = conflict.fieldName.prefix(1).uppercased() + conflict.fieldName.dropFirst()
        toasts.show(store.isOnline ? "\(field) updated · sending now" : "\(field) saved on this iPhone · sends automatically")
        dismiss()
    }
}

private struct ConflictOptionCard: View {
    var title: String
    var meta: String
    var text: String
    var isSelected: Bool
    var isPreview = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.red : Palette.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(meta).font(.footnote).foregroundStyle(Palette.ink3)
                    if isPreview {
                        Text("Result")
                            .captionStyle()
                            .padding(.top, Space.xs)
                    }
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, isPreview ? 0 : Space.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Palette.red : Palette.separator, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Sync Conflict") {
    Color.clear
        .sheet(isPresented: .constant(true)) { SyncConflictSheet(conflictID: "sc-riverwood") }
        .previewEnvironment()
}
