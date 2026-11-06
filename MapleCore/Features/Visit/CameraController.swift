import SwiftUI
import UIKit
import AVFoundation

/// Owns the AVFoundation capture pipeline for proof-of-work photos.
/// The session is configured and started on a private serial queue so the UI never stalls;
/// observable state is only written on the main queue.
@Observable
final class CameraController {
    enum Availability: Equatable {
        /// Permission not asked yet, or the session is still configuring.
        case pending
        case ready
        /// The person turned camera access off (or it's restricted).
        case denied
        /// No camera hardware (Simulator) or the device failed to configure.
        case unavailable
    }

    enum Flash: Equatable {
        case auto, off

        var avMode: AVCaptureDevice.FlashMode { self == .auto ? .auto : .off }
        var symbol: String { self == .auto ? "bolt.badge.automatic" : "bolt.slash" }
        var label: String { self == .auto ? "Flash auto" : "Flash off" }
    }

    /// One capture pipeline for the app. The visit cover's view struct is re-created often, so owning
    /// the session there would allocate a new AVCaptureSession on every parent update.
    @MainActor static let shared = CameraController()

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    var availability: Availability = CameraController.isSimulator ? .unavailable : .pending
    var flash: Flash = .auto
    var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.maplecore.camera")
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    init() {}

    /// Asks for permission if needed, configures once, then starts the session.
    func start() {
        guard !Self.isSimulator else {
            availability = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.availability = .denied
                    }
                }
            }
        case .denied, .restricted:
            availability = .denied
        @unknown default:
            availability = .denied
        }
    }

    func stop() {
        guard !Self.isSimulator else { return }
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        let session = self.session
        let output = self.output
        let needsConfiguration = !isConfigured
        isConfigured = true
        queue.async { [weak self] in
            if needsConfiguration {
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input),
                      session.canAddOutput(output) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async {
                        self?.isConfigured = false
                        self?.availability = .unavailable
                    }
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .balanced
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async {
                self?.availability = .ready
            }
        }
    }

    /// Captures one photo and hands back its encoded data (HEIC/JPEG) on the main queue, or nil on failure.
    func capture(_ completion: @escaping (Data?) -> Void) {
        guard availability == .ready, !isCapturing else {
            completion(nil)
            return
        }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flash.avMode) {
            settings.flashMode = flash.avMode
        }
        let id = settings.uniqueID
        let processor = PhotoCaptureProcessor { [weak self] data in
            DispatchQueue.main.async {
                self?.inFlight[id] = nil
                self?.isCapturing = false
                completion(data)
            }
        }
        inFlight[id] = processor
        let output = self.output
        queue.async {
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait
            }
            output.capturePhoto(with: settings, delegate: processor)
        }
    }
}

/// Bridges the AVCapturePhotoCaptureDelegate callback to a closure.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// Live camera preview backed by `AVCaptureVideoPreviewLayer`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {}

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
