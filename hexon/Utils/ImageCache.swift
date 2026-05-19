import UIKit
import CryptoKit

actor ImageCache {
    static let shared = ImageCache()

    private let mem = NSCache<NSString, UIImage>()
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("token_img", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = mem.object(forKey: key) { return hit }

        let file = dir.appendingPathComponent(fileKey(for: url))
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            mem.setObject(img, forKey: key)
            return img
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        mem.setObject(img, forKey: key)
        try? data.write(to: file)
        return img
    }

    private func fileKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
