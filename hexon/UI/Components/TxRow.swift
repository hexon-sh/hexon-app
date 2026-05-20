import SwiftUI

struct TxRow: View {
    let tx: WalletTx
    let tokenLookup: [String: TokenBalance]
    let jupiterTokens: [String: JupiterToken]

    private var primaryChange: TxBalanceChange? { tx.balanceChanges.first }
    private var isIncoming: Bool { (primaryChange?.humanAmount ?? 0) > 0 }
    private var hasError: Bool { tx.error != nil }

    private func token(for change: TxBalanceChange) -> TokenBalance? { tokenLookup[change.mint] }
    private func jupToken(for change: TxBalanceChange) -> JupiterToken? { jupiterTokens[change.mint] }

    private func logoURL(for change: TxBalanceChange) -> URL? {
        if change.isSol { return solLogoURL }
        let tok = token(for: change)
        if tok?.symbol?.uppercased() == "SOL" { return solLogoURL }
        return jupToken(for: change)?.logoURL ?? tok?.logoUri.flatMap { URL(string: $0) }
    }

    var body: some View {
        HStack(spacing: 14) {
            tokenIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let change = primaryChange, let tok = token(for: change), !change.isSol {
                    Text(tok.name ?? tok.symbol ?? change.tokenLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let ts = tx.timestamp {
                    Text(Date(timeIntervalSince1970: TimeInterval(ts)), style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let change = primaryChange {
                    let symbol = change.isSol ? "SOL" : (token(for: change)?.symbol ?? change.tokenLabel)
                    Text(String(format: "%+.4f %@", change.humanAmount, symbol))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasError ? .red : (isIncoming ? .green : .red))
                }
                if let ts = tx.timestamp {
                    Text(Date(timeIntervalSince1970: TimeInterval(ts)), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var tokenIcon: some View {
        ZStack {
            if let change = primaryChange, let url = logoURL(for: change) {
                CachedAsyncImage(url: url)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())

                Circle()
                    .fill(hasError ? Color.red : (isIncoming ? Color.green : Color.red))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: hasError ? "xmark" : (isIncoming ? "arrow.down" : "arrow.up"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: 13, y: 13)
            } else {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: 42, height: 42)
    }

    private var title: String {
        if hasError { return "Failed" }
        return isIncoming ? "Received" : "Sent"
    }

    private var iconName: String {
        if hasError { return "xmark.circle" }
        return isIncoming ? "arrow.down" : "arrow.up"
    }

    private var iconColor: Color {
        if hasError { return .red }
        return isIncoming ? .green : .red
    }
}
