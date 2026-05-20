import SwiftUI

struct ErrorBottomSheet: View {
    let error: AppError
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var isComingSoon: Bool { error.isUmbraUnavailable }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(UIColor.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Image(systemName: isComingSoon ? "lock.shield.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(isComingSoon ? .purple : .red)

            Text(isComingSoon ? "Coming Soon" : "Error")
                .font(.title3.bold())
                .padding(.top, 12)

            if !isComingSoon, let code = error.code {
                Text(code)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
                    .padding(.top, 8)
            }

            Text(error.userFacingMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                if !isComingSoon {
                    Button {
                        UIPasteboard.general.string = error.copyText
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy Error", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .glassEffect(in: .rect(cornerRadius: 14))
                }

                Button("Dismiss") { dismiss() }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .glassEffect(in: .rect(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
    }
}
