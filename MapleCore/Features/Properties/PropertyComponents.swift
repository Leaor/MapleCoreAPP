import SwiftUI
import MapleCoreKit

// Shared building blocks for the Properties feature. Prefixed to avoid clashing with other features.

/// Status badge for a timeline entry: colour + icon + text.
struct PropertyTimelineBadge: Hashable {
    var text: String
    var tone: Tone
    var symbol: String
}

extension VisitRecord {
    var propertyTimelineBadge: PropertyTimelineBadge {
        switch kind {
        case .visit:
            switch review {
            case .approved: return PropertyTimelineBadge(text: "Reviewed", tone: .green, symbol: "checkmark.seal.fill")
            case .awaiting: return PropertyTimelineBadge(text: "Awaiting review", tone: .amber, symbol: "clock")
            case .changesRequested: return PropertyTimelineBadge(text: "Changes requested", tone: .red, symbol: "arrow.uturn.backward")
            }
        case .issue:
            if let resolvedAt {
                return PropertyTimelineBadge(text: "Resolved \(Fmt.shortDate(resolvedAt))", tone: .green, symbol: "checkmark.circle.fill")
            }
            return PropertyTimelineBadge(text: "Open", tone: .amber, symbol: "exclamationmark.triangle.fill")
        case .note:
            return PropertyTimelineBadge(text: "Internal", tone: .amber, symbol: "lock.fill")
        case .skipped:
            return PropertyTimelineBadge(text: "Skipped", tone: .neutral, symbol: "forward.end.fill")
        }
    }

    /// "Fall cleanup · 42 min" for visits, otherwise the title.
    var propertyTimelineTitle: String {
        if kind == .visit && workMinutes > 0 { return "\(title) · \(Fmt.duration(minutes: workMinutes))" }
        return title
    }

    var propertyTimelineSymbol: String {
        switch kind {
        case .visit: "leaf.fill"
        case .issue: "exclamationmark.triangle.fill"
        case .note: "note.text"
        case .skipped: "forward.end.fill"
        }
    }

    var propertyTimelineTone: Tone {
        switch kind {
        case .visit: review == .awaiting ? .amber : .green
        case .issue: resolvedAt == nil ? .amber : .neutral
        case .note: .neutral
        case .skipped: .neutral
        }
    }
}

/// One tile in the property quick-action grid.
struct PropertyQuickActionLabel: View {
    var title: String
    var symbol: String
    var note: String? = nil
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: Space.xs + 2) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.white : Palette.ink)
                .frame(width: 48, height: 48)
                .background(isPrimary ? Palette.red : Palette.surface2, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Hit.min)
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Section caption with optional "Admin" badge and trailing link content.
struct PropertySectionHeader<Trailing: View>: View {
    var title: String
    var adminBadge = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title)
                .captionStyle()
                .accessibilityAddTraits(.isHeader)
            if adminBadge {
                Pill(text: "Admin", tone: .neutral, symbol: "lock.fill")
                    .accessibilityLabel("Admin only")
            }
            Spacer(minLength: Space.s)
            trailing
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.redText)
        }
        .padding(.horizontal, Space.xs)
    }
}

/// Wrapping layout for chips (equipment, services). Lines break when the next chip doesn't fit.
struct PropertyFlowLayout: Layout {
    var spacing: CGFloat = Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = measured(subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = measured(subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func measured(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

/// Static chip (equipment).
struct PropertyChip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
    }
}

/// Toggle chip used for services in Add Property.
struct PropertyToggleChip: View {
    var text: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isOn {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text(text)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? Palette.redText : Palette.ink)
            .background(isOn ? Palette.redSoft : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Palette.separator, lineWidth: 1))
            .frame(minHeight: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Small document kind badge: PDF / QTE / RPT.
struct PropertyDocumentBadge: View {
    var kind: DocumentKind

    var body: some View {
        Text(kind.badge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tone.foreground)
            .frame(width: 40, height: 40)
            .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private var tone: Tone {
        switch kind {
        case .pdf: .red
        case .quote: .blue
        case .report: .green
        }
    }
}

/// A sheet with one multiline text field: used for Note and Issue.
struct PropertyTextEntrySheet: View {
    var title: String
    var prompt: String
    var footnote: String
    var actionTitle: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(prompt, text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                } footer: {
                    Text(store.isReadOnly ? "Preview only — changes aren't saved in Field Mode preview." : footnote)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trimmed.isEmpty { dismiss() } else { confirmDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        onSave(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmed.isEmpty || store.isReadOnly)
                }
            }
            .confirmationDialog("Discard this text?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!trimmed.isEmpty)
    }
}

/// Honest preview sheet for documents: fixture documents carry metadata only.
struct PropertyDocumentInfoSheet: View {
    var document: PropertyDocument
    var propertyName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
                    PropertyDocumentBadge(kind: document.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title).font(.headline)
                        Text(document.detail).font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                }
                NoticeCard(symbol: "doc.badge.clock",
                           text: "Document files sync in Phase 2 — this preview build has metadata only. The file isn't stored on this iPhone yet.",
                           tone: .blue)
                VStack(spacing: 0) {
                    KeyValueRow(label: "Property", value: propertyName)
                    Divider()
                    KeyValueRow(label: "Type", value: document.kind.badge)
                    if let tag = document.tag {
                        Divider()
                        KeyValueRow(label: "Status", value: tag)
                    }
                }
                .cardStyle(padding: Space.l)
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .screenBackground()
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Text summary used by Share buttons for documents (no file exists in this build).
func propertyDocumentShareText(_ document: PropertyDocument, propertyName: String) -> String {
    var lines = [document.title, document.detail, propertyName]
    if let tag = document.tag { lines.append("Status: \(tag)") }
    lines.append("Shared from MapleCore · document file not attached")
    return lines.joined(separator: "\n")
}
