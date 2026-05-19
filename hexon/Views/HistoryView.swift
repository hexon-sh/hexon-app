import SwiftUI

struct HistoryView: View {
    let walletAddress: String?
    let tokenLookup: [String: TokenBalance]
    let jupiterTokens: [String: JupiterToken]
    @State private var transactions: [WalletTx] = []
    @State private var isLoading = false
    @State private var selectedTx: WalletTx?
    @State private var socket = WalletWebSocket()
    @AppStorage("selectedNetwork") private var selectedNetworkRaw = SolanaNetwork.mainnet.rawValue

    private var selectedNetwork: SolanaNetwork {
        SolanaNetwork(rawValue: selectedNetworkRaw) ?? .mainnet
    }

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
            await connectAndFetch(address: address)
        }
        .onChange(of: selectedNetworkRaw) { _, _ in
            guard let address = walletAddress else { return }
            transactions = []
            Task { await connectAndFetch(address: address) }
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

    private func connectAndFetch(address: String) async {
        let network = selectedNetwork
        await fetchHistory(address: address, network: network)
        socket.onNewActivity = {
            Task { await fetchHistory(address: address, network: network) }
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
