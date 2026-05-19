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
        case .missingDestATA:        return "Recipient has no token account for this token"
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

// MARK: - Little-endian u64

private func u64LE(_ value: UInt64) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

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

    // Account order: sender(signer,writable), recipient(writable), SystemProgram(readonly)
    let keys = [sender, recipient, sysProg]
    // SystemProgram transfer discriminator = 2, then u64 lamports
    let data: [UInt8] = [2, 0, 0, 0] + u64LE(lamports)
    let ix = CompiledInstruction(programIndex: 2, accountIndices: [0, 1], data: data)

    let message = buildMessageV0(
        feePayer: sender,
        accountKeys: keys,
        numSigners: 1,
        numReadonlySigned: 0,
        numReadonlyUnsigned: 1,
        instructions: [ix],
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

    // Account order: src_ata(writable), dst_ata(writable), owner(signer), TokenProgram(readonly)
    let keys = [srcATA, dstATA, sender, tokProg]
    // SPL Token Transfer discriminator = 3, then u64 amount
    let data: [UInt8] = [3] + u64LE(amount)
    let ix = CompiledInstruction(programIndex: 3, accountIndices: [0, 1, 2], data: data)

    let message = buildMessageV0(
        feePayer: sender,
        accountKeys: keys,
        numSigners: 1,
        numReadonlySigned: 0,
        numReadonlyUnsigned: 1,
        instructions: [ix],
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
