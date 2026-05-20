import Foundation
import UIKit
import PrivySDK

// MARK: - Response Models

struct TxBuildResponse: Decodable {
    let requestId: String
    let network: String
    let action: String
    let unsignedTransactionBase64: String
    let lastValidBlockHeight: Int?
    let expiresAt: String?
    let rpcUrl: String
    let warnings: [String]
}

struct UmbraMultiTxBuildResponse: Decodable {
    let requestIds: [String]
    let network: String
    let action: String
    let unsignedTransactionsBase64: [String]
    let rpcUrl: String
    let warnings: [String]
}

struct HexonBalances: Decodable {
    let walletAddress: String
    let network: String
    let balances: [HexonTokenBalance]
}

struct HexonTokenBalance: Decodable {
    let asset: String   // "SOL" | "USDC"
    let mint: String
    let amount: String  // base units as string
    let decimals: Int
    let uiAmount: String
}

struct JupiterQuoteResponse: Decodable {
    let quoteId: String
    let network: String
    let inputAsset: String
    let outputAsset: String
    let inAmount: String
    let outAmount: String
    let priceImpactPct: String
    let slippageBps: Int
    let expiresAt: String
    let warning: String?
}

// MARK: - Errors

enum HexonError: LocalizedError {
    case invalidTransaction
    case invalidURL
    case httpError(Int, String, String?)   // statusCode, message, errorCode
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidTransaction:            return "Could not decode transaction from server."
        case .invalidURL:                    return "Invalid backend URL."
        case .httpError(let c, let m, _):    return "Server error \(c): \(m)"
        case .decodingError(let m):          return "Response decode error: \(m)"
        }
    }
}

// MARK: - Structured Error (for UI presentation)

struct AppError: Identifiable {
    let id = UUID()
    let code: String?
    let message: String

    var copyText: String { code.map { "[\($0)] \(message)" } ?? message }

    var isUmbraUnavailable: Bool {
        guard let code else { return false }
        return code.hasPrefix("UMBRA_")
    }

    var userFacingMessage: String { message }

    init(code: String? = nil, message: String) {
        self.code = code
        self.message = message
    }

    init(from error: Error) {
        if let h = error as? HexonError, case let .httpError(_, msg, code) = h {
            self.code = code
            self.message = msg
        } else {
            self.code = nil
            self.message = error.localizedDescription
        }
    }
}

// MARK: - API Client

enum HexonAPI {

    // MARK: Transaction Decoder

    /// Extracts the message bytes from a serialized VersionedTransaction for Privy signing.
    /// Parses the compact-u16 signature count from the wire format so it works for any
    /// number of signers (Jupiter may return 1 or 2).
    ///
    /// Wire format: [compact-u16 numSigs][numSigs × 64-byte sig slots][message...]
    static func decodeBackendTransaction(_ base64: String, signerAddress: String) -> BuiltTransaction? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        // Parse compact-u16
        var numSigs = 0
        var headerLen = 0
        let b0 = bytes[0]
        if b0 & 0x80 == 0 {
            numSigs = Int(b0); headerLen = 1
        } else if bytes.count > 1 {
            let b1 = bytes[1]
            numSigs = Int(b0 & 0x7f) | (Int(b1 & 0x7f) << 7)
            headerLen = b1 & 0x80 == 0 ? 2 : 3
        } else { return nil }

