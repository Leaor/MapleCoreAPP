import SwiftUI
import MapleCoreKit

/// Shows `content` only when the signed-in role has `capability`; otherwise explains why not.
struct BizCapabilityGate<Content: View>: View {
    var capability: Capabilities
    var title: String
    var message: String
    @ViewBuilder var content: Content

    @Environment(AppStore.self) private var store

    var body: some View {
        if store.capabilities.contains(capability) {
            content
        } else {
            EmptyStateView(symbol: "lock", title: title, message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
        }
    }
}

/// Big figure + caption tile ("$7,271.50 · Outstanding · 3").
struct BizSummaryTile: View {
    var value: String
    var caption: String
    var tone: Tone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .numeric()
                .foregroundStyle(tone?.foreground ?? Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// Two summary tiles side by side, stacked when they don't fit (AX sizes, iPhone SE).
struct BizSummaryRow<First: View, Second: View>: View {
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.m) {
                first
                second
            }
            VStack(spacing: Space.m) {
                first
                second
            }
        }
    }
}

// MARK: - Line items

/// Editable line items for quotes and invoices. Lives inside a `Form`/`List` so rows get
/// swipe-to-delete and drag-to-reorder. The parent attaches `.bizLineItemEditor(editing:items:)`
/// to the Form so the editor sheet is presented from outside the section.
struct BizLineItemsSection: View {
    @Binding var items: [LineItem]
    @Binding var editing: LineItem?
    var isEditable: Bool
    var footer: String? = nil

