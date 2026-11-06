import SwiftUI
import MapleCoreKit

/// Photo review and caption (PhotoReview board): big photo, angle progress, caption,
/// where the time came from, and the honest upload state.
struct VisitPhotoReviewScreen: View {
    @Environment(AppStore.self) private var store

    let session: VisitSession
    let photoID: VisitPhoto.ID
    var go: (VisitScreen) -> Void

    @State private var caption = ""
    @State private var isDeleteConfirming = false
    @FocusState private var captionFocused: Bool

    private var photo: VisitPhoto? { session.photos.first { $0.id == photoID } }

    var body: some View {
        Group {
            if let photo {
                content(photo)
            } else {
                MissingRecordView(title: "Photo removed", message: "This photo is no longer part of the visit.")
                    .safeAreaInset(edge: .bottom) {
                        BottomActionBar {
                            Button("Back to Camera") { go(.camera(.before)) }
                                .buttonStyle(.mc(.secondary))
                        }
                    }
            }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private func content(_ photo: VisitPhoto) -> some View {
        let kindPhotos = session.photos(photo.kind)
        let position = (kindPhotos.firstIndex { $0.id == photo.id } ?? 0) + 1
        let total = max(kindPhotos.count, photo.kind == .work ? kindPhotos.count : VisitSession.requiredBeforePhotos)
        return VStack(spacing: 0) {
            topBar(photo, title: "\(photo.kind.label) · \(position) of \(total)")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    PhotoTile(photo: photo, cornerRadius: Radius.card, showsKindLabel: true, maxPixel: 1400)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    if photo.kind != .work { angleProgress(photo) }
                    captionField(photo)
                    details(photo)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomActionBar {
                HStack(spacing: Space.s) {
                    Button("Retake") { retake(photo) }
                        .buttonStyle(.mc(.secondary, glove: true))
                    Button(nextTitle(photo)) {
                        saveCaption(photo)
                        go(.camera(photo.kind))
                    }
                    .buttonStyle(.mc(.primary, glove: true))
                }
            }
        }
        .onAppear { caption = photo.caption }
        .onDisappear { saveCaption(photo) }
        .confirmationDialog("Delete this photo?", isPresented: $isDeleteConfirming, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) { delete(photo) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from this visit and from this iPhone.")
        }
    }

    private func topBar(_ photo: VisitPhoto, title: String) -> some View {
        HStack(spacing: Space.s) {
            Button {
                saveCaption(photo)
                go(.camera(photo.kind))
            } label: {
                Label("Camera", systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: Hit.min)
            }
            .accessibilityLabel("Back to camera")
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
            Button {
                isDeleteConfirming = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.iconCircle)
            .accessibilityLabel("Delete photo")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }

    private func angleProgress(_ photo: VisitPhoto) -> some View {
        let taken = Set(session.photos(photo.kind).map(\.angle))
        let remaining = session.requiredAngles.filter { !taken.contains($0) }.count
        return VStack(alignment: .leading, spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(session.requiredAngles, id: \.self) { angle in
                        Pill(
                            text: angle,
                            tone: angle == photo.angle ? .red : (taken.contains(angle) ? .green : .neutral),
                            symbol: taken.contains(angle) ? "checkmark" : nil
                        )
                    }
                }
            }
            Text(remaining == 0 ? "All angles covered" : "\(Fmt.plural(remaining, "more angle")) needed")
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private func captionField(_ photo: VisitPhoto) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Caption").captionStyle()
            TextField("What does this photo show?", text: $caption, axis: .vertical)
                .lineLimit(1...4)
                .focused($captionFocused)
                .submitLabel(.done)
                .onSubmit { saveCaption(photo) }
                .padding(Space.m)
                .frame(minHeight: Hit.min)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityLabel("Caption")
        }
    }

    private func details(_ photo: VisitPhoto) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            TimeStampLabel(source: photo.source == .imported ? .imported : .device, date: photo.capturedAt)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(store.property(session.propertyID)?.name ?? session.propertyName)
                    .font(.subheadline.weight(.semibold))
                Text("Stop \(session.stopNumber) · \(photo.angle)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
            .accessibilityElement(children: .combine)
            Divider()
            uploadLine(photo)
        }
        .cardStyle()
    }

    private func uploadLine(_ photo: VisitPhoto) -> some View {
        let (symbol, text): (String, String) = {
            switch photo.upload {
            case .savedOnDevice: return ("iphone", "Saved on this iPhone · uploads when you submit")
            case .uploading: return ("arrow.up.circle", "Uploading")
            case .uploaded: return ("checkmark.circle.fill", "Uploaded")
            case .failed: return ("exclamationmark.circle", "Upload failed · retries automatically")
            }
        }()
        return Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(photo.upload.tone.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    private func nextTitle(_ photo: VisitPhoto) -> String {
        guard photo.kind != .work else { return "Keep" }
        return session.nextAngle(for: photo.kind) == nil ? "Keep" : "Keep · Next Angle"
    }

    // MARK: Actions

    private func saveCaption(_ photo: VisitPhoto) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != photo.caption, session.photos.contains(where: { $0.id == photo.id }) else { return }
        store.visitAction { s, _ in s.setCaption(trimmed, forPhoto: photo.id) }
    }

    private func retake(_ photo: VisitPhoto) {
        remove(photo)
        go(.camera(photo.kind, angle: photo.kind == .work ? nil : photo.angle))
    }

    private func delete(_ photo: VisitPhoto) {
        remove(photo)
        Haptics.warning()
        go(.camera(photo.kind))
    }

    private func remove(_ photo: VisitPhoto) {
        if let name = photo.localFileName { PhotoStorage.delete(name) }
        store.visitAction { s, _ in s.removePhoto(id: photo.id) }
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost(beforePhotos: 1)
        .previewEnvironment(role: .field)
}
#endif
