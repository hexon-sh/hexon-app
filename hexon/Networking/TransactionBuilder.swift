import Foundation

// MARK: - Errors

enum TxError: LocalizedError {
    case invalidAddress(String)
    case missingSourceATA
    case missingDestATA
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let a): return "Invalid address: \(a)"
        case .missingSourceATA:      return "You don't have a token account for this token"
        case .missingDestATA:        return "The recipient doesn't have a wallet set up for this token yet. They need to receive or create a token account first."
        case .signingFailed:         return "Transaction signing failed"
        }
    }
}

// MARK: - Compact-U16 encoding (Solana wire format)

private func compactU16(_ value: Int) -> [UInt8] {
    var val = value
    var out: [UInt8] = []
    repeat {
        var b = UInt8(val & 0x7f)
        val >>= 7
        if val != 0 { b |= 0x80 }
        out.append(b)
    } while val != 0
    return out
}

private func encodeCompactArray(_ arrays: [[UInt8]]) -> [UInt8] {
    var out = compactU16(arrays.count)
    for a in arrays { out += a }
    return out
}

// MARK: - Address → bytes

private func pubkey(_ address: String) throws -> [UInt8] {
    guard let bytes = Base58.decodeToBytes(address), bytes.count == 32 else {
        throw TxError.invalidAddress(address)
    }
    return bytes
}

// MARK: - Little-endian helpers

private func u64LE(_ value: UInt64) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

private func u32LE(_ value: UInt32) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

// MARK: - Compute Budget instructions
// Included in every transaction for reliable mainnet inclusion.

private let computeUnitLimit: UInt32 = 200_000
private let computeUnitPrice: UInt64 = 5_000  // microLamports per CU

// SetComputeUnitLimit (discriminator 2)
private func setComputeUnitLimitData() -> [UInt8] { [2] + u32LE(computeUnitLimit) }
// SetComputeUnitPrice (discriminator 3)
private func setComputeUnitPriceData() -> [UInt8] { [3] + u64LE(computeUnitPrice) }

// MARK: - MessageV0 builder

private struct CompiledInstruction {
    let programIndex: UInt8
    let accountIndices: [UInt8]
    let data: [UInt8]

    func encode() -> [UInt8] {
        var out = [programIndex]
        out += compactU16(accountIndices.count) + accountIndices
        out += compactU16(data.count) + data
        return out
    }
}

private func buildMessageV0(
    feePayer: [UInt8],
    accountKeys: [[UInt8]],
    numSigners: Int,
    numReadonlySigned: Int,
    numReadonlyUnsigned: Int,
    instructions: [CompiledInstruction],
    recentBlockhash: [UInt8]
) -> [UInt8] {
    // MessageV0 prefix: 0x80 = version prefix byte, then version 0
    var msg: [UInt8] = [0x80]
    // Header
    msg += [UInt8(numSigners), UInt8(numReadonlySigned), UInt8(numReadonlyUnsigned)]
    // Static account keys
    msg += compactU16(accountKeys.count)
    for key in accountKeys { msg += key }
    // Recent blockhash
    msg += recentBlockhash
    // Instructions
    msg += compactU16(instructions.count)
    for ix in instructions { msg += ix.encode() }
    // Address table lookups (none)
    msg += compactU16(0)
    return msg
}

// MARK: - Assemble versioned transaction (unsigned placeholder)

private func assembleTransaction(message: [UInt8]) -> [UInt8] {
    // [compact-u16: 1 signature] + [64 zero bytes] + [message]
    return compactU16(1) + [UInt8](repeating: 0, count: 64) + message
}

// MARK: - Public build functions

struct BuiltTransaction {
    let messageBytes: Data     // bytes Privy needs to sign
    let unsignedBase64: String // full tx with zero signature, base64 for display/debug
    let signerAddress: String
}

