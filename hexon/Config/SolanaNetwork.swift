import Foundation

enum SolanaNetwork: String, CaseIterable, Identifiable {
    case mainnet = "Mainnet"
    case devnet  = "Devnet"

    var id: String { rawValue }
    var isDevnet: Bool { self == .devnet }

    var restBase: String {
        switch self {
        case .mainnet: return "https://api.helius.xyz/v1/wallet"
        case .devnet:  return "https://api-devnet.helius.xyz/v1/wallet"
        }
    }

    var wsURL: String {
        switch self {
        case .mainnet: return "wss://mainnet.helius-rpc.com/?api-key=\(heliusApiKey)"
        case .devnet:  return "wss://devnet.helius-rpc.com/?api-key=\(heliusApiKey)"
        }
    }

    var rpcURL: URL {
        switch self {
        case .mainnet: return URL(string: "https://mainnet.helius-rpc.com/?api-key=\(heliusApiKey)")!
        case .devnet:  return URL(string: "https://devnet.helius-rpc.com/?api-key=\(heliusApiKey)")!
        }
    }
}
