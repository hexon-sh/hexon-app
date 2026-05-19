import SwiftUI

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
