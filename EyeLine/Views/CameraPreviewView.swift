import SwiftUI
import AVFoundation

/// Hosts the AVCaptureVideoPreviewLayer full-screen behind the teleprompter
/// overlay. Purely a passthrough view onto the live camera feed — it applies
/// no filters or transforms beyond what AVFoundation's preview layer does by
/// default (including the standard mirrored front-camera preview).
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraService

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer = camera.makePreviewLayer()
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let previewLayer {
                    previewLayer.frame = bounds
                    layer.insertSublayer(previewLayer, at: 0)
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
