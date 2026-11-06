import SwiftUI
import MapleCoreKit

/// Step 4 · Before / after compare (BeforeAfter board): drag to compare each angle pair,
/// with each photo's time labelled by where it came from.
struct VisitCompareStep: View {
    @Environment(AppStore.self) private var store

    let session: VisitSession
    var go: (VisitScreen) -> Void

    @State private var selectedAngle: String?
    @State private var errorMessage: String?

    /// Required angles first, then any extra angles that have photos.
    private var angles: [String] {
        var result = session.requiredAngles
        for photo in session.photos where photo.kind != .work && !result.contains(photo.angle) {
            result.append(photo.angle)
        }
        return result
    }

    private var matchedAngles: [String] {
        angles.filter { before(for: $0) != nil && after(for: $0) != nil }
    }

    private var currentAngle: String {
        selectedAngle ?? matchedAngles.first ?? angles.first ?? "Front beds"
    }

    private func before(for angle: String) -> VisitPhoto? { session.photos(.before).first { $0.angle == angle } }
    private func after(for angle: String) -> VisitPhoto? { session.photos(.after).last { $0.angle == angle } }

    private var shareURLs: [URL] {
        [before(for: currentAngle), after(for: currentAngle)]
            .compactMap { $0?.localFileName }
            .map { PhotoStorage.url(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                titleRow
                PhotoCompareSlider(before: before(for: currentAngle), after: after(for: currentAngle))
                    .id(currentAngle)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                pairPicker
                Text("\(Fmt.plural(matchedAngles.count, "matched pair")) · \(Fmt.plural(session.photos(.work).count, "work photo"))")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                times
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                if let errorMessage { VisitInlineError(message: errorMessage) }
                Button("Continue to Review", action: continueToReview)
                    .buttonStyle(.mc(.primary, glove: true))
                Button {
                    go(.camera(.after))
                } label: {
                    Label("Back to After Photos", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Hit.min)
                }
                .foregroundStyle(Palette.ink2)
            }
        }
    }

    private var titleRow: some View {
        HStack {
            Text(currentAngle)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            shareButton
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !shareURLs.isEmpty {
            ShareLink(items: shareURLs) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.iconCircle)
            .accessibilityLabel("Share comparison")
        } else {
            ShareLink(item: summaryText) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.iconCircle)
            .accessibilityLabel("Share comparison summary")
        }
    }

    private var summaryText: String {
        "\(session.propertyName) · \(currentAngle) — before and after photos from stop \(session.stopNumber)."
    }

    private var pairPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(angles, id: \.self) { angle in
                    pairThumb(angle)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func pairThumb(_ angle: String) -> some View {
        let selected = angle == currentAngle
        let matched = before(for: angle) != nil && after(for: angle) != nil
        return Button {
            selectedAngle = angle
            Haptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: 2) {
                    PhotoTile(photo: before(for: angle), swatch: 0, cornerRadius: 6, maxPixel: 200)
                    PhotoTile(photo: after(for: angle), swatch: 1, cornerRadius: 6, maxPixel: 200)
                }
                .frame(width: 104, height: 52)
                .opacity(matched ? 1 : 0.5)
                Text(angle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? Palette.redText : Palette.ink2)
                    .lineLimit(1)
            }
            .padding(Space.xs)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? Palette.red : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(angle) pair\(matched ? "" : ", missing a photo")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var times: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            timeRow("Before", photo: before(for: currentAngle))
            Divider()
            timeRow("After", photo: after(for: currentAngle))
            Divider()
            HStack(alignment: .top) {
                Text("Server").font(.subheadline).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
                TimeStampLabel(source: .server, date: nil)
            }
            .accessibilityElement(children: .combine)
        }
        .cardStyle()
    }

    private func timeRow(_ title: String, photo: VisitPhoto?) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.subheadline).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
            if let photo {
                TimeStampLabel(source: photo.source == .imported ? .imported : .device, date: photo.capturedAt)
            } else {
                Text("No photo for this angle")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Work is done once the after photos are in: freeze the timer, then review notes.
    private func continueToReview() {
        if session.state == .working || session.state == .paused {
            errorMessage = store.visitAction { s, now in try s.complete(at: now) }
            guard errorMessage == nil else {
                Haptics.error()
                return
            }
        }
        errorMessage = nil
        go(.review)
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost(beforePhotos: 3, startWork: true)
        .previewEnvironment(role: .field)
}
#endif
