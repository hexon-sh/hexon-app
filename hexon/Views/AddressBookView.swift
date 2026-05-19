import SwiftUI

struct Contact: Codable, Identifiable {
    var id = UUID()
    var name: String
    var address: String
}

@Observable
class AddressBook {
    var contacts: [Contact] = [] {
        didSet { save() }
    }

    init() { load() }

    private func save() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: "hexon_contacts")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "hexon_contacts"),
              let saved = try? JSONDecoder().decode([Contact].self, from: data)
        else { return }
        contacts = saved
    }

    func add(_ contact: Contact) { contacts.append(contact) }

    func update(_ contact: Contact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[idx] = contact
    }

    func delete(at offsets: IndexSet) { contacts.remove(atOffsets: offsets) }
}

struct AddressBookView: View {
    @State var book: AddressBook
    @State private var showAddSheet = false
    @State private var editingContact: Contact?

    var body: some View {
        NavigationStack {
            Group {
                if book.contacts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(book.contacts) { contact in
                            ContactRow(contact: contact, onEdit: { editingContact = contact })
                        }
                        .onDelete { book.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Address Book")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                ContactFormSheet(book: book, existing: nil)
            }
            .sheet(item: $editingContact) { contact in
                ContactFormSheet(book: book, existing: contact)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Contacts Yet")
                .font(.headline)
            Text("Tap + to add a wallet address")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    let onEdit: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.name)
                .font(.headline)
            Text(truncated(contact.address))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button {
                UIPasteboard.general.string = contact.address
                copied = true
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }
}

struct ContactFormSheet: View {
    let book: AddressBook
    let existing: Contact?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet Name") {
                    TextField("e.g. My Trading Wallet", text: $name)
                        .autocapitalization(.words)
                }
                Section("Wallet Address") {
                    TextField("Solana address", text: $address)
                        .autocapitalization(.none)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if isEditing, var updated = existing {
                            updated.name = name
                            updated.address = address
                            book.update(updated)
                        } else {
                            book.add(Contact(name: name, address: address))
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || address.isEmpty)
                }
            }
            .onAppear {
                name = existing?.name ?? ""
                address = existing?.address ?? ""
            }
        }
    }
}