/// SOL native transfer (both mainnet and devnet)
func buildSOLTransfer(
    from senderAddress: String,
    to recipientAddress: String,
    lamports: UInt64,
    recentBlockhash: String
) throws -> BuiltTransaction {
    guard let blockhashBytes = Base58.decodeToBytes(recentBlockhash), blockhashBytes.count == 32 else {
        throw TxError.invalidAddress("blockhash")
    }
    let sender    = try pubkey(senderAddress)
    let recipient = try pubkey(recipientAddress)
    let sysProg   = try pubkey(systemProgramId)
    let cbProg    = try pubkey(computeBudgetProgId)

    // Account order:
    //   0: sender        — signer, writable (fee payer)
    //   1: recipient     — writable unsigned
    //   2: SystemProgram — readonly unsigned
    //   3: ComputeBudget — readonly unsigned
    let keys = [sender, recipient, sysProg, cbProg]

    let ixLimit   = CompiledInstruction(programIndex: 3, accountIndices: [], data: setComputeUnitLimitData())
    let ixPrice   = CompiledInstruction(programIndex: 3, accountIndices: [], data: setComputeUnitPriceData())
    let ixTransfer = CompiledInstruction(
        programIndex: 2,
        accountIndices: [0, 1],
        data: [2, 0, 0, 0] + u64LE(lamports)   // SystemProgram::Transfer discriminator
    )

    let message = buildMessageV0(
        feePayer: sender,
        accountKeys: keys,
        numSigners: 1,
        numReadonlySigned: 0,
        numReadonlyUnsigned: 2,   // SystemProgram + ComputeBudget
        instructions: [ixLimit, ixPrice, ixTransfer],
        recentBlockhash: blockhashBytes
    )
    let txBytes = assembleTransaction(message: message)
    return BuiltTransaction(
        messageBytes: Data(message),
        unsignedBase64: Data(txBytes).base64EncodedString(),
        signerAddress: senderAddress
    )
}

/// SPL token transfer — uses pre-fetched source and destination ATA pubkeys
func buildSPLTransfer(
    from senderAddress: String,
    sourceATA: String,
    destinationATA: String,
    tokenMint: String,
    amount: UInt64,
    recentBlockhash: String
) throws -> BuiltTransaction {
    guard let blockhashBytes = Base58.decodeToBytes(recentBlockhash), blockhashBytes.count == 32 else {
        throw TxError.invalidAddress("blockhash")
    }
    let sender  = try pubkey(senderAddress)
    let srcATA  = try pubkey(sourceATA)
    let dstATA  = try pubkey(destinationATA)
    let tokProg = try pubkey(tokenProgramId)
    let cbProg  = try pubkey(computeBudgetProgId)

    // Account order — sender MUST be first (index 0) as the sole signer / fee payer:
    //   0: sender        — signer, writable (authority + fee payer)
    //   1: srcATA        — writable unsigned
    //   2: dstATA        — writable unsigned
    //   3: TokenProgram  — readonly unsigned
    //   4: ComputeBudget — readonly unsigned
    let keys = [sender, srcATA, dstATA, tokProg, cbProg]

    let ixLimit    = CompiledInstruction(programIndex: 4, accountIndices: [], data: setComputeUnitLimitData())
    let ixPrice    = CompiledInstruction(programIndex: 4, accountIndices: [], data: setComputeUnitPriceData())
    let ixTransfer = CompiledInstruction(
        programIndex: 3,
        accountIndices: [1, 2, 0],              // srcATA, dstATA, authority(sender)
        data: [3] + u64LE(amount)               // SPL Token::Transfer discriminator
    )

    let message = buildMessageV0(
        feePayer: sender,
        accountKeys: keys,
        numSigners: 1,
        numReadonlySigned: 0,
        numReadonlyUnsigned: 2,   // TokenProgram + ComputeBudget
        instructions: [ixLimit, ixPrice, ixTransfer],
        recentBlockhash: blockhashBytes
    )
    let txBytes = assembleTransaction(message: message)
    return BuiltTransaction(
        messageBytes: Data(message),
        unsignedBase64: Data(txBytes).base64EncodedString(),
        signerAddress: senderAddress
    )
}

/// Attach a 64-byte signature to an unsigned transaction base64 string
func attachSignature(unsignedBase64: String, signature: Data) -> String? {
    guard var txBytes = Data(base64Encoded: unsignedBase64) else { return nil }
    guard signature.count == 64 else { return nil }
    // Replace the zero signature at offset 1 (after compact-u16 = [0x01])
    let sigOffset = 1
    txBytes.replaceSubrange(sigOffset ..< sigOffset + 64, with: signature)
    return txBytes.base64EncodedString()
}
