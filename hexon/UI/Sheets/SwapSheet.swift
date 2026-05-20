import SwiftUI
import PrivySDK

struct SwapSheet: View {
    let walletAddress: String
    let network: SolanaNetwork
    var onSuccess: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var inputAsset = "SOL"
    @State private var amountText = ""
    @State private var quote: JupiterQuoteResponse?
    @State private var isFetchingQuote = false
    @State private var isSwapping = false
    @State private var txSignature: String?
    @State private var errorMessage: String?

    private var outputAsset: String { inputAsset == "SOL" ? "USDC" : "SOL" }
    private var amount: Double { Double(amountText) ?? 0 }
    private var canFetchQuote: Bool { amount > 0 && !isFetchingQuote && !isSwapping }
    private var canSwap: Bool { quote != nil && !isSwapping }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let sig = txSignature {
                    successView(signature: sig)
                } else if network.isDevnet {
                    devnetUnavailableView
                } else {
                    formView
                }
            }
            .padding(20)
        }
        .navigationTitle("Swap")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(txSignature != nil)
    }

    private var devnetUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            Text("Mainnet Only")
                .font(.title2.bold())
            Text("Jupiter swaps are only available on mainnet. Switch to mainnet in Settings to use this feature.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: Form

    private var formView: some View {
        VStack(spacing: 16) {
            // Asset direction
            VStack(alignment: .leading, spacing: 8) {
                Text("From").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Text(inputAsset)
                        .font(.headline)
                        .padding(14)
                    Spacer()
                    Button {
                        inputAsset = outputAsset
                        quote = nil
                    } label: {
                        Image(systemName: "arrow.2.squarepath")
                            .foregroundStyle(Color(UIColor.label))
                            .padding(14)
                    }
                    Text(outputAsset)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
                .glassEffect(in: .rect(cornerRadius: 12))
            }

            // Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (\(inputAsset))").font(.footnote).foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 12))
                    .onChange(of: amountText) { _, _ in quote = nil }
            }

            // Get Quote button
            Button {
                Task { await fetchQuote() }
            } label: {
                HStack {
                    if isFetchingQuote { ProgressView().tint(Color(UIColor.label)) }
                    Text(isFetchingQuote ? "Getting Quote…" : "Get Quote")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassEffect(in: .rect(cornerRadius: 12))
            .disabled(!canFetchQuote)

            // Quote card
            if let q = quote {
                quoteCard(q)
            }

            // Warnings
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Swap button
            if quote != nil {
                Button {
                    Task { await swap() }
                } label: {
                    HStack {
                        if isSwapping { ProgressView().tint(Color(UIColor.label)) }
                        Label(isSwapping ? "Swapping…" : "Swap \(inputAsset) → \(outputAsset)", systemImage: "arrow.2.squarepath")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .glassEffect(in: .rect(cornerRadius: 14))
                .disabled(!canSwap)
            }
        }
    }

    private func quoteCard(_ q: JupiterQuoteResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quote").font(.footnote).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                quoteRow("You pay", "\(amountText) \(inputAsset)")
                quoteRow("You receive", "\(q.outAmount) \(outputAsset)")
                quoteRow("Price impact", "\(q.priceImpactPct)%")
                quoteRow("Slippage", "\(q.slippageBps) bps")
                if let warn = q.warning {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warn).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
    }

    private func quoteRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium))
        }
    }

    // MARK: Success

    private func successView(signature: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Swapped!")
                .font(.title.bold())
            Text("Your \(inputAsset) → \(outputAsset) swap has been submitted.")
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

    // MARK: Actions

    private func fetchQuote() async {
        isFetchingQuote = true
        errorMessage = nil
        quote = nil
        do {
            let decimals = inputAsset == "SOL" ? 9 : 6
            let rawAmount = UInt64(amount * pow(10.0, Double(decimals)))
            quote = try await HexonAPI.getSwapQuote(
                walletAddress: walletAddress,
                inputAsset: inputAsset,
                outputAsset: outputAsset,
                amount: String(rawAmount)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isFetchingQuote = false
    }

    private func swap() async {
        isSwapping = true
        errorMessage = nil
        do {
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                errorMessage = "Please open hexon and sign in first."
                isSwapping = false
                return
            }
            let decimals = inputAsset == "SOL" ? 9 : 6
            let rawAmount = UInt64(amount * pow(10.0, Double(decimals)))
            let response = try await HexonAPI.buildSwap(
                walletAddress: walletAddress,
                inputAsset: inputAsset,
                outputAsset: outputAsset,
                amount: String(rawAmount),
                quoteId: quote?.quoteId
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
            errorMessage = error.localizedDescription
        }
        isSwapping = false
    }
}
