import Foundation

enum JupiterAPI {
    private static let base   = "https://api.jup.ag/tokens/v2/search"
    private static let apiKey = "jup_85bcd26efa39c04f7d9e70763be0040d2942b36e5741b569a2ccd8b4f4caecfc"

    static func searchTokens(mints: [String], network: SolanaNetwork) async throws -> [String: JupiterToken] {
        guard !mints.isEmpty, !network.isDevnet else { return [:] }
        let remapped = mints.map { isSolMint($0) ? solMint : $0 }
        let unique   = Array(Set(remapped))
        var result: [String: JupiterToken] = [:]
        let chunks = stride(from: 0, to: unique.count, by: 100).map {
            Array(unique[$0 ..< min($0 + 100, unique.count)])
        }
        for chunk in chunks {
            let query = chunk.joined(separator: ",")
            guard let url = URL(string: "\(base)?x-api-key=\(apiKey)&query=\(query)") else { continue }
            let (data, _) = try await URLSession.shared.data(from: url)
            let tokens = try JSONDecoder().decode([JupiterToken].self, from: data)
            for token in tokens { result[token.id] = token }
        }
        return result
    }
}
