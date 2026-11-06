import SwiftUI
import MapleCoreKit

/// "Report an issue" for the active visit. Saved on the visit (`session.issue`) and sent with it
/// for supervisor review when the visit is submitted.
struct VisitIssueSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var didLoad = false
    @FocusState private var focused: Bool

    private static let presets = ["Damage on site", "Customer request", "Equipment problem", "Safety hazard", "Access problem"]

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var original: String { store.activeVisit?.issue ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($focused)
                        .accessibilityLabel("Issue details")
                } footer: {
                    Text("Sent with this visit for supervisor review. Add a work photo if it helps show the problem.")
                }
                Section("Quick start") {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            text = text.isEmpty ? "\(preset): " : "\(text)\n\(preset): "
                            focused = true
                        } label: {
                            Label(preset, systemImage: "plus.circle")
                        }
                    }
                }
                if !original.isEmpty {
                    Section {
                        Button("Remove Issue", role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle("Report an Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(trimmed) }
                        .disabled(trimmed.isEmpty || trimmed == original)
                }
            }
        }
        .interactiveDismissDisabled(trimmed != original.trimmingCharacters(in: .whitespacesAndNewlines))
        .onAppear {
            guard !didLoad else { return }
            text = original
            didLoad = true
        }
    }

    private func save(_ value: String?) {
        let message = store.visitAction { s, _ in s.issue = value }
        if let message {
            toasts.show(message, symbol: "exclamationmark.circle", tone: .red)
        } else {
            Haptics.success()
            toasts.show(value == nil ? "Issue removed" : "Issue added · sends with this visit")
        }
        dismiss()
    }
}

/// "Can't service this stop?" — choose a reason, then the stop is marked Skipped.
struct VisitSkipSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSkip: (String) -> Void

    @State private var preset: String?
    @State private var detail = ""
    @State private var isConfirming = false

    private static let presets = ["Gate locked", "No access — vehicle blocking", "Customer asked to skip", "Unsafe conditions", "Weather", "Other"]

    private var reason: String? {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preset else { return nil }
        if preset == "Other" { return trimmedDetail.isEmpty ? nil : trimmedDetail }
        return trimmedDetail.isEmpty ? preset : "\(preset) — \(trimmedDetail)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Self.presets, id: \.self) { option in
                        Button {
                            preset = option
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(option).foregroundStyle(Palette.ink)
                                Spacer()
                                if preset == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.redText)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: Hit.min)
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(preset == option ? .isSelected : [])
                    }
                } header: {
                    Text("Reason")
                } footer: {
                    Text("The office sees this reason. The stop is marked Skipped and the visit ends without photos.")
                }
                Section(preset == "Other" ? "Details (required)" : "Details (optional)") {
                    TextField("Anything the office should know", text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Can't Service This Stop?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip Stop") { isConfirming = true }
                        .disabled(reason == nil)
                }
            }
            .confirmationDialog("Skip this stop?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Skip Stop", role: .destructive) {
                    if let reason { onSkip(reason) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(reason ?? "")
            }
        }
        .interactiveDismissDisabled(preset != nil || !detail.isEmpty)
    }
}

#if DEBUG
#Preview("Issue") {
    VisitIssueSheet()
        .previewEnvironment(role: .field)
}

#Preview("Skip") {
    VisitSkipSheet { _ in }
        .previewEnvironment(role: .field)
}
#endif
