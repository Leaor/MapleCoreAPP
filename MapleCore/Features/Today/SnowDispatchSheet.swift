import SwiftUI
import MapleCoreKit

/// Choose snow routes that have reached their trigger, pick a start time, and message the crews.
struct SnowDispatchSheet: View {
    private enum StartOption: Hashable { case now, scheduled }

    private static let defaultMessage = "Snow event live. Load salt at the yard first. Priority lots must be clear by 7 AM — freezing rain expected after 5."

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<SnowRoute.ID> = []
    @State private var initialSelection: Set<SnowRoute.ID> = []
    @State private var didLoad = false
    @State private var start: StartOption = .now
    @State private var message = SnowDispatchSheet.defaultMessage
    @State private var confirmDiscard = false
    @FocusState private var messageFocused: Bool

    private var hasEdits: Bool {
        selection != initialSelection || start != .now || message != Self.defaultMessage
    }

    /// The next 4:00 AM after now.
    private var scheduledStart: Date {
        Calendar.current.nextDate(after: store.now, matching: DateComponents(hour: 4, minute: 0), matchingPolicy: .nextTime) ?? store.now
    }

    var body: some View {
        NavigationStack {
            Group {
                if let event = store.snowEvent {
                    form(event)
                } else {
                    MissingRecordView(title: "No active snow event", message: "There's no live snow event to dispatch crews for.")
                }
            }
            .navigationTitle("Dispatch Crews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasEdits { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { messageFocused = false }
                    }
                }
            }
            .confirmationDialog("Discard this dispatch?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasEdits)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: loadDefaults)
    }

    private func loadDefaults() {
        guard !didLoad, let event = store.snowEvent else { return }
        didLoad = true
        let ids = Set(event.pendingRoutes.filter { !$0.isBelowTrigger }.map(\.id))
        selection = ids
        initialSelection = ids
    }

    // MARK: Form

    private func form(_ event: SnowEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                Text("Trigger reached at \(Fmt.time(event.triggerReachedAt)). Ground accumulation passed the \(event.triggerCm) cm contract threshold for \(event.newlyTriggeredCount) more properties.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                routesSection(event)
                startSection
                messageSection
            }
            .padding(Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: { dispatch(event) }) {
                    Text(primaryTitle(event))
                }
                .buttonStyle(.mc(.primary))
                .disabled(selection.isEmpty)
                if selection.isEmpty {
                    Text("Choose at least one route.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
        }
    }

    private func routesSection(_ event: SnowEvent) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Routes to dispatch")
            if event.pendingRoutes.isEmpty {
                Text("Every snow route is already out.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .cardStyle()
            } else {
                CardList(data: event.pendingRoutes, inset: 40) { route in
                    DispatchRouteRow(route: route, isSelected: selection.contains(route.id)) {
                        toggle(route)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Start")
            Picker("Start time", selection: $start) {
                Text("Now").tag(StartOption.now)
                Text("At \(Fmt.time(scheduledStart))").tag(StartOption.scheduled)
            }
            .pickerStyle(.segmented)
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Message to crews")
            TextEditor(text: $message)
                .focused($messageFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(Space.m)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityLabel("Message to crews")
            Text("Posted to the All crews channel with the dispatch. Saved on this iPhone first and sent automatically.")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, Space.xs)
        }
    }

    // MARK: Logic

    private func primaryTitle(_ event: SnowEvent) -> String {
        let routes = event.routes.filter { selection.contains($0.id) }
        let people = store.snowDispatchHeadcount(routes)
        return "Dispatch \(Fmt.plural(routes.count, "Route")) · \(Fmt.plural(people, "Person", "People"))"
    }

    private func toggle(_ route: SnowRoute) {
        guard !route.isBelowTrigger else { return }
        if selection.contains(route.id) {
            selection.remove(route.id)
        } else {
            selection.insert(route.id)
        }
    }

    private func dispatch(_ event: SnowEvent) {
        guard !selection.isEmpty else { return }
        let count = selection.count
        store.dispatchSnow(routeIDs: selection, startAt: start == .now ? nil : scheduledStart, message: message)
        Haptics.success()
        if store.isOnline {
            toasts.show("\(Fmt.plural(count, "route")) dispatched · sending to crews", symbol: "snowflake")
        } else {
            toasts.show("Dispatch saved on this iPhone · sends automatically", symbol: "tray.and.arrow.up", tone: .amber)
        }
        dismiss()
    }
}

private struct DispatchRouteRow: View {
    @Environment(AppStore.self) private var store
    var route: SnowRoute
    var isSelected: Bool
    var action: () -> Void

    private var detail: String {
        if route.isBelowTrigger {
            return "Below the trigger for these contracts — can't dispatch yet"
        }
        let crewName = store.crew(route.crewID)?.name ?? "No crew assigned"
        return "\(route.propertyCount) \(route.unitLabel) · \(crewName) · est. \(Fmt.duration(minutes: route.estimatedMinutes))"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: route.isBelowTrigger ? "minus.circle" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(route.isBelowTrigger ? Palette.ink3 : (isSelected ? Palette.red : Palette.ink3))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(route.code) · \(route.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(route.isBelowTrigger ? Palette.ink3 : Palette.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(route.isBelowTrigger ? Palette.ink3 : Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.m)
            .frame(minHeight: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(route.isBelowTrigger)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Snow Dispatch") {
    Color.clear
        .sheet(isPresented: .constant(true)) { SnowDispatchSheet() }
        .previewEnvironment()
}
