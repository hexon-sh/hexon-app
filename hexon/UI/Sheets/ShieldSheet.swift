import SwiftUI
import PrivySDK

struct ShieldSheet: View {
    let walletAddress: String
    let umbraSignature: String
    let network: SolanaNetwork
    var onSuccess: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAsset = "SOL"
    @State private var amountText = ""
    @State private var isSending = false
    @State private var txSignature: String?
    @State private var appError: AppError?

    private let assets = ["SOL", "USDC"]
    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool { amount > 0 && !isSending }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let sig = txSignature {
                    successView(signature: sig)
                } else {
                    formView
                }
            }
            .padding(20)
        }
        .navigationTitle("Shield")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(txSignature != nil)
        .sheet(item: $appError) { ErrorBottomSheet(error: $0).presentationDetents([.medium]) }
    }

    // MARK: Form

    private var formView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About Shielding").font(.footnote).foregroundStyle(.secondary)
                Text("Move funds from your public wallet into an encrypted private balance. The transfer will not be visible on block explorers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(assets, id: \.self) { asset in
                        Button {
                            selectedAsset = asset
                        } label: {
                            Text(asset)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(selectedAsset == asset ? Color.purple.opacity(0.2) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedAsset == asset ? .purple : Color(UIColor.label))
                    }
                }
                .glassEffect(in: .rect(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Amount").font(.footnote).foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }


            Button {
                Task { await shield() }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(Color(UIColor.label)) }
                    Label(isSending ? "Shielding…" : "Shield \(selectedAsset)", systemImage: "arrow.down.to.line")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(!isValid)
        }
    }

    // MARK: Success

    private func successView(signature: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.purple)
            Text("Shielded!")
                .font(.title.bold())
            Text("\(String(format: "%.4f", amount)) \(selectedAsset) moved to your private balance.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { UIPasteboard.general.string = signature } label: {
                Label("Copy Signature", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassEffect(in: .rect(cornerRadius: 12))
            Button("Back") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding(.top, 40)
    }

    // MARK: Action

    private func shield() async {
        isSending = true
        appError = nil
        do {
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                appError = AppError(message: "Please open hexon and sign in first.")
                isSending = false
                return
            }
            let lamports = selectedAsset == "SOL"
                ? UInt64(amount * 1_000_000_000)
                : UInt64(amount * 1_000_000)
            let response = try await HexonAPI.buildShield(
                walletAddress: walletAddress,
                asset: selectedAsset,
                amount: String(lamports),
                umbraSignature: umbraSignature
            )
            let sig = try await HexonAPI.signAndBroadcast(
                response: response,
                wallet: wallet,
                walletAddress: walletAddress,
                network: network
            )
            txSignature = sig
            await onSuccess?()
        } catch {
            appError = AppError(from: error)
        }
        isSending = false
    }
}
