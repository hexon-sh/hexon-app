//
//  HistoryView.swift
//  hexon
//

import SwiftUI

// MARK: - WebSocket Manager

@Observable
class WalletWebSocket {
    var isConnected = false
    var onNewActivity: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private let apiKey = "57682451-258e-45ae-84e4-e666ce11256a"

    func connect(address: String) {
        let url = URL(string: "wss://mainnet.helius-rpc.com/?api-key=\(apiKey)")!
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        sendSubscribe(address: address)
        listen()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func sendSubscribe(address: String) {
        let msg = """
        {"jsonrpc":"2.0","id":1,"method":"accountSubscribe","params":["\(address)",{"encoding":"jsonParsed","commitment":"confirmed"}]}
        """
        task?.send(.string(msg)) { _ in }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   text.contains("accountNotification") {
                    DispatchQueue.main.async { self.onNewActivity?() }
                }
                self.listen()
            case .failure:
                self.isConnected = false
            }
        }
    }
}

// MARK: - History View

struct HistoryView: View {
    let walletAddress: String?
    let tokenLookup: [String: TokenBalance]
    let jupiterTokens: [String: JupiterToken]
    @State private var transactions: [WalletTx] = []
    @State private var isLoading = false
    @State private var selectedTx: WalletTx?
    @State private var socket = WalletWebSocket()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transactions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(transactions) { tx in
                                TxRow(tx: tx, tokenLookup: tokenLookup, jupiterTokens: jupiterTokens)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTx = tx }
                                if tx.id != transactions.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
        .sheet(item: $selectedTx) { tx in
            TxDetailSheet(tx: tx, tokenLookup: tokenLookup, jupiterTokens: jupiterTokens)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            guard let address = walletAddress else { return }
            await fetchHistory(address: address)
            socket.onNewActivity = {
                Task { await fetchHistory(address: address) }
            }
            socket.connect(address: address)
        }
        .onDisappear { socket.disconnect() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Transactions")
                .font(.headline)
            Text("Activity will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fetchHistory(address: String) async {
        isLoading = true
        if let txs = try? await HeliusAPI.getHistory(address: address) {
            transactions = txs
        }
        isLoading = false
    }
}

// MARK: - Transaction Row

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
        return jupToken(for: change)?.logoURL ?? token(for: change)?.logoUri.flatMap { URL(string: $0) }
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
                    let symbol = token(for: change)?.symbol ?? change.tokenLabel
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

// MARK: - Transaction Detail Sheet

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
                    // Status card
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

                    // Balance changes
                    if !tx.balanceChanges.isEmpty {
                        sectionHeader("Balance Changes")
                        glassSection {
                            ForEach(Array(tx.balanceChanges.enumerated()), id: \.offset) { idx, change in
                                let jupTok = jupiterTokens[isSolMint(change.mint) ? solMint : change.mint]
                                let helTok = tokenLookup[change.mint]
                                let symbol = jupTok?.symbol ?? helTok?.symbol ?? change.tokenLabel
                                let name = jupTok?.name ?? helTok?.name
                                let logoURL: URL? = isSolMint(change.mint)
                                    ? solLogoURL
                                    : (jupTok?.logoURL ?? helTok?.logoUri.flatMap { URL(string: $0) })
                                if idx > 0 { Divider() }
                                HStack(spacing: 12) {
                                    CachedAsyncImage(url: logoURL)
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(symbol)
                                            .font(.subheadline.weight(.medium))
                                        if let name {
                                            Text(name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
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

                    // Signature
                    sectionHeader("Signature")
                    glassSection {
                        row(label: "Signature") {
                            Text("\(tx.signature.prefix(8))...\(tx.signature.suffix(8))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Explorer
                    Button {
                        UIPasteboard.general.string = explorerURL.absoluteString
                        urlCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            urlCopied = false
                        }
                    } label: {
                        HStack {
                            Label(urlCopied ? "Copied!" : "Copy Explorer URL", systemImage: urlCopied ? "checkmark" : "doc.on.doc")
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
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            value()
        }
        .padding(.vertical, 12)
    }
}
