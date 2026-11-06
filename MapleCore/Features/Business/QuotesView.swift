import SwiftUI
import MapleCoreKit

/// Quotes list: totals awaiting approval, status segments, rows that open the builder.
struct QuotesView: View {
    var body: some View {
        BizCapabilityGate(capability: .finance, title: "Quotes aren't available", message: "Quotes and pricing are visible to owners and managers. Ask an admin if you need access.") {
            QuotesContent()
        }
        .navigationTitle("Quotes")
    }
}

private struct QuotesContent: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var filter: QuoteFilter = .open
    @State private var editing: Quote?
    @State private var pendingDelete: Quote?

    private var filtered: [Quote] {
        store.quotes.filter { filter.includes($0) }.sorted { lhs, rhs in
            (lhs.sentAt ?? lhs.updatedAt) > (rhs.sentAt ?? rhs.updatedAt)
        }
    }

    var body: some View {
        let quotes = filtered
        let open = store.quotes.filter { $0.status.isOpen }
        let approved = store.bizQuotesApprovedThisMonth
        List {
            Section {
                BizSummaryRow {
                    BizSummaryTile(value: Fmt.moneyWhole(store.bizTotal(of: open)), caption: "\(open.count) awaiting approval")
                } second: {
                    BizSummaryTile(value: Fmt.moneyWhole(store.bizTotal(of: approved)), caption: "Approved in \(monthName)", tone: approved.isEmpty ? nil : .green)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Picker("Quote status", selection: $filter) {
                    ForEach(QuoteFilter.allCases, id: \.self) { option in
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
                if quotes.isEmpty {
                    EmptyStateView(symbol: "doc.text", title: emptyTitle, message: emptyMessage) {
                        if filter == .open || filter == .drafts {
                            Button("New Quote") { editing = store.newQuoteDraft() }
                                .buttonStyle(.mc(.ink, compact: true))
                                .frame(maxWidth: 240)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(quotes) { quote in
                        Button {
                            editing = quote
                        } label: {
                            QuoteRow(quote: quote)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if quote.status == .draft {
                                Button(role: .destructive) {
                                    pendingDelete = quote
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .motionAnimation(value: quotes.map(\.id))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = store.newQuoteDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New quote")
                .disabled(store.isReadOnly)
            }
        }
        .fullScreenCover(item: $editing) { quote in
            QuoteBuilderView(quote: quote)
        }
        .confirmationDialog("Delete draft \(pendingDelete?.number ?? "")?", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { quote in
            Button("Delete Draft", role: .destructive) {
                withMotion { store.deleteQuote(quote.id) }
                toasts.show("Draft \(quote.number) deleted", symbol: "trash", tone: .neutral)
            }
        } message: { _ in
            Text("The draft is removed from this iPhone. Sent quotes are never deleted.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var monthName: String {
        store.now.formatted(.dateTime.month(.wide).locale(Fmt.locale))
    }

    private var emptyTitle: String {
        switch filter {
        case .open: "No quotes awaiting approval"
        case .approved: "No approved quotes"
        case .declined: "No declined quotes"
        case .drafts: "No drafts"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .open: "Quotes you send appear here until the customer approves or declines."
        case .approved: "Approved quotes appear here."
        case .declined: "Declined quotes appear here so you can follow up next season."
        case .drafts: "Drafts autosave on this iPhone while you build them."
        }
    }
}

/// One quote row: property, total, number · title, status and follow-up line.
private struct QuoteRow: View {
    @Environment(AppStore.self) private var store
    let quote: Quote

    var body: some View {
        let info = secondaryInfo
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(headline)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.s)
                Text(Fmt.money(quote.totals.total))
                    .font(.body.weight(.semibold))
                    .numeric()
                    .foregroundStyle(Palette.ink)
            }
            Text("\(quote.number) · \(quote.title.isEmpty ? "Untitled quote" : quote.title)")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    statusPill
                    if let info { Text(info.text).font(.footnote).foregroundStyle(info.tone.foreground) }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    statusPill
                    if let info { Text(info.text).font(.footnote).foregroundStyle(info.tone.foreground) }
                }
            }
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(quote.status == .draft ? "Opens the quote builder" : "Opens the quote")
    }

    private var headline: String {
        store.property(quote.propertyID)?.name ?? store.customer(quote.customerID)?.name ?? "No customer yet"
    }

    private var statusPill: some View {
        switch quote.status {
        case .draft: Pill(text: "Draft", tone: .neutral, symbol: "pencil")
        case .sent: Pill(text: quote.status.label, tone: .amber, symbol: "envelope")
        case .viewed: Pill(text: quote.status.label, tone: .blue, symbol: "eye")
        case .approved: Pill(text: "Approved", tone: .green, symbol: "checkmark")
        case .declined: Pill(text: "Declined", tone: .red, symbol: "xmark")
        }
    }

    private var secondaryInfo: (text: String, tone: Tone)? {
        let now = store.now
        switch quote.status {
        case .draft:
            return (quote.division == .construction ? quote.division.companyName : "Edited \(Fmt.ago(quote.updatedAt, now: now))", .neutral)
        case .sent, .viewed:
            if let expires = quote.expiresAt, store.bizDays(from: now, to: expires) <= 7 {
                return ("Expires \(Fmt.shortDate(expires))", .amber)
            }
            if quote.status == .sent, let sent = quote.sentAt, store.bizDays(from: sent, to: now) >= 5 {
                return ("Follow up", .red)
            }
            if let sent = quote.sentAt {
                let days = store.bizDays(from: sent, to: now)
                return (days == 0 ? "Sent today" : "Sent \(Fmt.plural(days, "day")) ago", .neutral)
            }
            return nil
        case .approved:
            guard let approvedAt = quote.approvedAt else { return nil }
            return ("Approved \(Fmt.shortDate(approvedAt))", Tone.green)
        case .declined:
            guard let sentAt = quote.sentAt else { return nil }
            return ("Sent \(Fmt.shortDate(sentAt))", Tone.neutral)
        }
    }
}

#Preview("Quotes") {
    NavigationStack {
        QuotesView().appDestinations()
    }
    .previewEnvironment()
}
