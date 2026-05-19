import Foundation

let heliusApiKey  = "57682451-258e-45ae-84e4-e666ce11256a"
let solMint       = "So11111111111111111111111111111111111111112"
let nativeSolMint = "So11111111111111111111111111111111111111111"
let solLogoURL    = URL(string: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png")!

func isSolMint(_ mint: String) -> Bool {
    mint == solMint || mint == nativeSolMint
}
