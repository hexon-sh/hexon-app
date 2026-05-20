import SwiftUI
import PrivySDK

struct UmbraConsentSheet: View {
    var onActivated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var consentMessage: String?
    @State private var isLoadingMessage = true
    @State private var isSigning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                        Text("Umbra Privacy Protocol")
                            .font(.title2.bold())
                        Text("You are about to activate private transactions. Please read and agree to the terms below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    // Consent message
                    Text("Consent & Acknowledgement")
                        .font(.headline)

                    if let msg = consentMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .glassEffect(in: .rect(cornerRadius: 12))
                    } else if isLoadingMessage {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(14)
                    } else {
                        Text("Could not load consent message. Please check your connection.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(14)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Sign button
                    Button {
                        Task { await signAndActivate() }
                    } label: {
                        HStack {
                            if isSigning { ProgressView().tint(Color(UIColor.label)) }
                            Text(isSigning ? "Signing with Wallet…" : "I Agree & Activate")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .glassEffect(in: .rect(cornerRadius: 14))
                    .disabled(isSigning || consentMessage == nil)

                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("Privacy Consent")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadConsentMessage() }
        }
    }

    private func loadConsentMessage() async {
        isLoadingMessage = true
        do {
            consentMessage = try await HexonAPI.fetchUmbraMessageToSign()
        } catch {
            errorMessage = "Failed to load consent message: \(error.localizedDescription)"
        }
        isLoadingMessage = false
    }

    private func signAndActivate() async {
        guard let message = consentMessage else {
            errorMessage = "Consent message not loaded yet."
            return
        }
        isSigning = true
        errorMessage = nil
        do {
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                errorMessage = "No embedded wallet found. Please sign in."
                isSigning = false
                return
            }
            let signature = try await HexonAPI.signUmbraConsentMessage(wallet: wallet, message: message)
            onActivated(signature)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSigning = false
    }
}
