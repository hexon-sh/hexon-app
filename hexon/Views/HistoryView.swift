import SwiftUI

struct HistoryView: View {
    let walletAddress: String?
    let tokenLookup: [String: TokenBalance]
    let jupiterTokens: [String: JupiterToken]
    var onActivity: (() async -> Void)? = nil
    @State private var transactions: [WalletTx] = []
    @State private var isLoading = false
    @State private var selectedTx: WalletTx?
    @State private var socket = WalletWebSocket()
    @AppStorage("selectedNetwork") private var selectedNetworkRaw = SolanaNetwork.mainnet.rawValue
    @AppStorage("selectedExplorer") private var selectedExplorerRaw = SolanaExplorer.solanaExplorer.rawValue

    private var selectedNetwork: SolanaNetwork {
        SolanaNetwork(rawValue: selectedNetworkRaw) ?? .mainnet
    }

    private var selectedExplorer: SolanaExplorer {
        SolanaExplorer(rawValue: selectedExplorerRaw) ?? .solanaExplorer
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedNetwork.isDevnet {
                    devnetExplorerView
                } else if isLoading && transactions.isEmpty {
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
                    .refreshable {
                        guard let address = walletAddress else { return }
                        await fetchHistory(address: address, network: selectedNetwork)
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
            guard let address = walletAddress, !selectedNetwork.isDevnet else { return }
            await connectAndFetch(address: address)
        }
        .onChange(of: selectedNetworkRaw) { _, _ in
            transactions = []
            socket.disconnect()
            guard let address = walletAddress, !selectedNetwork.isDevnet else { return }
            Task { await connectAndFetch(address: address) }
        }
        .onDisappear { socket.disconnect() }
    }

    private var devnetExplorerView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                Text("Devnet Mode")
                    .font(.title2.bold())
                Text("Transaction history is not available on devnet. View your wallet activity on the explorer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let address = walletAddress,
               let url = Optional(selectedExplorer.addressURL(address: address, isDevnet: true)) {
                Link(destination: url) {
                    Label("View on \(selectedExplorer.rawValue)", systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .glassEffect(in: .rect(cornerRadius: 14))
                .padding(.horizontal, 32)

                Text(address.prefix(8) + "…" + address.suffix(8))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func connectAndFetch(address: String) async {
        let network = selectedNetwork
        await fetchHistory(address: address, network: network)
        socket.onNewActivity = { [self] in
            Task {
                await fetchHistory(address: address, network: network)
                await onActivity?()
            }
        }
        socket.connect(address: address, network: network)
    }

    private func fetchHistory(address: String, network: SolanaNetwork) async {
        isLoading = true
        if let txs = try? await HeliusAPI.getHistory(address: address, network: network) {
            transactions = txs
        }
        isLoading = false
    }
}
