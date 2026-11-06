import SwiftUI
import MapleCoreKit

/// Admin / manager / supervisor home: what's happening today and what needs a decision.
/// Data is local (AppStore), so there's no loading skeleton — pull to refresh nudges the sync queue.
struct AdminTodayView: View {
    @Environment(AppStore.self) private var store

    @State private var routeDraft: Route?
    @State private var showAddProperty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                TodayGreeting()
                VStack(spacing: Space.m) {
                    TodayWeatherCard()
                    TodayWorkCard()
                }
                TodayNeedsAttention()
                quickActions
                TodayActiveCrews()
                TodayRecentPhotos()
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xxxl)
        }
        .screenBackground()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppDestination.settings) {
                    Avatar(initials: store.account?.initials ?? "–", size: 34, tone: .neutral)
                }
                .accessibilityLabel("Account and settings")
            }
        }
        .refreshable { store.scheduleSync() }
        .fullScreenCover(item: $routeDraft) { draft in
            RoutePlannerView(draft: draft)
        }
        .sheet(isPresented: $showAddProperty) {
            AddPropertySheet()
        }
    }

    private var quickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) { quickActionButtons }
            VStack(spacing: Space.s) { quickActionButtons }
        }
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        if store.capabilities.contains(.routePlanning) {
            Button {
                routeDraft = store.newRouteDraft(on: store.now)
            } label: {
                Label("New Route", systemImage: "plus")
            }
            .buttonStyle(.mc(.primary))
        }
        Button {
            showAddProperty = true
        } label: {
            Label("Property", systemImage: "plus")
        }
        .buttonStyle(.mc(.secondary))
        .accessibilityLabel("Add property")
    }
}

// MARK: - Greeting

private struct TodayGreeting: View {
    @Environment(AppStore.self) private var store

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: store.now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        guard let name = store.account?.firstName else { return part }
        return "\(part), \(name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.longDay(store.now))
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            Text(greeting)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, Space.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Weather

private struct TodayWeatherCard: View {
    @Environment(AppStore.self) private var store

    private var canOpenSnowOps: Bool { store.capabilities.contains(.snowDispatch) }

    var body: some View {
        if canOpenSnowOps {
            NavigationLink(value: AppDestination.snowOps) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Snow Operations")
        } else {
            content
        }
    }

    private var content: some View {
        let weather = store.weather
        return HStack(spacing: Space.m) {
            Image(systemName: "cloud")
                .font(.title2)
                .foregroundStyle(Palette.ink2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(weather.temperatureC)° \(weather.condition) · \(weather.place)")
                    .font(.headline)
                    .numeric()
                    .foregroundStyle(Palette.ink)
                Text("Low \(weather.lowC)° · \(weather.outlook)")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                Text("Sample forecast · preview data")
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: Space.s)
            if weather.snowWatch {
                Pill(text: "Snow watch", tone: .blue, symbol: "snowflake")
            }
            if canOpenSnowOps {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today's work

private struct TodayWorkCard: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = store.todayStats
        Button {
            model.open(.routes)
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Text("Today's work").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.s) { tiles(stats) }
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(alignment: .top, spacing: Space.s) {
                            StatTile(value: "\(stats.scheduled)", label: "Scheduled")
                            StatTile(value: "\(stats.completed)", label: "Completed", tone: .green)
                        }
                        HStack(alignment: .top, spacing: Space.s) {
                            StatTile(value: "\(stats.pending)", label: "Pending")
                            StatTile(value: "\(stats.crewsActive)/\(stats.crewsTotal)", label: "Crews active")
                        }
                    }
                }
                WorkStackedBar(stats: stats)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.l) { legend(stats) }
                    VStack(alignment: .leading, spacing: Space.xs) { legend(stats) }
                }
            }
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's work: \(stats.scheduled) scheduled, \(stats.completed) completed, \(stats.pending) pending, \(stats.inProgress) in progress, \(stats.delayed) delayed. \(stats.crewsActive) of \(stats.crewsTotal) crews active.")
        .accessibilityHint("Opens Routes")
    }

    @ViewBuilder
    private func tiles(_ stats: AppStore.TodayStats) -> some View {
        StatTile(value: "\(stats.scheduled)", label: "Scheduled")
        StatTile(value: "\(stats.completed)", label: "Completed", tone: .green)
        StatTile(value: "\(stats.pending)", label: "Pending")
        StatTile(value: "\(stats.crewsActive)/\(stats.crewsTotal)", label: "Crews active")
    }

    @ViewBuilder
    private func legend(_ stats: AppStore.TodayStats) -> some View {
        LegendItem(color: Palette.green, text: "Done \(stats.completed)")
        LegendItem(color: Palette.blue, text: "In progress \(stats.inProgress)")
        LegendItem(color: Palette.amber, text: "Delayed \(stats.delayed)")
    }
}

