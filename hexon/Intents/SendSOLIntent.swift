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
            title: "\(name)",
            subtitle: "\(address.prefix(6))…\(address.suffix(4))"
        )
    }
}

struct ContactQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ContactEntity] {
        loadContacts().filter { identifiers.contains($0.id) }
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
    static var title: LocalizedStringResource = "Transfer SOL"
    static var description = IntentDescription(
        "Send SOL from your hexon wallet to a saved contact.",
        categoryName: "Wallet"
    )
    static var openAppWhenRun = false

    @Parameter(title: "To", description: "Saved contact to send SOL to")
    var recipient: ContactEntity

    @Parameter(title: "Amount (SOL)", description: "Amount of SOL to send", controlStyle: .field)
    var amount: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let walletAddress = UserDefaults.standard.string(forKey: "hexon_wallet_address"),
              !walletAddress.isEmpty else {
            return .result(dialog: "Open hexon first so your wallet can be loaded, then try again.")
        }

        let networkRaw = UserDefaults.standard.string(forKey: "selectedNetwork") ?? SolanaNetwork.mainnet.rawValue
        let network = SolanaNetwork(rawValue: networkRaw) ?? .mainnet

        let sendLamports = UInt64(amount * 1_000_000_000)
        let balance = (try? await SolanaRPC.getBalance(address: walletAddress, network: network)) ?? 0
        guard balance >= sendLamports + 5_000 else {
            let sol = Double(balance) / 1_000_000_000.0
            return .result(dialog: "Insufficient balance. You have \(String(format: "%.4f", sol)) SOL on \(network.rawValue).")
        }

        try await requestConfirmation(
            actionName: .send,
            dialog: IntentDialog("Send \(String(format: "%.4f", amount)) SOL to \(recipient.name) on \(network.rawValue)?")
        )

        guard let user = await privy.getUser(),
              let wallet = user.embeddedSolanaWallets.first else {
            return .result(dialog: "Please open hexon and make sure you're signed in, then try again.")
        }

        do {
            let blockhash = try await SolanaRPC.getLatestBlockhash(network: network)
            let builtTx = try await MainActor.run {
                try buildSOLTransfer(
                    from: walletAddress,
                    to: recipient.address,
                    lamports: sendLamports,
                    recentBlockhash: blockhash
                )
            }
            let signedTx = try await signWithPrivy(wallet: wallet, builtTx: builtTx)
            let sig = try await SolanaRPC.sendTransaction(signedTx, network: network)
            return .result(dialog: "Sent \(String(format: "%.4f", amount)) SOL to \(recipient.name). Signature: \(sig.prefix(8))…")
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
        case .insufficientBalance: return "Insufficient SOL balance."
        case .message(let m):      return m
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:         return "Open hexon and sign in before using Siri."
        case .insufficientBalance: return "Insufficient SOL balance."
        case .message(let m):      return "\(m)"
        }
    }
}
