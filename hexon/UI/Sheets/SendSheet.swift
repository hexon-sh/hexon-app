import SwiftUI
import PrivySDK

// MARK: - Sendable token model

struct SendableToken: Identifiable {
    let id: String          // mint address or "SOL"
    let symbol: String
    let name: String
    let decimals: Int
    let balance: Double     // human-readable
    let logoURL: URL?
    let ataAddress: String? // nil for native SOL
}

// MARK: - Send Sheet

struct SendSheet: View {
    let walletAddress: String
    let walletBalances: WalletBalances?
    let jupiterTokens: [String: JupiterToken]
    let network: SolanaNetwork
    let addressBook: AddressBook
    var prefillAddress: String = ""
    var onSendSuccess: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var recipient   = ""
    @State private var amountText  = ""
    @State private var selectedToken: SendableToken?
    @State private var tokens: [SendableToken] = []
    @State private var isLoadingTokens = false
    @State private var isSending = false
    @State private var txSignature: String?
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var showTokenPicker = false
    @State private var showContactPicker = false

    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool {
        parseSolanaAddress(recipient) != nil && amount > 0 &&
        amount <= (selectedToken?.balance ?? 0) && !isSending
    }

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
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(txSignature != nil)
        .sheet(isPresented: $showScanner) {
            QRScannerView { address in recipient = address }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showTokenPicker) {
            tokenPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showContactPicker) {
            contactPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            recipient = prefillAddress
            await loadTokens()
        }
    }

    // MARK: Form

    private var formView: some View {
        VStack(spacing: 16) {
            // Recipient
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    TextField("Solana address", text: $recipient)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    if UIPasteboard.general.hasStrings {
                        Button {
                            recipient = UIPasteboard.general.string ?? ""
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(Color(UIColor.label))
                        }
                    }
                    if !addressBook.contacts.isEmpty {
                        Button {
                            showContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(Color(UIColor.label))
                        }
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundStyle(Color(UIColor.label))
                    }
                }
                .padding(14)
                .glassEffect(in: .rect(cornerRadius: 12))

                if !recipient.isEmpty, parseSolanaAddress(recipient) == nil {
                    Text("Invalid Solana address")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Token selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Token").font(.footnote).foregroundStyle(.secondary)
                Button { showTokenPicker = true } label: {
                    HStack {
                        if let tok = selectedToken {
                            CachedAsyncImage(url: tok.logoURL)
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tok.symbol).font(.headline)
                                Text(String(format: "%.4f available", tok.balance))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if isLoadingTokens {
                            ProgressView().padding(.vertical, 4)
                        } else {
                            Text("Select token")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .glassEffect(in: .rect(cornerRadius: 12))
                .foregroundStyle(Color(UIColor.label))
            }

            // Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    if let tok = selectedToken {
                        Button("MAX") {
                            amountText = String(format: "%.\(tok.decimals)f", tok.balance)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    }
                }
                .padding(14)
                .glassEffect(in: .rect(cornerRadius: 12))
            }

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Send button
            Button {
                Task { await send() }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(Color(UIColor.label)) }
                    Text(isSending ? "Sending…" : "Send")
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Sent!")
                .font(.title.bold())

            VStack(spacing: 4) {
                Text("Transaction submitted")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.4f %@", amount, selectedToken?.symbol ?? ""))
                    .font(.headline)
                Text("to \(recipient.prefix(8))…\(recipient.suffix(8))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                UIPasteboard.general.string = signature
            } label: {
                Label("Copy Signature", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassEffect(in: .rect(cornerRadius: 12))

            Button("Back to Home") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding(.top, 40)
    }

    // MARK: Token Picker Sheet

    private var tokenPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(tokens) { tok in
                    Button {
                        selectedToken = tok
                        showTokenPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: tok.logoURL)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tok.symbol).font(.headline).foregroundStyle(Color(UIColor.label))
                                Text(String(format: "%.4f", tok.balance))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedToken?.id == tok.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Token")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Contact Picker Sheet

    private var contactPickerSheet: some View {
        NavigationStack {
            List(addressBook.contacts) { contact in
                Button {
                    recipient = contact.address
                    showContactPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.name)
                            .font(.headline)
                            .foregroundStyle(Color(UIColor.label))
                        Text("\(contact.address.prefix(8))…\(contact.address.suffix(8))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Choose Contact")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Load tokens

    private func loadTokens() async {
        isLoadingTokens = true
        var result: [SendableToken] = []

        // Native SOL always first
        if let sol = walletBalances?.balances.first(where: { isSolMint($0.mint) }) {
            result.append(SendableToken(
                id: "SOL",
                symbol: "SOL",
                name: "Solana",
                decimals: 9,
                balance: sol.balance,
                logoURL: solLogoURL,
                ataAddress: nil
            ))
        }

        // SPL tokens — on devnet only include the devnet USDC mint; on mainnet include all
        if let accounts = try? await SolanaRPC.getTokenAccounts(owner: walletAddress, network: network) {
            for account in accounts where account.uiAmount > 0 {
                if network.isDevnet && account.mint != network.usdcMint { continue }
                let jup = jupiterTokens[account.mint]
                let bal = walletBalances?.balances.first { $0.mint == account.mint }
                let isDevnetUsdc = network.isDevnet && account.mint == network.usdcMint
                result.append(SendableToken(
                    id: account.mint,
                    symbol: isDevnetUsdc ? "USDC" : (jup?.symbol ?? bal?.symbol ?? String(account.mint.prefix(6))),
                    name: isDevnetUsdc ? "USD Coin (Devnet)" : (jup?.name ?? bal?.name ?? account.mint),
                    decimals: account.decimals,
                    balance: account.uiAmount,
                    logoURL: isDevnetUsdc ? usdcLogoURL : (jup?.logoURL ?? bal?.logoUri.flatMap { URL(string: $0) }),
                    ataAddress: account.pubkey
                ))
            }
        }

        tokens = result
        selectedToken = result.first
        isLoadingTokens = false
    }

    // MARK: Send

    private func send() async {
        guard let tok = selectedToken,
              let address = parseSolanaAddress(recipient) else { return }
        isSending = true
        errorMessage = nil

        do {
            let blockhash = try await SolanaRPC.getLatestBlockhash(network: network)
            let builtTx: BuiltTransaction

            if tok.id == "SOL" {
                let lamports = UInt64(amount * 1_000_000_000)
                builtTx = try buildSOLTransfer(
                    from: walletAddress,
                    to: address,
                    lamports: lamports,
                    recentBlockhash: blockhash
                )
            } else {
                // Fetch destination ATA from RPC
                guard let srcATA = tok.ataAddress else { throw TxError.missingSourceATA }
                guard let dstAccounts = try? await SolanaRPC.getTokenAccounts(owner: address, network: network),
                      let dstAccount = dstAccounts.first(where: { $0.mint == tok.id })
                else { throw TxError.missingDestATA }

                let rawAmount = UInt64(amount * pow(10.0, Double(tok.decimals)))
                builtTx = try buildSPLTransfer(
                    from: walletAddress,
                    sourceATA: srcATA,
                    destinationATA: dstAccount.pubkey,
                    tokenMint: tok.id,
                    amount: rawAmount,
                    recentBlockhash: blockhash
                )
            }

            // Sign via Privy embedded wallet
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                throw TxError.signingFailed
            }

            // Privy signs the message bytes and returns the transaction signature
            let signedTxBase64 = try await signWithPrivy(wallet: wallet, builtTx: builtTx)

            // Submit — returns immediately on broadcast, not on confirmation
            let signature = try await SolanaRPC.sendTransaction(signedTxBase64, network: network)
            await MainActor.run { txSignature = signature }
            Task { await HexonAPI.recordBroadcast(requestId: UUID().uuidString, signature: signature) }

            // Wait for on-chain confirmation before refreshing balance
            await SolanaRPC.confirmTransaction(signature, network: network)
            await onSendSuccess?()

            // Second refresh a few seconds later in case the first was still propagating
            Task {
                try? await Task.sleep(for: .seconds(4))
                await onSendSuccess?()
            }

        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        isSending = false
    }
}