private struct WorkStackedBar: View {
    var stats: AppStore.TodayStats

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(stats.scheduled, 1))
            let width = proxy.size.width
            HStack(spacing: 0) {
                Rectangle().fill(Palette.green).frame(width: width * CGFloat(stats.completed) / total)
                Rectangle().fill(Palette.blue).frame(width: width * CGFloat(stats.inProgress) / total)
                Rectangle().fill(Palette.amber).frame(width: width * CGFloat(stats.delayed) / total)
                Rectangle().fill(Palette.surface2)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct LegendItem: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(Palette.ink2).numeric()
        }
    }
}

// MARK: - Needs attention

private struct AttentionItem: Identifiable {
    enum Action { case push(AppDestination), inbox }

    var id: String
    var symbol: String
    var tone: Tone
    var title: String
    var detail: String?
    var action: Action
}

private struct TodayNeedsAttention: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    private var items: [AttentionItem] {
        var items: [AttentionItem] = []
        for thread in store.urgentThreads {
            let place = store.property(thread.propertyID)?.name ?? thread.subtitle
            items.append(AttentionItem(
                id: "thread-\(thread.id)",
                symbol: "exclamationmark.circle.fill",
                tone: .red,
                title: thread.lastMessage?.text ?? thread.title,
                detail: "Urgent request · \(place) · \(Fmt.ago(thread.lastActivity, now: store.now))",
                action: .push(.thread(thread.id))))
        }
        let queue = store.reviewQueue
        if store.capabilities.contains(.visitReview), let first = queue.first {
            items.append(AttentionItem(id: "review", symbol: "photo.on.rectangle", tone: .blue,
                                       title: "\(Fmt.plural(queue.count, "visit")) awaiting review", detail: nil,
                                       action: .push(.review(first.id))))
        }
        let unread = store.unreadCount(forField: false)
        if unread > 0 {
            items.append(AttentionItem(id: "unread", symbol: "bubble.left", tone: .neutral,
                                       title: "\(Fmt.plural(unread, "unread message"))", detail: nil, action: .inbox))
        }
        let needCrew = store.todayRoutesNeedingCrew
        if store.capabilities.contains(.routePlanning), let first = needCrew.first {
            items.append(AttentionItem(id: "crew", symbol: "person.badge.plus", tone: .amber,
                                       title: "\(Fmt.plural(needCrew.count, "route")) \(needCrew.count == 1 ? "needs" : "need") a crew",
                                       detail: "\(first.name) · \(Fmt.relativeDay(first.date, now: store.now))",
                                       action: .push(.route(first.id))))
        }
        return items
    }

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Needs attention")
            if items.isEmpty {
                HStack(spacing: Space.m) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                    Text("All caught up — nothing needs you right now.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                .cardStyle()
                .accessibilityElement(children: .combine)
            } else {
                CardList(data: items, inset: 40) { item in
                    Button { perform(item.action) } label: { AttentionRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func perform(_ action: AttentionItem.Action) {
        switch action {
        case let .push(destination): model.push(destination)
        case .inbox: model.open(.inbox)
        }
    }
}

private struct AttentionRow: View {
    var item: AttentionItem

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: item.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.tone.foreground)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Active crews

private struct TodayActiveCrews: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let routes = store.todayActiveCrewRoutes
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "Active crews") {
                NavigationLink("See all", value: AppDestination.crews)
                    .frame(minHeight: Hit.min)
            }
            if routes.isEmpty {
                Text("No crews are on a route right now.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .cardStyle()
            } else {
                CardList(data: routes, inset: 48) { route in
                    NavigationLink(value: AppDestination.route(route.id)) {
                        ActiveCrewRow(route: route)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ActiveCrewRow: View {
    @Environment(AppStore.self) private var store
    var route: Route

    private var stopNumber: Int {
        if let stop = route.inProgressStop, let index = route.index(of: stop.id) { return index + 1 }
        return min(route.finishedCount + 1, max(route.stops.count, 1))
    }

    var body: some View {
        let crew = store.crew(route.crewID)
        HStack(spacing: Space.m) {
            CrewBadge(letter: crew?.letter ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(crew?.name ?? "Crew") · \(store.crewMemberNames(route.crewID))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(route.name) · stop \(stopNumber) of \(route.stops.count) · \(route.isDelayed ? "\(route.delayMinutes) min behind" : "on time")")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if route.isDelayed {
                Pill(text: "+\(route.delayMinutes) min", tone: .amber, symbol: "clock")
            } else {
                Pill(text: "Working", tone: .blue, symbol: StopStatus.inProgress.symbol)
            }
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent photos

private struct TodayRecentPhotos: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let photos = store.todayRecentPhotos()
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionHeader(title: "Recent photos") {
                    if let first = photos.first {
                        NavigationLink("Gallery", value: AppDestination.gallery(first.propertyID))
                            .frame(minHeight: Hit.min)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { _, item in
                            NavigationLink(value: AppDestination.gallery(item.propertyID)) {
                                PhotoTile(photo: item.photo, cornerRadius: Radius.control, maxPixel: 300)
                                    .frame(width: 104, height: 104)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the \(store.property(item.propertyID)?.name ?? "property") gallery")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

#Preview("Admin Today") {
    NavigationStack {
        AdminTodayView().appDestinations()
    }
    .previewEnvironment()
}
