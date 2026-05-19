import Foundation

struct JupiterToken: Codable {
    let id: String
    let symbol: String?
    let name: String?
    let icon: String?
    let decimals: Int?

    var logoURL: URL? { icon.flatMap { URL(string: $0) } }
}
