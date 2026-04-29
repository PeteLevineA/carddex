import SwiftUI

#if canImport(VisionKit) && canImport(UIKit)
import VisionKit
import AVFoundation
import UIKit

/// SwiftUI wrapper around `DataScannerViewController` with an AVFoundation
/// fallback for devices that don't support DataScanner. The `onCaptureFrame`
/// closure is called with a stable, debounced still after a card is detected.
public struct CameraScannerView: UIViewControllerRepresentable {

    public var onCaptureFrame: (CGImage) -> Void

    public init(onCaptureFrame: @escaping (CGImage) -> Void) {
        self.onCaptureFrame = onCaptureFrame
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            let vc = DataScannerViewController(
                recognizedDataTypes: [.barcode()],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: true,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
            vc.delegate = context.coordinator
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
        init(onCaptureFrame: @escaping (CGImage) -> Void) { self.onCaptureFrame = onCaptureFrame }

        public func dataScanner(_ dataScanner: DataScannerViewController,
                                didTapOn item: RecognizedItem) {
            // Capture the current camera frame and forward to the scanner pipeline.
            dataScanner.capturePhoto { result in
                if case let .success(photo) = result, let cg = photo.image.cgImage {
                    self.onCaptureFrame(cg)
                }
            }
        }
    }
}

/// Minimal AVFoundation fallback for older devices.
final class AVCaptureViewController: UIViewController {
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
        Task.detached(priority: .userInitiated) { [session] in session.startRunning() }
    }
}
#endif
