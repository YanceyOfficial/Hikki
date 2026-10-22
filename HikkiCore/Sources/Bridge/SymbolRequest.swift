import Foundation

/// The page's request for an SF Symbol drawn natively, as the editor's scheme serves it:
/// `hikki-editor://sf/<symbol>.png?pt=<points>` (lib/sf-icons.ts). Only a symbol name — letters, digits and dots,
/// never a path — and a point size within reason get through.
public struct SymbolRequest: Equatable, Sendable {
    public var name: String
    public var points: Double

    public static let host = "sf"
    public static let defaultPoints = 17.0
    static let pointRange = 8.0...96.0

    public init(name: String, points: Double = SymbolRequest.defaultPoints) {
        self.name = name
        self.points = points
    }

    /// Nil for anything but `sf://<name>.png` with a well-formed name; `pt` is whole points, clamped to 8–96 (so the
    /// sizes — and the renderings kept for them — are a bounded set; a non-number is the default).
    public static func parse(_ url: URL) -> SymbolRequest? {
        guard url.host == host, url.pathComponents.count == 2, url.pathExtension == "png" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, name.count <= 80,
            name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }), name.first != ".",
            name.last != "."
        else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let points = query.first { $0.name == "pt" }?.value.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            .map { min(max($0.rounded(), pointRange.lowerBound), pointRange.upperBound) }
        return SymbolRequest(name: name, points: points ?? defaultPoints)
    }

    /// One rendering per name and size.
    public var cacheKey: String { "\(name)@\(points)" }
}
