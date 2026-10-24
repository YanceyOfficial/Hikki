import Foundation

/// A photo for a cover, as Hikki's backend (`apps/bff`, which keeps the Unsplash key) hands it over: the picture at
/// three sizes plus one sized for a cover, its photographer with utm-tagged links (Unsplash's attribution rule) and
/// where a pick is reported.
public struct UnsplashPhoto: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let thumb: URL
    public let regular: URL
    public let full: URL
    /// High resolution, sized for a cover (the backend's `coverURL`: `urls.raw` at 2560 px); nil from an older one.
    public let cover: URL?
    /// The photo's average colour ("#a0b1c2"), shown while it loads.
    public let color: String?
    public let alt: String?
    public let author: String
    public let authorUrl: URL
    public let photoUrl: URL
    public let downloadLocation: URL

    public init(
        id: String, thumb: URL, regular: URL, full: URL, cover: URL? = nil, color: String?, alt: String?, author: String,
        authorUrl: URL, photoUrl: URL, downloadLocation: URL
    ) {
        self.id = id
        self.thumb = thumb
        self.regular = regular
        self.full = full
        self.cover = cover
        self.color = color
        self.alt = alt
        self.author = author
        self.authorUrl = authorUrl
        self.photoUrl = photoUrl
        self.downloadLocation = downloadLocation
    }

    /// What a pick sets as the cover: the high-resolution `cover` (the grid keeps the thumbnails), `regular` from a
    /// backend that doesn't send one.
    public var coverURL: URL { cover ?? regular }
}

/// Unsplash through Hikki's backend — the native side of `apps/editor/src/lib/unsplash.ts`: landscape photos for a
/// search (a random batch for no query), and a pick counted as a download (Unsplash's guideline).
public struct UnsplashClient: Sendable {
    /// Unsplash's home with the referral utm the attribution guideline asks for.
    public static let home = URL(string: "https://unsplash.com/?utm_source=hikki&utm_medium=referral")!

    /// A failed search, by the backend's code (`design/errors.json`): `rateLimited` for Unsplash's hourly limit.
    public struct Failure: Error, Equatable {
        public let code: ErrorCode
        public let status: Int
    }

    let base: URL
    let session: URLSession

    public init(base: URL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    public func search(_ query: String, page: Int = 1) async throws -> [UnsplashPhoto] {
        let (data, response) = try await session.data(from: Self.searchURL(base: base, query: query, page: page))
        return try Self.photos(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Counts a picked photo for its photographer. Never blocks or fails the pick: a failure is only logged.
    public func trackDownload(_ photo: UnsplashPhoto) async {
        var request = URLRequest(url: base.appending(path: "api/unsplash/download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["downloadLocation": photo.downloadLocation.absoluteString])
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(status) {
                Log.warn("unsplash download not counted", category: "covers", context: ["status": "\(status)"])
            }
        } catch {
            Log.warn("unsplash download not counted", category: "covers", context: ["error": "\(error)"])
        }
    }

    static func searchURL(base: URL, query: String, page: Int) -> URL {
        base.appending(path: "api/unsplash/photos").appending(queryItems: [
            URLQueryItem(name: "query", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    /// A search's answer: its photos, or the failure its `{error: {code, id}}` body names. An older backend answered
    /// 403 for the hourly limit.
    static func photos(from data: Data, status: Int) throws -> [UnsplashPhoto] {
        guard (200..<300).contains(status) else {
            struct Body: Decodable {
                struct Inner: Decodable { let id: String? }
                let error: Inner?
            }
            let id = (try? JSONDecoder().decode(Body.self, from: data))?.error?.id
            let code = id.flatMap(ErrorCode.init(rawValue:)) ?? .upstreamFailed
            throw Failure(code: status == 403 || status == 429 ? .rateLimited : code, status: status)
        }
        struct Page: Decodable { let photos: [UnsplashPhoto] }
        return try JSONDecoder().decode(Page.self, from: data).photos
    }
}
