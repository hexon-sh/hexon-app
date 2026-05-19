import AppIntents

struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Wallet Balance"
    static var description = IntentDescription(
        "Check the SOL balance in your hexon wallet.",
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

        do {
            let lamports = try await SolanaRPC.getBalance(address: address, network: network)
            let sol = Double(lamports) / 1_000_000_000.0
            return .result(dialog: "Your \(network.rawValue) balance is \(String(format: "%.4f", sol)) SOL.")
        } catch {
            return .result(dialog: "Couldn't fetch balance right now. Try again in a moment.")
        }
    }
}
