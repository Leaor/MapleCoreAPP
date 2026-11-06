import SwiftUI
import MapleCoreKit

/// One invoice: amount, timeline, line items, proof of work, reminders and payments.
struct InvoiceDetailView: View {
    let invoiceID: Invoice.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        BizCapabilityGate(capability: .finance, title: "Invoice not available", message: "Billing is visible to owners and managers.") {
            if let invoice = store.invoice(invoiceID) {
                InvoiceDetailContent(invoice: invoice)
            } else {
                MissingRecordView(title: "Invoice not available")
            }
        }
    }
}

private struct InvoiceDetailContent: View {
    let invoice: Invoice
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var showsPayment = false
    @State private var reminderCount = 0

    private var company: String { store.account?.company ?? Division.lawnCare.companyName }

    private var plainText: String {
        var footer = ["Invoice date: \(Fmt.shortDate(invoice.issuedAt))", "Due: \(Fmt.shortDate(invoice.dueDate))", "Payment: \(invoice.paymentTerms)"]
        if invoice.amountPaid > 0 { footer.append("Paid: \(Fmt.money(invoice.amountPaid)) · Balance: \(Fmt.money(invoice.balance))") }
        return BizPlainText.document(
            heading: "Invoice \(invoice.number)\(invoice.title.isEmpty ? "" : " · \(invoice.title)")",
            company: company,
            billTo: invoice.billToName,
            property: store.property(invoice.propertyID).map { "\($0.name), \($0.address)" },
            items: invoice.lineItems,
            totals: invoice.totals,
            footer: footer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                timeline
                itemsCard
                proofAndTerms
                if !invoice.payments.isEmpty { paymentsCard }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !invoice.isPaid && !store.isReadOnly {
                BottomActionBar {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Space.m) { actionButtons }
                        VStack(spacing: Space.s) { actionButtons }
                    }
                }
            }
        }
        .navigationTitle(invoice.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: plainText, subject: Text("Invoice \(invoice.number)")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share invoice")
            }
        }
        .sheet(isPresented: $showsPayment) {
            RecordPaymentSheet(invoice: invoice)
        }
        .sensoryFeedback(.success, trigger: reminderCount)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(invoice.number) · \(company)")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            Text(Fmt.money(invoice.totals.total))
                .font(.largeTitle.weight(.bold))
                .numeric()
                .foregroundStyle(Palette.ink)
            if invoice.amountPaid > 0 && !invoice.isPaid {
                Text("Balance \(Fmt.money(invoice.balance)) · \(Fmt.money(invoice.amountPaid)) paid")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.amber)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { headerMeta }
                VStack(alignment: .leading, spacing: Space.xs) { headerMeta }
            }
        }
        .cardStyle(padding: Space.xl)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headerMeta: some View {
        Text(invoice.billToName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
        BizInvoiceStatusPill(invoice: invoice, now: store.now)
    }

    private var timeline: some View {
        let steps: [(String, Date?)] = [
            ("Created", invoice.issuedAt),
            ("Sent", invoice.sentAt),
            ("Viewed", invoice.viewedAt),
            ("Paid", invoice.paidAt)
        ]
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Timeline")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: Space.m) {
                        Image(systemName: step.1 == nil ? "circle" : "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(step.1 == nil ? Palette.ink3 : Palette.green)
                            .accessibilityHidden(true)
                        Text(step.0)
                            .font(.body)
                            .foregroundStyle(step.1 == nil ? Palette.ink3 : Palette.ink)
                        Spacer(minLength: Space.s)
                        Text(step.1.map { Fmt.shortDate($0) } ?? "—")
                            .font(.subheadline)
                            .numeric()
                            .foregroundStyle(Palette.ink2)
                    }
                    .frame(minHeight: Hit.min)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(step.1.map { "\(step.0) \(Fmt.shortDate($0))" } ?? "\(step.0), not yet")
                    if index < steps.count - 1 { Divider().padding(.leading, 36) }
                }
            }
            .padding(.horizontal, Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if invoice.remindersSent > 0 {
                Text("\(Fmt.plural(invoice.remindersSent, "reminder")) sent")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, Space.xs)
            }
        }
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Line items")
            VStack(spacing: 0) {
                ForEach(invoice.lineItems) { item in
                    BizLineItemRow(item: item)
                        .padding(.vertical, Space.xs)
                    Divider()
                }
                totalLine("Subtotal", invoice.totals.subtotal)
                totalLine(Tax.label, invoice.totals.tax)
                totalLine("Total", invoice.totals.total, emphasized: true)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.xs)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func totalLine(_ label: String, _ value: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Fmt.money(value)).numeric()
        }
        .font(emphasized ? .headline : .body)
        .foregroundStyle(emphasized ? Palette.ink : Palette.ink2)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private var proofAndTerms: some View {
        VStack(spacing: 0) {
            if let propertyID = invoice.propertyID, invoice.reviewedVisitCount > 0 {
                NavigationLink(value: AppDestination.visitHistory(propertyID)) {
                    HStack(spacing: Space.m) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Palette.green)
                            .accessibilityHidden(true)
                        Text("Backed by \(Fmt.plural(invoice.reviewedVisitCount, "reviewed visit report"))")
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            KeyValueRow(label: "Payment method", value: invoice.paymentTerms)
        }
        .padding(.horizontal, Space.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("Payments")
            CardList(data: invoice.payments) { payment in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.method).font(.body.weight(.semibold))
                        Text([Fmt.shortDate(payment.receivedAt), payment.reference].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                    }
                    Spacer()
                    Text(Fmt.money(payment.amount))
                        .font(.body.weight(.semibold))
                        .numeric()
                        .foregroundStyle(Palette.green)
                }
                .padding(.vertical, Space.m)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Send Reminder") { sendReminder() }
            .buttonStyle(.mc(.secondary))
        Button("Record Payment") { showsPayment = true }
            .buttonStyle(.mc(.primary))
    }

    private func sendReminder() {
        store.sendReminder(invoiceID: invoice.id)
        reminderCount += 1
        toasts.show(store.isOnline ? "Reminder queued" : "Reminder saved on this iPhone · sends automatically")
    }
}

