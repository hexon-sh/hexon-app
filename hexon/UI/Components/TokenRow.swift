import SwiftUI

struct TokenRow: View {
    let token: TokenBalance
    let jupiterToken: JupiterToken?
    var isDevnet: Bool = false

    private var logoURL: URL? {
        if isSolMint(token.mint) { return solLogoURL }
        return jupiterToken?.logoURL ?? token.logoUri.flatMap { URL(string: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: isDevnet && !isSolMint(token.mint) ? nil : logoURL)
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(token.symbol ?? "—")
                    .font(.headline)
                Text(token.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.4f", token.balance))
                    .font(.subheadline.weight(.medium))
                if !isDevnet, let usd = token.usdValue {
                    Text(usd, format: .currency(code: "USD"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
