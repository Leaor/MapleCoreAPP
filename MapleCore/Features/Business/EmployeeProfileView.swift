import SwiftUI
import MapleCoreKit

/// One team member: status, quick actions, live status, this week's numbers and availability.
struct EmployeeProfileView: View {
    let staffID: StaffMember.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let person = store.member(staffID) {
            EmployeeProfileContent(person: person)
        } else {
            MissingRecordView(title: "Team member not available")
        }
    }
}

private struct EmployeeProfileContent: View {
    let person: StaffMember
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var crew: Crew? { store.crew(person.crewID) }
    private var todayRoute: Route? { store.bizTodayRoute(forCrew: person.crewID) }
    private var phoneURL: URL? {
        let digits = person.phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                actions
                if case let .live(place, updatedAt) = person.location, store.capabilities.contains(.staffLocation) {
                    liveCard(place: place, updatedAt: updatedAt)
                }
                stats
                availability
                shiftHistory
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s) {
            Avatar(initials: person.initials, size: 72, tone: person.isOnDuty ? .green : .neutral)
            Text(person.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(roleLine)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
            dutyPill
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var roleLine: String {
        var parts = [person.jobTitle]
        if let crew { parts.append(crew.name) }
        parts.append("since \(person.startYear)")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var dutyPill: some View {
        if let since = person.onDutySince {
            Pill(text: "On duty since \(Fmt.time(since))", tone: .green, symbol: "circle.fill")
        } else if let starts = person.shiftStartsAt, starts > store.now {
            Pill(text: "Off duty · starts \(Fmt.time(starts))", tone: .neutral, symbol: "clock")
        } else {
            Pill(text: "Off duty", tone: .neutral, symbol: "moon")
        }
    }

    // MARK: Actions

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) { actionButtons }
            VStack(spacing: Space.s) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            if let phoneURL { openURL(phoneURL) }
        } label: {
            Label("Call", systemImage: "phone.fill")
        }
        .buttonStyle(.mc(.secondary, compact: true))
        .disabled(phoneURL == nil)
        .accessibilityLabel("Call \(person.firstName)")

        Button {
            if let id = store.directThread(with: person.id) {
                model.push(.thread(id))
            } else {
                toasts.show("Preview only — new conversations can't be started", symbol: "eye", tone: .blue)
            }
        } label: {
            Label("Message", systemImage: "message.fill")
        }
        .buttonStyle(.mc(.secondary, compact: true))
        .accessibilityLabel("Message \(person.firstName)")

        Button {
            if let route = todayRoute { model.push(.route(route.id)) }
        } label: {
            Label("Route", systemImage: "map.fill")
        }
        .buttonStyle(.mc(.secondary, compact: true))
        .disabled(todayRoute == nil)
        .accessibilityLabel(todayRoute == nil ? "No route today" : "Today's route")
    }

    // MARK: Live status

    private func liveCard(place: String, updatedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label {
                Text(workingLine(place: place))
                    .font(.headline)
            } icon: {
                Image(systemName: "location.fill")
                    .foregroundStyle(Palette.blue)
            }
            Text("Live location shared by \(person.firstName) during the shift · updated \(Fmt.ago(updatedAt, now: store.now))")
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func workingLine(place: String) -> String {
        if let route = todayRoute, let stop = route.inProgressStop,
           let property = store.property(stop.propertyID), property.name == place, let started = stop.startedAt {
            let minutes = max(0, Int(store.now.timeIntervalSince(started) / 60))
            return "Working at \(place) · \(minutes) min"
        }
        return "At \(place)"
    }

    // MARK: Stats

    private var stats: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("This week")
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.m) { statTiles }
                } else {
                    HStack(alignment: .top, spacing: Space.m) { statTiles }
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        StatTile(value: "\(person.visitsThisWeek)", label: "Visits done")
        StatTile(value: Fmt.percent(person.onTimeRate), label: "Arrived on time", tone: person.onTimeRate < 0.9 ? .amber : nil)
        StatTile(value: Fmt.percent(person.photoProofRate), label: "Photo proof", tone: person.photoProofRate < 0.95 ? .amber : nil)
    }

    // MARK: Availability

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let offsetToMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offsetToMonday, to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Availability")
            HStack(spacing: Space.xs) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    let available = person.availability.indices.contains(index) ? person.availability[index] : false
                    let isToday = Calendar.current.isDate(day, inSameDayAs: store.now)
                    VStack(spacing: 2) {
                        Text(String(Fmt.weekdayShort(day).prefix(1)))
                            .font(.caption.weight(.semibold))
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.subheadline.weight(.semibold))
                            .numeric()
                        Image(systemName: available ? "checkmark" : "xmark")
                            .font(.caption2.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(available ? Palette.green : Palette.ink3)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(available ? Palette.greenSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Palette.ink, lineWidth: 1.5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Fmt.shortDay(day))\(isToday ? ", today" : ""), \(available ? "available" : "not available")")
                }
            }
        }
    }

    // MARK: Shift history

    private var shiftHistory: some View {
        NavigationLink(value: AppDestination.routeHistory) {
            HStack {
                Text("Shift history")
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("Last: \(person.lastShift)")
                    .foregroundStyle(Palette.ink2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Hit.min)
            .cardStyle(padding: Space.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Employee") {
    NavigationStack {
        EmployeeProfileView(staffID: Fixtures.ID.daniel).appDestinations()
    }
    .previewEnvironment()
}
