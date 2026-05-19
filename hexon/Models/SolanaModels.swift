import Foundation

struct TokenBalance: Codable, Identifiable {
    var id: String { mint }
    let mint: String
    let symbol: String?
    let name: String?
    let balance: Double
    let decimals: Int
    let pricePerToken: Double?
    let usdValue: Double?
    let logoUri: String?
}

struct WalletBalances: Codable {
    let balances: [TokenBalance]
    let totalUsdValue: Double?
}

struct TxBalanceChange: Codable {
    let mint: String
    let amount: Double
    let decimals: Int

    var humanAmount: Double { amount / (isSol ? 1_000_000_000.0 : pow(10.0, Double(decimals))) }
    var tokenLabel: String { isSolMint(mint) ? "SOL" : "\(mint.prefix(4))...\(mint.suffix(4))" }
    var isSol: Bool { isSolMint(mint) }
}

struct WalletTx: Codable, Identifiable {
    var id: String { signature }
    let signature: String
    let timestamp: Int?
    let fee: Double?
    let error: String?
    let balanceChanges: [TxBalanceChange]
}
