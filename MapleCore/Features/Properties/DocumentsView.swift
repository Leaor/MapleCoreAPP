import SwiftUI
import MapleCoreKit

/// Property documents: featured agreement plus all documents. Fixture documents carry metadata only,
/// so previews say so instead of pretending to open a file.
struct DocumentsView: View {
    let propertyID: Property.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let property = store.property(propertyID) {
            DocumentsContent(property: property)
        } else {
            MissingRecordView()
        }
    }
}

private struct DocumentsContent: View {
    let property: Property

    @Environment(AppStore.self) private var store
    @Environment(\.isRolePreview) private var isRolePreview

    @State private var previewing: PropertyDocument?
    @State private var openQuote: Quote?

    private var documents: [PropertyDocument] { store.documents(for: property.id) }
    private var canFinance: Bool { store.capabilities.contains(.finance) && !isRolePreview }

    var body: some View {
        let docs = documents
        let featured = docs.first { $0.isFeatured }
        let others = docs.filter { $0.id != featured?.id }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                if docs.isEmpty {
                    EmptyStateView(symbol: "doc.on.doc", title: "No documents yet", message: "Agreements, quotes and visit reports for this property appear here.")
                } else {
                    if let featured { featuredCard(featured) }
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionHeader("All documents")
                            CardList(data: others, inset: 52) { doc in
                                row(doc)
                            }
                        }
                    }
                    Text("Document files sync in Phase 2. This build shows document details only.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.horizontal, Space.xs)
                }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $previewing) { doc in
            PropertyDocumentInfoSheet(document: doc, propertyName: property.name)
        }
        .fullScreenCover(item: $openQuote) { quote in
            QuoteBuilderView(quote: quote)
        }
    }

    // MARK: Featured

    private func featuredCard(_ doc: PropertyDocument) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                PropertyDocumentBadge(kind: doc.kind)
                Spacer(minLength: Space.s)
                if let tag = doc.tag {
                    Pill(text: tag, tone: tag.localizedCaseInsensitiveContains("signed") ? .green : .neutral, symbol: tag.localizedCaseInsensitiveContains("signed") ? "checkmark.seal.fill" : nil)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(doc.detail).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.s) {
                Button {
                    previewing = doc
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(.mc(.secondary, compact: true))
                .accessibilityHint("Shows document details. The file itself syncs in a later release.")

                ShareLink(item: propertyDocumentShareText(doc, propertyName: property.name)) {
                    Label("Share Details", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.mc(.secondary, compact: true))
            }
        }
        .cardStyle(padding: Space.l)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ doc: PropertyDocument) -> some View {
        switch doc.kind {
        case .quote:
            if canFinance, let quote = store.quote(doc.quoteID) {
                Button { openQuote = quote } label: { rowLabel(doc, chevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens quote \(quote.number)")
            } else if canFinance {
                NavigationLink(value: AppDestination.quotes) { rowLabel(doc, chevron: true) }
                    .buttonStyle(.plain)
            } else {
                rowLabel(doc, chevron: false, note: "Quotes are available to office staff")
            }
        case .report:
            if let destination = reportDestination(doc) {
                NavigationLink(value: destination) { rowLabel(doc, chevron: true) }
                    .buttonStyle(.plain)
            } else {
                rowLabel(doc, chevron: false, note: "Visit not on this iPhone")
            }
        case .pdf:
            Button { previewing = doc } label: { rowLabel(doc, chevron: true) }
                .buttonStyle(.plain)
                .accessibilityHint("Shows document details")
        }
    }

    private func reportDestination(_ doc: PropertyDocument) -> AppDestination? {
        guard let id = doc.visitID, let visit = store.visit(id) else { return nil }
        if visit.review == .awaiting && store.capabilities.contains(.visitReview) { return .review(id) }
        return .photoCompare(id)
    }

    private func rowLabel(_ doc: PropertyDocument, chevron: Bool, note: String? = nil) -> some View {
        HStack(spacing: Space.m) {
            PropertyDocumentBadge(kind: doc.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(note ?? doc.detail).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if let tag = doc.tag {
                Pill(text: tag, tone: tone(for: tag))
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func tone(for tag: String) -> Tone {
        let t = tag.lowercased()
        if t.contains("signed") || t.contains("approved") { return .green }
        if t.contains("awaiting") { return .blue }
        if t.contains("renew") || t.contains("expir") { return .amber }
        return .neutral
    }
}

#Preview("Documents") {
    NavigationStack {
        DocumentsView(propertyID: Fixtures.ID.islington)
            .appDestinations()
    }
    .previewEnvironment()
}
