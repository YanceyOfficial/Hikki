import ImageIO
import SwiftUI

/// A page's cover as a band (Home's gallery cards): a built-in gradient, or a picture filling the band at its stored
/// vertical position. Pictures load off the main thread, scaled down to the size drawn, and stay in memory for the
/// run (`CoverImageLoader`), so scrolling back past a card draws it at once; meanwhile the band is the muted surface.
public struct PageCoverView: View {
    public enum Art: Hashable, Sendable {
        case gradient(CoverGradient)
        /// A picture — a file in the workspace or a web address — and where it sits vertically (0 = its top shows,
        /// 100 = its bottom), as the editor stores it.
        case image(URL, position: Double)
    }

    let art: Art
    /// The widest the band is drawn, in points: pictures are decoded at this size (times the screen's scale).
    let width: CGFloat

    public init(_ art: Art, width: CGFloat = Size.homeCard * 2) {
        self.art = art
        self.width = width
    }

    public var body: some View {
        switch art {
        case .gradient(let gradient):
            Rectangle().fill(gradient.gradient).accessibilityHidden(true)
        case .image(let url, let position):
            CoverPicture(url: url, position: position, width: width).accessibilityHidden(true)
        }
    }
}

/// A picture cover: the muted surface until it has loaded, then the picture fading in.
private struct CoverPicture: View {
    let url: URL
    let position: Double
    let width: CGFloat
    @State private var loaded: CoverBitmap?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let bitmap {
                picture(bitmap.image, in: proxy.size).transition(.opacity)
            }
        }
        .background(Theme.muted)
        .clipped()
        .animation(Motion.easeOut(), value: bitmap != nil)
        .task(id: key) {
            guard CoverImageLoader.cached(key) == nil else { return }
            let result = await CoverImageLoader.load(url, maxPixels: maxPixels)
            guard !Task.isCancelled else { return }
            loaded = result
        }
    }

    private var maxPixels: Int { Int(width * max(displayScale, 1)) }

    private var key: String { CoverImageLoader.key(url, maxPixels: maxPixels) }

    /// What has loaded for this address and size — already in the cache when the card was shown before.
    private var bitmap: CoverBitmap? {
        if let loaded, loaded.key == key { return loaded }
        return CoverImageLoader.cached(key)
    }

    /// The picture scaled to fill the band, its overflow placed as the editor's `background-position: 50% y%` does.
    private func picture(_ image: CGImage, in size: CGSize) -> some View {
        let imageWidth = CGFloat(max(image.width, 1))
        let imageHeight = CGFloat(max(image.height, 1))
        let scale = max(size.width / imageWidth, size.height / imageHeight)
        let drawn = CGSize(width: imageWidth * scale, height: imageHeight * scale)
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: drawn.width, height: drawn.height)
            .offset(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) * CGFloat(min(100, max(0, position)) / 100))
    }
}

/// A decoded cover picture, as the loader hands it over (a class, so the cache can hold it).
nonisolated final class CoverBitmap: @unchecked Sendable {
    let key: String
    let image: CGImage

    init(key: String, image: CGImage) {
        self.key = key
        self.image = image
    }
}

/// Loads cover pictures for `PageCoverView`: a file through ImageIO, a web address through the shared URL session
/// (its HTTP cache) — both decoded off the main thread as thumbnails no larger than they are drawn, kept in a memory
/// cache by address and size. A picture that can't be loaded is remembered for the run and not tried again.
nonisolated enum CoverImageLoader {
    private nonisolated final class Failure {}

    nonisolated(unsafe) private static let images: NSCache<NSString, CoverBitmap> = {
        let cache = NSCache<NSString, CoverBitmap>()
        cache.countLimit = 200
        return cache
    }()
    nonisolated(unsafe) private static let failures = NSCache<NSString, Failure>()

    nonisolated static func key(_ url: URL, maxPixels: Int) -> String { "\(maxPixels)|\(url.absoluteString)" }

    nonisolated static func cached(_ key: String) -> CoverBitmap? { images.object(forKey: key as NSString) }

    @concurrent nonisolated static func load(_ url: URL, maxPixels: Int) async -> CoverBitmap? {
        let cacheKey = key(url, maxPixels: maxPixels)
        if let hit = cached(cacheKey) { return hit }
        guard failures.object(forKey: cacheKey as NSString) == nil else { return nil }
        let source: CGImageSource?
        if url.isFileURL {
            source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        } else {
            source = await download(url).flatMap {
                CGImageSourceCreateWithData($0 as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            }
        }
        if Task.isCancelled { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1),
        ]
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            failures.setObject(Failure(), forKey: cacheKey as NSString)
            return nil
        }
        let bitmap = CoverBitmap(key: cacheKey, image: image)
        images.setObject(bitmap, forKey: cacheKey as NSString)
        return bitmap
    }

    nonisolated private static func download(_ url: URL) async -> Data? {
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return result.0
    }
}

#Preview {
    VStack(spacing: Spacing.s3) {
        PageCoverView(.gradient(.ocean)).frame(width: Size.homeCard, height: Size.homeCardCover)
        PageCoverView(.gradient(.ember)).frame(width: Size.homeCard, height: Size.homeCardCover)
        PageCoverView(.image(URL(string: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=800")!, position: 30))
            .frame(width: Size.homeCard, height: Size.homeCardCover)
    }
    .padding()
}
