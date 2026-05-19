import SwiftUI
import AVFoundation

// MARK: - Camera coordinator

final class QRScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let raw = obj.stringValue else { return }
        onScan?(raw)
    }
}

// MARK: - UIKit camera preview

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct QRCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Scanner view

struct QRScannerView: View {
    var onResult: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var session    = AVCaptureSession()
    @State private var coordinator = QRScannerCoordinator()
    @State private var permissionDenied = false
    @State private var scanned = false

    var body: some View {
        ZStack {
            if permissionDenied {
                deniedView
            } else {
                QRCameraPreview(session: session)
                    .ignoresSafeArea()

                // Viewfinder overlay
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) * 0.65
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .mask(
                                Rectangle()
                                    .ignoresSafeArea()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .frame(width: side, height: side)
                                            .blendMode(.destinationOut)
                                    )
                            )

                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: side, height: side)
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }
                    Spacer()
                    Text("Scan a Solana address QR code")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.bottom, 48)
                }
            }
        }
        .task { await setupCamera() }
        .onDisappear { session.stopRunning() }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.headline)
            Text("Allow camera access in Settings to scan QR codes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { await MainActor.run { permissionDenied = true }; return }
        default:
            await MainActor.run { permissionDenied = true }
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let metaOutput = AVCaptureMetadataOutput()
        session.beginConfiguration()
        if session.canAddInput(input)       { session.addInput(input) }
        if session.canAddOutput(metaOutput) { session.addOutput(metaOutput) }
        metaOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
        if metaOutput.availableMetadataObjectTypes.contains(.qr) {
            metaOutput.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        coordinator.onScan = { [self] raw in
            guard !scanned else { return }
            guard let address = parseSolanaAddress(raw) else { return }
            scanned = true
            session.stopRunning()
            onResult(address)
            dismiss()
        }

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }
}
