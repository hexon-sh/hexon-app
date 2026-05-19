import SwiftUI

struct TxDetailSheet: View {
    let tx: WalletTx
    let tokenLookup: [String: TokenBalance]
    let jupiterTokens: [String: JupiterToken]
    @State private var urlCopied = false
    @AppStorage("selectedExplorer") private var selectedExplorerRaw = SolanaExplorer.solanaExplorer.rawValue

    private var explorerURL: URL {
        let explorer = SolanaExplorer(rawValue: selectedExplorerRaw) ?? .solanaExplorer
        return explorer.txURL(signature: tx.signature)
    }

    private var explorerName: String {
        SolanaExplorer(rawValue: selectedExplorerRaw)?.rawValue ?? "Explorer"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    glassSection {
                        row(label: "Status") {
                            Text(tx.error == nil ? "Success" : "Failed")
                                .foregroundStyle(tx.error == nil ? .green : .red)
                                .fontWeight(.medium)
                        }
                        if let ts = tx.timestamp {
                            Divider()
                            row(label: "Date") {
                                Text(Date(timeIntervalSince1970: TimeInterval(ts)),
                                     format: .dateTime.day().month().year().hour().minute())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let fee = tx.fee {
                            Divider()
                            row(label: "Fee") {
                                Text(String(format: "%.6f SOL", fee / 1_000_000_000.0))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !tx.balanceChanges.isEmpty {
                        sectionHeader("Balance Changes")
                        glassSection {
                            ForEach(Array(tx.balanceChanges.enumerated()), id: \.offset) { idx, change in
                                let jupTok  = jupiterTokens[isSolMint(change.mint) ? solMint : change.mint]
                                let helTok  = tokenLookup[change.mint]
                                let symbol  = jupTok?.symbol ?? helTok?.symbol ?? change.tokenLabel
                                let name    = jupTok?.name ?? helTok?.name
                                let logoURL: URL? = isSolMint(change.mint)
                                    ? solLogoURL
                                    : (jupTok?.logoURL ?? helTok?.logoUri.flatMap { URL(string: $0) })
                                if idx > 0 { Divider() }
                                HStack(spacing: 12) {
                                    CachedAsyncImage(url: logoURL)
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(symbol).font(.subheadline.weight(.medium))
                                        if let name {
                                            Text(name).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(String(format: "%+.6f", change.humanAmount))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(change.humanAmount > 0 ? .green : .red)
                                }
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    sectionHeader("Signature")
                    glassSection {
                        row(label: "Signature") {
                            Text("\(tx.signature.prefix(8))...\(tx.signature.suffix(8))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        UIPasteboard.general.string = explorerURL.absoluteString
                        urlCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            urlCopied = false
                        }
                    } label: {
                        HStack {
                            Label(urlCopied ? "Copied!" : "Copy Explorer URL",
                                  systemImage: urlCopied ? "checkmark" : "doc.on.doc")
                                .font(.headline)
                                .foregroundStyle(urlCopied ? .green : Color(UIColor.label))
                            Spacer()
                        }
                        .padding(16)
                    }
                    .glassEffect(in: .rect(cornerRadius: 14))
                    .animation(.easeInOut, value: urlCopied)

                    Link(destination: explorerURL) {
                        HStack {
                            Label("View on \(explorerName)", systemImage: "arrow.up.right.square")
                                .font(.headline)
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                        }
                        .padding(16)
                    }
                    .glassEffect(in: .rect(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func glassSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func row<Content: View>(label: String, @ViewBuilder value: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            value()
        }
        .padding(.vertical, 12)
    }
}
