import SwiftUI
import MapKit
import MapleCoreKit

/// Three-step "New Property" sheet: Location → Details → Service.
struct AddPropertySheet: View {
    private enum Step: Int, CaseIterable {
        case location = 1, details, service
        var title: String {
            switch self {
            case .location: "Location"
            case .details: "Details"
            case .service: "Service"
            }
        }
    }

    private enum Field: Hashable {
        case address, name, access, lawn, beds, parking, walkways
    }

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var search = AddressSearchModel()
    @State private var step: Step = .location
    @State private var confirmDiscard = false
    @State private var isLocating = false
    @FocusState private var focus: Field?

    // Step 1
    @State private var addressQuery = ""
    @State private var location: PropertyResolvedAddress?
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(center: AddressSearchModel.serviceCenter, latitudinalMeters: 30_000, longitudinalMeters: 30_000))
    @State private var kind: PropertyKind = .residential
    @State private var services: Set<ServiceType> = [.lawnCare]
    // Step 2
    @State private var name = ""
    @State private var customerID: Customer.ID?
    @State private var accessNotes = ""
    // Step 3
    @State private var frequency: ServiceFrequency = .weekly
    @State private var preferredDay: Weekday = .monday
    @State private var crewID: Crew.ID?
    @State private var measurements = SiteMeasurements()

    private var hasEdits: Bool {
        !addressQuery.isEmpty || location != nil || !name.isEmpty || customerID != nil || !accessNotes.isEmpty
            || crewID != nil || measurements != SiteMeasurements() || kind != .residential || services != [.lawnCare]
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAdvance: Bool {
        switch step {
        case .location: location != nil && !services.isEmpty
        case .details: !trimmedName.isEmpty
        case .service: !store.isReadOnly
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .location: locationStep
                case .details: detailsStep
                case .service: serviceStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if step != .location {
                    BottomActionBar {
                        Button {
                            withMotion { step = Step(rawValue: step.rawValue - 1) ?? .location }
                        } label: {
                            Label("Back to \(Step(rawValue: step.rawValue - 1)?.title ?? "Location")", systemImage: "chevron.left")
                        }
                        .buttonStyle(.mc(.secondary, compact: true))
                    }
                }
            }
            .confirmationDialog("Discard this new property?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .onChange(of: addressQuery) { _, value in
                if let location, value == location.street { return }
                location = nil
                search.update(query: value)
            }
            .sensoryFeedback(.selection, trigger: step)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasEdits)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasEdits { confirmDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("New Property").font(.headline)
                Text("Step \(step.rawValue) of 3 · \(step.title)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(step == .service ? "Save" : "Next") { advance() }
                .fontWeight(.semibold)
                .disabled(!canAdvance)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private func advance() {
        focus = nil
        switch step {
        case .location:
            if name.isEmpty, let location { name = location.street }
            withMotion { step = .details }
        case .details:
            withMotion { step = .service }
        case .service:
            save()
        }
    }

    // MARK: Step 1 · Location

    @ViewBuilder
    private var locationStep: some View {
        Section {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3).accessibilityHidden(true)
                TextField("Search address", text: $addressQuery)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .address)
                    .submitLabel(.search)
                    .accessibilityLabel("Property address")
                if search.isSearching || isLocating {
                    ProgressView()
                }
            }
            suggestionRows
        } header: {
            Text("Address")
        } footer: {
            if let error = search.lastError { Text(error) }
        }

        Section {
            mapPreview
                .listRowInsets(EdgeInsets())
        } footer: {
            if let location {
                Text(location.isLocated ? "Tap the map to move the pin to the service entrance." : "Couldn't place this address — tap the map to drop the pin where crews should go.")
            } else {
                Text("Choose an address to place the pin.")
            }
        }

        Section("Property type") {
            Picker("Property type", selection: $kind) {
                Text("Residential").tag(PropertyKind.residential)
                Text("Commercial").tag(PropertyKind.commercial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        Section {
            PropertyFlowLayout {
                ForEach(ServiceType.allCases, id: \.self) { service in
                    PropertyToggleChip(text: service.label, isOn: services.contains(service)) {
                        if services.contains(service) { services.remove(service) } else { services.insert(service) }
                    }
                }
            }
            .padding(.vertical, Space.xs)
        } header: {
            Text("Services")
        } footer: {
            if services.isEmpty { Text("Choose at least one service.") }
        }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        if location == nil {
            ForEach(search.suggestions) { suggestion in
                Button {
                    choose(suggestion)
                } label: {
                    suggestionLabel(title: suggestion.title, subtitle: suggestion.subtitle)
                }
                .buttonStyle(.plain)
            }
            let typed = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.count >= 3 && !search.isSearching {
                Button {
                    useManual(typed)
                } label: {
                    suggestionLabel(title: "Use “\(typed)”", subtitle: search.suggestions.isEmpty ? "No matches found · enter the address manually" : "Enter the address as typed", symbol: "keyboard")
                }
                .buttonStyle(.plain)
            }
        } else if let location {
            HStack(spacing: Space.m) {
                Image(systemName: location.isLocated ? "mappin.circle.fill" : "mappin.slash")
                    .foregroundStyle(location.isLocated ? Palette.red : Palette.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.street).font(.body.weight(.semibold))
                    Text(location.city.isEmpty ? "City not set" : location.city).font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
                Button("Change") {
                    self.location = nil
                    addressQuery = ""
                    search.clear()
                    focus = .address
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func suggestionLabel(title: String, subtitle: String, symbol: String = "mappin.and.ellipse") -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.ink3)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var mapPreview: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                if let location {
                    Marker(trimmedName.isEmpty ? location.street : trimmedName, coordinate: location.coordinate)
                        .tint(Palette.red)
                }
            }
            .mapStyle(.standard(emphasis: .muted))
            .onTapGesture { point in
                guard location != nil, let coordinate = proxy.convert(point, from: .local) else { return }
                location?.latitude = coordinate.latitude
                location?.longitude = coordinate.longitude
                Haptics.selection()
            }
        }
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel(location == nil ? "Map preview, no address chosen" : "Map preview with pin at \(location?.street ?? "")")
    }

    private func choose(_ suggestion: AddressSearchModel.Suggestion) {
        focus = nil
        isLocating = true
        Task {
            let resolved = await search.resolve(suggestion)
            isLocating = false
            if let resolved {
                place(resolved)
            } else {
                useManual("\(suggestion.title) \(suggestion.subtitle)")
            }
        }
    }

    private func useManual(_ text: String) {
        focus = nil
        isLocating = true
        Task {
            let resolved = await search.locate(manual: text)
            isLocating = false
            place(resolved)
        }
    }

    private func place(_ resolved: PropertyResolvedAddress) {
        location = resolved
        addressQuery = resolved.street
        search.clear()
        withMotion {
            mapPosition = .region(MKCoordinateRegion(center: resolved.coordinate, latitudinalMeters: resolved.isLocated ? 400 : 20_000, longitudinalMeters: resolved.isLocated ? 400 : 20_000))
        }
    }

    // MARK: Step 2 · Details

    @ViewBuilder
    private var detailsStep: some View {
        Section {
            TextField("Property name", text: $name)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .name)
                .accessibilityLabel("Property name")
            Picker("Customer", selection: $customerID) {
                Text("None yet").tag(Customer.ID?.none)
                ForEach(store.customers) { customer in
                    Text(customer.name).tag(Customer.ID?.some(customer.id))
                }
            }
        } header: {
            Text("Details")
        } footer: {
            if trimmedName.isEmpty { Text("A name is required, e.g. “Islington Medical Centre” or the street address.") }
        }

        Section {
            TextField("Gate codes, parking, hazards", text: $accessNotes, axis: .vertical)
                .lineLimit(3...8)
                .focused($focus, equals: .access)
                .accessibilityLabel("Access instructions")
        } header: {
            Text("Access instructions")
        } footer: {
            Label("Visible to crew only · Never shown to the customer", systemImage: "lock.fill")
        }
    }

    // MARK: Step 3 · Service

    @ViewBuilder
    private var serviceStep: some View {
        Section("Service") {
            Picker("Frequency", selection: $frequency) {
                ForEach(ServiceFrequency.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Preferred day", selection: $preferredDay) {
                ForEach(Weekday.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Assigned crew", selection: $crewID) {
                Text("Unassigned").tag(Crew.ID?.none)
                ForEach(store.crews) { crew in
                    Text(crew.name).tag(Crew.ID?.some(crew.id))
                }
            }
        }

        Section {
            measurementField("Lawn", unit: "m²", value: $measurements.lawnSqM, field: .lawn)
            measurementField("Garden beds", unit: "m²", value: $measurements.gardenBedsSqM, field: .beds)
            measurementField("Parking (snow)", unit: "m²", value: $measurements.parkingSqM, field: .parking)
            measurementField("Walkways (salt)", unit: "m", value: $measurements.walkwaysM, field: .walkways)
        } header: {
            Text("Site measurements")
        } footer: {
            Text(store.isReadOnly ? "Preview only — changes aren't saved in Field Mode preview." : (store.isOnline ? "You can refine these after the first visit." : "Offline — the property is saved on this iPhone and sends automatically."))
        }
    }

    private func measurementField(_ label: String, unit: String, value: Binding<Int>, field: Field) -> some View {
        LabeledContent {
            HStack(spacing: Space.xs) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .numeric()
                    .focused($focus, equals: field)
                    .accessibilityLabel("\(label), \(unit == "m" ? "metres" : "square metres")")
                Text(unit).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            }
        } label: {
            Text(label)
        }
    }

    // MARK: Save

    private func save() {
        guard let location, !trimmedName.isEmpty, !store.isReadOnly else { return }
        let ordered = ServiceType.allCases.filter { services.contains($0) }
        let property = Property(
            id: UUID().uuidString,
            name: trimmedName,
            address: location.street,
            city: location.city,
            kind: kind,
            descriptor: kind.label,
            customerID: customerID,
            services: ordered,
            primaryService: ordered.first?.label ?? "Lawn care",
            frequency: frequency,
            preferredDay: preferredDay,
            assignedCrewID: crewID,
            accessNotes: accessNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            measurements: SiteMeasurements(lawnSqM: max(0, measurements.lawnSqM), gardenBedsSqM: max(0, measurements.gardenBedsSqM),
                                           parkingSqM: max(0, measurements.parkingSqM), walkwaysM: max(0, measurements.walkwaysM)),
            latitude: location.latitude,
            longitude: location.longitude
        )
        store.addProperty(property)
        Haptics.success()
        toasts.show(store.isOnline ? "\(property.name) added" : "Saved on this iPhone · sends automatically")
        dismiss()
    }
}

#Preview("Add property") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddPropertySheet()
        }
        .previewEnvironment()
}
