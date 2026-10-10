import Foundation

/// Links to a page (`hikki://page/<id>`), as copied by "Copy link" and opened by the app.
public enum PageLink {
    public static let scheme = "hikki"

    public static func url(for id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "page"
        components.path = "/" + id
        return components.url!
    }

    /// The page id in a `hikki://page/<id>` link, or nil for anything else.
    public static func pageID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "page" else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty || id.contains("/") ? nil : id.removingPercentEncoding
    }
}
