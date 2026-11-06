import SwiftUI
import MapleCoreKit

/// Native form for editing a property's details, service, crew-only access notes and measurements.
struct EditPropertySheet: View {
    let propertyID: Property.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let property = store.property(propertyID) {
            EditPropertyForm(original: property)
        } else {
            NavigationStack {
                MissingRecordView()
            }
        }
    }
}

private enum EditPropertyField: Hashable {
    case name, access, lawn, beds, parking, walkways
}

private struct EditPropertyForm: View {
    let original: Property

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Property
    @State private var confirmDiscard = false
    @FocusState private var focus: EditPropertyField?

    init(original: Property) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var hasEdits: Bool { draft != original }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Enter a property name." }
        let m = draft.measurements
        if m.lawnSqM < 0 || m.gardenBedsSqM < 0 || m.parkingSqM < 0 || m.walkwaysM < 0 { return "Measurements can't be negative." }
        if m.lawnSqM > 1_000_000 || m.parkingSqM > 1_000_000 || m.gardenBedsSqM > 1_000_000 || m.walkwaysM > 100_000 { return "Check the measurements — one looks too large." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                serviceSection
                accessSection
                measurementsSection
                if store.isReadOnly {
                    Section {
                        Text("Preview only — changes aren't saved in Field Mode preview.")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
            .navigationTitle("Edit Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasEdits { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!hasEdits || validationMessage != nil || store.isReadOnly)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasEdits)
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Property name", text: $draft.name)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .name)
                    .submitLabel(.done)
            }
            Picker("Customer", selection: $draft.customerID) {
                Text("None").tag(Customer.ID?.none)
                ForEach(store.customers) { customer in
                    Text(customer.name).tag(Customer.ID?.some(customer.id))
                }
            }
            Picker("Type", selection: $draft.kind) {
                ForEach(PropertyKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
        } header: {
            Text("Details")
        } footer: {
            if let validationMessage, trimmedName.isEmpty || hasEdits {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(Palette.redText)
            }
        }
    }

    private var serviceSection: some View {
        Section("Service") {
            Picker("Frequency", selection: $draft.frequency) {
                ForEach(ServiceFrequency.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker("Preferred day", selection: $draft.preferredDay) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Text(day.label).tag(day)
                }
            }
            Picker("Assigned crew", selection: $draft.assignedCrewID) {
                Text("Unassigned").tag(Crew.ID?.none)
                ForEach(store.crews) { crew in
                    Text(crew.name).tag(Crew.ID?.some(crew.id))
                }
            }
        }
    }

    private var accessSection: some View {
        Section {
            TextField("Gate codes, parking, hazards", text: $draft.accessNotes, axis: .vertical)
                .lineLimit(3...8)
                .focused($focus, equals: .access)
                .accessibilityLabel("Access instructions")
        } header: {
            Text("Access instructions")
        } footer: {
            Label("Visible to crew only · Never shown to the customer", systemImage: "lock.fill")
        }
    }

    private var measurementsSection: some View {
        Section("Site measurements") {
            measurementField("Lawn", unit: "m²", value: $draft.measurements.lawnSqM, field: .lawn)
            measurementField("Garden beds", unit: "m²", value: $draft.measurements.gardenBedsSqM, field: .beds)
            measurementField("Parking (snow)", unit: "m²", value: $draft.measurements.parkingSqM, field: .parking)
            measurementField("Walkways (salt)", unit: "m", value: $draft.measurements.walkwaysM, field: .walkways)
        }
    }

    private func measurementField(_ label: String, unit: String, value: Binding<Int>, field: EditPropertyField) -> some View {
        LabeledContent {
            HStack(spacing: Space.xs) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .numeric()
                    .focused($focus, equals: field)
                    .accessibilityLabel("\(label), \(unit == "m" ? "metres" : "square metres")")
                Text(unit)
                    .foregroundStyle(Palette.ink2)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(label)
        }
    }

    // MARK: Save

    private func save() {
        focus = nil
        guard validationMessage == nil else { Haptics.error(); return }
        var updated = draft
        updated.name = trimmedName
        updated.accessNotes = draft.accessNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let crewID = updated.assignedCrewID, store.crew(crewID) == nil { updated.assignedCrewID = nil }
        store.updateProperty(updated)
        Haptics.success()
        toasts.show(store.isOnline ? "Property updated" : "Saved on this iPhone · sends automatically")
        dismiss()
    }
}

#Preview("Edit property") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            EditPropertySheet(propertyID: Fixtures.ID.islington)
        }
        .previewEnvironment()
}
