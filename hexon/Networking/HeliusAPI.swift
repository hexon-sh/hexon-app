import Foundation

private struct WalletHistory: Codable {
    let data: [WalletTx]
}

private struct WalletIdentity: Codable {
    let name: String?
    let domainNames: [String]?
}

enum HeliusAPI {
    static func getBalances(address: String, network: SolanaNetwork) async throws -> WalletBalances {
        let url = URL(string: "\(network.restBase)/\(address)/balances?api-key=\(heliusApiKey)&showNfts=false")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WalletBalances.self, from: data)
    }

    static func getHistory(address: String, network: SolanaNetwork) async throws -> [WalletTx] {
        let url = URL(string: "\(network.restBase)/\(address)/history?api-key=\(heliusApiKey)&limit=50&tokenAccounts=balanceChanged")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WalletHistory.self, from: data).data
    }

    static func getIdentity(address: String, network: SolanaNetwork) async throws -> String? {
        let url = URL(string: "\(network.restBase)/\(address)/identity?api-key=\(heliusApiKey)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let identity = try? JSONDecoder().decode(WalletIdentity.self, from: data)
        return identity?.domainNames?.first ?? identity?.name
    }
}
