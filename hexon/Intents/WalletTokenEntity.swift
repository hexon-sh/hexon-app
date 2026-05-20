import AppIntents

// MARK: - Entity

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

// MARK: - Cache

private enum TokenEntityCache {
    private static let key = "hexon_intent_token_cache"

    struct Row: Codable {
        let id: String
        let symbol: String
        let name: String
        let decimals: Int
        let balance: Double
        let ataAddress: String?
    }

    static func save(_ entities: [WalletTokenEntity]) {
        let rows = entities.map { Row(id: $0.id, symbol: $0.symbol, name: $0.name, decimals: $0.decimals, balance: $0.balance, ataAddress: $0.ataAddress) }
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [WalletTokenEntity] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.map { WalletTokenEntity(id: $0.id, symbol: $0.symbol, name: $0.name, decimals: $0.decimals, balance: $0.balance, ataAddress: $0.ataAddress) }
    }
}

// MARK: - Query

private struct SPLAccountRow {
    let mint: String
    let decimals: Int
    let uiAmount: Double
    let pubkey: String
}

struct WalletTokenQuery: EntityQuery {

    // Called when the shortcut resolves a previously chosen entity by id.
    // Uses the cache first so it never blocks on a network call.
    func entities(for identifiers: [String]) async throws -> [WalletTokenEntity] {
        let cached = TokenEntityCache.load()
        let fromCache = cached.filter { identifiers.contains($0.id) }
        if fromCache.count == identifiers.count { return fromCache }

        // Cache miss — refresh and try again
        let fresh = try await suggestedEntities()
        return fresh.filter { identifiers.contains($0.id) }
    }

    // Called when the user opens the parameter picker or Siri shows suggestions.
    // Fetches live data and updates the cache so entity resolution stays fast.
    func suggestedEntities() async throws -> [WalletTokenEntity] {
        guard let walletAddress = UserDefaults.standard.string(forKey: "hexon_wallet_address"),
              !walletAddress.isEmpty else { return TokenEntityCache.load() }

        let networkRaw = UserDefaults.standard.string(forKey: "selectedNetwork") ?? SolanaNetwork.mainnet.rawValue
        let network = SolanaNetwork(rawValue: networkRaw) ?? .mainnet
        let isDevnet = network.isDevnet

        var result: [WalletTokenEntity] = []

        let lamports = (try? await SolanaRPC.getBalance(address: walletAddress, network: network)) ?? 0
        result.append(WalletTokenEntity(
            id: "SOL",
            symbol: "SOL",
            name: "Solana",
            decimals: 9,
            balance: Double(lamports) / 1_000_000_000.0,
            ataAddress: nil
        ))

        if let accounts = try? await SolanaRPC.getTokenAccounts(owner: walletAddress, network: network) {
            let rows: [SPLAccountRow] = accounts
                .filter { $0.uiAmount > 0 }
                .filter { !isDevnet || $0.mint == network.usdcMint }
                .map { SPLAccountRow(mint: $0.mint, decimals: $0.decimals, uiAmount: $0.uiAmount, pubkey: $0.pubkey) }

            if !rows.isEmpty {
                let mints = rows.map { $0.mint }
                let jupTokens = (!isDevnet ? (try? await JupiterAPI.searchTokens(mints: mints, network: network)) : nil) ?? [:]
                for row in rows {
                    let jup = jupTokens[row.mint]
                    let isDevnetUsdc = isDevnet && row.mint == network.usdcMint
                    result.append(WalletTokenEntity(
                        id: row.mint,
                        symbol: isDevnetUsdc ? "USDC" : (jup?.symbol ?? "\(row.mint.prefix(6))…"),
                        name: isDevnetUsdc ? "USD Coin (Devnet)" : (jup?.name ?? row.mint),
                        decimals: row.decimals,
                        balance: row.uiAmount,
                        ataAddress: row.pubkey
                    ))
                }
            }
        }

        TokenEntityCache.save(result)
        return result
    }
}
