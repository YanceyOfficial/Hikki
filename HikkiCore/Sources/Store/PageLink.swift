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

    /// A page body with the pages `ids` renames (old id → new) linked under their new ids: `hikki://page/<id>` in any
    /// string (a link's href, its `#block` kept) and a mention's `id`. Imported pages that took new ids keep pointing
    /// at each other.
    public static func rewrite(_ content: JSONValue, ids: [String: String]) -> JSONValue {
        guard !ids.isEmpty else { return content }
        switch content {
        case .string(let text) where text.contains("hikki://page/"):
            return .string(
                text.replacing(#/hikki://page/([\w-]+)/#) { match in "hikki://page/" + (ids[String(match.1)] ?? String(match.1)) })
        case .array(let items):
            return .array(items.map { rewrite($0, ids: ids) })
        case .object(var object):
            for (key, value) in object { object[key] = rewrite(value, ids: ids) }
            if object["type"] == .string("mention"), case .object(var attrs)? = object["attrs"], case .string(let id)? = attrs["id"],
                let renamed = ids[id]
            {
                attrs["id"] = .string(renamed)
                object["attrs"] = .object(attrs)
            }
            return .object(object)
        default:
            return content
        }
    }

    /// The page id in a `hikki://page/<id>` link, or nil for anything else.
    public static func pageID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "page" else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty || id.contains("/") ? nil : id.removingPercentEncoding
    }
}
