import SwiftUI
import PrivySDK

private let useTestWallet = false
private let testWalletAddress = "5cJ9ypegoEt5QaYJig1a3CNHDPLf6UXVgSuHWjLFnFQt"

// MARK: - Root Tab Container

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var walletAddress: String?
    @State private var walletBalances: WalletBalances?
    @State private var jupiterTokens: [String: JupiterToken] = [:]
    @State private var isLoadingWallet = false
    @State private var isLoadingData = false
    @State private var addressBook = AddressBook()
    @AppStorage("selectedNetwork") private var selectedNetworkRaw = SolanaNetwork.mainnet.rawValue

    private var selectedNetwork: SolanaNetwork {
        SolanaNetwork(rawValue: selectedNetworkRaw) ?? .mainnet
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab(
                walletAddress: walletAddress,
                walletBalances: walletBalances,
                jupiterTokens: jupiterTokens,
                isLoading: isLoadingWallet || isLoadingData,
                isDevnet: selectedNetwork.isDevnet,
                onRefresh: { await fetchData() }
            )
            .tabItem { Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house") }
            .tag(0)

            HistoryView(walletAddress: walletAddress, tokenLookup: tokenLookup, jupiterTokens: jupiterTokens)
                .tabItem { Label("History", systemImage: selectedTab == 1 ? "clock.fill" : "clock") }
                .tag(1)

            SettingsView(addressBook: addressBook)
                .tabItem { Label("Settings", systemImage: selectedTab == 2 ? "gearshape.fill" : "gearshape") }
                .tag(2)
        }
        .tint(Color(UIColor.label))
        .task { await loadWalletThenData() }
        .onChange(of: selectedNetworkRaw) { _, _ in
            Task { await fetchData() }
        }
    }

    private func loadWalletThenData() async {
        if useTestWallet {
            walletAddress = testWalletAddress
            await fetchData()
            return
        }
        guard let user = await privy.getUser() else { return }
        isLoadingWallet = true
        do {
            if let existing = user.embeddedSolanaWallets.first {
                walletAddress = existing.address
            } else {
                walletAddress = try await user.createSolanaWallet().address
            }
        } catch {}
        isLoadingWallet = false
        await fetchData()
    }

    var tokenLookup: [String: TokenBalance] {
        Dictionary(uniqueKeysWithValues: walletBalances?.balances.map { ($0.mint, $0) } ?? [])
    }

    private func fetchData() async {
        guard let address = walletAddress else { return }
        let network = selectedNetwork
        isLoadingData = true
        walletBalances = nil
        jupiterTokens = [:]
        async let balances = HeliusAPI.getBalances(address: address, network: network)
        async let history  = HeliusAPI.getHistory(address: address, network: network)
        let (b, h) = (try? await balances, (try? await history) ?? [])
        walletBalances = b
        var mints = Set(b?.balances.map(\.mint) ?? [])
        for tx in h { tx.balanceChanges.forEach { mints.insert($0.mint) } }
        if !mints.isEmpty {
            jupiterTokens = (try? await JupiterAPI.searchTokens(mints: Array(mints), network: network)) ?? [:]
        }
        isLoadingData = false
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    let walletAddress: String?
    let walletBalances: WalletBalances?
    let jupiterTokens: [String: JupiterToken]
    let isLoading: Bool
    let isDevnet: Bool
    let onRefresh: () async -> Void

    @State private var showQR = false
    @State private var showSendAlert = false

    private var allTokens: [TokenBalance] {
        walletBalances?.balances ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroBalance
                    if isDevnet { devnetBanner }
                    actionButtons
                    if !allTokens.isEmpty { tokenList }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showQR = true } label: {
                        Image(systemName: "qrcode")
                    }
                    .disabled(walletAddress == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await onRefresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .sheet(isPresented: $showQR) {
            if let address = walletAddress {
                QRSheet(address: address)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Coming Soon", isPresented: $showSendAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Send functionality will be available soon.")
        }
    }

    // MARK: Hero

    private var heroBalance: some View {
        VStack(spacing: 4) {
            if isLoading && walletBalances == nil {
                ProgressView().padding(.vertical, 32)
            } else if isDevnet {
                Text("Devnet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let sol = walletBalances?.balances.first { isSolMint($0.mint) }
                Text(sol.map { String(format: "%.4f SOL", $0.balance) } ?? "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            } else {
                let usd = walletBalances?.totalUsdValue ?? 0
                Text(usd, format: .currency(code: "USD"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 36)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var devnetBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Devnet Mode — prices unavailable")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    // MARK: Send / Receive

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button { showSendAlert = true } label: {
                Label("Send", systemImage: "arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))

            Button { showQR = true } label: {
                Label("Receive", systemImage: "arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(walletAddress == nil)
        }
    }

    // MARK: Token List

    private var tokenList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tokens")
                .font(.headline)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(allTokens) { token in
                    TokenRow(token: token, jupiterToken: jupiterTokens[token.mint], isDevnet: isDevnet)
                    if token.id != allTokens.last?.id {
                        Divider()
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }
}
