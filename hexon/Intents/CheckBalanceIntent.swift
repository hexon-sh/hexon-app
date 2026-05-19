import AppIntents

struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Wallet Balance"
    static var description = IntentDescription(
        "Check the balance in your hexon wallet.",
        categoryName: "Wallet"
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let address = UserDefaults.standard.string(forKey: "hexon_wallet_address"),
              !address.isEmpty else {
            return .result(dialog: "Open hexon first so your wallet can be loaded.")
        }

        let networkRaw = UserDefaults.standard.string(forKey: "selectedNetwork") ?? SolanaNetwork.mainnet.rawValue
        let network = SolanaNetwork(rawValue: networkRaw) ?? .mainnet
        let isDevnet = await MainActor.run { network.isDevnet }

        do {
            if isDevnet {
                let lamports = try await SolanaRPC.getBalance(address: address, network: network)
                let sol = Double(lamports) / 1_000_000_000.0
                return .result(dialog: "Your Devnet balance is \(String(format: "%.4f", sol)) SOL.")
            } else {
                let balances = try await HeliusAPI.getBalances(address: address, network: network)
                let usd = balances.totalUsdValue ?? 0
                let formatted = String(format: "$%.2f", usd)
                return .result(dialog: "Your wallet balance is \(formatted).")
            }
        } catch {
            return .result(dialog: "Couldn't fetch balance right now. Try again in a moment.")
        }
    }
}
