import SwiftUI
import PrivySDK

struct PrivateSendSheet: View {
    let walletAddress: String
    let umbraSignature: String
    let network: SolanaNetwork
    let addressBook: AddressBook
    var onSuccess: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var selectedAsset = "SOL"
    @State private var amountText = ""
    @State private var memo = ""
    @State private var isSending = false
    @State private var txSignature: String?
    @State private var appError: AppError?
    @State private var showContactPicker = false

    private let assets = ["SOL", "USDC"]
    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool {
        !recipientAddress.isEmpty &&
        parseSolanaAddress(recipientAddress) != nil &&
        amount > 0 &&
        !isSending
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let sig = txSignature {
                    successView(signature: sig)
                } else {
                    formView
                }
            }
            .padding(20)
        }
        .navigationTitle("Private Send")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(txSignature != nil)
        .sheet(item: $appError) { ErrorBottomSheet(error: $0).presentationDetents([.medium]) }
        .sheet(isPresented: $showContactPicker) {
            NavigationStack {
                List(addressBook.contacts) { contact in
                    Button {
                        recipientAddress = contact.address
                        showContactPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contact.name)
                                .font(.headline)
                                .foregroundStyle(Color(UIColor.label))
                            Text("\(contact.address.prefix(8))…\(contact.address.suffix(8))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .navigationTitle("Choose Contact")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Form

    private var formView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    TextField("Solana address", text: $recipientAddress)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    if !addressBook.contacts.isEmpty {
                        Button {
                            showContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(Color(UIColor.label))
                        }
                    }
                }
                .padding(14)
                .glassEffect(in: .rect(cornerRadius: 12))
                if !recipientAddress.isEmpty, parseSolanaAddress(recipientAddress) == nil {
                    Text("Invalid Solana address")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(assets, id: \.self) { asset in
                        Button { selectedAsset = asset } label: {
                            Text(asset)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(selectedAsset == asset ? Color.purple.opacity(0.2) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedAsset == asset ? .purple : Color(UIColor.label))
                    }
                }
                .glassEffect(in: .rect(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Amount").font(.footnote).foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Memo (optional)").font(.footnote).foregroundStyle(.secondary)
                TextField("Add a private note…", text: $memo)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }


            Button {
                Task { await privateSend() }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(Color(UIColor.label)) }
                    Label(isSending ? "Sending…" : "Private Send", systemImage: "lock.fill")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .glassEffect(in: .rect(cornerRadius: 14))
            .disabled(!isValid)
        }
    }

    // MARK: Success

    private func successView(signature: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.purple)
            Text("Sent Privately!")
                .font(.title.bold())
            Text("Your transfer is encrypted and not visible on public explorers.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { UIPasteboard.general.string = signature } label: {
                Label("Copy Signature", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassEffect(in: .rect(cornerRadius: 12))
            Button("Back") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding(.top, 40)
    }

    // MARK: Action

    private func privateSend() async {
        guard let address = parseSolanaAddress(recipientAddress) else { return }
        isSending = true
        appError = nil
        do {
            guard let user = await privy.getUser(),
                  let wallet = user.embeddedSolanaWallets.first else {
                appError = AppError(message: "Please open hexon and sign in first.")
                isSending = false
                return
            }
            let decimals = selectedAsset == "SOL" ? 9 : 6
            let rawAmount = UInt64(amount * pow(10.0, Double(decimals)))
            let response = try await HexonAPI.buildPrivateSend(
                sender: walletAddress,
                umbraSignature: umbraSignature,
                recipient: address,
                asset: selectedAsset,
                amount: String(rawAmount),
                memo: memo.isEmpty ? nil : memo
            )
            let sig = try await HexonAPI.signAndBroadcast(
                response: response,
                wallet: wallet,
                walletAddress: walletAddress,
                network: network
            )
            txSignature = sig
            await onSuccess?()
        } catch {
            appError = AppError(from: error)
        }
        isSending = false
    }
}
