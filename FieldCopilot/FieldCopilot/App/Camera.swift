import AVFoundation
import CoreLocation
import Observation
import UIKit

/// Where a photo was taken.
struct CaptureLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    /// How far off the position may be, in meters.
    let accuracy: Double
}

/// Owns the capture session. Setup, frames and photos run on the camera's own queue; results come back
/// through the callbacks.
nonisolated final class CameraSession: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.alexeigodfray.FieldCopilot.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var lastMeasured = Date.distantPast
    private var photoHandler: (@Sendable (Data?) -> Void)?
    /// The quality of what's in view, a few times a second.
    var onQuality: (@Sendable (PhotoQuality) -> Void)?

    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    func start() {
        queue.async {
            self.configure()
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// Focuses and exposes at a point in the camera's coordinates, 0 to 1.
    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func takePhoto(_ handler: @escaping @Sendable (Data?) -> Void) {
        queue.async {
            guard self.configured else { return handler(nil) }
            self.photoHandler = handler
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: Setup

    private func configure() {
        guard !configured else { return }
        // The virtual multi-camera devices switch to the ultra-wide lens on their own for close-up (macro) shots.
        guard let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(videoOutput)
        // The app is portrait only.
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()

        if (try? device.lockForConfiguration()) != nil {
            // Start on the main lens, like the Camera app; the device still switches lenses for close-ups.
            if let mainLens = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                device.videoZoomFactor = CGFloat(truncating: mainLens)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        self.device = device
        configured = true
    }

    // MARK: Frames and photos

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date.now.timeIntervalSince(lastMeasured) > 0.25, let onQuality,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastMeasured = .now
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let quality = PhotoQuality.measure(luma: base.assumingMemoryBound(to: UInt8.self),
                                           width: CVPixelBufferGetWidthOfPlane(buffer, 0),
                                           height: CVPixelBufferGetHeightOfPlane(buffer, 0),
                                           rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
        onQuality(quality)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        photoHandler?(data)
        photoHandler = nil
    }
}

/// The camera screen's state: permission, what's in view, the light, and taking the photo with its location.
@Observable
final class CameraModel {
    enum State { case starting, running, noCamera, denied }

    var state = State.starting
    var quality: PhotoQuality?
    var torchOn = false {
        didSet { camera.setTorch(torchOn) }
    }
    var taking = false
    @ObservationIgnored let camera = CameraSession()
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var location: CaptureLocation?

    func start() async {
        guard CameraSession.hasCamera else { return state = .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return state = .denied }
        default: return state = .denied
        }
        camera.onQuality = { [weak self] quality in
            guard let self else { return }
            Task { @MainActor in self.quality = quality }
        }
        camera.start()
        state = .running
        startLocation()
    }

    func stop() {
        camera.stop()
        locationTask?.cancel()
    }

    /// Takes the photo. Returns its data and where it was taken, if location is allowed.
    func takePhoto() async -> (Data, CaptureLocation?)? {
        taking = true
        defer { taking = false }
        let data = await withCheckedContinuation { continuation in
            camera.takePhoto { continuation.resume(returning: $0) }
        }
        return data.map { ($0, location) }
    }

    private func startLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let found = update.location, found.horizontalAccuracy >= 0 else { continue }
                    self?.location = CaptureLocation(latitude: found.coordinate.latitude, longitude: found.coordinate.longitude,
                                                     accuracy: found.horizontalAccuracy)
                }
            } catch {}
        }
    }
}
