import SwiftUI
import UIKit
import ImageIO
import MapleCoreKit

/// Renders a visit photo: the captured image when one exists on this iPhone, otherwise a tinted
/// placeholder (fixture photos have no image data). Never draws metadata on the photo itself.
struct PhotoTile: View {
    var photo: VisitPhoto?
    var swatch: Int = 0
    var cornerRadius: CGFloat = Radius.control
    var showsKindLabel = false
    var maxPixel: CGFloat = 600

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Palette.swatches[(photo?.swatch ?? swatch) % Palette.swatches.count].gradient)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "leaf")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.35))
                            .accessibilityHidden(true)
                    }
                }
                .clipped()
            if showsKindLabel, let photo {
                Text(photo.kind.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
            if photo?.source == .imported {
                Text("Imported")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.amber, in: Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: photo?.localFileName) {
            guard let name = photo?.localFileName else { image = nil; return }
            image = await ThumbnailCache.shared.image(for: name, maxPixel: maxPixel)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityText: String {
        guard let photo else { return "Photo" }
        var parts = ["\(photo.kind.label) photo", photo.angle]
        if !photo.caption.isEmpty { parts.append(photo.caption) }
        if photo.source == .imported { parts.append("imported") }
        return parts.joined(separator: ", ")
    }
}

/// Before / after compare with a draggable divider. Accessible as an adjustable control.
struct PhotoCompareSlider: View {
    var before: VisitPhoto?
    var after: VisitPhoto?
    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                PhotoTile(photo: after, swatch: 1, cornerRadius: 0, maxPixel: 1200)
                PhotoTile(photo: before, swatch: 0, cornerRadius: 0, maxPixel: 1200)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * split)
                    }
                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .offset(x: width * split - 1.5)
                    .shadow(radius: 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .floatingShadow()
                    .offset(x: width * split - 20)
                label("BEFORE").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                label("AFTER").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(value.location.x / max(width, 1), 0.05), 0.95)
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Before and after comparison")
        .accessibilityValue("\(Int(split * 100)) percent before")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(split + 0.1, 0.95)
            case .decrement: split = max(split - 0.1, 0.05)
            @unknown default: break
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(Space.m)
    }
}
