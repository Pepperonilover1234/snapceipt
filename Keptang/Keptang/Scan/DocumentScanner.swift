import AVFoundation
import SwiftUI
import VisionKit

/// Whether the camera can open, and if not, why, so the Scan button always explains itself.
enum CameraGate: Equatable {
    case open
    /// Ask first; iOS shows the permission prompt.
    case ask
    /// No camera on this device, for example the Simulator.
    case unavailable
    /// The person turned camera access off for Snapceipt in Settings.
    case denied
    /// A parent or company setting blocks the camera.
    case restricted

    static func decide(isSupported: Bool, status: AVAuthorizationStatus) -> CameraGate {
        guard isSupported else { return .unavailable }
        switch status {
        case .authorized: return .open
        case .notDetermined: return .ask
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .ask
        }
    }

    static var current: CameraGate {
        decide(isSupported: DocumentScanner.isSupported, status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}

/// Apple's document camera: finds the receipt edges, flattens and cleans up the page automatically.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void = { _ in }

    /// True only where there's a real camera to look through. The Simulator reports the document
    /// camera as supported but has no camera, so it would open a black viewfinder.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return VNDocumentCameraViewController.isSupported && AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
