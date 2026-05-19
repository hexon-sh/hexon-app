import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color.secondary.opacity(0.15))
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.image(for: url)
        }
    }
}
