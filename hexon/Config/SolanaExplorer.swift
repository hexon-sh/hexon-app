import Foundation

enum SolanaExplorer: String, CaseIterable, Identifiable {
    case solanaExplorer = "Solana Explorer"
    case solscan        = "Solscan"
    case solanaFM       = "Solana FM"
    case orb            = "Orb"

    var id: String { rawValue }

    func txURL(signature: String) -> URL {
        switch self {
        case .solanaExplorer: return URL(string: "https://explorer.solana.com/tx/\(signature)")!
        case .solscan:        return URL(string: "https://solscan.io/tx/\(signature)")!
        case .solanaFM:       return URL(string: "https://solana.fm/tx/\(signature)")!
        case .orb:            return URL(string: "https://orb.helius.dev/tx/\(signature)")!
        }
    }

    func addressURL(address: String, isDevnet: Bool) -> URL {
        let cluster = isDevnet ? "?cluster=devnet" : ""
        switch self {
        case .solanaExplorer: return URL(string: "https://explorer.solana.com/address/\(address)\(cluster)")!
        case .solscan:        return URL(string: "https://solscan.io/account/\(address)\(isDevnet ? "?cluster=devnet" : "")")!
        case .solanaFM:       return URL(string: "https://solana.fm/address/\(address)\(isDevnet ? "?cluster=devnet-solana" : "")")!
        case .orb:            return URL(string: "https://orbmarkets.io/address/\(address)\(isDevnet ? "?cluster=devnet" : "")")!
        }
    }
}