    var body: some View {
        Section {
            if items.isEmpty {
                Text(isEditable ? "No line items yet. Add the first one below." : "No line items.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            ForEach(items) { item in
                Button {
                    if isEditable { editing = item }
                } label: {
                    BizLineItemRow(item: item, showsChevron: isEditable)
                }
                .buttonStyle(.plain)
                .disabled(!isEditable)
            }
            .onDelete(perform: isEditable ? deleteItems : nil)
            .onMove(perform: isEditable ? moveItems : nil)

            if isEditable {
                Button {
                    editing = LineItem(id: UUID().uuidString, title: "", unitPrice: 0)
                } label: {
                    Label("Add Line Item", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.redText)
                        .frame(minHeight: Hit.min)
                }
            }
        } header: {
            Text("Line items")
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private func deleteItems(_ offsets: IndexSet) {
        withMotion { items.remove(atOffsets: offsets) }
    }

    private func moveItems(_ source: IndexSet, _ destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
}

extension View {
    /// Presents the line item editor for `editing`, writing the result back into `items`.
    func bizLineItemEditor(editing: Binding<LineItem?>, items: Binding<[LineItem]>) -> some View {
        sheet(item: editing) { item in
            BizLineItemEditor(item: item, isNew: !items.wrappedValue.contains { $0.id == item.id }) { updated in
                if let index = items.wrappedValue.firstIndex(where: { $0.id == updated.id }) {
                    items.wrappedValue[index] = updated
                } else {
                    withMotion { items.wrappedValue.append(updated) }
                }
            } onDelete: {
                withMotion { items.wrappedValue.removeAll { $0.id == item.id } }
            }
        }
    }
}

/// Read-only line item row: title, quantity × price, total, optional tag.
struct BizLineItemRow: View {
    let item: LineItem
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    Text(item.title.isEmpty ? "Untitled item" : item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if item.isOptional {
                        Pill(text: "Optional", tone: .neutral)
                    }
                }
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            Text(Fmt.money(item.total))
                .font(.body.weight(.semibold))
                .numeric()
                .foregroundStyle(item.isOptional ? Palette.ink3 : Palette.ink)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        let unit = item.unit.isEmpty ? "" : " / \(item.unit)"
        var text = "\(item.quantity) × \(Fmt.money(item.unitPrice))\(unit)"
        if item.isOptional { text += " · not in total" }
        if !item.detail.isEmpty { text += " · \(item.detail)" }
        return text
    }
}

/// Sheet that edits one line item. Changes apply on Done.
struct BizLineItemEditor: View {
    var isNew: Bool
    var onSave: (LineItem) -> Void
    var onDelete: () -> Void

    @State private var item: LineItem
    @State private var priceText: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(item: LineItem, isNew: Bool, onSave: @escaping (LineItem) -> Void, onDelete: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _item = State(initialValue: item)
        _priceText = State(initialValue: item.unitPrice == 0 ? "" : BizDecimal.plain(item.unitPrice))
    }

    private var parsedPrice: Decimal? { BizDecimal.parse(priceText) }
    private var isValid: Bool {
        !item.title.trimmingCharacters(in: .whitespaces).isEmpty && parsedPrice != nil && item.quantity > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Title", text: $item.title)
                    TextField("Detail (optional)", text: $item.detail, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    Stepper(value: $item.quantity, in: 1...999) {
                        LabeledContent("Quantity", value: "\(item.quantity)")
                    }
                    .accessibilityValue("\(item.quantity)")
                    HStack {
                        Text("Unit price")
                        Spacer()
                        Text("$").foregroundStyle(Palette.ink2)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .accessibilityLabel("Unit price in dollars")
                    }
                    TextField("Unit (visit, season, h)", text: $item.unit)
                    Toggle("Optional", isOn: $item.isOptional)
                } header: {
                    Text("Price")
                } footer: {
                    Text(item.isOptional ? "Optional items are shown to the customer but not included in the total." : "Line total \(Fmt.money((parsedPrice ?? 0) * Decimal(item.quantity)))")
                }
                if !isNew {
                    Section {
                        Button("Delete Line Item", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Line Item" : "Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = item
                        updated.title = updated.title.trimmingCharacters(in: .whitespaces)
                        updated.unitPrice = parsedPrice ?? 0
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this line item?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Line Item", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isNew ? !item.title.isEmpty : false)
    }
}

/// Totals block: Subtotal, HST 13%, Total.
struct BizTotalsSection: View {
    var totals: Totals

    var body: some View {
        Section {
            LabeledContent("Subtotal", value: Fmt.money(totals.subtotal))
            LabeledContent(Tax.label, value: Fmt.money(totals.tax))
            LabeledContent {
                Text(Fmt.money(totals.total)).font(.headline).numeric()
            } label: {
                Text("Total").font(.headline)
            }
        }
    }
}

/// Decimal helpers for money text fields.
enum BizDecimal {
    /// Parses "1,234.50" or "70" into a Decimal (nil when not a number or negative).
    /// Accepts the device's decimal separator too ("12,50" on a French keyboard), since `.decimalPad`
    /// types the current locale's separator.
    static func parse(_ text: String) -> Decimal? {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        var cleaned = text.replacingOccurrences(of: "$", with: "")
            .filter { !$0.isWhitespace }
        if decimalSeparator == "," {
            // "1.234,50" or "12,50" → "1234.50". Without a comma, "." is the decimal point ("70.00" prefill).
            if cleaned.contains(",") {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            }
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value.rounded(scale: 2)
    }

    /// "70.00" without currency symbol or grouping, for prefilling fields.
    static func plain(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value.rounded(scale: 2))
        return String(format: "%.2f", number.doubleValue)
    }
}

/// Plain-text rendering of a quote or invoice, for ShareLink.
enum BizPlainText {
    static func document(heading: String, company: String, billTo: String, property: String?, items: [LineItem], totals: Totals, footer: [String]) -> String {
        var lines: [String] = [company, heading, "", "Bill to: \(billTo)"]
        if let property { lines.append("Property: \(property)") }
        lines.append("")
        for item in items {
            let unit = item.unit.isEmpty ? "" : " / \(item.unit)"
            lines.append("\(item.title) — \(item.quantity) × \(Fmt.money(item.unitPrice))\(unit) = \(Fmt.money(item.total))\(item.isOptional ? " (optional, not in total)" : "")")
            if !item.detail.isEmpty { lines.append("  \(item.detail)") }
        }
        lines.append("")
        lines.append("Subtotal: \(Fmt.money(totals.subtotal))")
        lines.append("\(Tax.label): \(Fmt.money(totals.tax))")
        lines.append("Total: \(Fmt.money(totals.total))")
        if !footer.isEmpty {
            lines.append("")
            lines.append(contentsOf: footer)
        }
        return lines.joined(separator: "\n")
    }
}
