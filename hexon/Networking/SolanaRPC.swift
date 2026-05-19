import Foundation

// MARK: - JSON-RPC plumbing

private struct RPCRequest<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id       = 1
    let method: String
    let params: P
}

private struct RPCResponse<R: Decodable>: Decodable {
    let result: R?
    let error: RPCError?
}

private struct RPCError: Decodable, LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { "RPC \(code): \(message)" }
}

private func rpc<P: Encodable, R: Decodable>(
    method: String, params: P, network: SolanaNetwork
) async throws -> R {
    var req = URLRequest(url: network.rpcURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(RPCRequest(method: method, params: params))
    let (data, _) = try await URLSession.shared.data(for: req)
    let response = try JSONDecoder().decode(RPCResponse<R>.self, from: data)
    if let err = response.error { throw err }
    guard let result = response.result else { throw URLError(.badServerResponse) }
    return result
}

// MARK: - getLatestBlockhash

private struct BlockhashResponse: Decodable {
    let value: BlockhashValue
    struct BlockhashValue: Decodable {
        let blockhash: String
        let lastValidBlockHeight: Int
    }
}

// MARK: - getTokenAccountsByOwner

struct TokenAccountInfo: Decodable {
    let pubkey: String
    let account: AccountInfo

    struct AccountInfo: Decodable {
        let data: ParsedData
        struct ParsedData: Decodable {
            let parsed: Parsed
            struct Parsed: Decodable {
                let info: Info
                struct Info: Decodable {
                    let mint: String
                    let tokenAmount: TokenAmount
                    struct TokenAmount: Decodable {
                        let amount: String
                        let decimals: Int
                        let uiAmount: Double?
                    }
                }
            }
        }
    }

    var mint: String { account.data.parsed.info.mint }
    var decimals: Int { account.data.parsed.info.tokenAmount.decimals }
    var uiAmount: Double { account.data.parsed.info.tokenAmount.uiAmount ?? 0 }
    var rawAmount: UInt64 { UInt64(account.data.parsed.info.tokenAmount.amount) ?? 0 }
}

private struct TokenAccountsResponse: Decodable {
    let value: [TokenAccountInfo]
}

// MARK: - Public API

enum SolanaRPC {
    static func getLatestBlockhash(network: SolanaNetwork) async throws -> String {
        let response: BlockhashResponse = try await rpc(
            method: "getLatestBlockhash",
            params: [["commitment": "confirmed"]],
            network: network
        )
        return response.value.blockhash
    }

    static func getTokenAccounts(owner: String, network: SolanaNetwork) async throws -> [TokenAccountInfo] {
        let params: [AnyCodable] = [
            AnyCodable(owner),
            AnyCodable(["programId": tokenProgramId]),
            AnyCodable(["encoding": "jsonParsed"])
        ]
        let response: TokenAccountsResponse = try await rpc(
            method: "getTokenAccountsByOwner",
            params: params,
            network: network
        )
        return response.value
    }

    static func getBalance(address: String, network: SolanaNetwork) async throws -> UInt64 {
        struct BalanceResponse: Decodable { let value: UInt64 }
        let response: BalanceResponse = try await rpc(
            method: "getBalance",
            params: [AnyCodable(address), AnyCodable(["commitment": "confirmed"])],
            network: network
        )
        return response.value
    }

    static func sendTransaction(_ base64Tx: String, network: SolanaNetwork) async throws -> String {
        let params: [AnyCodable] = [
            AnyCodable(base64Tx),
            AnyCodable(["encoding": "base64", "preflightCommitment": "confirmed"])
        ]
        return try await rpc(method: "sendTransaction", params: params, network: network)
    }

    // Polls getSignatureStatuses until the tx reaches "confirmed" or times out (20s).
    static func confirmTransaction(_ signature: String, network: SolanaNetwork) async {
        struct TxStatus: Decodable {
            let confirmationStatus: String?
        }
        struct StatusValue: Decodable {
            let value: [TxStatus?]
        }

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(800))
            let params: [AnyCodable] = [
                AnyCodable([signature]),
                AnyCodable(["searchTransactionHistory": false])
            ]
            guard let response = try? await rpc(
                method: "getSignatureStatuses",
                params: params,
                network: network
            ) as StatusValue else { continue }
            if let status = response.value.first,
               let s = status,
               s.confirmationStatus == "confirmed" || s.confirmationStatus == "finalized" {
                return
            }
        }
    }
}

// MARK: - AnyCodable helper

struct AnyCodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { _encode = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
