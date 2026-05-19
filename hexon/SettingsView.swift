//
//  SettingsView.swift
//  hexon
//

import SwiftUI
import PrivySDK

struct SettingsView: View {
    let addressBook: AddressBook
    @State private var showLogoutAlert = false
    @State private var showExplorerPicker = false
    @AppStorage("selectedExplorer") private var selectedExplorer = SolanaExplorer.solanaExplorer.rawValue

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

                Section("Explorer") {
                    Button {
                        showExplorerPicker = true
                    } label: {
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
                        Text("Mainnet")
                            .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showExplorerPicker) {
                ExplorerPickerSheet(selectedExplorer: $selectedExplorer)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
    }
}

// MARK: - Explorer Picker Sheet

struct ExplorerPickerSheet: View {
    @Binding var selectedExplorer: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Block Explorer")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(SolanaExplorer.allCases.enumerated()), id: \.element.id) { idx, explorer in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    Button {
                        selectedExplorer = explorer.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            Text(explorer.rawValue)
                                .foregroundStyle(Color(UIColor.label))
                                .font(.body)
                            Spacer()
                            if selectedExplorer == explorer.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}
