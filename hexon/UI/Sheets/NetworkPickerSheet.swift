import SwiftUI

struct NetworkPickerSheet: View {
    @Binding var selectedNetwork: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Network")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(SolanaNetwork.allCases.enumerated()), id: \.element.id) { idx, network in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    Button {
                        selectedNetwork = network.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            Text(network.rawValue)
                                .foregroundStyle(network.isDevnet ? .orange : Color(UIColor.label))
                                .font(.body)
                            Spacer()
                            if selectedNetwork == network.rawValue {
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
