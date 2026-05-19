import SwiftUI
import CoreImage.CIFilterBuiltins

func generateQRCode(from string: String) -> UIImage {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return UIImage() }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
    return UIImage(cgImage: cgImage)
}

struct QRSheet: View {
    let address: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Receive")
                .font(.headline)
                .padding(.top, 20)
            Image(uiImage: generateQRCode(from: address))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(16)
                .glassEffect(in: .rect(cornerRadius: 16))
            Text(address)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