        let msgOffset = headerLen + numSigs * 64
        guard bytes.count > msgOffset else { return nil }
        let messageBytes = Data(bytes[msgOffset...])
        return BuiltTransaction(
            messageBytes: messageBytes,
            unsignedBase64: base64,
            signerAddress: signerAddress
        )
    }

    // MARK: Sign + Broadcast (shared helper for all backend-built txs)

    static func signAndBroadcast(
        response: TxBuildResponse,
        wallet: EmbeddedSolanaWallet,
        walletAddress: String,
        network: SolanaNetwork
    ) async throws -> String {
        guard let builtTx = decodeBackendTransaction(response.unsignedTransactionBase64, signerAddress: walletAddress) else {
            throw HexonError.invalidTransaction
        }
        let signedTx = try await signWithPrivy(wallet: wallet, builtTx: builtTx)
        let sig = try await SolanaRPC.sendTransaction(signedTx, network: network)
        await recordBroadcast(requestId: response.requestId, signature: sig)
        return sig
    }

    /// Sign and broadcast multiple sequential transactions (e.g. Umbra registration).
    static func signAndBroadcastSequential(
        response: UmbraMultiTxBuildResponse,
        wallet: EmbeddedSolanaWallet,
        walletAddress: String,
        network: SolanaNetwork
    ) async throws -> [String] {
        var signatures: [String] = []
        for (index, base64) in response.unsignedTransactionsBase64.enumerated() {
            guard let builtTx = decodeBackendTransaction(base64, signerAddress: walletAddress) else {
                throw HexonError.invalidTransaction
            }
            let signedTx = try await signWithPrivy(wallet: wallet, builtTx: builtTx)
            let sig = try await SolanaRPC.sendTransaction(signedTx, network: network)
            if index < response.requestIds.count {
                await recordBroadcast(requestId: response.requestIds[index], signature: sig)
            }
            signatures.append(sig)
        }
        return signatures
    }

    /// Sign the Umbra consent message with the embedded Solana wallet.
    /// `message` must be the exact string fetched from GET /v1/umbra/message-to-sign.
    /// Returns the base64-encoded 64-byte Ed25519 signature.
    static func signUmbraConsentMessage(wallet: EmbeddedSolanaWallet, message: String) async throws -> String {
        let messageBytes = Data(message.utf8)
        let messageBase64 = messageBytes.base64EncodedString()
        let signatureBase64 = try await wallet.provider.signMessage(message: messageBase64)
        guard let signatureData = Data(base64Encoded: signatureBase64),
              signatureData.count == 64 else {
            throw HexonError.invalidTransaction
        }
        return signatureBase64
    }

    // MARK: Session

    static func syncSession(walletAddress: String) async {
        struct Body: Encodable {
            let walletAddress: String
            let deviceId: String
        }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        _ = try? await postRaw("/v1/session/sync", body: Body(walletAddress: walletAddress, deviceId: deviceId))
    }

    // MARK: Balances

    static func getPrivateBalances(address: String) async throws -> HexonBalances {
        try await get("/v1/balances/\(address)")
    }

    // MARK: Umbra

    static func fetchUmbraMessageToSign() async throws -> String {
        struct Response: Decodable { let message: String }
        let r: Response = try await get("/v1/umbra/message-to-sign")
        return r.message
    }

    static func buildUmbraRegister(walletAddress: String, umbraSignature: String, confidential: Bool = true, anonymous: Bool = false) async throws -> UmbraMultiTxBuildResponse {
        struct Body: Encodable { let walletAddress, umbraSignature: String; let confidential, anonymous: Bool }
        return try await post("/v1/umbra/register/build", body: Body(walletAddress: walletAddress, umbraSignature: umbraSignature, confidential: confidential, anonymous: anonymous))
    }

    static func buildShield(walletAddress: String, asset: String, amount: String, umbraSignature: String) async throws -> TxBuildResponse {
        struct Body: Encodable { let walletAddress, asset, amount, umbraSignature: String }
        return try await post("/v1/umbra/shield/build", body: Body(walletAddress: walletAddress, asset: asset, amount: amount, umbraSignature: umbraSignature))
    }

    static func buildPrivateSend(
        sender: String,
        umbraSignature: String,
        recipient: String,
        asset: String,
        amount: String,
        memo: String? = nil
    ) async throws -> TxBuildResponse {
        struct Body: Encodable {
            let senderWalletAddress, umbraSignature, recipientWalletAddress, asset, amount: String
            let memo: String?
        }
        return try await post("/v1/umbra/private-send/build", body: Body(
            senderWalletAddress: sender,
            umbraSignature: umbraSignature,
            recipientWalletAddress: recipient,
            asset: asset,
            amount: amount,
            memo: memo
        ))
    }

    static func buildClaim(walletAddress: String, umbraSignature: String, asset: String, amount: String, destinationAddress: String? = nil) async throws -> TxBuildResponse {
        struct Body: Encodable {
            let walletAddress, umbraSignature, asset, amount: String
            let destinationAddress: String?
        }
        return try await post("/v1/umbra/claim/build", body: Body(walletAddress: walletAddress, umbraSignature: umbraSignature, asset: asset, amount: amount, destinationAddress: destinationAddress))
    }

    // MARK: Jupiter

    static func getSwapQuote(walletAddress: String, inputAsset: String, outputAsset: String, amount: String) async throws -> JupiterQuoteResponse {
        struct Body: Encodable { let walletAddress, inputAsset, outputAsset, amount: String }
        return try await post("/v1/jupiter/quote", body: Body(walletAddress: walletAddress, inputAsset: inputAsset, outputAsset: outputAsset, amount: amount))
    }

    static func buildSwap(walletAddress: String, inputAsset: String, outputAsset: String, amount: String, quoteId: String? = nil) async throws -> TxBuildResponse {
        struct Body: Encodable { let walletAddress, inputAsset, outputAsset, amount: String; let quoteId: String? }
        return try await post("/v1/jupiter/swap/build", body: Body(walletAddress: walletAddress, inputAsset: inputAsset, outputAsset: outputAsset, amount: amount, quoteId: quoteId))
    }

    // MARK: Transaction Recording

    static func recordBroadcast(requestId: String, signature: String) async {
        struct Body: Encodable { let requestId, signature: String }
        _ = try? await postRaw("/v1/tx/record-broadcast", body: Body(requestId: requestId, signature: signature))
    }

    static func getTxStatus(requestId: String) async throws -> TxStatusResponse {
        try await get("/v1/tx/\(requestId)")
    }

    // MARK: HTTP Helpers

    private static func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let data = try await postRaw(path, body: body)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HexonError.decodingError(error.localizedDescription)
        }
    }

    @discardableResult
    private static func postRaw<Body: Encodable>(_ path: String, body: Body) async throws -> Data {
        guard let url = URL(string: AppConfig.backendBaseURL + path) else { throw HexonError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let userId = await privy.getUser()?.id {
            req.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw HexonError.httpError(http.statusCode, extractErrorMessage(from: data), extractErrorCode(from: data))
        }
        return data
    }

    private static func get<Response: Decodable>(_ path: String) async throws -> Response {
        guard let url = URL(string: AppConfig.backendBaseURL + path) else { throw HexonError.invalidURL }
        var req = URLRequest(url: url)
        if let userId = await privy.getUser()?.id {
            req.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw HexonError.httpError(http.statusCode, extractErrorMessage(from: data), extractErrorCode(from: data))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HexonError.decodingError(error.localizedDescription)
        }
    }
}

// MARK: - Supporting Response Types

struct TxStatusResponse: Decodable {
    let requestId: String
    let signature: String?
    let status: String
    let slot: Int?
    let error: String?
}

// MARK: - JSON Error Parsing

private struct BackendErrorBody: Decodable {
    struct Inner: Decodable { let code: String?; let message: String }
    let error: Inner
}

private func extractErrorCode(from data: Data) -> String? {
    (try? JSONDecoder().decode(BackendErrorBody.self, from: data))?.error.code
}

private func extractErrorMessage(from data: Data) -> String {
    if let parsed = try? JSONDecoder().decode(BackendErrorBody.self, from: data) {
        return parsed.error.message
    }
    return String(data: data, encoding: .utf8) ?? "Unknown error"
}
