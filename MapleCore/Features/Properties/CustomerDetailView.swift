import SwiftUI
import MapleCoreKit

/// Customer profile: contacts, properties and (finance only) billing.
struct CustomerDetailView: View {
    let customerID: Customer.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let customer = store.customer(customerID) {
            CustomerDetailContent(customer: customer)
        } else {
            MissingRecordView()
        }
    }
}

private struct CustomerDetailContent: View {
    let customer: Customer

    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var quoteDraft: Quote?
    @State private var contactForActions: Contact?

    private var properties: [Property] { store.properties(of: customer.id) }
    private var canFinance: Bool { store.capabilities.contains(.finance) && !isRolePreview }
    private var thread: MessageThread? {
        guard let t = store.customerThread(forCustomer: customer.id) else { return nil }
        let visible = (store.activeRole == .field || isRolePreview) ? t.visibleToField : t.visibleToAdmin
        return visible ? t : nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                header
                actionRow
                contactsSection
                propertiesSection
                if canFinance { billingSection }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $quoteDraft) { quote in
            QuoteBuilderView(quote: quote)
        }
        .confirmationDialog(contactForActions?.name ?? "Contact", isPresented: contactDialogBinding, titleVisibility: .visible, presenting: contactForActions) { contact in
            if let phone = contact.phone, let url = telURL(phone) {
                Button("Call \(phone)") { openURL(url) }
            }
            if let email = contact.email, let url = URL(string: "mailto:\(email)") {
                Button("Email \(email)") { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { contact in
            Text(contact.detail)
        }
    }

    private var contactDialogBinding: Binding<Bool> {
        Binding(get: { contactForActions != nil }, set: { if !$0 { contactForActions = nil } })
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s) {
            Avatar(initials: customer.initials, size: 72, tone: .red)
            Text(customer.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("\(customer.isCommercial ? "Commercial" : "Residential") customer since \(String(customer.customerSince)) · \(Fmt.plural(properties.count, "property", "properties"))")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var primary: Contact? { customer.primaryContact }
    private var phoneContact: Contact? { customer.contacts.first { $0.isPrimary && $0.phone != nil } ?? customer.contacts.first { $0.phone != nil } }
    private var emailContact: Contact? { customer.contacts.first { $0.isPrimary && $0.email != nil } ?? customer.contacts.first { $0.email != nil } }

    private var actionRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.s)], spacing: Space.s) {
            NavigationLink(value: thread.map { AppDestination.thread($0.id) }) {
                PropertyQuickActionLabel(title: "Message", symbol: "bubble.left.fill", note: thread == nil ? "No thread" : nil)
            }
            .disabled(thread == nil)
            .accessibilityHint(thread == nil ? "No conversation with this customer yet" : "Opens the conversation")

            Button {
                if let phone = phoneContact?.phone, let url = telURL(phone) { openURL(url) }
            } label: {
                PropertyQuickActionLabel(title: "Call", symbol: "phone.fill", note: phoneContact == nil ? "No number" : nil)
            }
            .disabled(phoneContact == nil)
            .accessibilityHint(phoneContact.map { "Calls \($0.name)" } ?? "No phone number on file")

            Button {
                if let email = emailContact?.email, let url = URL(string: "mailto:\(email)") { openURL(url) }
            } label: {
                PropertyQuickActionLabel(title: "Email", symbol: "envelope.fill", note: emailContact == nil ? "No email" : nil)
            }
            .disabled(emailContact == nil)
            .accessibilityHint(emailContact.map { "Emails \($0.name)" } ?? "No email on file")

            if canFinance {
                Button {
                    quoteDraft = store.newQuoteDraft(customerID: customer.id, propertyID: properties.first?.id)
                } label: {
                    PropertyQuickActionLabel(title: "Quote", symbol: "doc.text.fill")
                }
                .accessibilityHint("Starts a new quote for this customer")
            }
        }
        .buttonStyle(.plain)
        .cardStyle(padding: Space.s)
    }

    private func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    // MARK: Contacts

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Contacts")
            if customer.contacts.isEmpty {
                Text("No contacts on file.").font(.subheadline).foregroundStyle(Palette.ink3).cardStyle()
            } else {
                CardList(data: customer.contacts) { contact in
                    Button {
                        contactForActions = contact
                    } label: {
                        contactRow(contact)
                    }
                    .buttonStyle(.plain)
                    .disabled(contact.phone == nil && contact.email == nil)
                    .accessibilityHint(contact.phone == nil && contact.email == nil ? "No phone or email on file" : "Shows call and email options")
                }
            }
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(contact.detail).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if contact.isPrimary {
                Pill(text: "Primary", tone: .red, symbol: "star.fill")
            }
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Properties")
            if properties.isEmpty {
                Text("No properties linked yet.").font(.subheadline).foregroundStyle(Palette.ink3).cardStyle()
            } else {
                CardList(data: properties) { property in
                    NavigationLink(value: AppDestination.property(property.id)) {
                        HStack(spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(property.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text(property.fullAddress).font(.footnote).foregroundStyle(Palette.ink2)
                            }
                            Spacer(minLength: Space.s)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink3)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, Space.s)
                        .frame(minHeight: Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Billing (finance only)

    private var billingSection: some View {
        let balance = store.balanceDue(forCustomer: customer.id)
        let open = store.quotes(forCustomer: customer.id).filter { $0.status.isOpen }
        return VStack(alignment: .leading, spacing: Space.s) {
            PropertySectionHeader(title: "Billing", adminBadge: true) { EmptyView() }
            VStack(spacing: 0) {
                NavigationLink(value: AppDestination.invoices) {
                    billingRow(title: "Balance due", value: Fmt.money(balance), tone: balance > 0 ? .amber : .green)
                }
                Divider()
                NavigationLink(value: AppDestination.quotes) {
                    billingRow(title: "Open quotes", value: open.isEmpty ? "None" : "\(open.count) awaiting approval", tone: open.isEmpty ? nil : .blue)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func billingRow(title: String, value: String, tone: Tone?) -> some View {
        KeyValueRow(label: title, value: value, valueTone: tone, showsChevron: true)
            .contentShape(Rectangle())
    }
}

#Preview("Customer") {
    NavigationStack {
        CustomerDetailView(customerID: Fixtures.ID.northwest)
            .appDestinations()
    }
    .previewEnvironment()
}
