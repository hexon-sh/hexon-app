//
//  SolanaRPC.swift
//  hexon
//

import Foundation

private let apiKey = "57682451-258e-45ae-84e4-e666ce11256a"
private let base = "https://api.helius.xyz/v1/wallet"

// MARK: - Explorer

enum SolanaExplorer: String, CaseIterable, Identifiable {
    case solanaExplorer = "Solana Explorer"
    case solscan = "Solscan"
    case solanaFM = "Solana FM"
    case orb = "Orb"

    var id: String { rawValue }

    func txURL(signature: String) -> URL {
        switch self {
        case .solanaExplorer: return URL(string: "https://explorer.solana.com/tx/\(signature)")!
        case .solscan:        return URL(string: "https://solscan.io/tx/\(signature)")!
        case .solanaFM:       return URL(string: "https://solana.fm/tx/\(signature)")!
        case .orb:            return URL(string: "https://orb.helius.dev/tx/\(signature)")!
        }
    }
}

// MARK: - Models

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
    var tokenLabel: String { mint == solMint ? "SOL" : "\(mint.prefix(4))...\(mint.suffix(4))" }
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

private struct WalletHistory: Codable {
    let data: [WalletTx]
}

private struct WalletIdentity: Codable {
    let name: String?
    let domainNames: [String]?
}

// MARK: - Jupiter Models

struct JupiterToken: Codable {
    let id: String
    let symbol: String?
    let name: String?
    let icon: String?
    let decimals: Int?

    var logoURL: URL? { icon.flatMap { URL(string: $0) } }
}

// MARK: - Jupiter API

enum JupiterAPI {
    private static let base = "https://api.jup.ag/tokens/v2/search"
    private static let apiKey = "jup_85bcd26efa39c04f7d9e70763be0040d2942b36e5741b569a2ccd8b4f4caecfc"

    static func searchTokens(mints: [String]) async throws -> [String: JupiterToken] {
        guard !mints.isEmpty else { return [:] }
        let nativeSol = "So11111111111111111111111111111111111111111"
        let remapped = mints.map { $0 == nativeSol ? solMint : $0 }
        let unique = Array(Set(remapped))
        var result: [String: JupiterToken] = [:]
        let chunks = stride(from: 0, to: unique.count, by: 100).map {
            Array(unique[$0 ..< min($0 + 100, unique.count)])
        }
        for chunk in chunks {
            let query = chunk.joined(separator: ",")
            guard let url = URL(string: "\(base)?x-api-key=\(apiKey)&query=\(query)") else { continue }
            let (data, _) = try await URLSession.shared.data(from: url)
            let tokens = try JSONDecoder().decode([JupiterToken].self, from: data)
            for token in tokens { result[token.id] = token }
        }
        return result
    }
}

// MARK: - API

let solMint = "So11111111111111111111111111111111111111112"
let nativeSolMint = "So11111111111111111111111111111111111111111"
let solLogoURL = URL(string: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png")!

func isSolMint(_ mint: String) -> Bool {
    mint == solMint || mint == nativeSolMint
}

enum HeliusAPI {
    static func getBalances(address: String) async throws -> WalletBalances {
        let url = URL(string: "\(base)/\(address)/balances?api-key=\(apiKey)&showNfts=false")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WalletBalances.self, from: data)
    }

    static func getHistory(address: String) async throws -> [WalletTx] {
        let url = URL(string: "\(base)/\(address)/history?api-key=\(apiKey)&limit=50&tokenAccounts=balanceChanged")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WalletHistory.self, from: data).data
    }

    static func getIdentity(address: String) async throws -> String? {
        let url = URL(string: "\(base)/\(address)/identity?api-key=\(apiKey)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let identity = try? JSONDecoder().decode(WalletIdentity.self, from: data)
        return identity?.domainNames?.first ?? identity?.name
    }
}
