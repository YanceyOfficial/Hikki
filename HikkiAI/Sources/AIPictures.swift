import Foundation

/// A picture's shape: landscape, square or portrait, at the image model's sizes.
public enum PictureShape: String, Codable, CaseIterable, Sendable {
    case wide, square, tall

    /// The size the image model is asked for.
    var size: String {
        switch self {
        case .wide: "1536x1024"
        case .square: "1024x1024"
        case .tall: "1024x1536"
        }
    }

    /// Width over height, as its tile draws it.
    public var aspect: Double {
        switch self {
        case .wide: 1.5
        case .square: 1
        case .tall: 2.0 / 3
        }
    }
}

/// A picture an Ask AI answer asks for (see `AIPictures`), checked: a description, its shape, the detailed model or
/// not, and the earlier picture it changes (an id the chat gave the model, or "attached").
public struct PictureSpec: Equatable, Sendable {
    public var prompt: String
    public var shape: PictureShape
    public var detailed: Bool
    public var from: String?

    public init(prompt: String, shape: PictureShape = .wide, detailed: Bool = false, from: String? = nil) {
        self.prompt = prompt
        self.shape = shape
        self.detailed = detailed
        self.from = from
    }
}

/// Ask AI making pictures: an answer that makes some ends with a fenced `hikki-pictures` block of JSON — what to draw,
/// one entry per picture — which the app makes with OpenAI's image model, whichever model wrote the answer. The block
/// never shows in the chat; what's in it is untrusted and checked here (at most `maxPerAnswer`, known shapes, known
/// pictures to change).
public enum AIPictures {
    static let fence = "```hikki-pictures"
    /// Pictures one answer may make: each costs money and takes up to a minute.
    public static let maxPerAnswer = 4
    static let maxPrompt = 4000
    /// The id `from` uses for the picture the user attached to change.
    public static let attached = "attached"
    /// Quick, the default.
    public static let fastModel = "gpt-image-2.5-flare"
    /// Slower and more detailed; also every change to an existing picture (it keeps the rest of it better).
    public static let detailedModel = "gpt-image-2.5-sunburst"

    /// Whether the answer has started its pictures block.
    public static func hasPictures(_ answer: String) -> Bool { answer.contains(fence) }

    /// The pictures the answer asks for; `known`: the pictures it may change (ids the chat gave the model, plus
    /// `attached` when the user attached one). None when there is no block or it can't be read.
    public static func pictures(in answer: String, known: Set<String> = []) -> [PictureSpec] {
        guard let start = answer.range(of: fence) else { return [] }
        var body = answer[start.upperBound...]
        if let end = body.range(of: "```") { body = body[..<end.lowerBound] }
        guard let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close,
            let data = String(body[open...close]).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = object["pictures"] as? [Any]
        else { return [] }
        return list.compactMap { item -> PictureSpec? in
            guard let fields = item as? [String: Any], let prompt = fields["prompt"] as? String else { return nil }
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let from = (fields["from"] as? String).flatMap { known.contains($0) ? $0 : nil }
            return PictureSpec(
                prompt: String(trimmed.prefix(maxPrompt)),
                shape: (fields["shape"] as? String).flatMap(PictureShape.init(rawValue:)) ?? .wide,
                detailed: fields["detailed"] as? Bool ?? false, from: from)
        }
        .prefix(maxPerAnswer).map { $0 }
    }

    /// The line an earlier answer's picture is named by in the conversation the model gets.
    public static func reference(id: String, prompt: String) -> String {
        "[picture \(id)] \(prompt)"
    }

    /// What the user asked for when the composer was set up for pictures (a shape and the detailed model chosen).
    static func request(shape: PictureShape, detailed: Bool) -> String {
        "I'm asking for pictures: make them \(shape.rawValue)\(detailed ? ", detailed" : "")."
    }

    static let instructions = """


        You can make pictures. When the user asks for pictures — illustrations, photos, posters, icons, covers, \
        variations of an earlier picture — and only then, say in a sentence what you will make, then end your reply \
        with one fenced block listing them, with nothing after it:
        ```hikki-pictures
        {"pictures":[{"prompt":"<a full, self-contained description of the picture>","shape":"wide"}]}
        ```
        Fields: "prompt" describes subject, style, composition and light so it stands alone (the image model sees \
        nothing else); "shape" is wide (3:2), square or tall (2:3) — wide unless asked or the subject suits another; \
        "detailed": true for the slower, more detailed model, when the user asks for detail or for text in the picture; \
        "from": to change an earlier picture instead of making a new one, its id (earlier pictures are listed as \
        [picture <id>]) or "attached" for a picture the user attached. At most 4 pictures in a reply; asked for more, \
        make 4 and say so. Never put a hikki-pictures block in a reply that doesn't make pictures.
        """
}

/// What a picture being made yields: rougher versions while it forms, then the picture.
public enum PictureEvent: Equatable, Sendable {
    case partial(Data)
    /// The finished picture and its file extension.
    case done(Data, fileExtension: String)
}

/// A picture to make: from words, or changing `source` (a picture's data and type).
public struct PictureRequest: Sendable {
    public var prompt: String
    public var shape: PictureShape
    public var detailed: Bool
    public var source: (data: Data, mimeType: String)?

