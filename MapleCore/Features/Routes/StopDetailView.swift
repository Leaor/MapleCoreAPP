import SwiftUI
import MapKit
import MapleCoreKit

/// Admin view of one stop: status track, priority, access notes, tasks and actions.
struct StopDetailView: View {
    let routeID: Route.ID
    let stopID: RouteStop.ID

    @Environment(AppStore.self) private var store

    var body: some View {
        if let route = store.route(routeID),
           let index = route.index(of: stopID),
           let property = store.property(route.stops[index].propertyID) {
            StopDetailScreen(route: route, stop: route.stops[index], number: index + 1, property: property)
        } else {
            MissingRecordView(title: "Stop not available")
        }
    }
}

private struct StopDetailScreen: View {
    let route: Route
    let stop: RouteStop
    let number: Int
    let property: Property

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var showsSkipDialog = false
    @State private var showsOtherReason = false
    @State private var otherReason = ""

    private static let skipPresets = ["Gate locked", "Weather", "Customer request"]

    private var canPlan: Bool { store.capabilities.contains(.routePlanning) && !store.isReadOnly }
    private var isNext: Bool { route.inProgressStop == nil && route.nextStop?.id == stop.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                StopStatusTrack(status: stop.status, skipReason: stop.skipReason)
                    .cardStyle()
                timeAndPriority
                accessCard
                if !stop.tasks.isEmpty {
                    tasksCard
                }
                actionRow
                skipSection
                    .padding(.top, Space.xl)
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppDestination.property(property.id)) {
                    Text("Property")
                }
            }
        }
        .confirmationDialog("Skip this stop?", isPresented: $showsSkipDialog, titleVisibility: .visible) {
            ForEach(Self.skipPresets, id: \.self) { reason in
                Button(reason, role: .destructive) { skip(reason) }
            }
            Button("Other…") {
                otherReason = ""
                showsOtherReason = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a reason. It's saved to the property's history and the crew moves to the next stop.")
        }
        .alert("Reason for skipping", isPresented: $showsOtherReason) {
            TextField("Reason", text: $otherReason)
            Button("Skip Stop", role: .destructive) { skip(otherReason) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A short reason the office and crew will see.")
        }
    }

    // MARK: Header

    private var roleLine: String {
        let prefix: String
        if isNext {
            prefix = "Next stop"
        } else {
            switch stop.status {
            case .inProgress: prefix = "In progress"
            case .done: prefix = "Completed"
            case .skipped: prefix = "Skipped"
            case .enRoute: prefix = "En route"
            case .delayed: prefix = "Delayed"
            case .pending, .urgent: prefix = "Stop"
            }
        }
        var line = "\(prefix) · \(number) of \(route.stops.count)"
        if !stop.status.isFinished, let eta = stop.eta {
            line += " · ETA \(Fmt.clock(eta))"
        }
        return line
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(isNext ? Palette.red : stop.status.tone.background)
                    Text("\(number)")
                        .font(.title2.weight(.bold))
                        .numeric()
                        .foregroundStyle(isNext ? Color.white : stop.status.tone.foreground)
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

                Text(roleLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isNext ? Palette.redText : Palette.ink2)
                    .numeric()
            }
            Text(property.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("\(property.address) · \(property.kind.label) · \(stop.serviceName)")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Time & priority

    private var priorityBinding: Binding<Priority> {
        let routeID = route.id
        let stopID = stop.id
        let current = stop.priority
        return Binding(
            get: { current },
            set: { store.setPriority($0, routeID: routeID, stopID: stopID) }
        )
    }

    private var timeAndPriority: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            KeyValueRow(label: "Estimated time", value: Fmt.duration(minutes: stop.estimatedMinutes))
            if let actual = stop.actualMinutes {
                Divider()
                KeyValueRow(label: "Actual time", value: Fmt.duration(minutes: actual), valueTone: actual > stop.estimatedMinutes ? .amber : .green)
            }
            Divider()
            Text("Priority")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .padding(.top, Space.xs)
            Picker("Priority", selection: priorityBinding) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Text(priority.label).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canPlan || stop.status.isFinished)
            .sensoryFeedback(.selection, trigger: stop.priority)
            if !canPlan {
                Text("Changing priority needs route-planning access.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            } else if stop.priority == .high {
                Text("High-priority stops stay first when the route is optimized.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .cardStyle()
    }

    // MARK: Access & tasks

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Palette.amber)
                    .accessibilityHidden(true)
                Text("Access")
                    .font(.headline)
                Spacer()
                Pill(text: "Crew only", tone: .amber, symbol: "lock.fill")
            }
            Text(property.accessNotes.isEmpty ? "No access notes yet." : property.accessNotes)
                .font(.body)
                .foregroundStyle(property.accessNotes.isEmpty ? Palette.ink3 : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !property.equipment.isEmpty {
                RoutesFlowLayout(spacing: Space.s) {
                    ForEach(property.equipment, id: \.self) { item in
                        RoutesTagChip(text: item)
                    }
                }
                .padding(.top, Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Equipment: \(property.equipment.joined(separator: ", "))")
            }
        }
        .cardStyle()
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Tasks")
                .font(.headline)
            ForEach(stop.tasks) { task in
                HStack(spacing: Space.m) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isDone ? Palette.green : Palette.ink3)
                        .accessibilityHidden(true)
                    Text(task.title)
                        .foregroundStyle(Palette.ink)
                        .strikethrough(task.isDone, color: Palette.ink3)
                    Spacer(minLength: Space.s)
                    if task.addedToday {
                        Pill(text: "Added today", tone: .blue)
                    }
                }
                .frame(minHeight: Hit.min)
                .accessibilityElement(children: .combine)
                .accessibilityValue(task.isDone ? "Done" : "Not done")
            }
        }
        .cardStyle()
    }

    // MARK: Actions

    private var customerThreadID: MessageThread.ID? {
        guard store.capabilities.contains(.customerMessaging) else { return nil }
        return store.customerThread(for: property.id)?.id
    }

    @ViewBuilder
    private var actionButtons: some View {
        NavigationLink(value: AppDestination.property(property.id)) {
            Label("Property", systemImage: "building.2")
        }
        .buttonStyle(.mc(.secondary, compact: true))

        if let threadID = customerThreadID {
            NavigationLink(value: AppDestination.thread(threadID)) {
                Label("Customer", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.mc(.secondary, compact: true))
        } else {
            Button {} label: {
                Label("Customer", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.mc(.secondary, compact: true))
            .disabled(true)
        }

        Button {
            openDirections()
        } label: {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        .buttonStyle(.mc(.secondary, compact: true))
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { actionButtons }
                VStack(spacing: Space.s) { actionButtons }
            }
            if customerThreadID == nil {
                Text(store.capabilities.contains(.customerMessaging)
                     ? "No customer conversation for this property yet."
                     : "Customer messaging isn't part of your role.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    @ViewBuilder
    private var skipSection: some View {
        if !stop.status.isFinished {
            VStack(alignment: .leading, spacing: Space.s) {
                Button(role: .destructive) {
                    showsSkipDialog = true
                } label: {
                    Text("Skip Stop…")
                }
                .buttonStyle(.mc(.destructiveOutline, compact: true))
                .disabled(!canPlan)
                Text(canPlan
                     ? "Skipping needs a reason and is recorded on the property's history."
                     : "Skipping stops needs route-planning access.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    private func openDirections() {
        let placemark = MKPlacemark(coordinate: RoutesGeo.coordinate(property))
        let item = MKMapItem(placemark: placemark)
        item.name = property.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func skip(_ reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toasts.show("Add a reason to skip this stop", symbol: "exclamationmark.circle", tone: .amber)
            return
        }
        store.skipStop(routeID: route.id, stopID: stop.id, reason: trimmed)
        Haptics.success()
        toasts.show(store.isOnline ? "Stop skipped · \(trimmed)" : "Stop skipped · saved on this iPhone, sends automatically",
                    symbol: "forward.end.fill", tone: .amber)
    }
}

// MARK: - Status track

/// Pending → En route → Arrived → Working → Done. Colour + icon + label for each step.
private struct StopStatusTrack: View {
    let status: StopStatus
    var skipReason: String?

    private static let steps = ["Pending", "En route", "Arrived", "Working", "Done"]

    private var current: Int {
        switch status {
        case .pending, .delayed, .urgent, .skipped: 0
        case .enRoute: 1
        case .inProgress: 3
        case .done: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Status")
                    .font(.headline)
                Spacer()
                StatusPill(status: status, text: status == .skipped ? "Skipped" : nil)
            }
            if status == .skipped {
                Text("Skipped" + (skipReason.map { " · \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalTrack
                    verticalTrack
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if status == .skipped { return "Status: skipped" + (skipReason.map { ", \($0)" } ?? "") }
        return "Status: \(Self.steps[current]), step \(current + 1) of \(Self.steps.count)"
    }

    private var horizontalTrack: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            ForEach(0..<Self.steps.count, id: \.self) { index in
                VStack(spacing: 6) {
                    dot(index)
                    Text(Self.steps[index])
                        .font(.caption.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index <= current ? Palette.ink : Palette.ink3)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var verticalTrack: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(0..<Self.steps.count, id: \.self) { index in
                HStack(spacing: Space.m) {
                    dot(index)
                    Text(Self.steps[index])
                        .font(.body.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index <= current ? Palette.ink : Palette.ink3)
                }
            }
        }
    }

    private func dot(_ index: Int) -> some View {
        let symbol: String
        let color: Color
        if index < current || (index == current && status == .done) {
            symbol = "checkmark.circle.fill"
            color = Palette.green
        } else if index == current {
            symbol = status.symbol
            color = status.tone == .neutral ? Palette.ink : status.tone.foreground
        } else {
            symbol = "circle"
            color = Palette.ink3
        }
        return Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
    }
}

#Preview("Stop Detail") {
    NavigationStack {
        StopDetailView(routeID: Fixtures.ID.routeNorth, stopID: "north-6")
            .appDestinations()
    }
    .previewEnvironment()
}
