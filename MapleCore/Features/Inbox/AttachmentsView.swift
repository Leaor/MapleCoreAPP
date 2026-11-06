import SwiftUI
import MapleCoreKit

/// Everything shared in a thread: photos, files and visit reports for the linked property.
struct AttachmentsView: View {
    let threadID: MessageThread.ID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let thread = store.thread(threadID) {
            AttachmentsContent(thread: thread)
        } else {
            MissingRecordView(title: "Attachments not available")
        }
    }
}

private enum AttachmentSegment: String, CaseIterable, Hashable {
    case photos, files, visits
}

private struct SharedPhoto: Identifiable {
    var attachment: Attachment
    var sentAt: Date
    var id: Attachment.ID { attachment.id }
}

private struct AttachmentsContent: View {
    let thread: MessageThread
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts
    @State private var segment: AttachmentSegment = .photos
    @State private var viewing: SharedPhoto?

    private var photos: [SharedPhoto] {
        thread.messages.flatMap { message in
            message.attachments.filter { $0.kind == .photo }.map { SharedPhoto(attachment: $0, sentAt: message.sentAt) }
        }
        .reversed()
    }

    private var files: [(attachment: Attachment, message: Message)] {
        thread.messages.flatMap { message in
            message.attachments.filter { $0.kind != .photo }.map { (attachment: $0, message: message) }
        }
        .reversed()
    }

    private var visits: [VisitRecord] {
        guard let propertyID = thread.propertyID else { return [] }
        return store.history(for: propertyID).filter { $0.kind == .visit }
    }

    var body: some View {
        let photos = self.photos
        let files = self.files
        let visits = self.visits
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Picker("Attachment type", selection: $segment) {
                    Text("Photos \(photos.count)").tag(AttachmentSegment.photos)
                    Text("Files \(files.count)").tag(AttachmentSegment.files)
                    Text("Visits \(visits.count)").tag(AttachmentSegment.visits)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: segment)

                switch segment {
                case .photos: photoSection(photos)
                case .files: fileSection(files)
                case .visits: visitSection(visits)
                }
            }
            .padding(Space.l)
        }
        .screenBackground()
        .navigationTitle("Attachments")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewing) { photo in
            AttachmentPhotoViewer(photo: photo)
        }
    }

    // MARK: Photos

    @ViewBuilder
    private func photoSection(_ photos: [SharedPhoto]) -> some View {
        if photos.isEmpty {
            EmptyStateView(symbol: "photo.on.rectangle", title: "No photos yet", message: "Photos sent in this conversation appear here.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s)], spacing: Space.s) {
                ForEach(photos) { photo in
                    AttachmentGridTile(photo: photo, isOnline: store.isOnline) {
                        viewing = photo
                    } retry: {
                        store.sendNow()
                        toasts.show("Retrying uploads", symbol: "arrow.clockwise", tone: .blue)
                    }
                }
            }
            if thread.kind == .customer {
                Label("Customer can see photos sent in this thread.", systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            } else {
                Label("Internal — customers never see these photos.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
            }
        }
    }

    // MARK: Files

    @ViewBuilder
    private func fileSection(_ files: [(attachment: Attachment, message: Message)]) -> some View {
        if files.isEmpty {
            EmptyStateView(symbol: "doc", title: "No files yet", message: "Visit reports and quotes shared here appear in this list.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.attachment.id) { index, entry in
                    fileRow(entry.attachment, message: entry.message)
                    if index < files.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    @ViewBuilder
    private func fileRow(_ attachment: Attachment, message: Message) -> some View {
        let destination = fileDestination(for: attachment)
        let row = AttachmentFileRow(attachment: attachment, author: message.isMine(store.inboxViewerID) ? "You" : message.authorName, date: message.sentAt, showsChevron: destination != nil)
        if let destination {
            Button {
                model.push(destination)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func fileDestination(for attachment: Attachment) -> AppDestination? {
        switch attachment.kind {
        case .visitReport:
            return thread.propertyID.map { AppDestination.documents($0) }
        case .quote:
            return store.capabilities.contains(.finance) ? .quotes : nil
        case .file, .photo:
            return nil
        }
    }

    // MARK: Visits

    @ViewBuilder
    private func visitSection(_ visits: [VisitRecord]) -> some View {
        if visits.isEmpty {
            EmptyStateView(symbol: "checkmark.seal", title: "No visit reports", message: thread.propertyID == nil ? "This conversation isn't linked to a property." : "Reviewed visits for this property appear here.")
        } else {
            CardList(data: visits, inset: 0) { visit in
                Button {
                    model.push(.photoCompare(visit.id))
                } label: {
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text("\(Fmt.shortDay(visit.date)) · \(visit.crewNames) · \(Fmt.plural(visit.photos.count, "photo"))")
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink2)
                        }
                        Spacer(minLength: Space.s)
                        Pill(text: visit.review.label, tone: visit.review == .approved ? .green : (visit.review == .awaiting ? .blue : .amber),
                             symbol: visit.review == .approved ? "checkmark" : "clock")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Space.m)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Photo grid tile with upload state overlay.
private struct AttachmentGridTile: View {
    let photo: SharedPhoto
    let isOnline: Bool
    var open: () -> Void
    var retry: () -> Void

    var body: some View {
        ZStack {
            Button(action: open) {
                PhotoTile(photo: photo.attachment.inboxPhoto(at: photo.sentAt), cornerRadius: Radius.control, maxPixel: 300)
                    .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo, \(photo.attachment.inboxDisplayName), \(statusText ?? "uploaded")")
            overlay
        }
    }

    private var statusText: String? {
        switch photo.attachment.upload {
        case .uploaded: nil
        case let .uploading(progress): "Uploading \(Int(progress * 100))%"
        case .savedOnDevice: isOnline ? "Saved on iPhone" : "Waiting for connection"
        case .failed: "Upload failed"
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch photo.attachment.upload {
        case .uploaded:
            EmptyView()
        case let .uploading(progress):
            VStack(spacing: Space.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .numeric()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        case .savedOnDevice:
            Label(isOnline ? "Saved" : "Waiting", systemImage: isOnline ? "iphone" : "wifi.slash")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Palette.amber, in: Capsule())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        case .failed:
            Button(action: retry) {
                VStack(spacing: Space.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.bold))
                    Text("Tap to retry")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.red.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upload failed. Retry")
        }
    }
}

/// File row: badge, name, author and date.
private struct AttachmentFileRow: View {
    let attachment: Attachment
    let author: String
    let date: Date
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.redText)
                .frame(width: 40, height: 40)
                .background(Palette.redSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text([author, Fmt.shortDate(date), attachment.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.s)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Space.m)
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var badge: String {
        switch attachment.kind {
        case .visitReport: "PDF"
        case .quote: "QTE"
        case .file: "FILE"
        case .photo: "IMG"
        }
    }
}

/// Large view of one shared photo.
private struct AttachmentPhotoViewer: View {
    let photo: SharedPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.m) {
                PhotoTile(photo: photo.attachment.inboxPhoto(at: photo.sentAt), cornerRadius: Radius.card, maxPixel: 1600)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                Text("Sent \(Fmt.relativeDay(photo.sentAt)) \(Fmt.time(photo.sentAt))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .screenBackground()
            .navigationTitle(photo.attachment.inboxDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview("Attachments") {
    NavigationStack {
        AttachmentsView(threadID: Fixtures.ID.threadSandra).appDestinations()
    }
    .previewEnvironment()
}
