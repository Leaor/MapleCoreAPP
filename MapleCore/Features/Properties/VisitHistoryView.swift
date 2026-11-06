import SwiftUI
import MapleCoreKit

enum VisitHistoryFilter: String, CaseIterable, Hashable {
    case all, visits, issues, notes

    var label: String { rawValue.capitalized }

    func includes(_ record: VisitRecord) -> Bool {
        switch self {
        case .all: true
        case .visits: record.kind == .visit || record.kind == .skipped
        case .issues: record.kind == .issue
        case .notes: record.kind == .note
        }
    }
}

/// Property timeline grouped by month: visits, issues, notes and skipped visits.
struct VisitHistoryView: View {
    let propertyID: Property.ID
    @Environment(AppStore.self) private var store
    @State private var filter: VisitHistoryFilter = .all

    private struct MonthGroup: Identifiable {
        var id: Date
        var title: String
        var records: [VisitRecord]
    }

    private var groups: [MonthGroup] {
        let cal = Calendar.current
        let records = store.history(for: propertyID).filter { filter.includes($0) }
        var order: [Date] = []
        var buckets: [Date: [VisitRecord]] = [:]
        for record in records {
            let month = cal.dateInterval(of: .month, for: record.date)?.start ?? record.date
            if buckets[month] == nil { order.append(month) }
            buckets[month, default: []].append(record)
        }
        return order.map { MonthGroup(id: $0, title: Fmt.monthYear($0), records: buckets[$0] ?? []) }
    }

    var body: some View {
        if let property = store.property(propertyID) {
            content(property)
        } else {
            MissingRecordView()
        }
    }

    private func content(_ property: Property) -> some View {
        let groups = self.groups
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.l, pinnedViews: []) {
                FilterChips(options: VisitHistoryFilter.allCases, selection: $filter, label: { $0.label }, count: { option in
                    option == .all ? nil : store.history(for: propertyID).filter { option.includes($0) }.count
                })
                .padding(.horizontal, -Space.l)

                if groups.isEmpty {
                    EmptyStateView(symbol: "clock.arrow.circlepath", title: "Nothing here yet", message: emptyMessage)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionHeader(group.title)
                            VStack(spacing: 0) {
                                ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                    VisitHistoryEntry(record: record)
                                    if index < group.records.count - 1 {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                            .padding(.horizontal, Space.l)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                    }
                }
            }
            .padding(Space.l)
            .motionAnimation(value: filter)
        }
        .screenBackground()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("History").font(.headline)
                    Text(property.name).font(.caption).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: "Visits, issues and notes for this property will appear here."
        case .visits: "No visits recorded yet."
        case .issues: "No issues have been reported here."
        case .notes: "No internal notes yet."
        }
    }
}

private struct VisitHistoryEntry: View {
    let record: VisitRecord
    @Environment(AppStore.self) private var store

    var body: some View {
        if let destination {
            NavigationLink(value: destination) {
                row(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
        } else {
            row(showsChevron: false)
        }
    }

    /// Visits open the review when awaiting and the user can review; otherwise the photo compare.
    private var destination: AppDestination? {
        guard record.kind == .visit else { return nil }
        if record.review == .awaiting && store.capabilities.contains(.visitReview) { return .review(record.id) }
        return record.photos.isEmpty ? nil : .photoCompare(record.id)
    }

    private var hint: String {
        if case .some(.review(_)) = destination { return "Opens the review" }
        return "Opens before and after photos"
    }

    private func row(showsChevron: Bool) -> some View {
        let badge = record.propertyTimelineBadge
        return HStack(alignment: .top, spacing: Space.m) {
            VStack(spacing: 0) {
                Text(PropertyFormat.dayNumber(record.date))
                    .font(.title3.weight(.semibold))
                    .numeric()
                    .foregroundStyle(Palette.ink)
                Text(Fmt.weekdayShort(record.date))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
            .frame(minWidth: 40)
            VStack(alignment: .leading, spacing: Space.xs) {
                PropertyFlowLayout(spacing: 6) {
                    Text(record.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Pill(text: badge.text, tone: badge.tone, symbol: badge.symbol)
                }
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !record.photos.isEmpty {
                    Label(Fmt.plural(record.photos.count, "photo"), systemImage: "photo.on.rectangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        switch record.kind {
        case .visit:
            var parts: [String] = []
            if let crew = store.crew(record.crewID) { parts.append(crew.name) }
            if let start = record.arrivedAt ?? record.workStart, let end = record.workEnd {
                parts.append("\(Fmt.clock(start))–\(Fmt.time(end))")
            }
            if record.workMinutes > 0 { parts.append(Fmt.duration(minutes: record.workMinutes)) }
            if let by = record.reviewedBy { parts.append("reviewed by \(by)") }
            return parts.isEmpty ? record.detail : parts.joined(separator: " · ")
        default:
            return record.detail.isEmpty ? "—" : record.detail
        }
    }
}

#Preview("Visit history") {
    NavigationStack {
        VisitHistoryView(propertyID: Fixtures.ID.islington)
            .appDestinations()
    }
    .previewEnvironment()
}
