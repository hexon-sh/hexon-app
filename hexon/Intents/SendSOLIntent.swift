import AppIntents
import PrivySDK

// MARK: - Contact Entity

struct ContactEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Contact"
    static var defaultQuery = ContactQuery()

    var id: UUID
    var name: String
    var address: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: "\(address.prefix(6))…\(address.suffix(4))")
        )
    }
}

struct ContactQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ContactEntity] {
        // Load directly from UserDefaults — no network, always fast.
        // Must return every requested identifier or Siri marks the selection as failed.
        let all = loadContacts()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        loadContacts()
    }

    private func loadContacts() -> [ContactEntity] {
        guard let data = UserDefaults.standard.data(forKey: "hexon_contacts"),
              let contacts = try? JSONDecoder().decode([Contact].self, from: data) else {
            return []
        }
        return contacts.map { ContactEntity(id: $0.id, name: $0.name, address: $0.address) }
    }
}

// MARK: - Intent

struct SendSOLIntent: AppIntent {
    static var title: LocalizedStringResource = "Transfer Token"
    static var description = IntentDescription(
        "Send a token from your hexon wallet to a saved contact.",
        categoryName: "Wallet"
    )
    static var openAppWhenRun = false

    // Parameters are declared in prompt order: 1 → token, 2 → recipient, 3 → amount
    @Parameter(title: "Token", description: "Token to send", requestValueDialog: IntentDialog("Which token do you want to send?"))
    var token: WalletTokenEntity

    @Parameter(title: "To", description: "Saved contact to send to", requestValueDialog: IntentDialog("Send to which contact?"))
    var recipient: ContactEntity

    @Parameter(title: "Amount", description: "Amount to send", controlStyle: .field, requestValueDialog: IntentDialog("How much?"))
    var amount: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Transfer \(\.$amount) \(\.$token) to \(\.$recipient)")
    }

    private static func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 9
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let walletAddress = UserDefaults.standard.string(forKey: "hexon_wallet_address"),
              !walletAddress.isEmpty else {
            return .result(dialog: "Open hexon first so your wallet can be loaded, then try again.")
        }

        let networkRaw = UserDefaults.standard.string(forKey: "selectedNetwork") ?? SolanaNetwork.mainnet.rawValue
        let network = SolanaNetwork(rawValue: networkRaw) ?? .mainnet

        // Balance check
        guard amount <= token.balance else {
            return .result(dialog: "Insufficient \(token.symbol) balance. You have \(Self.formatAmount(token.balance)) \(token.symbol).")
        }
        if token.id == "SOL" {
            let lamports = (try? await SolanaRPC.getBalance(address: walletAddress, network: network)) ?? 0
            let sendLamports = UInt64(amount * 1_000_000_000)
            guard lamports >= sendLamports + 5_000 else {
                let sol = Double(lamports) / 1_000_000_000.0
                return .result(dialog: "Insufficient balance. You have \(Self.formatAmount(sol)) SOL (need a little extra for fees).")
            }
        }

        let amountStr = Self.formatAmount(amount)
        try await requestConfirmation(
            actionName: .send,
            dialog: IntentDialog("Send \(amountStr) \(token.symbol) to \(recipient.name) on \(network.rawValue)?")
        )

        guard let user = await privy.getUser(),
              let wallet = user.embeddedSolanaWallets.first else {
            return .result(dialog: "Please open hexon and make sure you're signed in, then try again.")
        }

        do {
            let blockhash = try await SolanaRPC.getLatestBlockhash(network: network)
            let builtTx: BuiltTransaction

            if token.id == "SOL" {
                let lamports = UInt64(amount * 1_000_000_000)
                builtTx = try await MainActor.run {
                    try buildSOLTransfer(
                        from: walletAddress,
                        to: recipient.address,
                        lamports: lamports,
                        recentBlockhash: blockhash
                    )
                }
            } else {
                guard let srcATA = token.ataAddress else {
                    return .result(dialog: "No \(token.symbol) token account found in your wallet.")
                }
                guard let dstAccounts = try? await SolanaRPC.getTokenAccounts(owner: recipient.address, network: network) else {
                    return .result(dialog: "\(recipient.name) doesn't have a \(token.symbol) token account. They need to receive \(token.symbol) first.")
                }
                guard let dstPubkey = await MainActor.run(body: {
                    dstAccounts.first(where: { $0.mint == token.id })?.pubkey
                }) else {
                    return .result(dialog: "\(recipient.name) doesn't have a \(token.symbol) token account. They need to receive \(token.symbol) first.")
                }
                let rawAmount = UInt64(amount * pow(10.0, Double(token.decimals)))
                builtTx = try await MainActor.run {
                    try buildSPLTransfer(
                        from: walletAddress,
                        sourceATA: srcATA,
                        destinationATA: dstPubkey,
                        tokenMint: token.id,
                        amount: rawAmount,
                        recentBlockhash: blockhash
                    )
                }
            }

            let signedTx = try await signWithPrivy(wallet: wallet, builtTx: builtTx)
            let sig = try await SolanaRPC.sendTransaction(signedTx, network: network)
            return .result(dialog: "Sent \(amountStr) \(token.symbol) to \(recipient.name). Signature: \(sig.prefix(8))…")
        } catch {
            return .result(dialog: "Transfer failed. Open hexon and try sending from there.")
        }
    }

}

// MARK: - Intent Error

enum IntentError: Swift.Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case insufficientBalance
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:         return "Open hexon and sign in before using Siri."
        case .insufficientBalance: return "Insufficient balance."
        case .message(let m):      return m
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:         return "Open hexon and sign in before using Siri."
        case .insufficientBalance: return "Insufficient balance."
        case .message(let m):      return "\(m)"
        }
    }
}
