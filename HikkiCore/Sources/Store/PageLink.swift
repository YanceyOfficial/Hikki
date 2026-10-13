import Foundation

/// Links to a page (`hikki://page/<id>`), as copied by "Copy link" and opened by the app.
public enum PageLink {
    public static let scheme = "hikki"

    /// `hikki://page/<id>`, with `#<block>` for a block inside the page ("Copy link to block").
    public static func url(for id: String, block: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "page"
        components.path = "/" + id
        components.fragment = block
        return components.url!
    }

    /// What a dragged page carries (a sidebar row): its link as a URL and as text. The editor turns the
    /// dropped link into a labelled hyperlink, the tab strip opens the page, and anything outside gets the URL.
    public static func dragItem(_ id: String) -> NSItemProvider {
        let url = url(for: id)
        let provider = NSItemProvider(object: url as NSURL)
        provider.registerObject(url.absoluteString as NSString, visibility: .all)
        return provider
    }

    /// The block id in a `hikki://page/<id>#<block>` link, or nil.
    public static func blockID(from url: URL) -> String? {
        guard pageID(from: url) != nil, let fragment = url.fragment(), !fragment.isEmpty else { return nil }
        return fragment.contains("/") ? nil : fragment
    }

    /// The page id in a `hikki://page/<id>` link, or nil for anything else.
    public static func pageID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "page" else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty || id.contains("/") ? nil : id.removingPercentEncoding
    }
}
