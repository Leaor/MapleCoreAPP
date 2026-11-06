import SwiftUI
import MapleCoreKit

/// Invoices list: outstanding and overdue totals, status segments, rows to detail.
struct InvoicesView: View {
    var body: some View {
        BizCapabilityGate(capability: .finance, title: "Invoices aren't available", message: "Billing is visible to owners and managers. Ask an admin if you need access.") {
            InvoicesContent()
        }
        .navigationTitle("Invoices")
    }
}

private struct InvoicesContent: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @State private var filter: InvoiceFilter = .all
    @State private var showsNewInvoice = false

    private var filtered: [Invoice] {
        let now = store.now
        return store.invoices.filter { filter.includes($0, now: now) }.sorted { lhs, rhs in
            let lo = lhs.isOverdue(asOf: now), ro = rhs.isOverdue(asOf: now)
            if lo != ro { return lo }
            if lhs.isPaid != rhs.isPaid { return !lhs.isPaid }
            return lhs.issuedAt > rhs.issuedAt
        }
    }

    var body: some View {
        let invoices = filtered
        let outstanding = store.outstandingInvoices
        let overdue = store.overdueInvoices
        List {
            Section {
                BizSummaryRow {
                    BizSummaryTile(value: Fmt.money(balance(of: outstanding)), caption: "Outstanding · \(outstanding.count)")
                } second: {
                    BizSummaryTile(value: Fmt.money(balance(of: overdue)), caption: "Overdue · \(overdue.count)", tone: overdue.isEmpty ? nil : .red)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Picker("Invoice status", selection: $filter) {
                    ForEach(InvoiceFilter.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .sensoryFeedback(.selection, trigger: filter)
            }
            .listSectionSeparator(.hidden)

            Section {
                if invoices.isEmpty {
                    EmptyStateView(symbol: "doc.text.magnifyingglass", title: emptyTitle, message: "Invoices appear here once they're created from reviewed visits or by hand.")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(invoices) { invoice in
                        NavigationLink(value: AppDestination.invoice(invoice.id)) {
                            InvoiceRow(invoice: invoice)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .motionAnimation(value: invoices.map(\.id))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNewInvoice = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New invoice")
                .disabled(store.isReadOnly)
            }
        }
        .sheet(isPresented: $showsNewInvoice) {
            BizNewInvoiceSheet { id in
                model.push(.invoice(id))
            }
        }
    }

    private func balance(of invoices: [Invoice]) -> Decimal {
        invoices.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No invoices yet"
        case .unpaid: "Nothing unpaid"
        case .overdue: "Nothing overdue"
        case .paid: "No paid invoices"
        }
    }
}

/// Bill-to, number · title, amount and status.
private struct InvoiceRow: View {
    @Environment(AppStore.self) private var store
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(invoice.billToName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                Text(Fmt.money(invoice.isPaid ? invoice.totals.total : invoice.balance))
                    .font(.body.weight(.semibold))
                    .numeric()
                    .foregroundStyle(Palette.ink)
            }
            Text(secondLine)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            BizInvoiceStatusPill(invoice: invoice, now: store.now)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var secondLine: String {
        if invoice.isOverdue(asOf: store.now) {
            return "\(invoice.number) · due \(Fmt.shortDate(invoice.dueDate))"
        }
        let subject = invoice.title.isEmpty ? (store.property(invoice.propertyID)?.name ?? "") : invoice.title
        return subject.isEmpty ? invoice.number : "\(invoice.number) · \(subject)"
    }
}

/// Overdue N days (red) · Due date · Viewed (blue) · Paid date (green).
struct BizInvoiceStatusPill: View {
    let invoice: Invoice
    let now: Date

    var body: some View {
        if invoice.isPaid {
            Pill(text: "Paid \(invoice.paidAt.map(Fmt.shortDate) ?? "")", tone: .green, symbol: "checkmark.circle.fill")
        } else if invoice.isOverdue(asOf: now) {
            Pill(text: "Overdue \(Fmt.plural(invoice.daysOverdue(asOf: now), "day"))", tone: .red, symbol: "exclamationmark.circle.fill")
        } else if invoice.status == .viewed {
            Pill(text: "Viewed · due \(Fmt.shortDate(invoice.dueDate))", tone: .blue, symbol: "eye")
        } else {
            Pill(text: "Due \(Fmt.shortDate(invoice.dueDate))", tone: .neutral, symbol: "clock")
        }
    }
}

/// Simple new invoice: customer, property, line items, due in N days.
struct BizNewInvoiceSheet: View {
    var onCreate: (Invoice.ID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var customerID: Customer.ID?
    @State private var propertyID: Property.ID?
    @State private var title = ""
    @State private var items: [LineItem] = []
    @State private var dueInDays = 30
    @State private var editingItem: LineItem?

    private var canCreate: Bool { customerID != nil && !items.isEmpty && !store.isReadOnly }
    private var hasEdits: Bool { customerID != nil || !items.isEmpty || !title.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Customer", selection: customerBinding) {
                        Text("Choose…").tag(Customer.ID?.none)
                        ForEach(store.customers.sorted { $0.name < $1.name }) { customer in
                            Text(customer.name).tag(Customer.ID?.some(customer.id))
                        }
                    }
                    Picker("Property", selection: $propertyID) {
                        Text("None").tag(Property.ID?.none)
                        ForEach(customerID.map { store.properties(of: $0) } ?? []) { property in
                            Text(property.name).tag(Property.ID?.some(property.id))
                        }
                    }
                    .disabled(customerID == nil)
                    TextField("Title, e.g. October service", text: $title)
                }
                BizLineItemsSection(items: $items, editing: $editingItem, isEditable: true)
                BizTotalsSection(totals: Totals(items: items))
                Section {
                    Picker("Due in", selection: $dueInDays) {
                        ForEach([7, 15, 30, 45, 60], id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                } footer: {
                    Text(store.isOnline ? "The invoice is created and queued to send to the customer." : "You're offline. The invoice is saved on this iPhone and sends automatically.")
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            .bizLineItemEditor(editing: $editingItem, items: $items)
        }
        .interactiveDismissDisabled(hasEdits)
    }

    private var customerBinding: Binding<Customer.ID?> {
        Binding(get: { customerID }, set: { newValue in
            customerID = newValue
            let options = newValue.map { store.properties(of: $0) } ?? []
            if let propertyID, !options.contains(where: { $0.id == propertyID }) { self.propertyID = nil }
            if propertyID == nil, options.count == 1 { propertyID = options[0].id }
        })
    }

    private func create() {
        guard let customerID else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let id = store.createInvoice(customerID: customerID, propertyID: propertyID, title: trimmed, items: items, dueInDays: dueInDays) else {
            toasts.show("Couldn't create the invoice", symbol: "exclamationmark.triangle.fill", tone: .amber)
            return
        }
        Haptics.success()
        toasts.show(store.isOnline ? "Invoice created · queued to send" : "Saved on this iPhone · sends automatically")
        dismiss()
        onCreate(id)
    }
}

#Preview("Invoices") {
    NavigationStack {
        InvoicesView().appDestinations()
    }
    .previewEnvironment()
}

#Preview("New invoice") {
    BizNewInvoiceSheet { _ in }
        .previewEnvironment()
}
