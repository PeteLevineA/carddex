import SwiftUI

#if canImport(VisionKit) && canImport(UIKit)
import VisionKit
import AVFoundation
import UIKit

/// SwiftUI wrapper around `DataScannerViewController` with an AVFoundation
/// fallback for devices that don't support DataScanner. The `onCaptureFrame`
/// closure is called with a stable, debounced still after the user taps the
/// preview (DataScanner: tap a recognized text region or anywhere via the
/// gesture recognizer; AVFoundation: tap-to-capture).
public struct CameraScannerView: UIViewControllerRepresentable {

    public var onCaptureFrame: (CGImage) -> Void

    public init(onCaptureFrame: @escaping (CGImage) -> Void) {
        self.onCaptureFrame = onCaptureFrame
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            // Pokémon cards aren't barcoded, so we recognize text — the OCR'd
            // card number / name region — which gives the user something to
            // tap on, and we additionally install a full-view tap recognizer
            // for "tap anywhere to capture".
            let vc = DataScannerViewController(
                recognizedDataTypes: [.text()],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: true,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
            vc.delegate = context.coordinator
            let tap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleScannerTap(_:))
            )
            tap.cancelsTouchesInView = false
            vc.view.addGestureRecognizer(tap)
            context.coordinator.dataScanner = vc
            try? vc.startScanning()
            return vc
        } else {
            return AVCaptureViewController(onFrame: onCaptureFrame)
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onCaptureFrame: onCaptureFrame) }

    public final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCaptureFrame: (CGImage) -> Void
        weak var dataScanner: DataScannerViewController?
        init(onCaptureFrame: @escaping (CGImage) -> Void) { self.onCaptureFrame = onCaptureFrame }

        public func dataScanner(_ dataScanner: DataScannerViewController,
                                didTapOn item: RecognizedItem) {
            capture(from: dataScanner)
        }

        @objc func handleScannerTap(_ gr: UITapGestureRecognizer) {
            guard let scanner = dataScanner else { return }
            capture(from: scanner)
        }

        private func capture(from scanner: DataScannerViewController) {
            scanner.capturePhoto { result in
                if case let .success(photo) = result, let cg = photo.image.cgImage {
                    self.onCaptureFrame(cg)
                }
            }
        }
    }
}

/// Minimal AVFoundation fallback for older devices. Tap the preview to
/// capture a still and feed it into the scanner pipeline.
final class AVCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let onFrame: (CGImage) -> Void
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)

        Task.detached(priority: .userInitiated) { [session] in session.startRunning() }
    }

    @objc private func handleTap() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let cg = photo.cgImageRepresentation() else { return }
        onFrame(cg)
    }
}
#endif
