import AVFoundation
import SwiftUI

/// The full-screen camera: a frame to fit the label in, a live check of sharpness, glare and light, a
/// flashlight, tap to focus, and the shutter.
struct CameraView: View {
    /// Called with the photo and where it was taken.
    let onCapture: (Data, CaptureLocation?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.state {
            case .starting, .running:
                CameraPreview(session: model.camera.session) { model.camera.focus(at: $0) }
                    .ignoresSafeArea()
                viewfinder
            case .noCamera:
                unavailable("No camera", "This device has no camera. Close this and choose a photo instead.")
            case .denied:
                unavailable("Camera access is off", "Allow Field Copilot to use the camera in Settings to scan labels.") {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            controls
        }
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .sensoryFeedback(.impact, trigger: model.taking)
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        GeometryReader { geometry in
            let frame = CGRect(x: geometry.size.width * 0.075, y: geometry.size.height * 0.2,
                               width: geometry.size.width * 0.85, height: geometry.size.height * 0.5)
            ZStack {
                // Dim everything outside the frame.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRoundedRect(in: frame, cornerSize: CGSize(width: 20, height: 20))
                }
                .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 20)
                    .stroke(frameColor, lineWidth: 3)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(.easeInOut(duration: 0.2), value: frameColor)
                Text("Fit the label inside the frame")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: frame.midX, y: frame.maxY + 22)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var frameColor: Color {
        guard let quality = model.quality else { return .white }
        return quality.problems.isEmpty ? .green : Color.orange
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            HStack {
                circleButton("Close", "xmark") { dismiss() }
                Spacer()
                if model.state == .running {
                    statusPill
                    Spacer()
                    circleButton(model.torchOn ? "Turn off light" : "Turn on light",
                                 model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") { model.torchOn.toggle() }
                        .foregroundStyle(model.torchOn ? Color.orange : .white)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            Spacer()
            if model.state == .running { shutter.padding(.bottom, 24) }
        }
    }

    private var statusPill: some View {
        let (text, symbol, good) = status
        return Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(good ? Color.white : Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(good ? Color.green.opacity(0.85) : Color.orange, in: .capsule)
            .animation(.default, value: text)
    }

    /// What to fix first, in plain words.
    private var status: (String, String, Bool) {
        guard let quality = model.quality else { return ("Point at the label", "viewfinder", true) }
        switch quality.problems.first {
        case .dark: return (model.torchOn ? "Too dark: move closer" : "Too dark: turn on the light", "moon.fill", false)
        case .glare: return ("Glare: tilt the phone", "sun.max.fill", false)
        case .blurry: return ("Hold steady or tap to focus", "camera.metering.unknown", false)
        case nil: return ("Looks good", "checkmark.circle.fill", true)
        }
    }

    private var shutter: some View {
        Button {
            Task {
                guard let (data, location) = await model.takePhoto() else { return }
                onCapture(data, location)
                dismiss()
            }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(.white).frame(width: 64, height: 64)
                if model.taking { ProgressView().tint(.black) }
            }
        }
        .disabled(model.taking)
        .accessibilityLabel("Take photo")
    }

    private func circleButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.4), in: .circle)
    }

    private func unavailable(_ title: String, _ message: String,
                             @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera")
        } description: {
            Text(message)
        } actions: {
            actions()
        }
        .foregroundStyle(.white)
    }
}

/// The live camera picture. Tapping focuses there.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        // The preview has a connection to rotate only once the session is set up and running.
        view.observer = NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification,
                                                               object: session, queue: .main) { [weak view] _ in
            MainActor.assumeIsolated { view?.portrait() }
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onTap = onTap
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint) -> Void)?
        var observer: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        /// The app is portrait only.
        func portrait() {
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            onTap?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
        }
    }
}
