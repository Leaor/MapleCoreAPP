import SwiftUI
import MapleCoreKit

/// Full-screen quote builder. Drafts autosave on this iPhone; sent quotes open read-only.
struct QuoteBuilderView: View {
    let quote: Quote

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    /// The quote being shown. Starts as `quote`; replaced when duplicating.
    @State private var draft: Quote
    /// Last state written to the store, so autosave only runs on real edits.
    @State private var baseline: Quote
    @State private var hasAutosaved = false
    @State private var editingItem: LineItem?
    @State private var showsPreview = false
    @State private var showsValidation = false

    init(quote: Quote) {
        self.quote = quote
        _draft = State(initialValue: quote)
        _baseline = State(initialValue: quote)
    }

    private var isEditable: Bool { draft.status == .draft && !store.isReadOnly }
    private var hasContent: Bool { draft.customerID != nil || !draft.lineItems.isEmpty || !draft.title.isEmpty }
    private var missing: [String] {
        var items: [String] = []
        if draft.customerID == nil { items.append("a customer") }
        if draft.lineItems.isEmpty { items.append("at least one line item") }
        return items
    }

    var body: some View {
        NavigationStack {
            BizCapabilityGate(capability: .finance, title: "Quotes aren't available", message: "Quotes and pricing are visible to owners and managers.") {
                form
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task(id: draft) { await autosave() }
        .sheet(isPresented: $showsPreview) {
            QuotePreviewSheet(quote: draft)
        }
        .bizLineItemEditor(editing: $editingItem, items: $draft.lineItems)
    }

    // MARK: Form

    private var form: some View {
        Form {
            if !isEditable {
                Section {
                    HStack(spacing: Space.s) {
                        statusPill
                        if let sent = draft.sentAt {
                            Text("Sent \(Fmt.shortDate(sent))").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                        if let expires = draft.expiresAt, draft.status.isOpen {
                            Text("· Expires \(Fmt.shortDate(expires))").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    }
                    Text(store.isReadOnly ? "Preview only — quotes can't be changed." : "Sent quotes can't be edited. Duplicate it to make changes as a new draft.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
            customerSection
            BizLineItemsSection(items: $draft.lineItems, editing: $editingItem, isEditable: isEditable,
                                footer: isEditable ? "Tap to edit · swipe to delete · hold to reorder" : nil)
            BizTotalsSection(totals: draft.totals)
            actionSection
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var customerSection: some View {
        Section {
            if isEditable {
                Picker("Customer", selection: customerBinding) {
                    Text("Choose…").tag(Customer.ID?.none)
                    ForEach(store.customers.sorted { $0.name < $1.name }) { customer in
                        Text(customer.name).tag(Customer.ID?.some(customer.id))
                    }
                }
                Picker("Property", selection: $draft.propertyID) {
                    Text("None").tag(Property.ID?.none)
                    ForEach(propertyOptions) { property in
                        Text(property.name).tag(Property.ID?.some(property.id))
                    }
                }
                .disabled(draft.customerID == nil)
                Picker("Division", selection: $draft.division) {
                    ForEach(Division.allCases, id: \.self) { division in
                        Text(division.label).tag(division)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Title, e.g. Spring aeration & overseed", text: $draft.title)
            } else {
                LabeledContent("Customer", value: store.customer(draft.customerID)?.name ?? "—")
                LabeledContent("Property", value: store.property(draft.propertyID)?.name ?? "—")
                LabeledContent("Division", value: draft.division.companyName)
                LabeledContent("Title", value: draft.title.isEmpty ? "—" : draft.title)
            }
        } footer: {
            if isEditable {
                Text("Quotes from \(draft.division.companyName).")
            }
        }
    }

    private var propertyOptions: [Property] {
        guard let customerID = draft.customerID else { return [] }
        return store.properties(of: customerID)
    }

    private var customerBinding: Binding<Customer.ID?> {
        Binding(get: { draft.customerID }, set: { newValue in
            draft.customerID = newValue
            if let propertyID = draft.propertyID, store.property(propertyID)?.customerID != newValue {
                draft.propertyID = nil
            }
            if draft.propertyID == nil, let id = newValue {
                let options = store.properties(of: id)
                if options.count == 1 { draft.propertyID = options[0].id }
            }
        })
    }

    @ViewBuilder
    private var actionSection: some View {
        if isEditable {
            Section {
                Button {
                    sendForApproval()
                } label: {
                    Text("Send for Approval")
                }
                .buttonStyle(.mc(.primary))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if showsValidation && !missing.isEmpty {
                    Label("Add \(missing.joined(separator: " and ")) to send.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Palette.redText)
                } else {
                    Text(store.isOnline ? "The customer gets a link to review and approve." : "You're offline. The quote is saved on this iPhone and sends automatically.")
                }
            }
        } else if !store.isReadOnly {
            Section {
                Button {
                    duplicate()
                } label: {
                    Label("Duplicate as new draft", systemImage: "plus.square.on.square")
                }
                .frame(minHeight: Hit.min)
            }
        }
    }

    private var statusPill: some View {
        switch draft.status {
        case .draft: Pill(text: "Draft", tone: .neutral, symbol: "pencil")
        case .sent: Pill(text: draft.status.label, tone: .amber, symbol: "envelope")
        case .viewed: Pill(text: draft.status.label, tone: .blue, symbol: "eye")
        case .approved: Pill(text: "Approved", tone: .green, symbol: "checkmark")
        case .declined: Pill(text: "Declined", tone: .red, symbol: "xmark")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(closeTitle) { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("Quote \(draft.number)").font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Preview") { showsPreview = true }
                .disabled(draft.lineItems.isEmpty)
        }
    }

    private var closeTitle: String { hasAutosaved || !isEditable ? "Close" : "Cancel" }

    private var subtitle: String {
        guard draft.status == .draft else { return draft.status.label }
        return hasAutosaved ? "Draft · autosaved" : "Draft"
    }

    // MARK: Actions

    private func autosave() async {
        guard isEditable, draft != baseline, hasContent else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        store.saveQuote(draft)
        baseline = draft
        hasAutosaved = true
    }

    private func sendForApproval() {
        guard missing.isEmpty else {
            withMotion { showsValidation = true }
            Haptics.warning()
            return
        }
        store.sendQuote(draft)
        Haptics.success()
        toasts.show(store.isOnline ? "Quote \(draft.number) queued to send" : "Saved on this iPhone · sends automatically")
        dismiss()
    }

    private func duplicate() {
        var copy = store.newQuoteDraft(customerID: draft.customerID, propertyID: draft.propertyID)
        copy.title = draft.title
        copy.division = draft.division
        copy.lineItems = draft.lineItems.map { item in
            var newItem = item
            newItem.id = UUID().uuidString
            return newItem
        }
        store.saveQuote(copy)
        baseline = copy
        withMotion { draft = copy }
        hasAutosaved = true
        Haptics.success()
        toasts.show("Duplicated as \(copy.number)", symbol: "plus.square.on.square")
    }
}

/// Clean, read-only document layout for checking a quote before sending.
private struct QuotePreviewSheet: View {
    let quote: Quote
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var customer: Customer? { store.customer(quote.customerID) }
    private var property: Property? { store.property(quote.propertyID) }

    private var plainText: String {
        var footer: [String] = []
        if let expires = quote.expiresAt { footer.append("Valid until \(Fmt.shortDate(expires))") }
        footer.append("Optional items are not included in the total.")
        return BizPlainText.document(
            heading: "Quote \(quote.number)\(quote.title.isEmpty ? "" : " · \(quote.title)")",
            company: quote.division.companyName,
            billTo: customer?.name ?? "Customer not chosen",
            property: property.map { "\($0.name), \($0.address)" },
            items: quote.lineItems,
            totals: quote.totals,
            footer: footer)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(quote.division.companyName)
                            .font(.title3.weight(.bold))
                        Text("Quote \(quote.number) · \(Fmt.shortDate(quote.sentAt ?? store.now))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Prepared for").captionStyle()
                        Text(customer?.name ?? "Customer not chosen")
                            .font(.headline)
                        if let contact = customer?.primaryContact {
                            Text(contact.name).font(.subheadline).foregroundStyle(Palette.ink2)
                        }
                        if let property {
                            Text("\(property.name) · \(property.address)")
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink2)
                        }
                    }
                    if !quote.title.isEmpty {
                        Text(quote.title).font(.title3.weight(.semibold))
                    }
                    VStack(spacing: 0) {
                        ForEach(quote.lineItems) { item in
                            BizLineItemRow(item: item)
                                .padding(.vertical, Space.xs)
                            Divider()
                        }
                    }
                    VStack(spacing: Space.s) {
                        totalRow("Subtotal", quote.totals.subtotal)
                        totalRow(Tax.label, quote.totals.tax)
                        totalRow("Total", quote.totals.total, emphasized: true)
                    }
                    Text("Optional items are shown for reference and not included in the total.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                .padding(Space.xl)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(Space.l)
            }
            .screenBackground()
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: plainText, subject: Text("Quote \(quote.number)")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share quote as text")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func totalRow(_ label: String, _ value: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Fmt.money(value)).numeric()
        }
        .font(emphasized ? .headline : .body)
        .foregroundStyle(emphasized ? Palette.ink : Palette.ink2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Quote builder · draft") {
    QuoteBuilderView(quote: Quote(id: "preview", number: "Q-299", customerID: Fixtures.ID.riverwoodCorp, propertyID: Fixtures.ID.riverwood, title: "Snow & ice season", division: .lawnCare, status: .draft, lineItems: [
        LineItem(id: "l1", title: "Seasonal plowing", detail: "Nov 15 – Apr 15", unitPrice: 9600, unit: "season"),
        LineItem(id: "l2", title: "Bulk salt application", quantity: 20, unitPrice: 70, unit: "visit")
    ]))
    .previewEnvironment()
}

#Preview("Quote builder · sent") {
    QuoteBuilderView(quote: Quote(id: "preview-sent", number: "Q-300", customerID: Fixtures.ID.northwest, propertyID: Fixtures.ID.islington, title: "Spring aeration", division: .lawnCare, status: .viewed, sentAt: Date(), lineItems: [
        LineItem(id: "l1", title: "Aeration", unitPrice: 650)
    ]))
    .previewEnvironment()
}
