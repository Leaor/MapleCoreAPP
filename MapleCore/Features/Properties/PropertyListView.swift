import SwiftUI
import MapKit
import MapleCoreKit

enum PropertyListFilter: String, CaseIterable, Hashable {
    case all, commercial, residential, snow

    var label: String {
        switch self {
        case .all: "All"
        case .commercial: "Commercial"
        case .residential: "Residential"
        case .snow: "Snow contracts"
        }
    }

    func includes(_ property: Property) -> Bool {
        switch self {
        case .all: true
        case .commercial: property.kind.isCommercial
        case .residential: !property.kind.isCommercial
        case .snow: property.hasSnowContract
        }
    }
}

/// Properties tab root: searchable list with filter chips, or a map of every property.
struct PropertyListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var query = ""
    @State private var filter: PropertyListFilter = .all
    @State private var showsMap = false
    @State private var isAdding = false

    private var filtered: [Property] {
        let base = store.properties.filter { filter.includes($0) }
        return store.searchProperties(matching: query, in: base)
    }

    private var canAdd: Bool { store.activeRole?.usesAdminShell == true && !isRolePreview }

    var body: some View {
        let rows = filtered
        Group {
            if showsMap {
                PropertyMapMode(properties: rows)
            } else {
                PropertyListContent(properties: rows, query: query, filter: $filter, totalCount: store.properties.count)
            }
        }
        .navigationTitle("Properties")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Name, address or customer")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withMotion { showsMap.toggle() }
                } label: {
                    Image(systemName: showsMap ? "list.bullet" : "map")
                }
                .accessibilityLabel(showsMap ? "Show as list" : "Show on map")

                if canAdd {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add property")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: showsMap)
        .sheet(isPresented: $isAdding) {
            AddPropertySheet()
        }
    }
}

// MARK: - List mode

private struct PropertyListContent: View {
    var properties: [Property]
    var query: String
    @Binding var filter: PropertyListFilter
    var totalCount: Int

    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                FilterChips(options: PropertyListFilter.allCases, selection: $filter, label: { $0.label }, count: { $0 == .all ? totalCount : nil })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if properties.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(properties) { property in
                        NavigationLink(value: AppDestination.property(property.id)) {
                            PropertyRow(property: property)
                        }
                    }
                } footer: {
                    Text("\(Fmt.plural(properties.count, "property", "properties")) · cached rows stay usable while refreshing")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .refreshable {
            // Phase 1 has no live backend: pulling sends anything queued and keeps cached rows on screen.
            store.scheduleSync()
            try? await Task.sleep(for: .milliseconds(600))
        }
        .motionAnimation(value: filter)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            EmptyStateView(symbol: "building.2", title: "No \(filter.label.lowercased()) properties", message: "Try another filter, or add a property with the + button.")
        }
    }
}

struct PropertyRow: View {
    var property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        let status = store.todayStatus(for: property.id)
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(property.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("\(property.address) · \(property.descriptor)")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            PropertyFlowLayout(spacing: 6) {
                if property.openIssues > 0 {
                    Pill(text: Fmt.plural(property.openIssues, "open issue"), tone: .amber, symbol: "exclamationmark.triangle.fill")
                }
                if let status {
                    StatusPill(status: status.status, text: status.text)
                } else {
                    Pill(text: property.frequency.label, tone: .neutral, symbol: "arrow.triangle.2.circlepath")
                }
                if property.hasSnowContract {
                    Pill(text: "Snow", tone: .blue, symbol: "snowflake")
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Map mode

private struct PropertyMapMode: View {
    var properties: [Property]
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: Property.ID?
    @Environment(AppStore.self) private var store

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(properties) { property in
                Marker(property.name, systemImage: property.kind.isCommercial ? "building.2.fill" : "house.fill",
                       coordinate: CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude))
                    .tint(property.openIssues > 0 ? Palette.amber : Palette.red)
                    .tag(property.id)
            }
        }
        .mapStyle(.standard(emphasis: .muted))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if let id = selectedID, let property = store.property(id) {
                selectedCard(property)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if properties.isEmpty {
                Text("No properties match")
                    .font(.subheadline.weight(.semibold))
                    .padding(Space.m)
                    .background(Palette.bar, in: Capsule())
                    .floatingShadow()
                    .padding(.bottom, Space.l)
            }
        }
        .motionAnimation(value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
        .onChange(of: properties.map(\.id)) { _, ids in
            if let id = selectedID, !ids.contains(id) { selectedID = nil }
            position = .automatic
        }
    }

    private func selectedCard(_ property: Property) -> some View {
        NavigationLink(value: AppDestination.property(property.id)) {
            HStack(spacing: Space.m) {
                PropertyRow(property: property)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .padding(Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .floatingShadow()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
        .accessibilityHint("Opens the property")
    }
}

#Preview("Properties") {
    NavigationStack {
        PropertyListView()
            .appDestinations()
    }
    .previewEnvironment()
}
