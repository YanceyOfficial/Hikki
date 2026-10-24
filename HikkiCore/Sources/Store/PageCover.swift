import Foundation

/// A page's stored cover, read the way the editor reads it (`apps/editor/src/lib/covers.ts`): `gradient:<id>` for a
/// built-in cover, or a picture's URL — uploaded (`hikki-editor://assets/<name>`), linked or Unsplash — whose vertical
/// position rides along as a `#y=<0-100>` fragment (50, centred, when absent).
public enum PageCover: Equatable, Sendable {
    /// A built-in gradient by its id (`CoverGradient`'s raw value in HikkiUI).
    case gradient(String)
    /// A picture: its URL without the position fragment, and where it sits vertically (0 = its top, 100 = its bottom).
    case image(url: String, position: Double)

    private static let imageSchemes = ["hikki-editor:", "https:", "http:", "blob:", "data:"]

    public init?(_ raw: String?) {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("gradient:") {
            let id = String(raw.dropFirst("gradient:".count))
            guard !id.isEmpty else { return nil }
            self = .gradient(id)
            return
        }
        guard Self.imageSchemes.contains(where: { raw.hasPrefix($0) }) else { return nil }
        var url = raw
        var position = 50.0
        if let marker = raw.range(of: "#y=", options: .backwards) {
            let digits = raw[marker.upperBound...]
            if (1...3).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) {
                position = Double(min(100, value))
                url = String(raw[..<marker.lowerBound])
            }
        }
        self = .image(url: url, position: position)
    }

    /// The asset name when the picture is one of the workspace's own (`hikki-editor://assets/<name>`), else nil.
    public var assetName: String? {
        guard case .image(let url, _) = self else { return nil }
        return AssetStore.name(fromURL: url)
    }

    /// A picture the app can load itself (https / http / data — not the editor's own scheme, not a page's blob),
    /// or nil.
    public var webURL: URL? {
        guard case .image(let url, _) = self, url.hasPrefix("https:") || url.hasPrefix("http:") || url.hasPrefix("data:")
        else { return nil }
        return URL(string: url)
    }
}
