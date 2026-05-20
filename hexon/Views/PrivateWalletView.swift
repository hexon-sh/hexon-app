import SwiftUI
import PrivySDK

struct PrivateWalletView: View {
    let walletAddress: String?
    let network: SolanaNetwork
    let addressBook: AddressBook

    @State private var balances: HexonBalances?
    @State private var isLoading = false
    @State private var isRegistering = false
    @State private var showShield = false
    @State private var showPrivateSend = false
    @State private var showClaim = false
    @State private var showConsentSheet = false
    @State private var appError: AppError?

    @State private var umbraSignature: String?

    // Persisted per wallet address — survives app restart, reset when wallet changes
    private var registeredKey: String {
        "hexon_umbra_registered_\(walletAddress ?? "none")"
    }
    private var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: registeredKey)
    }
    private func markRegistered() {
        UserDefaults.standard.set(true, forKey: registeredKey)
    }

    private var umbraReady: Bool { umbraSignature != nil }
    // Full setup: consent signed + on-chain account exists
    private var fullyReady: Bool { umbraReady && isRegistered }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    balanceCard
                    if network.isDevnet { devnetBanner }
                    if !umbraReady {
                        activatePrivacyCard
                    } else if !isRegistered {
                        registerCard
                    } else {
                        actionButtons
                    }
                    privacyNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await fetchBalances() }
            .navigationTitle("Private")
            .navigationDestination(isPresented: $showShield) {
                ShieldSheet(
                    walletAddress: walletAddress ?? "",
                    umbraSignature: umbraSignature ?? "",
                    network: network,
                    onSuccess: { await fetchBalances() }
                )
            }
            .navigationDestination(isPresented: $showPrivateSend) {
                PrivateSendSheet(
                    walletAddress: walletAddress ?? "",
                    umbraSignature: umbraSignature ?? "",
                    network: network,
                    addressBook: addressBook,
                    onSuccess: { await fetchBalances() }
                )
            }
            .navigationDestination(isPresented: $showClaim) {
                ClaimSheet(
                    walletAddress: walletAddress ?? "",
                    umbraSignature: umbraSignature ?? "",
                    network: network,
                    onSuccess: { await fetchBalances() }
                )
            }
            .task { await fetchBalances() }
            .sheet(isPresented: $showConsentSheet) {
                UmbraConsentSheet { sig in
                    umbraSignature = sig
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $appError) {
                ErrorBottomSheet(error: $0)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Balance Card

    private var balanceCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.purple)
                Text("Private Balance")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(network.isDevnet ? "Devnet" : "Mainnet")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(network.isDevnet ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(network.isDevnet ? .orange : .green)
            }

            if isLoading && balances == nil {
                ProgressView().padding(.vertical, 16)
            } else if let balances {
                HStack(spacing: 32) {
                    ForEach(balances.balances, id: \.asset) { token in
                        VStack(spacing: 2) {
                            Text(token.uiAmount)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text(token.asset)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if balances.balances.isEmpty {
                        Text("No private balance")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    // MARK: Devnet Banner

    private var devnetBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Private transactions on Devnet — test only")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    // MARK: Step 1 — Sign Consent

    private var activatePrivacyCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 1 — Activate Privacy")
                        .font(.headline)
                    Text("Sign the Umbra consent message with your wallet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                showConsentSheet = true
            } label: {
                Text("Review & Sign")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(walletAddress == nil)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: Step 2 — Register On-Chain

    private var registerCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 2 — Create Private Account")
                        .font(.headline)
                    Text("Register your encrypted account on Solana (one-time setup)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                Task { await register() }
            } label: {
                HStack {
                    if isRegistering { ProgressView().tint(Color(UIColor.label)) }
                    Text(isRegistering ? "Creating Account…" : "Create Private Account")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(walletAddress == nil || isRegistering)

            Button {
                umbraSignature = nil
            } label: {
                Text("Start over")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Privacy active")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    umbraSignature = nil
                    UserDefaults.standard.removeObject(forKey: registeredKey)
                } label: {
                    Text("Reset")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 12))

            HStack(spacing: 14) {
                Button { showShield = true } label: {
                    Label("Shield", systemImage: "arrow.down.to.line")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .glassEffect(in: .rect(cornerRadius: 14))
                .disabled(walletAddress == nil)

                Button { showPrivateSend = true } label: {
                    Label("Private Send", systemImage: "lock.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .glassEffect(in: .rect(cornerRadius: 14))
                .disabled(walletAddress == nil)
            }

            Button { showClaim = true } label: {
                Label("Withdraw to Wallet", systemImage: "arrow.up.from.line")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(walletAddress == nil)
        }
    }

    // MARK: Privacy Note

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Powered by Umbra Protocol", systemImage: "eye.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Private transactions are not visible on public explorers. Balances shown here are your encrypted on-chain holdings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    // MARK: Actions

    private func register() async {
        guard let address = walletAddress, let sig = umbraSignature else { return }
        isRegistering = true
        appError = nil
        do {
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                appError = AppError(message: "No embedded wallet found. Please sign in.")
                isRegistering = false
                return
            }
            let response = try await HexonAPI.buildUmbraRegister(
                walletAddress: address,
                umbraSignature: sig
            )
            _ = try await HexonAPI.signAndBroadcastSequential(
                response: response,
                wallet: wallet,
                walletAddress: address,
                network: network
            )
            markRegistered()
            await fetchBalances()
        } catch {
            appError = AppError(from: error)
        }
        isRegistering = false
    }

    private func fetchBalances() async {
        guard let address = walletAddress else { return }
        isLoading = true
        appError = nil
        do {
            balances = try await HexonAPI.getPrivateBalances(address: address)
        } catch {
            appError = AppError(from: error)
        }
        isLoading = false
    }
}
