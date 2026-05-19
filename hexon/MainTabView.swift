//
//  MainTabView.swift
//  hexon
//

import SwiftUI
import PrivySDK
import CoreImage.CIFilterBuiltins

// Set to true to use a hardcoded wallet for testing, false to use the Privy wallet
private let useTestWallet = true
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

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab(
                walletAddress: walletAddress,
                walletBalances: walletBalances,
                jupiterTokens: jupiterTokens,
                isLoading: isLoadingWallet || isLoadingData,
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
        isLoadingData = true
        async let balances = HeliusAPI.getBalances(address: address)
        async let history = HeliusAPI.getHistory(address: address)
        let (b, h) = (try? await balances, (try? await history) ?? [])
        walletBalances = b
        var mints = Set(b?.balances.map(\.mint) ?? [])
        for tx in h { tx.balanceChanges.forEach { mints.insert($0.mint) } }
        if !mints.isEmpty {
            jupiterTokens = (try? await JupiterAPI.searchTokens(mints: Array(mints))) ?? [:]
        }
        isLoadingData = false
    }
}

// MARK: - QR Code

func generateQRCode(from string: String) -> UIImage {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return UIImage() }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
    return UIImage(cgImage: cgImage)
}

struct QRSheet: View {
    let address: String
    var body: some View {
        VStack(spacing: 20) {
            Text("Receive")
                .font(.headline)
                .padding(.top, 20)
            Image(uiImage: generateQRCode(from: address))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(16)
                .glassEffect(in: .rect(cornerRadius: 16))
            Text(address)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    let walletAddress: String?
    let walletBalances: WalletBalances?
    let jupiterTokens: [String: JupiterToken]
    let isLoading: Bool
    let onRefresh: () async -> Void

    @State private var showQR = false
    @State private var showSendAlert = false

    private var solToken: TokenBalance? {
        walletBalances?.balances.first { isSolMint($0.mint) }
    }

    private var otherTokens: [TokenBalance] {
        walletBalances?.balances ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroBalance
                    actionButtons
                    if !otherTokens.isEmpty { tokenList }
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
                ForEach(otherTokens) { token in
                    TokenRow(token: token, jupiterToken: jupiterTokens[token.mint])
                    if token.id != otherTokens.last?.id {
                        Divider()
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }

}

// MARK: - Token Row

struct TokenRow: View {
    let token: TokenBalance
    let jupiterToken: JupiterToken?

    private var logoURL: URL? {
        if isSolMint(token.mint) { return solLogoURL }
        return jupiterToken?.logoURL ?? token.logoUri.flatMap { URL(string: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: logoURL)
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
                if let usd = token.usdValue {
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

