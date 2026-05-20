import SwiftUI
import PrivySDK
import AppIntents

struct SettingsView: View {
    let addressBook: AddressBook
    @State private var showLogoutAlert = false
    @State private var showExplorerPicker = false
    @State private var showNetworkPicker = false
    @AppStorage("selectedExplorer") private var selectedExplorer = SolanaExplorer.solanaExplorer.rawValue
    @AppStorage("selectedNetwork") private var selectedNetwork = SolanaNetwork.mainnet.rawValue
    @ViewBuilder
    private func shortcutRow(icon: String, color: Color, title: String, phrase: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(phrase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Wallet") {
                    NavigationLink {
                        AddressBookView(book: addressBook)
                    } label: {
                        Label("Address Book", systemImage: "book")
                    }
                }

                Section("Network") {
                    Button { showNetworkPicker = true } label: {
                        HStack {
                            Label("Network", systemImage: "network")
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            Text(selectedNetwork)
                                .foregroundStyle(selectedNetwork == SolanaNetwork.devnet.rawValue ? .orange : .secondary)
                                .font(.subheadline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Explorer") {
                    Button { showExplorerPicker = true } label: {
                        HStack {
                            Label("Block Explorer", systemImage: "globe")
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            Text(selectedExplorer)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    shortcutRow(
                        icon: "arrow.up.circle.fill",
                        color: .blue,
                        title: "Transfer Token",
                        phrase: "\"Transfer token with hexon\""
                    )
                    shortcutRow(
                        icon: "dollarsign.circle.fill",
                        color: .green,
                        title: "Check Balance",
                        phrase: "\"Check my hexon balance\""
                    )
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text("Say these phrases to Siri, or open Shortcuts to customise and add to your Home Screen.")
                }

                Section("Account") {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                    }
                }

                Section("App") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Network") {
                        Text(selectedNetwork).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    Task { await privy.getUser()?.logout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
            .sheet(isPresented: $showNetworkPicker) {
                NetworkPickerSheet(selectedNetwork: $selectedNetwork)
                    .presentationDetents([.height(220)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $showExplorerPicker) {
                ExplorerPickerSheet(selectedExplorer: $selectedExplorer)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
    }
}
