import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.setSession(session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setSession(session)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        configureMirroring()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The preview connection can be created after its session is assigned.
        // Reapply the policy here so Continuity Camera never falls back to its
        // device-dependent automatic mirroring behaviour.
        configureMirroring()
    }

    private func configureMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
