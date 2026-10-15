import Foundation

/// Where a provider's requests go: its own API, or a base URL the user set (a proxy, a gateway, a compatible
/// server). Each base follows its provider's SDK convention — OpenAI's includes `/v1`, Anthropic's doesn't — so a
/// URL copied from either's docs works as is. A key is only sent to https, or to http on this machine.
public enum AIEndpoint {
    public static func defaultBase(_ provider: AIProvider) -> URL {
        switch provider {
        case .openAI: URL(string: "https://api.openai.com/v1")!
        case .anthropic: URL(string: "https://api.anthropic.com")!
        }
    }

    /// The base the user typed (blank: the provider's own), or nil when it isn't an http(s) URL with a host.
    public static func base(_ text: String?, for provider: AIProvider) -> URL? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultBase(provider) }
        var cleaned = trimmed
        while cleaned.hasSuffix("/") { cleaned.removeLast() }
        guard let url = URL(string: cleaned), url.scheme == "https" || url.scheme == "http", url.host() != nil,
            url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    /// The request URL under a base.
    public static func requestURL(_ provider: AIProvider, base: URL) -> URL {
        switch provider {
        case .openAI: base.appending(path: "responses")
        case .anthropic: base.appending(path: "v1/messages")
        }
    }

    /// Whether a key may be sent to this base: https anywhere, http only to loopback.
    public static func mayCarryKey(_ url: URL) -> Bool {
        url.scheme == "https" || (url.scheme == "http" && isLoopback(url))
    }

    /// The scheme, host and port a key belongs to: it is only ever sent back there.
    public static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        return "\(scheme)://\(host.lowercased())" + (url.port.map { ":\($0)" } ?? "")
    }

    /// The Keychain account of a provider's key for a base: the provider's own API keeps the original account; any
    /// other origin has its own, so a key typed for one address is never sent to another one typed later.
    public static func keyAccount(_ provider: AIProvider, base: URL?) -> String? {
        guard let base, let here = origin(of: base) else { return nil }
        let own = origin(of: defaultBase(provider))
        return here == own ? "ai.key.\(provider.rawValue)" : "ai.key.\(provider.rawValue)|\(here)"
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }
}
