import SwiftUI
import MapleCoreKit

/// Admin before/after compare for a submitted visit. Pairs are matched by angle.
struct PhotoCompareView: View {
    let visitID: VisitRecord.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let visit = store.visit(visitID) {
            PhotoCompareContent(visit: visit)
        } else {
            MissingRecordView()
        }
    }
}

private struct PhotoCompareContent: View {
    let visit: VisitRecord
    @Environment(AppStore.self) private var store
    @State private var selectedPairID: PropertyPhotoPair.ID?

    var body: some View {
        let pairs = store.photoPairs(for: visit)
        let selected = pairs.first { $0.id == selectedPairID } ?? pairs.first
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let selected {
                    PhotoCompareSlider(before: selected.before, after: selected.after)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .id(selected.id)
                    pairPicker(pairs, selected: selected)
                    timestamps(selected)
                } else {
                    EmptyStateView(symbol: "rectangle.split.2x1", title: "No matched pairs",
                                   message: "This visit doesn't have a before and after photo from the same angle.")
                    if !visit.photos.isEmpty {
                        unmatchedGrid
                    }
                }
                reviewLink
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle(selected?.angle ?? "Before & After")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(selected)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share comparison")
            }
        }
        .sensoryFeedback(.selection, trigger: selectedPairID)
    }

    private var propertyName: String { store.property(visit.propertyID)?.name ?? "Property" }

    // MARK: Pair picker

    private func pairPicker(_ pairs: [PropertyPhotoPair], selected: PropertyPhotoPair) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(pairs) { pair in
                        let isOn = pair.id == selected.id
                        Button {
                            withMotion { selectedPairID = pair.id }
                        } label: {
                            VStack(spacing: Space.xs) {
                                HStack(spacing: 2) {
                                    PhotoTile(photo: pair.before, cornerRadius: 6, maxPixel: 200)
                                    PhotoTile(photo: pair.after, cornerRadius: 6, maxPixel: 200)
                                }
                                .frame(width: 96, height: 56)
                                .padding(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .strokeBorder(isOn ? Palette.red : Color.clear, lineWidth: 2)
                                )
                                Text(pair.angle)
                                    .font(.caption.weight(isOn ? .semibold : .regular))
                                    .foregroundStyle(isOn ? Palette.ink : Palette.ink2)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: Hit.min)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(pair.angle) pair")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            Text(Fmt.plural(pairs.count, "matched pair"))
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }

    // MARK: Timestamps

    private func timestamps(_ pair: PropertyPhotoPair) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stampRow("Before") {
                TimeStampLabel(source: pair.before.source == .imported ? .imported : .device, date: pair.before.capturedAt)
            }
            Divider()
            stampRow("After") {
                TimeStampLabel(source: pair.after.source == .imported ? .imported : .device, date: pair.after.capturedAt)
            }
            Divider()
            stampRow("Server") {
                TimeStampLabel(source: .server, date: pair.after.receivedAt ?? visit.receivedAt)
            }
        }
        .padding(.horizontal, Space.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func stampRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .frame(minWidth: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Unmatched / review

    private var unmatchedGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.xs)], spacing: Space.xs) {
            ForEach(visit.photos) { photo in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { PhotoTile(photo: photo, showsKindLabel: true, maxPixel: 400) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var reviewLink: some View {
        if visit.review == .awaiting && store.capabilities.contains(.visitReview) {
            NavigationLink(value: AppDestination.review(visit.id)) {
                Text("Open Review")
            }
            .buttonStyle(.mc(.primary))
        } else {
            HStack(spacing: Space.s) {
                let badge = visit.propertyTimelineBadge
                Pill(text: badge.text, tone: badge.tone, symbol: badge.symbol)
                Text("\(propertyName) · \(Fmt.shortDate(visit.date)) · \(visit.title)")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func shareText(_ pair: PropertyPhotoPair?) -> String {
        var lines = ["\(propertyName) · \(visit.title) · \(Fmt.shortDate(visit.date))"]
        if let pair {
            lines.append("Angle: \(pair.angle)")
            lines.append("Before captured \(Fmt.time(pair.before.capturedAt)) (iPhone clock)")
            lines.append("After captured \(Fmt.time(pair.after.capturedAt)) (iPhone clock)")
            if let received = pair.after.receivedAt ?? visit.receivedAt {
                lines.append("Received by server \(Fmt.time(received))")
            } else {
                lines.append("Server: pending upload")
            }
        }
        lines.append(visit.review.label)
        return lines.joined(separator: "\n")
    }
}

#Preview("Before & after") {
    NavigationStack {
        PhotoCompareView(visitID: "v-isl-1")
            .appDestinations()
    }
    .previewEnvironment()
}