    public init(prompt: String, shape: PictureShape, detailed: Bool, source: (data: Data, mimeType: String)? = nil) {
        self.prompt = prompt
        self.shape = shape
        self.detailed = detailed
        self.source = source
    }

    /// The image model: a change always runs on the detailed one.
    public var model: String { detailed || source != nil ? AIPictures.detailedModel : AIPictures.fastModel }
}

/// Something that makes pictures (OpenAI's Image API; tests fake it).
public protocol PictureClient: Sendable {
    func make(_ request: PictureRequest) -> AsyncThrowingStream<PictureEvent, Error>
}

/// OpenAI's Image API: `images/generations` (JSON) or `images/edits` (multipart, the source picture as `image[]`),
/// streamed with two partial pictures. Errors map like the chat's; a picture the provider's filter declines is
/// `.refused`. A gateway that ignores `stream` and answers with the whole picture as JSON works too.
public struct OpenAIPictureClient: PictureClient {
    static let partials = 2
    let key: String
    let base: URL
    let session: URLSession

    public static func make(key: String?, base: URL, session: URLSession = AIClients.defaultSession) throws -> OpenAIPictureClient {
        guard let key, !key.isEmpty else { throw AIError.missingKey(.openAI) }
        guard AIEndpoint.mayCarryKey(base) else { throw AIError.badBaseURL(.openAI) }
        return OpenAIPictureClient(key: key, base: base, session: session)
    }

    public func make(_ request: PictureRequest) -> AsyncThrowingStream<PictureEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let http = try urlRequest(request)
                    let (bytes, response) = try await session.bytes(for: http)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let json = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true
                    if !(200..<300).contains(status) || json {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        guard (200..<300).contains(status) else { throw HTTPErrors.map(status: status, body: body) }
                        continuation.yield(try Self.whole(body))
                        continuation.finish()
                        return
                    }
                    var done = false
                    for try await line in bytes.lines {
                        guard let event = sseJSON(line), let picture = try Self.event(event) else { continue }
                        continuation.yield(picture)
                        if case .done = picture { done = true }
                    }
                    guard done else { throw AIError.invalidResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPErrors.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func urlRequest(_ request: PictureRequest) throws -> URLRequest {
        var fields: [(String, String)] = [
            ("model", request.model), ("prompt", request.prompt), ("size", request.shape.size),
            ("quality", request.detailed || request.source != nil ? "high" : "medium"), ("output_format", "jpeg"),
            ("stream", "true"), ("partial_images", "\(Self.partials)"),
        ]
        var http: URLRequest
        if let source = request.source {
            http = URLRequest(url: base.appending(path: "images/edits"))
            let boundary = "hikki-\(UUID().uuidString)"
            http.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            for (name, value) in fields {
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
            }
            let ext = source.mimeType == "image/png" ? "png" : source.mimeType == "image/webp" ? "webp" : "jpg"
            body.append(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"picture.\(ext)\"\r\n"
                    + "Content-Type: \(source.mimeType)\r\n\r\n")
            body.append(source.data)
            body.append("\r\n--\(boundary)--\r\n")
            http.httpBody = body
        } else {
            http = URLRequest(url: base.appending(path: "images/generations"))
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
            fields.removeAll { $0.0 == "stream" || $0.0 == "partial_images" }
            var object: [String: Any] = Dictionary(uniqueKeysWithValues: fields)
            object["n"] = 1
            object["stream"] = true
            object["partial_images"] = Self.partials
            http.httpBody = try JSONSerialization.data(withJSONObject: object)
        }
        http.httpMethod = "POST"
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Up to a couple of minutes for a detailed picture.
        http.timeoutInterval = 300
        return http
    }

    /// A stream event as a picture event: `image_generation.*` / `image_edit.*` `partial_image` and `completed`, each
    /// with `b64_json`; an `error` event throws. Anything else is skipped.
    static func event(_ json: [String: Any]) throws -> PictureEvent? {
        let type = json["type"] as? String ?? ""
        if type == "error" || type.hasSuffix(".failed") {
            let error = json["error"] as? [String: Any] ?? json
            throw HTTPErrors.pictureError(code: error["code"] as? String, message: error["message"] as? String ?? "")
        }
        guard let b64 = json["b64_json"] as? String, let data = Data(base64Encoded: b64) else { return nil }
        if type.hasSuffix(".partial_image") { return .partial(data) }
        if type.hasSuffix(".completed") { return .done(data, fileExtension: fileExtension(json["output_format"])) }
        return nil
    }

    /// A whole answer (`{"data":[{"b64_json":…}]}`) as the finished picture.
    static func whole(_ body: Data) throws -> PictureEvent {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let first = (object["data"] as? [[String: Any]])?.first, let b64 = first["b64_json"] as? String,
            let data = Data(base64Encoded: b64)
        else { throw AIError.invalidResponse }
        return .done(data, fileExtension: fileExtension(object["output_format"]))
    }

    static func fileExtension(_ format: Any?) -> String {
        switch format as? String {
        case "png": "png"
        case "webp": "webp"
        default: "jpg"
        }
    }
}

extension Data {
    fileprivate mutating func append(_ text: String) { append(Data(text.utf8)) }
}
