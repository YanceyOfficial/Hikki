import Foundation

/// A picture on the web, fetched to keep in the workspace (a picture an AI answer's web search found, added to the
/// page): LinkPreview's rules for an address someone else chose — http/https, public hosts only, every redirect
/// checked — and capped in time and size. Only the picture types the asset store takes come back. As there, the
/// connection isn't pinned to the checked addresses (URLSession has no hook), so a DNS answer that changes between the
/// check and the connect could reach a local address; accepted for the same reasons — a GET whose answer must parse
/// as a picture, fetched when the user asks for it (Add to page) or to show a thumbnail on this device.
public enum WebImage {
    public struct NotAPicture: Error {}

    static let maxBytes = 20 * 1024 * 1024
    static let deadline: Duration = .seconds(30)

    /// The picture's bytes and the extension its type is stored under.
    public static func fetch(_ url: URL) async throws -> (data: Data, fileExtension: String) {
        try await withThrowingTaskGroup(of: (data: Data, fileExtension: String).self) { group in
            group.addTask { try await fetchUnbounded(url) }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw URLError(.cancelled) }
            return result
        }
    }

    /// The stored extension for a picture's `Content-Type` (nil: not a picture the store takes).
    static func fileExtension(forContentType type: String?) -> String? {
        let mime = type?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return switch mime {
        case "image/png": "png"
        case "image/jpeg", "image/jpg", "image/pjpeg": "jpg"
        case "image/gif": "gif"
        case "image/webp": "webp"
        case "image/heic": "heic"
        case "image/heif": "heif"
        case "image/avif": "avif"
        default: nil
        }
    }

    private static func fetchUnbounded(_ url: URL) async throws -> (data: Data, fileExtension: String) {
        try await PublicHost.check(url)
        let guardDelegate = RedirectGuard()
        let session = URLSession(configuration: .ephemeral, delegate: guardDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let ext = fileExtension(forContentType: http.value(forHTTPHeaderField: "Content-Type"))
        else { throw NotAPicture() }
        if http.expectedContentLength > maxBytes { throw AssetStore.AssetError.tooLarge(Int(http.expectedContentLength)) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw AssetStore.AssetError.tooLarge(data.count) }
            if data.count % 65536 == 0 { try Task.checkCancellation() }
        }
        return (data, ext)
    }
}
