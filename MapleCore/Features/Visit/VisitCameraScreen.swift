import SwiftUI
import PhotosUI
import UIKit
import MapleCoreKit

/// Proof-of-work camera (CameraBefore / CameraAfter boards): live preview, required-angle chips,
/// BEFORE · WORK · AFTER modes, 84pt shutter and an onion-skin of the before photo in After mode.
/// Every capture is written to the app container first, then attached to the visit. No network.
struct VisitCameraScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    let session: VisitSession
    let initialMode: PhotoKind
    let initialAngle: String?
    let camera: CameraController
    var go: (VisitScreen) -> Void

    @State private var mode: PhotoKind
    @State private var selectedAngle: String?
    @State private var showsOverlay = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pickerItem: PhotosPickerItem?

    init(session: VisitSession, initialMode: PhotoKind, initialAngle: String?, camera: CameraController, go: @escaping (VisitScreen) -> Void) {
        self.session = session
        self.initialMode = initialMode
        self.initialAngle = initialAngle
        self.camera = camera
        self.go = go
        _mode = State(initialValue: initialMode)
        _selectedAngle = State(initialValue: initialAngle)
    }

    // MARK: Derived

    private var required: Int {
        mode == .after ? VisitSession.requiredAfterPhotos : VisitSession.requiredBeforePhotos
    }

    private var modePhotos: [VisitPhoto] { session.photos(mode) }

    private var currentAngle: String {
        if mode == .work { return "Work in progress" }
        return selectedAngle ?? session.nextAngle(for: mode) ?? "Extra"
    }

    private var overlayPhoto: VisitPhoto? {
        guard mode == .after, showsOverlay else { return nil }
        return session.beforePhoto(forAngle: currentAngle)
    }

    private var canShoot: Bool {
        guard !isSaving, !camera.isCapturing else { return false }
        return camera.availability == .ready || CameraController.isSimulator
    }

    private func isModeAvailable(_ kind: PhotoKind) -> Bool {
        switch kind {
        case .before: return [.notStarted, .travelling, .arrived].contains(session.state)
        case .work: return session.state == .working || session.state == .paused
        case .after: return [.working, .paused, .completed].contains(session.state)
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            viewfinder
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if mode != .work { angleChips }
                Spacer(minLength: Space.s)
                if let errorMessage {
                    VisitInlineError(message: errorMessage)
                        .padding(.horizontal, Space.l)
                        .padding(.bottom, Space.s)
                }
                bottomControls
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: mode) { _, _ in
            selectedAngle = nil
            errorMessage = nil
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
    }

    // MARK: Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            switch camera.availability {
            case .ready:
                CameraPreviewView(session: camera.session)
            case .pending:
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Starting camera")
            case .denied:
                permissionOff
            case .unavailable:
                noCamera
            }
            if let overlayPhoto {
                PhotoTile(photo: overlayPhoto, cornerRadius: 0, maxPixel: 1200)
                    .opacity(0.28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var permissionOff: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text("Camera is off for MapleCore")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Proof-of-work photos are taken in the app so they're tied to the visit. Turn on camera access to continue.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.mc(.primary))
            importButton
            Text("Imported photos are labelled “Imported” for supervisor review.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: 420)
    }

    private var noCamera: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "camera.metering.unknown")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text(CameraController.isSimulator ? "No camera in the Simulator" : "Camera couldn't start")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(CameraController.isSimulator
                 ? "The shutter adds a placeholder photo so you can test the visit flow."
                 : "Close the camera and try again, or import from Photos. Imported photos are labelled for review.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            importButton
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: 420)
    }

    private var importButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Import from Photos", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.mc(.secondary))
        .disabled(isSaving || !isModeAvailable(mode))
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.iconCircleOnDark)
            .accessibilityLabel("Close camera")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(clockLine(at: context.date))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("\(session.propertyName) · Stop \(session.stopNumber)")
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            Button {
                camera.flash = camera.flash == .auto ? .off : .auto
                Haptics.selection()
            } label: {
                Image(systemName: camera.flash.symbol)
            }
            .buttonStyle(.iconCircleOnDark)
            .disabled(camera.availability != .ready)
            .accessibilityLabel(camera.flash.label)
            .accessibilityHint("Switches between flash auto and off")
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func clockLine(at date: Date) -> String {
        switch mode {
        case .before: return "Visit \(Fmt.timer(session.onSiteElapsed(at: date)))"
        case .work: return "Working \(Fmt.timer(session.workingElapsed(at: date)))"
        case .after: return "Work done · \(Fmt.timer(session.workingElapsed(at: date)))"
        }
    }

    // MARK: Angles

    private var angleChips: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(session.requiredAngles, id: \.self) { angle in
                        angleChip(angle)
                    }
                }
                .padding(.horizontal, Space.l)
            }
            HStack(spacing: Space.s) {
                if !store.isOnline {
                    Pill(text: "No signal · \(store.pendingOutbox.count) queued", tone: .amber, symbol: "wifi.slash")
                }
                if mode == .after, session.beforePhoto(forAngle: currentAngle) != nil {
                    Button {
                        showsOverlay.toggle()
                    } label: {
                        Label(showsOverlay ? "Before overlay on" : "Before overlay off", systemImage: showsOverlay ? "square.on.square" : "square")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: Hit.min)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    .accessibilityHint("Shows the matching before photo faintly so you can line up the same angle")
                }
            }
        }
        .padding(.top, Space.s)
    }

    private func angleChip(_ angle: String) -> some View {
        let taken = modePhotos.contains { $0.angle == angle }
        let selected = angle == currentAngle
        return Button {
            selectedAngle = angle
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                if taken {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(angle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, Space.m)
            .frame(minHeight: Hit.min)
            .background(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.45)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(angle)\(taken ? ", photo taken" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Space.m) {
            if mode == .after {
                Text("Line up with the faded before photo for a matching angle")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else if mode == .before {
                Text("Angle: \(currentAngle)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            modePicker
            HStack(alignment: .center) {
                thumbnailButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                shutter
                doneButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("Saved on this iPhone first · uploads in the background")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var modePicker: some View {
        HStack(spacing: Space.xs) {
            ForEach(PhotoKind.allCases, id: \.self) { kind in
                let available = isModeAvailable(kind)
                Button {
                    mode = kind
                    Haptics.selection()
                } label: {
                    Text(kind.label.uppercased())
                        .font(.footnote.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(mode == kind ? Palette.red : Color.white.opacity(available ? 0.9 : 0.35))
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: Hit.min)
                        .background(mode == kind ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.clear), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .accessibilityAddTraits(mode == kind ? .isSelected : [])
                .accessibilityHint(available ? "" : unavailableHint(kind))
            }
        }
        .padding(Space.xs)
        .background(.black.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo type")
    }

    private func unavailableHint(_ kind: PhotoKind) -> String {
        kind == .before ? "Before photos are taken before work starts" : "Available after you start work"
    }

    @ViewBuilder
    private var thumbnailButton: some View {
        if let last = modePhotos.last {
            Button {
                go(.photo(last.id))
            } label: {
                PhotoTile(photo: last, cornerRadius: Radius.control)
                    .frame(width: 56, height: 56)
                    .overlay(alignment: .topTrailing) {
                        Text("\(modePhotos.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Palette.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review \(Fmt.plural(modePhotos.count, "\(mode.label.lowercased()) photo"))")
        } else {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
        }
    }

    private var shutter: some View {
        Button(action: shoot) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                Circle()
                    .fill(.white)
                    .padding(8)
                if isSaving || camera.isCapturing {
                    ProgressView().tint(.black)
                }
            }
            .frame(width: Hit.shutter, height: Hit.shutter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canShoot || !isModeAvailable(mode))
        .opacity(canShoot ? 1 : 0.45)
        .accessibilityLabel("Take \(mode.label.lowercased()) photo")
        .accessibilityHint(mode == .work ? "" : "Angle: \(currentAngle)")
    }

    @ViewBuilder
    private var doneButton: some View {
        let count = modePhotos.count
        let enough = mode == .work || count >= required
        Button(action: done) {
            VStack(spacing: 0) {
                Text(doneTitle(count: count, enough: enough))
                    .font(.subheadline.weight(.bold))
                if mode != .work {
                    Text("\(count) of \(required)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(enough ? Color.black : Color.white)
            .padding(.horizontal, Space.m)
            .frame(minWidth: Hit.min + 20, minHeight: Hit.min + 4)
            .background(enough ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.45)), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enough)
        .accessibilityLabel(doneAccessibility(count: count, enough: enough))
    }

    private func doneTitle(count: Int, enough: Bool) -> String {
        switch mode {
        case .before: return enough ? "Start Work" : "\(required - count) more"
        case .work: return "Done"
        case .after: return enough ? "Done" : "\(required - count) more"
        }
    }

    private func doneAccessibility(count: Int, enough: Bool) -> String {
        if !enough {
            return "Done, \(count) of \(required) \(mode.label.lowercased()) photos. \(required - count) more needed"
        }
        switch mode {
        case .before: return "Start work"
        case .work: return "Done, back to the work timer"
        case .after: return "Done, compare before and after"
        }
    }

    // MARK: Actions

    private func close() {
        switch mode {
        case .before: go(.arrived)
        case .work, .after: go(session.state == .completed ? .review : .timer)
        }
    }

    private func done() {
        switch mode {
        case .before:
            errorMessage = store.visitAction { s, now in try s.startWork(at: now) }
            if errorMessage == nil {
                Haptics.impact(.medium)
                go(.timer)
            } else {
                Haptics.error()
            }
        case .work:
            go(.timer)
        case .after:
            go(.compare)
        }
    }

    private func shoot() {
        let kind = mode
        let angle = currentAngle
        let shotAt = store.now
        errorMessage = nil
        Haptics.impact(.light)

        if CameraController.isSimulator {
            // No camera hardware: add a placeholder photo (no image file) so the flow can be tested.
            errorMessage = store.visitAction { s, _ in
                _ = s.addPhoto(kind: kind, angle: angle, at: shotAt, source: .inAppCamera, localFileName: nil)
            }
            selectedAngle = nil
            return
        }

        camera.capture { data in
            Task { @MainActor in
                guard let data else {
                    errorMessage = "Couldn't take that photo. Try again."
                    Haptics.error()
                    return
                }
                await savePhoto(data, kind: kind, angle: angle, at: shotAt, source: .inAppCamera)
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        let kind = mode
        let angle = currentAngle
        Task { @MainActor in
            defer { pickerItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "That photo couldn't be read. Try another one."
                    return
                }
                await savePhoto(data, kind: kind, angle: angle, at: store.now, source: .imported)
            } catch {
                errorMessage = "That photo couldn't be read. Try another one."
            }
        }
    }

    /// Saves to the app container FIRST, then attaches the file to the visit.
    @MainActor
    private func savePhoto(_ data: Data, kind: PhotoKind, angle: String, at date: Date, source: PhotoSource) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let name = try await Task.detached(priority: .userInitiated) {
                try PhotoStorage.save(data: data)
            }.value
            let message = store.visitAction { s, _ in
                _ = s.addPhoto(kind: kind, angle: angle, at: date, source: source, localFileName: name)
            }
            if let message {
                PhotoStorage.delete(name)
                errorMessage = message
            } else {
                selectedAngle = nil
            }
        } catch {
            errorMessage = "Couldn't save the photo on this iPhone. Check free storage and try again."
            Haptics.error()
        }
    }
}

#if DEBUG
#Preview {
    VisitFlowPreviewHost(beforePhotos: 1)
        .previewEnvironment(role: .field)
}
#endif
