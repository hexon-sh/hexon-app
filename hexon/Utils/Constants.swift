import Foundation

let heliusApiKey     = "57682451-258e-45ae-84e4-e666ce11256a"
let solMint          = "So11111111111111111111111111111111111111112"
let nativeSolMint    = "So11111111111111111111111111111111111111111"
let mainnetUsdcMint  = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
let devnetUsdcMint   = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"
let solLogoURL       = URL(string: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png")!
let usdcLogoURL      = URL(string: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png")!

// Solana program IDs
let systemProgramId      = "11111111111111111111111111111111"
let tokenProgramId       = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
let assocTokenProgId     = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1brs"
let computeBudgetProgId  = "ComputeBudget111111111111111111111111111111"

func isSolMint(_ mint: String) -> Bool {
    mint == solMint || mint == nativeSolMint
}

// Parse a Solana address from a raw string or solana: URI
func parseSolanaAddress(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidate = trimmed
    if let colonIdx = trimmed.range(of: "solana:") {
        candidate = String(trimmed[colonIdx.upperBound...])
    }
    // Strip query string if present
    if let q = candidate.firstIndex(of: "?") { candidate = String(candidate[..<q]) }
    // Basic Solana pubkey validation: base58, 32–44 chars
    let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    guard candidate.count >= 32, candidate.count <= 44,
          candidate.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) else { return nil }
    return candidate
}
