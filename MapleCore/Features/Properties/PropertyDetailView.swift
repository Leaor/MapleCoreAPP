import SwiftUI
import UIKit
import MapleCoreKit

/// Property profile: header, quick actions, service, access, photos, history, measurements, notes,
/// documents, invoices (finance only) and customer messages.
struct PropertyDetailView: View {
    let propertyID: Property.ID

    @Environment(AppStore.self) private var store

    var body: some View {
        if let property = store.property(propertyID) {
            PropertyDetailContent(property: property)
        } else {
            MissingRecordView()
        }
    }
}

private enum PropertySheet: String, Identifiable {
    case note, issue, edit
    var id: String { rawValue }
}

private struct PropertyDetailContent: View {
    let property: Property

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.isRolePreview) private var isRolePreview
    @Environment(\.openURL) private var openURL

    @State private var sheet: PropertySheet?

    private var isFieldContext: Bool { store.activeRole == .field || isRolePreview }
    private var canEdit: Bool { store.activeRole?.usesAdminShell == true && !isRolePreview }
    private var customer: Customer? { store.customer(property.customerID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                PropertyHeaderSection(property: property)
                quickActions
                if let customer, let contact = customer.primaryContact {
                    contactRow(customer: customer, contact: contact)
                }
                PropertyServiceCard(property: property)
                accessCard
                PropertyLastVisitSection(property: property)
                PropertyHistorySection(property: property)
                PropertyMeasurementsSection(property: property, canEdit: canEdit) { sheet = .edit }
                if !property.equipment.isEmpty { equipmentSection }
                notesSection
                PropertyDocumentsSection(property: property)
                if store.capabilities.contains(.finance) {
                    PropertyInvoicesSection(property: property)
                }
                PropertyMessagesSection(property: property, isFieldContext: isFieldContext)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.l)
        }
        .screenBackground()
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $sheet) { which in
            switch which {
            case .note:
                PropertyTextEntrySheet(title: "Add Note", prompt: "Note for the office and crews", footnote: "Internal · added to this property's timeline. Never shown to the customer.", actionTitle: "Save") { text in
                    store.addPropertyNote(text, propertyID: property.id)
                    Haptics.success()
                    toasts.show(store.isOnline ? "Note added to timeline" : "Saved on this iPhone · sends automatically")
                }
            case .issue:
                PropertyTextEntrySheet(title: "Report Issue", prompt: "What's wrong? e.g. broken irrigation head by the loading bay", footnote: "The office is notified and the issue stays open on this property until it's resolved.", actionTitle: "Report") { text in
                    store.reportIssue(text, propertyID: property.id)
                    Haptics.success()
                    toasts.show(store.isOnline ? "Issue reported" : "Saved on this iPhone · sends automatically", symbol: "exclamationmark.triangle.fill", tone: .amber)
                }
            case .edit:
                EditPropertySheet(propertyID: property.id)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if canEdit {
                Button("Edit") { sheet = .edit }
                    .accessibilityLabel("Edit property")
            }
            Menu {
                ShareLink(item: property.fullAddress, subject: Text(property.name), message: Text(property.name)) {
                    Label("Share Address", systemImage: "square.and.arrow.up")
                }
                Button {
                    openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                }
                Button {
                    UIPasteboard.general.string = property.fullAddress
                    toasts.show("Address copied", symbol: "doc.on.doc")
                } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
        }
    }

    private func openInMaps() {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: property.name),
            URLQueryItem(name: "ll", value: "\(property.latitude),\(property.longitude)"),
            URLQueryItem(name: "address", value: property.fullAddress)
        ]
        if let url = components?.url { openURL(url) }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: Space.s)]
        let todayRoute = store.todayRoute(servingProperty: property.id)
        return LazyVGrid(columns: columns, spacing: Space.s) {
            if isFieldContext {
                startAction
            }
            NavigationLink(value: AppDestination.gallery(property.id)) {
                PropertyQuickActionLabel(title: "Photo", symbol: "photo.on.rectangle")
            }
            .accessibilityHint("Opens the property's photos")
            Button { sheet = .note } label: {
                PropertyQuickActionLabel(title: "Note", symbol: "square.and.pencil")
            }
            NavigationLink(value: contactDestination) {
                PropertyQuickActionLabel(title: "Contact", symbol: "bubble.left.and.bubble.right")
            }
            .disabled(contactDestination == nil)
            routeAction(todayRoute)
            Button { sheet = .issue } label: {
                PropertyQuickActionLabel(title: "Issue", symbol: "exclamationmark.triangle")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Space.xs)
        .cardStyle(padding: Space.s)
    }

    @ViewBuilder
    private var startAction: some View {
        if let found = store.fieldStop(atProperty: property.id) {
            NavigationLink(value: AppDestination.fieldStop(found.route.id, found.stop.id)) {
                PropertyQuickActionLabel(title: "Start", symbol: "play.fill", isPrimary: true)
            }
            .accessibilityHint("Opens this stop on your route")
        } else {
            Button {} label: {
                PropertyQuickActionLabel(title: "Start", symbol: "play.fill", note: "Not on route")
            }
            .disabled(true)
            .accessibilityHint("This property isn't on your route today")
        }
    }

    @ViewBuilder
    private func routeAction(_ route: Route?) -> some View {
        if let route {
            NavigationLink(value: AppDestination.route(route.id)) {
                PropertyQuickActionLabel(title: "Route", symbol: "map", isPrimary: !isFieldContext)
            }
            .accessibilityHint("Opens \(route.name)")
        } else {
            Button {} label: {
                PropertyQuickActionLabel(title: "Route", symbol: "map", note: "None today")
            }
            .disabled(true)
            .accessibilityHint("No route visits this property today")
        }
    }

    /// Customer thread when one exists and is visible here, else the customer profile.
    private var contactDestination: AppDestination? {
        if let thread = store.customerThread(for: property.id),
           isFieldContext ? thread.visibleToField : thread.visibleToAdmin {
            return .thread(thread.id)
        }
        if let id = property.customerID { return .customer(id) }
        return nil
    }

    // MARK: Contact

    private func contactRow(customer: Customer, contact: Contact) -> some View {
        NavigationLink(value: AppDestination.customer(customer.id)) {
            HStack(spacing: Space.m) {
                Avatar(initials: initials(contact.name), size: 44, tone: .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(contactSubtitle(contact, customer: customer))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: Space.s)
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
        .accessibilityHint("Opens the customer")
    }

    private func contactSubtitle(_ contact: Contact, customer: Customer) -> String {
        let role = contact.detail.components(separatedBy: " · ").first ?? contact.detail
        return role.isEmpty ? customer.name : "\(role) · \(customer.name)"
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // MARK: Access, equipment, notes

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Access · crew only", systemImage: "lock.fill")
                .captionStyle()
            Text(property.accessNotes.isEmpty ? "No access instructions yet." : property.accessNotes)
                .font(.body)
                .foregroundStyle(property.accessNotes.isEmpty ? Palette.ink3 : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Equipment required") { EmptyView() }
            PropertyFlowLayout {
                ForEach(property.equipment, id: \.self) { item in
                    PropertyChip(text: item)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Property notes") { EmptyView() }
            VStack(alignment: .leading, spacing: Space.s) {
                Text(property.notes.isEmpty ? "No notes yet. Use Note above to add one to the timeline." : property.notes)
                    .font(.body)
                    .foregroundStyle(property.notes.isEmpty ? Palette.ink3 : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !property.notesUpdatedBy.isEmpty {
                    Text(notesUpdatedLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            .cardStyle()
            .accessibilityElement(children: .combine)
        }
    }

    private var notesUpdatedLine: String {
        if let date = property.notesUpdatedAt {
            return "Updated by \(property.notesUpdatedBy) · \(Fmt.shortDate(date))"
        }
        return "Updated by \(property.notesUpdatedBy)"
    }
}

// MARK: - Header

private struct PropertyHeaderSection: View {
    let property: Property

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(property.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(property.fullAddress)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            PropertyFlowLayout(spacing: 6) {
                if property.isContractActive {
                    Pill(text: "Contract active", tone: .green, symbol: "checkmark.seal.fill")
                } else if property.contractEnd != nil {
                    Pill(text: "Contract inactive", tone: .neutral, symbol: "doc")
                }
                Pill(text: property.kind.label, tone: .neutral)
                Pill(text: property.frequency.label, tone: .neutral, symbol: "arrow.triangle.2.circlepath")
                if property.hasSnowContract {
                    Pill(text: "Snow & salt", tone: .blue, symbol: "snowflake")
                }
                if property.openIssues > 0 {
                    Pill(text: Fmt.plural(property.openIssues, "open issue"), tone: .amber, symbol: "exclamationmark.triangle.fill")
                }
            }
            .padding(.top, Space.xs)
        }
    }
}

// MARK: - Service

private struct PropertyServiceCard: View {
    let property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            KeyValueRow(label: "Service", value: "\(property.primaryService) · \(property.frequency.label)")
            Divider()
            KeyValueRow(label: "Contract", value: PropertyFormat.contractRange(property.contractStart, property.contractEnd) ?? "No contract on file")
            Divider()
            KeyValueRow(label: "Assigned crew", value: crewText)
            Divider()
            KeyValueRow(label: "Next visit", value: nextVisitText)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var crewText: String {
        guard let crew = store.crew(property.assignedCrewID) else { return "Unassigned" }
        if let lead = store.member(crew.leadID) { return "\(crew.name) · \(lead.shortName)" }
        return crew.name
    }

    private var nextVisitText: String {
        guard let next = store.scheduledStop(forProperty: property.id) else {
            if let today = store.todayRoute(servingProperty: property.id),
               let stop = today.stops.first(where: { $0.propertyID == property.id }), stop.status == .done {
                return "Done today"
            }
            return "Not scheduled"
        }
        let day = Fmt.relativeDay(next.route.date, now: store.now)
        if next.stop.status == .inProgress { return "\(day) · on site now" }
        if let eta = next.stop.eta { return "\(day) · ETA \(Fmt.time(eta))" }
        return "\(day) · starts \(Fmt.time(next.route.startTime))"
    }
}

// MARK: - Last visit

private struct PropertyLastVisitSection: View {
    let property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        if let visit = store.latestPhotoVisit(forProperty: property.id) {
            let pair = store.photoPairs(for: visit).first
            let before = pair?.before ?? visit.photos(.before).first
            let after = pair?.after ?? visit.photos(.after).first
            VStack(alignment: .leading, spacing: Space.s) {
                PropertySectionHeader(title: "Last visit · \(Fmt.shortDate(visit.date))") {
                    NavigationLink("All photos", value: AppDestination.gallery(property.id))
                }
                NavigationLink(value: AppDestination.photoCompare(visit.id)) {
                    HStack(spacing: Space.s) {
                        tile(before, label: "Before", swatch: 0)
                        tile(after, label: "After", swatch: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare before and after photos from \(Fmt.shortDate(visit.date))")
            }
        }
    }

    private func tile(_ photo: VisitPhoto?, label: String, swatch: Int) -> some View {
        PhotoTile(photo: photo, swatch: swatch, cornerRadius: Radius.card)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(Space.s)
            }
    }
}

// MARK: - History

private struct PropertyHistorySection: View {
    let property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        let entries = Array(store.history(for: property.id).prefix(3))
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Service history") {
                NavigationLink("Timeline", value: AppDestination.visitHistory(property.id))
            }
            if entries.isEmpty {
                Text("No visits recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink3)
                    .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, record in
                        row(record, isLast: index == entries.count - 1)
                    }
                }
                .cardStyle()
            }
        }
    }

    private func row(_ record: VisitRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(spacing: 0) {
                Circle()
                    .fill(record.propertyTimelineTone.foreground)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle().fill(Palette.separator).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.propertyTimelineTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail(record))
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.bottom, isLast ? 0 : Space.m)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ record: VisitRecord) -> String {
        var parts = [Fmt.shortDate(record.date)]
        switch record.kind {
        case .visit:
            if let crew = store.crew(record.crewID) { parts.append(crew.name) }
            if !record.photos.isEmpty { parts.append(Fmt.plural(record.photos.count, "photo")) }
            parts.append(record.propertyTimelineBadge.text)
        case .issue:
            parts.append(record.detail.components(separatedBy: " · ").first ?? record.detail)
            parts.append(record.resolvedAt == nil ? "Open" : "Resolved")
        case .note, .skipped:
            if !record.detail.isEmpty { parts.append(record.detail) }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Measurements

private struct PropertyMeasurementsSection: View {
    let property: Property
    let canEdit: Bool
    var onEdit: () -> Void

    var body: some View {
        let m = property.measurements
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Site measurements") {
                if canEdit { Button("Edit", action: onEdit).accessibilityLabel("Edit site measurements") }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible())], alignment: .leading, spacing: Space.l) {
                cell(PropertyFormat.area(m.lawnSqM), "Lawn")
                cell(PropertyFormat.area(m.gardenBedsSqM), "Garden beds")
                cell(PropertyFormat.area(m.parkingSqM), "Parking (snow)")
                cell(PropertyFormat.length(m.walkwaysM), "Walkways (salt)")
            }
            .cardStyle()
        }
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).numeric().foregroundStyle(Palette.ink)
            Text(label).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Documents

private struct PropertyDocumentsSection: View {
    let property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        let docs = store.documents(for: property.id).sorted { $0.isFeatured && !$1.isFeatured }
        let shown = Array(docs.prefix(2))
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Documents") {
                NavigationLink("All", value: AppDestination.documents(property.id))
                    .accessibilityLabel("All documents")
            }
            if shown.isEmpty {
                NavigationLink(value: AppDestination.documents(property.id)) {
                    Text("No documents yet")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink3)
                        .cardStyle()
                }
                .buttonStyle(.plain)
            } else {
                CardList(data: shown) { doc in
                    NavigationLink(value: AppDestination.documents(property.id)) {
                        HStack(spacing: Space.m) {
                            Text(doc.title).font(.body).foregroundStyle(Palette.ink)
                            Spacer(minLength: Space.s)
                            Text(doc.kind.badge).font(.footnote).foregroundStyle(Palette.ink2)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Invoices (finance only)

private struct PropertyInvoicesSection: View {
    let property: Property
    @Environment(AppStore.self) private var store

    var body: some View {
        let invoices = Array(store.invoices(for: property.id).prefix(2))
        VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Invoices", adminBadge: true) {
                NavigationLink("All", value: AppDestination.invoices)
                    .accessibilityLabel("All invoices")
            }
            if invoices.isEmpty {
                Text("No invoices for this property yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink3)
                    .cardStyle()
            } else {
                CardList(data: invoices) { invoice in
                    NavigationLink(value: AppDestination.invoice(invoice.id)) {
                        HStack(spacing: Space.m) {
                            Text("\(invoice.number) · \(invoice.title)")
                                .font(.body)
                                .numeric()
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: Space.s)
                            pill(invoice)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func pill(_ invoice: Invoice) -> Pill {
        if invoice.isPaid { return Pill(text: "Paid", tone: .green, symbol: "checkmark") }
        if invoice.isOverdue(asOf: store.now) { return Pill(text: "Overdue", tone: .red, symbol: "exclamationmark.circle") }
        return Pill(text: "Due \(Fmt.shortDate(invoice.dueDate))", tone: .neutral, symbol: "clock")
    }
}

// MARK: - Customer messages

private struct PropertyMessagesSection: View {
    let property: Property
    let isFieldContext: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        if let thread = store.customerThread(for: property.id),
           isFieldContext ? thread.visibleToField : thread.visibleToAdmin {
            VStack(alignment: .leading, spacing: Space.s) {
                PropertySectionHeader(title: "Customer messages") {
                    NavigationLink("Open", value: AppDestination.thread(thread.id))
                        .accessibilityLabel("Open conversation")
                }
                NavigationLink(value: AppDestination.thread(thread.id)) {
                    preview(thread)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func preview(_ thread: MessageThread) -> some View {
        let message = store.latestCustomerMessage(in: thread)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(message?.authorName ?? thread.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                if let message {
                    Text(Fmt.stamp(message.sentAt, now: store.now))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Text(message?.text ?? "No messages yet")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Property detail") {
    NavigationStack {
        PropertyDetailView(propertyID: Fixtures.ID.islington)
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Property detail · field") {
    NavigationStack {
        PropertyDetailView(propertyID: Fixtures.ID.islington)
            .appDestinations()
    }
    .previewEnvironment(role: .field)
}
