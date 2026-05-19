import AppIntents

struct WalletTokenEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Token"
    static var defaultQuery = WalletTokenQuery()

    var id: String        // "SOL" or mint address
    var symbol: String
    var name: String
    var decimals: Int
    var balance: Double
    var ataAddress: String? // nil for native SOL

    var displayRepresentation: DisplayRepresentation {
        let balStr = String(format: "%.4f", balance)
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: symbol),
            subtitle: LocalizedStringResource(stringLiteral: "\(balStr) available · \(name)")
        )
    }
}

private struct SPLAccountRow {
    let mint: String
    let decimals: Int
    let uiAmount: Double
    let pubkey: String
}

struct WalletTokenQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WalletTokenEntity] {
        let all = try await suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WalletTokenEntity] {
        guard let walletAddress = UserDefaults.standard.string(forKey: "hexon_wallet_address"),
              !walletAddress.isEmpty else { return [] }

        let networkRaw = UserDefaults.standard.string(forKey: "selectedNetwork") ?? SolanaNetwork.mainnet.rawValue
        let network = SolanaNetwork(rawValue: networkRaw) ?? .mainnet
        let isDevnet = await MainActor.run { network.isDevnet }

        var result: [WalletTokenEntity] = []

        // SOL always first
        let lamports = (try? await SolanaRPC.getBalance(address: walletAddress, network: network)) ?? 0
        result.append(WalletTokenEntity(
            id: "SOL",
            symbol: "SOL",
            name: "Solana",
            decimals: 9,
            balance: Double(lamports) / 1_000_000_000.0,
            ataAddress: nil
        ))

        guard !isDevnet,
              let accounts = try? await SolanaRPC.getTokenAccounts(owner: walletAddress, network: network) else {
            return result
        }

        // Extract @MainActor-isolated properties on the main actor
        let rows: [SPLAccountRow] = await MainActor.run {
            accounts
                .filter { $0.uiAmount > 0 }
                .map { SPLAccountRow(mint: $0.mint, decimals: $0.decimals, uiAmount: $0.uiAmount, pubkey: $0.pubkey) }
        }

        guard !rows.isEmpty else { return result }

        let mints = rows.map { $0.mint }
        let jupTokens = (try? await JupiterAPI.searchTokens(mints: mints, network: network)) ?? [:]

        for row in rows {
            let jup = jupTokens[row.mint]
            result.append(WalletTokenEntity(
                id: row.mint,
                symbol: jup?.symbol ?? "\(row.mint.prefix(6))…",
                name: jup?.name ?? row.mint,
                decimals: row.decimals,
                balance: row.uiAmount,
                ataAddress: row.pubkey
            ))
        }

        return result
    }
}
