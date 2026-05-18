//
//  ContentView.swift
//  hexon
//
//  Created by CodeParth on 18/05/26.
//

import SwiftUI
import PrivySDK

// MARK: - Root

struct ContentView: View {
    @State private var authState: AuthState = .notReady

    var body: some View {
        Group {
            switch authState {
            case .authenticated:
                HomeView()
            case .notReady:
                ProgressView()
            default:
                LoginView()
            }
        }
        .task {
            for await state in privy.authStateStream {
                authState = state
            }
        }
    }
}

// MARK: - OTP Box Input

struct OTPBoxInput: View {
    @Binding var code: String
    let length = 6
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field capturing input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .focused($isFocused)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(length))
                }

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    let char = character(at: index)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                index == code.count ? Color(UIColor.label) : Color(UIColor.separator),
                                lineWidth: index == code.count ? 2 : 1
                            )
                            .frame(width: 46, height: 54)
                            .glassEffect(in: .rect(cornerRadius: 10))

                        Text(char)
                            .font(.title2.bold())
                            .foregroundStyle(Color(UIColor.label))
                    }
                }
            }
            .onTapGesture { isFocused = true }
        }
        .onAppear { isFocused = true }
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }
}

// MARK: - Login

enum LoginStep { case email, otp }

struct LoginView: View {
    @State private var step: LoginStep = .email
    @State private var email = ""
    @State private var otp = ""
    @State private var isEmailLoading = false
    @State private var isGoogleLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top — title (email step) or OTP content
            VStack(spacing: 40) {
                Spacer().frame(height: 60)

                VStack(spacing: 6) {
                    Text("hexon")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                }

                if step == .otp {
                    otpStep
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            // Bottom — email input + Google (email step only)
            if step == .email {
                VStack(spacing: 16) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    emailStep

                    divider

                    googleButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 0 {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
        )
    }

    // MARK: Email step

    private var emailStep: some View {
        VStack(spacing: 12) {
            TextField("Enter your email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .glassEffect(in: .rect(cornerRadius: 12))

            primaryButton(title: "Continue with Email", isLoading: isEmailLoading,
                          disabled: email.isEmpty || isGoogleLoading) {
                Task { await sendEmailCode() }
            }
        }
    }

    // MARK: OTP step

    private var otpStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Check your inbox")
                    .font(.headline)
                Text("We sent a code to \(email)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            OTPBoxInput(code: $otp)

            primaryButton(title: "Verify", isLoading: isEmailLoading,
                          disabled: otp.count < 6 || isGoogleLoading) {
                Task { await verifyOtp() }
            }

            Button("Use a different email") {
                step = .email; otp = ""; errorMessage = nil
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onChange(of: otp) { _, new in
            if new.count == 6 { Task { await verifyOtp() } }
        }
    }

    // MARK: Google button

    private var googleButton: some View {
        Button {
            Task { await loginWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if isGoogleLoading {
                    ProgressView().tint(Color(UIColor.label))
                } else {
                    Image("GoogleLogin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                Text("Continue With Google")
                    .font(.headline)
                    .foregroundStyle(Color(UIColor.label))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .glassEffect(in: .rect(cornerRadius: 14))
        .disabled(isGoogleLoading || isEmailLoading)
    }

    // MARK: Shared

    private func primaryButton(title: String, isLoading: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(Color(UIColor.label)) }
                Text(title).font(.headline)
                    .foregroundStyle(Color(UIColor.label))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .glassEffect(in: .rect(cornerRadius: 14))
        .disabled(disabled || isLoading)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().frame(height: 0.5).foregroundStyle(.secondary.opacity(0.4))
            Text("or").font(.footnote).foregroundStyle(.secondary)
            Rectangle().frame(height: 0.5).foregroundStyle(.secondary.opacity(0.4))
        }
    }

    // MARK: Actions

    private func sendEmailCode() async {
        isEmailLoading = true; errorMessage = nil
        do {
            try await privy.email.sendCode(to: email)
            step = .otp
        } catch { errorMessage = error.localizedDescription }
        isEmailLoading = false
    }

    private func verifyOtp() async {
        guard otp.count == 6, !isEmailLoading else { return }
        isEmailLoading = true; errorMessage = nil
        do { _ = try await privy.email.loginWithCode(otp, sentTo: email) }
        catch { errorMessage = error.localizedDescription }
        isEmailLoading = false
    }

    private func loginWithGoogle() async {
        isGoogleLoading = true; errorMessage = nil
        do { _ = try await privy.oAuth.login(with: OAuthProvider.google, appUrlScheme: "hexon") }
        catch { errorMessage = error.localizedDescription }
        isGoogleLoading = false
    }
}

// MARK: - Home

struct HomeView: View {
    @State private var walletAddress: String?
    @State private var isLoadingWallet = false
    @State private var walletError: String?
    @State private var copied = false
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                walletCard
                    .padding(.horizontal, 24)

                Spacer()

                Button {
                    showLogoutAlert = true
                } label: {
                    Text("Log out")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .glassEffect(in: .rect(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("hexon")
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    Task { await privy.getUser()?.logout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
        .task { await loadOrCreateWallet() }
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Solana Wallet", systemImage: "wallet.bifold")
                .font(.headline)

            if isLoadingWallet {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 8)
            } else if let address = walletAddress {
                Text(address)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = address
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy Address",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(copied ? .green : Color(UIColor.label))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .glassEffect(in: .rect(cornerRadius: 10))
                .animation(.easeInOut, value: copied)
            } else if let error = walletError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private func loadOrCreateWallet() async {
        guard let user = await privy.getUser() else { return }
        isLoadingWallet = true
        walletError = nil
        do {
            if let existing = user.embeddedSolanaWallets.first {
                walletAddress = existing.address
            } else {
                walletAddress = try await user.createSolanaWallet().address
            }
        } catch { walletError = error.localizedDescription }
        isLoadingWallet = false
    }
}

#Preview {
    ContentView()
}
