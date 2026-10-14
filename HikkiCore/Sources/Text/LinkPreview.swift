import Foundation

/// What a web page says about itself, for a link card: its title, a line of description and an icon — read from the
/// page's own `<head>` (Open Graph first, then the plain tags), on this device, no third party involved.
public struct LinkPreview: Equatable, Sendable {
    public var title: String?
    public var description: String?
    /// An absolute https/http URL, or nil.
    public var icon: String?

    public init(title: String? = nil, description: String? = nil, icon: String? = nil) {
        self.title = title
        self.description = description
        self.icon = icon
    }

    /// How much of a page is read: the head is near the top.
    static let maxBytes = 512 * 1024
    /// How much of that is parsed when the page never closes its head (the regexes stay linear and short).
    static let maxHeadCharacters = 64 * 1024
    /// The whole fetch, start to last byte: a server trickling bytes can't hold it longer.
    static let deadline: Duration = .seconds(12)

    /// Fetches `url` and reads its head; nil for anything that isn't a page (an error status, not HTML).
    ///
    /// The link comes from a document — possibly synced from another device or pasted — so the fetch follows exodus's
    /// rules for a URL someone else chose (`safe-fetch.ts`): http/https only, and the host must be on the public
    /// internet — not localhost, the LAN or link-local (cloud metadata) — for the first request and every redirect.
    /// Unlike exodus the connection isn't pinned to the checked addresses (URLSession has no hook for it), so a DNS
    /// answer that changes between the check and the connect could reach a local address. Accepted: what comes back
    /// only becomes a title, a description and an icon URL shown on this device — nothing is sent anywhere — and the
    /// whole fetch is capped in time and size.
    public static func fetch(_ url: URL) async throws -> LinkPreview? {
        try await withThrowingTaskGroup(of: LinkPreview?.self) { group in
            group.addTask { try await fetchUnbounded(url) }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private static func fetchUnbounded(_ url: URL) async throws -> LinkPreview? {
        try await PublicHost.check(url)
        let guardDelegate = RedirectGuard()
        let session = URLSession(configuration: .ephemeral, delegate: guardDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").lowercased().contains("html")
        else { return nil }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maxBytes { break }
            if data.count % 4096 == 0 { try Task.checkCancellation() }
        }
        return parse(html: String(decoding: data, as: UTF8.self), url: response.url ?? url)
    }

    /// Reads the head of `html`; relative icon links resolve against `url` (the page's final address).
    public static func parse(html: String, url: URL) -> LinkPreview {
        let closed = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.upperBound]) } ?? html
        let head = String(closed.prefix(maxHeadCharacters))
        var meta: [String: String] = [:]
        for tag in tags(named: "meta", in: head) {
            let attributes = attributes(of: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(), let content = attributes["content"]
            else { continue }
            if meta[key] == nil { meta[key] = content }
        }
        // Bounded and without nested quantifiers: linear on any input.
        let titleTag = firstMatch(#"<title[^>]{0,200}>([^<]{0,2000})</title>"#, in: head)
        let title = clean(meta["og:title"] ?? meta["twitter:title"] ?? titleTag)
        let description = clean(meta["og:description"] ?? meta["description"] ?? meta["twitter:description"])

        var icons: [(rank: Int, href: String)] = []
        for tag in tags(named: "link", in: head) {
            let attributes = attributes(of: tag)
            guard let rel = attributes["rel"]?.lowercased(), let href = attributes["href"], !href.isEmpty else { continue }
            if rel.contains("apple-touch-icon") {
                icons.append((0, href))
            } else if rel.split(separator: " ").contains("icon") {
                icons.append((href.lowercased().hasSuffix(".svg") ? 1 : 2, href))
            }
        }
        let iconHref = icons.min { $0.rank < $1.rank }?.href ?? "/favicon.ico"
        let icon = URL(string: decodeEntities(iconHref), relativeTo: url)?.absoluteURL
        let iconString = icon.flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
        return LinkPreview(title: title, description: description, icon: iconString)
    }

    // MARK: - A little HTML reading (heads only; no DOM needed)

    static func tags(named name: String, in html: String) -> [String] {
        matches("<\(name)\\b[^>]{0,2000}>", in: html)
    }

    static func attributes(of tag: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else {
            return out
        }
        let range = NSRange(tag.startIndex..., in: tag)
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: tag) }.first.map { String(tag[$0]) } ?? ""
            let key = tag[keyRange].lowercased()
            if out[key] == nil { out[key] = value }
        }
        return out
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    /// Entities decoded, whitespace collapsed, nil when nothing is left; long text cut.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = decodeEntities(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > 300 ? String(collapsed.prefix(299)) + "…" : collapsed
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for match in regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 2), in: out) else { continue }
                let hex = match.range(at: 1).length > 0
                if let code = UInt32(out[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    out.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Refuses redirects to a host that isn't public (each hop is checked like the first).
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    // The completion-handler form: the async one crashed the compiler (Swift 6.x, @objc thunk for an async method).
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url else { return completionHandler(nil) }
        Task {
            let allowed = (try? await PublicHost.check(url)) != nil
            completionHandler(allowed ? request : nil)
        }
    }
}