/// Records a payment received outside the app. There is no card processor.
private struct RecordPaymentSheet: View {
    let invoice: Invoice
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var method = "e-Transfer"
    @State private var reference = ""

    private static let methods = ["e-Transfer", "Cheque", "Cash", "Card (manual)"]

    init(invoice: Invoice) {
        self.invoice = invoice
        _amountText = State(initialValue: BizDecimal.plain(invoice.balance))
    }

    private var amount: Decimal? { BizDecimal.parse(amountText) }
    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0 && amount <= invoice.balance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("$").foregroundStyle(Palette.ink2)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Amount in dollars")
                    }
                    Picker("Method", selection: $method) {
                        ForEach(Self.methods, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Reference (cheque #, e-Transfer ID)", text: $reference)
                } header: {
                    Text("\(invoice.number) · balance \(Fmt.money(invoice.balance))")
                } footer: {
                    if let amount, amount > invoice.balance {
                        Text("Amount is more than the balance of \(Fmt.money(invoice.balance)).")
                            .foregroundStyle(Palette.redText)
                    } else {
                        Text("Records money you've already received. MapleCore doesn't process payments.")
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || store.isReadOnly)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!reference.isEmpty)
    }

    private func save() {
        guard let amount, isValid else { return }
        store.recordPayment(invoiceID: invoice.id, amount: amount, method: method, reference: reference.trimmingCharacters(in: .whitespaces))
        Haptics.success()
        toasts.show("Payment of \(Fmt.money(amount)) recorded")
        dismiss()
    }
}

#Preview("Invoice detail") {
    NavigationStack {
        InvoiceDetailView(invoiceID: "inv-1048").appDestinations()
    }
    .previewEnvironment()
}
