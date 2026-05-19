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

                Section("Siri & Shortcuts") {
                    HStack {
                        Label("Transfer Token", systemImage: "arrow.up.circle")
                        Spacer()
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }
                    HStack {
                        Label("Check Balance", systemImage: "dollarsign.circle")
                        Spacer()
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }
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
