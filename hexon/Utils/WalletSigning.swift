import Foundation
import PrivySDK

// Signs a built transaction with a Privy embedded wallet and returns the signed base64 tx.
func signWithPrivy(wallet: EmbeddedSolanaWallet, builtTx: BuiltTransaction) async throws -> String {
    let messageBase64 = builtTx.messageBytes.base64EncodedString()
    let signatureBase64 = try await wallet.provider.signMessage(message: messageBase64)
    guard let signatureData = Data(base64Encoded: signatureBase64),
          signatureData.count == 64 else {
        throw TxError.signingFailed
    }
    guard let signedTx = attachSignature(
        unsignedBase64: builtTx.unsignedBase64,
        signature: signatureData
    ) else { throw TxError.signingFailed }
    return signedTx
}

// Resolves a contact name or raw Solana address to (address, displayName).
// Checks address book first (exact then partial match), then falls back to raw address validation.
func resolveRecipient(_ input: String) -> (address: String, displayName: String)? {
    if let data = UserDefaults.standard.data(forKey: "hexon_contacts"),
       let contacts = try? JSONDecoder().decode([Contact].self, from: data) {
        if let match = contacts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(input) == .orderedSame
        }) {
            return (match.address, match.name)
        }
        if let match = contacts.first(where: {
            $0.name.localizedCaseInsensitiveContains(input)
        }) {
            return (match.address, match.name)
        }
    }
    if let address = parseSolanaAddress(input) {
        return (address, "\(address.prefix(6))…\(address.suffix(4))")
    }
    return nil
}
