import Foundation

/// How a page is published (the `PublishSheet`'s choice): only to people with the link — sealed, the key in the link
/// — or listed in Hikki Community, the website's public list (`/community`): stored readable, found by its tags and words.
public struct PublishOptions: Codable, Equatable, Sendable {
    public var listed: Bool
    /// `PublishTags.all` ids, at most `PublishTags.maxPerPage`; a listed page has at least one.
    public var tags: [String]
    /// The name the page shows as its author ("by …"), as the publisher typed it; empty for none.
    public var author: String

    public init(listed: Bool, tags: [String] = [], author: String = "") {
        self.listed = listed
        self.tags = tags
        self.author = author
    }

    /// The longest author name kept.
    public static let maxAuthorLength = 60

    /// Whether a page may be listed in Hikki Community. Off for v1: the list has no reporting, blocking or moderation yet
    /// (ISSUE-279–283), so the publish sheet offers the link alone and every publish goes out link-only.
    // TODO(ISSUE-284): turn on once the list is moderated.
    public static let listingOpen = false

    /// Only people with the link — the default, and the only choice before tags existed.
    public static let linkOnly = PublishOptions(listed: false)

    /// The options as they may be published: known tags only, in the list's order, no more than the limit (a page
    /// for people with the link may carry tags too — they show on it, nothing lists it); the author's name on one
    /// line, trimmed and cut to `maxAuthorLength`.
    public var normalized: PublishOptions {
        let chosen = Set(tags)
        let name = author.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return PublishOptions(
            listed: listed, tags: Array(PublishTags.all.filter(chosen.contains).prefix(PublishTags.maxPerPage)),
            author: String(name.prefix(Self.maxAuthorLength)))
    }

    /// A listed page needs a tag to be filed under.
    public var isComplete: Bool { !listed || !normalized.tags.isEmpty }
}

/// The preset tags a listed page is filed under — the same ids as the website's `PUBLISH_TAGS`
/// (`apps/website/src/publish.ts`); `design/fixtures/publish.json` holds both to the list. Each one's name is the
/// string `app:publish.tag.<id>`.
public enum PublishTags {
    public static let all = [
        "study", "language", "work", "tech", "design", "writing",
        "reading", "travel", "food", "health", "life", "templates",
    ]
    public static let maxPerPage = 3
}

/// The words a listed page is found by. CloudKit's public database matches whole values, so the page carries its
/// search terms as a list (`terms`, queried with `LIST_CONTAINS`): its words folded — no case, no accents, full-width
/// as half-width — each run of letters or digits two characters or longer as one term, and in Chinese, Japanese and
/// Korean every character and every pair of neighbours. A query is folded the same way and asks for each of its terms
/// (a pair stands in for the characters it holds). The website's `searchTerms` / `queryTerms` give the same answers
/// (`design/fixtures/publish.json`).
public enum PublishSearch {
    /// How many terms a page carries at most, and how many a query asks for.
    public static let maxTerms = 1500
    public static let maxQueryTerms = 5
    static let maxWordLength = 40

    public static func terms(_ text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        func add(_ term: String) {
            guard terms.count < maxTerms, seen.insert(term).inserted else { return }
            terms.append(term)
        }
        for segment in segments(of: fold(text)) {
            if segment.cjk {
                let characters = segment.scalars
                for index in characters.indices {
                    add(String(String.UnicodeScalarView([characters[index]])))
                    if index + 1 < characters.count {
                        add(String(String.UnicodeScalarView([characters[index], characters[index + 1]])))
                    }
                }
            } else if segment.scalars.count >= 2 {
                add(String(String.UnicodeScalarView(segment.scalars.prefix(maxWordLength))))
            }
        }
        return terms
    }

    /// A query's terms: a character already inside one of the query's pairs is left out.
    public static func queryTerms(_ query: String) -> [String] {
        let all = terms(query)
        let pairs = all.filter { $0.unicodeScalars.count == 2 && isCJK($0.unicodeScalars.first!) }
        let kept = all.filter { term in
            guard term.unicodeScalars.count == 1, isCJK(term.unicodeScalars.first!) else { return true }
            return !pairs.contains { $0.contains(term) }
        }
        return Array(kept.prefix(maxQueryTerms))
    }

    /// No case, no accents (only the combining marks Latin letters take, U+0300–036F, so Japanese voicing stays),
    /// full-width letters and digits as their plain forms.
    static func fold(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        return String(String.UnicodeScalarView(decomposed)).precomposedStringWithCanonicalMapping.lowercased()
    }

    struct Segment {
        var cjk: Bool
        var scalars: [Unicode.Scalar]
    }

    /// Runs of letters and digits, cut where they turn from CJK to other scripts and back.
    static func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var current: Segment?
        for scalar in text.unicodeScalars {
            guard isWordScalar(scalar) else {
                if let done = current { segments.append(done) }
                current = nil
                continue
            }
            let cjk = isCJK(scalar)
            if current?.cjk == cjk {
                current?.scalars.append(scalar)
            } else {
                if let done = current { segments.append(done) }
                current = Segment(cjk: cjk, scalars: [scalar])
            }
        }
        if let done = current { segments.append(done) }
        return segments
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber:
            true
        // Kana's voicing marks once composed text was decomposed (they stay with their kana).
        case .nonspacingMark, .spacingMark: isCJK(scalar)
        default: false
        }
    }

    /// Han, kana and Hangul — the scripts written without spaces between words.
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF,
            0x1100...0x11FF, 0x3130...0x318F, 0x20000...0x2FA1F:
            true
        default: false
        }
    }

    /// A listed page's line in the list: its first words, spaces run together.
    public static func excerpt(_ plainText: String, limit: Int = 240) -> String {
        let words = plainText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard words.count > limit else { return words }
        return String(words.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// The website's "Save to Hikki" link, `hikki://shared/<record>` — with `#<key>` for a page only for people with the
/// link — which the app opens to save a copy of the published page into the workspace.
public enum SharedLink {
    public struct Target: Equatable, Sendable {
        public var recordName: String
        public var key: String?
    }

    /// The record and key a link names, or nil for anything else (another host, a record name that isn't one).
    public static func parse(_ url: URL) -> Target? {
        guard url.scheme == PageLink.scheme, url.host() == "shared" else { return nil }
        let name = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard (1...64).contains(name.count), name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        let key = url.fragment().flatMap { $0.isEmpty ? nil : $0 }
        return Target(recordName: name, key: key)
    }
}

extension PublishedCover {
    /// The cover as a page stores it (`PageCover`'s forms): `gradient:<id>`, or a picture with its `#y=` position —
    /// the page's own (`assets/<name>`) through `assetURL`, which gives its address in this workspace (nil: none).
    public func stored(assetURL: (String) -> String?) -> String? {
        if let gradient { return gradient.isEmpty ? nil : "gradient:\(gradient)" }
        guard let image else { return nil }
        let url: String
        if image.hasPrefix("assets/") {
            guard let local = assetURL(String(image.dropFirst("assets/".count))) else { return nil }
            url = local
        } else {
            guard URL(string: image)?.scheme == "https" else { return nil }
            url = image
        }
        return "\(url)#y=\(Int(min(100, max(0, position)).rounded()))"
    }
}
