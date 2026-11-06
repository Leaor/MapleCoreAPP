import SwiftUI
import MapleCoreKit

/// Reference screen: the notification templates MapleCore sends, filled from current data and shown
/// as Lock Screen cards. Real delivery needs the push service (Phase 2).
struct PushNotificationsPreviewView: View {
    @Environment(AppStore.self) private var store

    private var templates: [NotificationTemplate] {
        var items: [NotificationTemplate] = []
        if let snow = snowTemplate { items.append(snow) }
        if let message = customerMessageTemplate { items.append(message) }
        if let review = reviewTemplate { items.append(review) }
        if let route = routeChangedTemplate { items.append(route) }
        return items
    }

    var body: some View {
        let templates = self.templates
        ScrollView {
            VStack(spacing: Space.l) {
                lockScreenClock
                if templates.isEmpty {
                    EmptyStateView(symbol: "bell.slash", title: "No templates to show", message: "Templates fill in from routes, messages and visits. There's nothing to preview yet.")
                } else {
                    VStack(spacing: Space.s) {
                        ForEach(templates) { template in
                            NotificationCard(template: template)
                        }
                    }
                }
                footnote
            }
            .padding(Space.l)
        }
        .background {
            LinearGradient(colors: [Palette.surface2, Palette.background], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationTitle("Notification templates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockScreenClock: some View {
        VStack(spacing: 0) {
            Text(Fmt.longDay(store.now))
                .font(.headline)
                .foregroundStyle(Palette.ink2)
            Text(Fmt.clock(store.now))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .numeric()
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lock Screen preview, \(Fmt.longDay(store.now))")
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Previews only", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("These are the templates MapleCore uses. Real delivery to iPhones needs the push service, which arrives in Phase 2. Choose which alerts you get in Settings → Notifications.")
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
        .cardStyle()
    }

    // MARK: Templates from store data

    private var snowTemplate: NotificationTemplate? {
        guard let event = store.snowEvent, let route = event.pendingRoutes.first ?? event.routes.first else { return nil }
        let crew = store.crew(route.crewID)?.name
        let body = "\(event.forecast) \(route.propertyCount) \(route.unitLabel) on \(route.name)\(crew.map { " for \($0)" } ?? ""). Confirm you're available."
        return NotificationTemplate(id: "snow", icon: "snowflake", iconTone: .blue, title: "Snow dispatch · Route \(route.code)", time: "now", body: body, isTimeSensitive: true, actions: ["I'm Available", "Can't Make It"])
    }

    private var customerMessageTemplate: NotificationTemplate? {
        let thread = store.adminThreads.first { thread in
            thread.kind == .customer && thread.messages.contains { $0.authorID == nil && !$0.text.isEmpty }
        }
        guard let thread, let message = thread.messages.last(where: { $0.authorID == nil && !$0.text.isEmpty }) else { return nil }
        let property = store.property(thread.propertyID)?.name
        let title = [thread.title, property].compactMap { $0 }.joined(separator: " · ")
        return NotificationTemplate(id: "message", initials: thread.initials, title: title, time: Fmt.clock(message.sentAt), body: message.text)
    }

    private var reviewTemplate: NotificationTemplate? {
        guard let visit = store.reviewQueue.first ?? store.visitRecords.first(where: { $0.kind == .visit }) else { return nil }
        let property = store.property(visit.propertyID)?.name ?? visit.title
        let crew = store.crew(visit.crewID)?.name ?? visit.crewNames
        let parts = [property, crew, Fmt.duration(minutes: visit.workMinutes), Fmt.plural(visit.photos.count, "photo")].filter { !$0.isEmpty }
        return NotificationTemplate(id: "review", icon: "checkmark.seal.fill", iconTone: .green, title: "Visit ready for review", time: Fmt.clock(visit.workEnd ?? visit.date), body: parts.joined(separator: " · "))
    }

    private var routeChangedTemplate: NotificationTemplate? {
        guard let route = store.todayRoutes.first(where: { $0.state != .completed && $0.stops.count > 1 }),
              let stop = route.nextStop,
              let index = route.index(of: stop.id),
              let property = store.property(stop.propertyID) else { return nil }
        return NotificationTemplate(id: "route", icon: "arrow.triangle.swap", iconTone: .amber, title: "Route changed", time: Fmt.clock(route.startTime), body: "\(property.name) moved to stop \(index + 1) on \(route.name) · +\(stop.estimatedMinutes) min")
    }
}

/// One notification template.
private struct NotificationTemplate: Identifiable {
    var id: String
    var icon: String? = nil
    var iconTone: Tone = .red
    var initials: String? = nil
    var title: String
    var time: String
    var body: String
    var isTimeSensitive = false
    var actions: [String] = []
}

/// Lock Screen–style card. Action labels are a picture of the notification, not live controls.
private struct NotificationCard: View {
    let template: NotificationTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(template.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.s)
                        Text(template.time)
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                    }
                    Text(template.body)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    if template.isTimeSensitive {
                        Label("Time sensitive", systemImage: "clock.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.redText)
                            .padding(.top, 2)
                    }
                }
            }
            if !template.actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s) { actionLabels }
                    VStack(spacing: Space.s) { actionLabels }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Actions: \(template.actions.joined(separator: ", "))")
            }
        }
        .padding(Space.m + 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        if let initials = template.initials {
            Avatar(initials: initials, size: 38, tone: .blue)
        } else {
            Image(systemName: template.icon ?? "bell.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(template.iconTone == .neutral ? Palette.ink : template.iconTone.foreground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var actionLabels: some View {
        ForEach(template.actions, id: \.self) { action in
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        }
    }
}

#Preview("Notification templates") {
    NavigationStack {
        PushNotificationsPreviewView()
    }
    .previewEnvironment()
}