/// Whether a URL's host is on the public internet (exodus's `isPublicAddress`, IANA special-purpose ranges).
enum PublicHost {
    struct Refused: Error {}

    static func check(_ url: URL) async throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty,
            host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local")
        else { throw Refused() }
        let addresses = try await resolve(host)
        guard !addresses.isEmpty, addresses.allSatisfy(isPublic) else { throw Refused() }
    }

    /// The host's addresses as bytes (a literal address is its own answer).
    static func resolve(_ host: String) async throws -> [[UInt8]] {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let literal = bytes(of: bare) { return [literal] }
        return try await Task.detached {
            var hints = addrinfo(
                ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(bare, nil, &hints, &result) == 0, let first = result else { throw Refused() }
            defer { freeaddrinfo(first) }
            var out: [[UInt8]] = []
            var node: UnsafeMutablePointer<addrinfo>? = first
            while let current = node {
                if let address = current.pointee.ai_addr {
                    if current.pointee.ai_family == AF_INET {
                        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                            var raw = pointer.pointee.sin_addr
                            out.append(withUnsafeBytes(of: &raw) { Array($0) })
                        }
                    } else if current.pointee.ai_family == AF_INET6 {
                        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                            var raw = pointer.pointee.sin6_addr
                            out.append(withUnsafeBytes(of: &raw) { Array($0) })
                        }
                    }
                }
                node = current.pointee.ai_next
            }
            return out
        }.value
    }

    static func bytes(of literal: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, literal, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, literal, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }

    static func inPrefix(_ bytes: [UInt8], _ prefix: [UInt8], _ bits: Int) -> Bool {
        var bit = 0
        while bit < bits {
            let take = min(8, bits - bit)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - take))
            let index = bit / 8
            if bytes[index] & mask != (index < prefix.count ? prefix[index] : 0) & mask { return false }
            bit += 8
        }
        return true
    }

    static let blockedV4: [([UInt8], Int)] = [
        ([0, 0, 0, 0], 8), ([10, 0, 0, 0], 8), ([100, 64, 0, 0], 10), ([127, 0, 0, 0], 8), ([169, 254, 0, 0], 16),
        ([172, 16, 0, 0], 12), ([192, 0, 0, 0], 24), ([192, 0, 2, 0], 24), ([192, 88, 99, 0], 24),
        ([192, 168, 0, 0], 16), ([198, 51, 100, 0], 24), ([203, 0, 113, 0], 24), ([224, 0, 0, 0], 4),
        ([240, 0, 0, 0], 4),
        // 198.18.0.0/15 stays allowed: a TUN proxy's fake-ip mode answers every name from it (exodus).
    ]

    static func isPublic(_ bytes: [UInt8]) -> Bool {
        if bytes.count == 4 { return !blockedV4.contains { inPrefix(bytes, $0.0, $0.1) } }
        guard bytes.count == 16 else { return false }
        let mapped: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]
        let nat64: [UInt8] = [0, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0]
        if inPrefix(bytes, mapped, 96) || inPrefix(bytes, nat64, 96) { return isPublic(Array(bytes[12...])) }
        // Only global unicast (2000::/3) is public, minus documentation and 6to4.
        guard inPrefix(bytes, [0x20], 3) else { return false }
        return ![([0x20, 0x01, 0x0D, 0xB8], 32), ([0x20, 0x02], 16), ([0x3F, 0xFF], 20)].contains {
            inPrefix(bytes, $0.0, $0.1)
        }
    }
}
