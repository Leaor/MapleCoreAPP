import SwiftUI
import MapleCoreKit

enum PropertyGalleryFilter: String, CaseIterable, Hashable {
    case all, before, after, work, issues

    var label: String { rawValue.capitalized }
}

/// One photo in the gallery with the record it belongs to.
struct PropertyGalleryItem: Identifiable, Hashable {
    var photo: VisitPhoto
    var recordID: VisitRecord.ID
    var recordTitle: String
    var recordDate: Date
    var isIssue: Bool
    var id: String { recordID + "/" + photo.id }
}

/// Every photo at a property, grouped by visit, with a full-screen viewer.
struct PropertyGalleryView: View {
    let propertyID: Property.ID
    @Environment(AppStore.self) private var store
    @State private var filter: PropertyGalleryFilter = .all
    @State private var viewer: PropertyPhotoViewerContext?

    private struct GallerySection: Identifiable {
        var record: VisitRecord
        var items: [PropertyGalleryItem]
        var id: VisitRecord.ID { record.id }
    }

    private var photoRecords: [VisitRecord] {
        store.history(for: propertyID).filter { !$0.photos.isEmpty }
    }

    private func items(for record: VisitRecord) -> [PropertyGalleryItem] {
        let isIssue = record.kind == .issue
        let photos: [VisitPhoto]
        switch filter {
        case .all: photos = record.photos
        case .before: photos = isIssue ? [] : record.photos(.before)
        case .after: photos = isIssue ? [] : record.photos(.after)
        case .work: photos = isIssue ? [] : record.photos(.work)
        case .issues: photos = isIssue ? record.photos : []
        }
        return photos.map { PropertyGalleryItem(photo: $0, recordID: record.id, recordTitle: record.title, recordDate: record.date, isIssue: isIssue) }
    }

    private var sections: [GallerySection] {
        photoRecords.compactMap { record -> GallerySection? in
            let recordItems = self.items(for: record)
            return recordItems.isEmpty ? nil : GallerySection(record: record, items: recordItems)
        }
    }

    var body: some View {
        if let property = store.property(propertyID) {
            content(property)
        } else {
            MissingRecordView()
        }
    }

    private func content(_ property: Property) -> some View {
        let sections = self.sections
        let total = photoRecords.reduce(0) { $0 + $1.photos.count }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                FilterChips(options: PropertyGalleryFilter.allCases, selection: $filter, label: { $0.label }, count: { $0 == .all ? total : nil })
                    .padding(.horizontal, -Space.l)

                if sections.isEmpty {
                    EmptyStateView(symbol: "photo.on.rectangle.angled", title: total == 0 ? "No photos yet" : "No \(filter.label.lowercased()) photos",
                                   message: total == 0 ? "Visit photos taken by crews appear here after each visit." : "Try another filter.")
                } else {
                    let allItems = sections.flatMap(\.items)
                    ForEach(sections) { section in
                        sectionView(section, allItems: allItems)
                    }
                }
            }
            .padding(Space.l)
            .motionAnimation(value: filter)
        }
        .screenBackground()
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $viewer) { context in
            PropertyPhotoViewer(context: context, propertyName: property.name)
        }
    }

    private func sectionView(_ section: GallerySection, allItems: [PropertyGalleryItem]) -> some View {
        let record = section.record
        let canCompare = record.kind == .visit && !record.photos(.before).isEmpty && !record.photos(.after).isEmpty
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Fmt.shortDate(record.date)) · \(record.title)")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(subtitle(record))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                if canCompare {
                    NavigationLink(value: AppDestination.photoCompare(record.id)) {
                        Pill(text: "Compare", tone: .red, symbol: "rectangle.split.2x1")
                            .frame(minHeight: Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Compare before and after, \(Fmt.shortDate(record.date))")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.xs)], spacing: Space.xs) {
                ForEach(section.items) { item in
                    Button {
                        viewer = PropertyPhotoViewerContext(items: allItems, selectedID: item.id)
                    } label: {
                        tile(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens full screen")
                }
            }
        }
    }

    private func tile(_ item: PropertyGalleryItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                PhotoTile(photo: item.photo, showsKindLabel: !item.isIssue, maxPixel: 400)
            }
            .overlay(alignment: .bottomLeading) {
                if item.isIssue {
                    Text("ISSUE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Palette.amber, in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func subtitle(_ record: VisitRecord) -> String {
        var parts: [String] = []
        if record.kind == .issue {
            parts.append("Issue")
        } else if let crew = store.crew(record.crewID) {
            parts.append(crew.name)
        }
        parts.append(Fmt.plural(record.photos.count, "photo"))
        if let by = record.reviewedBy { parts.append("reviewed by \(by)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Full-screen viewer

struct PropertyPhotoViewerContext: Identifiable {
    var items: [PropertyGalleryItem]
    var selectedID: PropertyGalleryItem.ID
    let id = UUID()
}

/// Paged full-screen photo viewer. Metadata sits beside the photo, never on it.
struct PropertyPhotoViewer: View {
    let context: PropertyPhotoViewerContext
    let propertyName: String
    @State private var selection: PropertyGalleryItem.ID
    @Environment(\.dismiss) private var dismiss

    init(context: PropertyPhotoViewerContext, propertyName: String) {
        self.context = context
        self.propertyName = propertyName
        _selection = State(initialValue: context.selectedID)
    }

    private var current: PropertyGalleryItem? { context.items.first { $0.id == selection } }
    private var position: Int { (context.items.firstIndex { $0.id == selection } ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(context.items) { item in
                    page(item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("\(position) of \(context.items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let current {
                        ShareLink(item: shareText(current)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share photo details")
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func page(_ item: PropertyGalleryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                PhotoTile(photo: item.photo, cornerRadius: 0, maxPixel: 1600)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.s) {
                        Pill(text: item.isIssue ? "Issue" : item.photo.kind.label, tone: item.isIssue ? .amber : .neutral)
                        Text(item.photo.angle).font(.headline)
                    }
                    if !item.photo.caption.isEmpty {
                        Text(item.photo.caption).font(.body)
                    }
                    Text("\(Fmt.shortDate(item.recordDate)) · \(item.recordTitle) · \(propertyName)")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                    TimeStampLabel(source: item.photo.source == .imported ? .imported : .device, date: item.photo.capturedAt)
                    TimeStampLabel(source: .server, date: item.photo.receivedAt)
                }
                .padding(.horizontal, Space.l)
            }
            .padding(.bottom, Space.xxl)
        }
        .foregroundStyle(Palette.ink)
    }

    private func shareText(_ item: PropertyGalleryItem) -> String {
        var lines = ["\(propertyName) · \(item.recordTitle)", "\(item.photo.kind.label) photo · \(item.photo.angle)"]
        lines.append("Captured \(Fmt.time(item.photo.capturedAt)) (iPhone clock)")
        if let received = item.photo.receivedAt { lines.append("Received \(Fmt.time(received)) (server)") }
        return lines.joined(separator: "\n")
    }
}

#Preview("Gallery") {
    NavigationStack {
        PropertyGalleryView(propertyID: Fixtures.ID.islington)
            .appDestinations()
    }
    .previewEnvironment()
}
