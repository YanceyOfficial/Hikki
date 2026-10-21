import Foundation

/// Mirror of apps/editor/src/protocol.ts. Bump both versions together.
public enum BridgeProtocol {
    public static let version = 34

    /// Whether a script message may reach the shell. WebKit gives every frame of the web view the message
    /// handlers, embedded third-party pages included, so only the main frame, loaded from the editor's own
    /// scheme, is listened to.
    public static func trustsFrame(isMainFrame: Bool, scheme: String?, editorScheme: String) -> Bool {
        isMainFrame && scheme?.lowercased() == editorScheme.lowercased()
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public var docId: String
    /// Body only — the title is a page property.
    public var content: JSONValue
    public var title: String
    public var text: String
    public var wordCount: Int

    public init(docId: String, content: JSONValue, title: String, text: String, wordCount: Int) {
        self.docId = docId
        self.content = content
        self.title = title
        self.text = text
        self.wordCount = wordCount
    }
}

/// A heading of the open page, for the inspector's outline (`id` is the block to scroll to; nil before the
/// editor stamped ids).
public struct OutlineHeading: Codable, Sendable, Equatable {
    public var id: String?
    public var level: Int
    public var text: String

    public init(id: String?, level: Int, text: String) {
        self.id = id
        self.level = level
        self.text = text
    }
}

/// Messages posted by the web editor to the native shell.
public enum BridgeMessage: Sendable, Equatable {
    case ready(protocolVersion: Int)
    case changed(Snapshot)
    case activeFormats([String])
    /// The open page's outline and size for the inspector: on load, then throttled as it changes.
    case pageInfo(docId: String, headings: [OutlineHeading], words: Int, characters: Int)
    /// The heading the reader is in changed (the page's scroll-spy); nil above the first heading.
    case activeHeading(docId: String, id: String?)
    /// The selected text ("" when nothing is): Ask AI offers it as context.
    case selection(docId: String, text: String)
    /// A bottom sheet of the page's opened or closed (a touch screen's cover, icon or comment sheet): the native bars
    /// beside it step aside meanwhile (an iPhone Duo's vertical bar), so the sheet has the whole width.
    case sheet(open: Bool)
    /// The page opened or closed something that takes the whole page (a drawing's editor): the native bars over the page
    /// (iPhone's navigation and floating bars) step aside meanwhile.
    case fullScreen(open: Bool)
    /// Comments (`PageComments`): a thread started on a passage — or, with `blockId`, on a whole block without text —
    /// with its first comment, a reply, resolving / reopening, deleting a comment or (`commentId` nil) the whole thread.
    case commentCreate(docId: String, threadId: String, quote: String, body: String, blockId: String? = nil)
    case commentReply(docId: String, threadId: String, body: String)
    case commentResolve(docId: String, threadId: String, resolved: Bool)
    case commentDelete(docId: String, threadId: String, commentId: String?)
    /// A comment's words rewritten.
    case commentEdit(docId: String, threadId: String, commentId: String, body: String)
    /// The thread open in the page changed (nil: none) — sent only where the native side draws threads itself
    /// (`setNativeComments`, the iPhone layout).
    case commentThread(docId: String, threadId: String?)
    /// The cover's sheet, sent only where the native side draws it (`setNativeCover`, the iPhone layout): its actions
    /// or the picker, with the page's cover and the editor's backend (`bff`, for Unsplash; nil in a build without one).
    /// The pick goes back as `window.hikki.applyCover`.
    case coverSheet(docId: String, cover: String?, mode: CoverSheetMode, bff: URL?)
    /// An icon picker, sent only where the native side draws it (`setNativeIcons`, the iPhone layout): the page's icon
    /// or a callout's (with its background, a palette name). The pick goes back under `id` as `window.hikki.applyIcon`
    /// (and `applyIconColor` for a callout's colour).
    case iconSheet(docId: String, id: String, kind: IconSheetKind, icon: String?, color: String?)
    /// Where the page is scrolled (throttled), so a tab shown again gets its place back.
    case scroll(docId: String, top: Double)
    /// AI on the selection (see `AIRequestPayload`); replies go back through `window.hikki.aiEvent`.
    case aiRequest(AIRequestPayload)
    /// Stop that AI request.
    case aiCancel(id: String)
    /// AI on the selection judged the request too big for it (`{"handoff": …}`): the app continues it in the chat.
    case aiHandoff(AIHandoff)
    /// A change Ask AI proposed to the page was reviewed in it (approved, skipped, edited) or went stale; with the
    /// block's text before and after, for the reviewed stack.
    case aiChange(docId: String, id: String, status: AIPageChange.Status, before: String?, after: String?)
    /// The change shown in the page (its bar open) is now this one; nil: none.
    case aiChangeFocus(docId: String, id: String?)
    case log(level: LogLevel, message: String, context: [String: String]?)
    /// A confirmation or note for the user, already in the page's language (shown as a toast).
    case toast(kind: String, message: String)
    /// A failure with its code (`ErrorCode.number`): logged with an incident id and shown with its message.
    case reportError(code: Int, detail: String?, context: [String: String]?)
    case setIcon(docId: String, icon: String?)
    case setCover(docId: String, cover: String?)
    /// Expects the asset URL as the reply.
    case saveAsset(fileExtension: String, data: Data)
    /// Chunked upload of a large file (video, audio, attachment). `beginUpload` replies with the upload id,
    /// `finishUpload` with the asset URL.
    case beginUpload(fileExtension: String, size: Int)
    case uploadChunk(id: String, data: Data)
    case finishUpload(id: String)
    case cancelUpload(id: String)
    /// Open an attachment with the system (Quick Look / default app), never inside the web view.
    case openAsset(url: String, name: String?)
    /// A page link was clicked (with the block to scroll to, for a link to a block).
    case openPage(id: String, block: String?)
    /// A page was dropped on the right edge of the page: open it in the split pane.
    case openInSplit(id: String)
    /// While split: a page held over the left page's right edge (it would replace the right side), or no longer.
    case splitDropHover(active: Bool)
    /// Any other link was clicked: the system opens it.
    case openLink(url: String)
    /// Furigana: expects `text` split into runs — `[{text, reading?}]`, a reading per kanji run — as the reply (nil
    /// when there is none).
    case suggestReading(text: String)
    /// A link card's details: expects `{title, description, icon}` (each may be null), or nil, as the reply.
    case linkPreview(url: String)
    /// Excalidraw's Library (the Mac, `setDrawings`): expects `{items}` as the reply, or nil when it can't be read.
    case drawingLibrary
    /// The Library changed: its items (checked by the editor) replace the stored ones.
    case saveDrawingLibrary(items: JSONValue)
}

public enum BridgeError: Error, Equatable {
    case notJSON
    case unknownType(String)
    case invalidPayload(String)
}

/// What `window.hikki.loadDocument(page)` receives (mirror of `PagePayload` in protocol.ts).
public enum PagePayload {
    public static func make(from record: DocumentRecord) throws -> [String: Any] {
        [
            "id": record.id,
            "title": record.title,
            "icon": record.icon ?? NSNull(),
            "cover": record.cover ?? NSNull(),
            "locked": record.isLocked,
            "content": try record.contentValue()?.foundationObject() ?? NSNull(),
        ]
    }
}

/// `window.hikki.exportPage(page, format)`: the formats the editor writes a page in (mirror of `ExportFormat`).
public enum ExportFormat: String, Sendable, CaseIterable {
    case markdown, html
}

/// `window.hikki.importDocument(text, format, fallbackTitle)`: the files it reads (mirror of `ImportFormat`).
public enum ImportFormat: String, Sendable, CaseIterable {
    case markdown, html, text

    /// By file extension (`md`, `markdown`, `html`, `htm`, `txt`…); nil for anything else.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": self = .markdown
        case "html", "htm", "xhtml": self = .html
        case "txt", "text": self = .text
        default: return nil
        }
    }
}

/// What `importDocument` returns (mirror of `ImportedPage`): the new page's title and body.
public struct ImportedPage: Decodable, Sendable, Equatable {
    public var title: String
    public var content: JSONValue
    /// Plain text and word count, as a save computes them.
    public var text: String
    public var wordCount: Int

    public init(title: String, content: JSONValue, text: String, wordCount: Int) {
        self.title = title
        self.content = content
        self.text = text
        self.wordCount = wordCount
    }

    /// Decodes the return value of `window.hikki.importDocument(…)`.
    public static func decode(scriptResult body: Any) throws -> ImportedPage {
        try JSONDecoder().decode(ImportedPage.self, from: jsonData(from: body))
    }
}

extension BridgeMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, snapshot, active, level, message, context, docId, icon, cover, fileExtension, dataBase64
        case size, id, url, block, text, headings, words, characters, name, top
        case threadId, quote, body, resolved, commentId, kind, code, detail, open, status, before, after, blockId
        case instruction, selection, mode, bff, color, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ready": self = .ready(protocolVersion: try c.decode(Int.self, forKey: .protocolVersion))
        case "changed": self = .changed(try c.decode(Snapshot.self, forKey: .snapshot))
        case "activeFormats": self = .activeFormats(try c.decode([String].self, forKey: .active))
        case "scroll":
            self = .scroll(docId: try c.decode(String.self, forKey: .docId), top: try c.decode(Double.self, forKey: .top))
        case "aiRequest":
            self = .aiRequest(try AIRequestPayload(from: decoder))
        case "aiCancel":
            self = .aiCancel(id: try c.decode(String.self, forKey: .id))
        case "aiHandoff":
            self = .aiHandoff(
                AIHandoff(
                    docId: try c.decode(String.self, forKey: .docId),
                    instruction: try c.decode(String.self, forKey: .instruction),
                    selection: try c.decode(String.self, forKey: .selection)))
        case "aiChange":
            self = .aiChange(
                docId: try c.decode(String.self, forKey: .docId), id: try c.decode(String.self, forKey: .id),
                status: try c.decode(AIPageChange.Status.self, forKey: .status),
                before: try c.decodeIfPresent(String.self, forKey: .before),
                after: try c.decodeIfPresent(String.self, forKey: .after))
        case "aiChangeFocus":
            self = .aiChangeFocus(docId: try c.decode(String.self, forKey: .docId), id: try c.decodeIfPresent(String.self, forKey: .id))
        case "commentCreate":
            self = .commentCreate(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decode(String.self, forKey: .threadId),
                quote: try c.decode(String.self, forKey: .quote), body: try c.decode(String.self, forKey: .body),
                blockId: try c.decodeIfPresent(String.self, forKey: .blockId))
        case "commentReply":
            self = .commentReply(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decode(String.self, forKey: .threadId),
                body: try c.decode(String.self, forKey: .body))
        case "commentResolve":
            self = .commentResolve(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decode(String.self, forKey: .threadId),
                resolved: try c.decode(Bool.self, forKey: .resolved))
        case "commentDelete":
            self = .commentDelete(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decode(String.self, forKey: .threadId),
                commentId: try c.decodeIfPresent(String.self, forKey: .commentId))
        case "commentEdit":
            self = .commentEdit(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decode(String.self, forKey: .threadId),
                commentId: try c.decode(String.self, forKey: .commentId), body: try c.decode(String.self, forKey: .body))
        case "selection":
            self = .selection(docId: try c.decode(String.self, forKey: .docId), text: try c.decode(String.self, forKey: .text))
        case "sheet":
            self = .sheet(open: try c.decode(Bool.self, forKey: .open))
        case "commentThread":
            self = .commentThread(
                docId: try c.decode(String.self, forKey: .docId), threadId: try c.decodeIfPresent(String.self, forKey: .threadId))
        case "coverSheet":
            self = .coverSheet(
                docId: try c.decode(String.self, forKey: .docId), cover: try c.decodeIfPresent(String.self, forKey: .cover),
                mode: try c.decode(CoverSheetMode.self, forKey: .mode),
                bff: try c.decodeIfPresent(String.self, forKey: .bff).flatMap(URL.init(string:)))
        case "iconSheet":
            self = .iconSheet(
                docId: try c.decode(String.self, forKey: .docId), id: try c.decode(String.self, forKey: .id),
                kind: try c.decode(IconSheetKind.self, forKey: .kind), icon: try c.decodeIfPresent(String.self, forKey: .icon),
                color: try c.decodeIfPresent(String.self, forKey: .color))
        case "fullScreen":
            self = .fullScreen(open: try c.decode(Bool.self, forKey: .open))
        case "activeHeading":
            self = .activeHeading(docId: try c.decode(String.self, forKey: .docId), id: try c.decodeIfPresent(String.self, forKey: .id))
        case "pageInfo":
            self = .pageInfo(
                docId: try c.decode(String.self, forKey: .docId), headings: try c.decode([OutlineHeading].self, forKey: .headings),
                words: try c.decode(Int.self, forKey: .words), characters: try c.decode(Int.self, forKey: .characters))
        case "toast":
            self = .toast(kind: try c.decode(String.self, forKey: .kind), message: try c.decode(String.self, forKey: .message))
        case "reportError":
            self = .reportError(
                code: try c.decode(Int.self, forKey: .code), detail: try c.decodeIfPresent(String.self, forKey: .detail),
                context: try c.decodeIfPresent([String: String].self, forKey: .context))
        case "log":
            self = .log(
                level: try c.decode(LogLevel.self, forKey: .level),
                message: try c.decode(String.self, forKey: .message),
                context: try c.decodeIfPresent([String: String].self, forKey: .context)
            )
        case "setIcon":
            self = .setIcon(docId: try c.decode(String.self, forKey: .docId), icon: try c.decodeIfPresent(String.self, forKey: .icon))
        case "setCover":
            self = .setCover(docId: try c.decode(String.self, forKey: .docId), cover: try c.decodeIfPresent(String.self, forKey: .cover))
        case "saveAsset":
            guard let data = Data(base64Encoded: try c.decode(String.self, forKey: .dataBase64)) else {
                throw BridgeError.invalidPayload("saveAsset: dataBase64 is not base64")
            }
            self = .saveAsset(fileExtension: try c.decode(String.self, forKey: .fileExtension), data: data)
        case "beginUpload":
            self = .beginUpload(
                fileExtension: try c.decode(String.self, forKey: .fileExtension), size: try c.decode(Int.self, forKey: .size))
        case "uploadChunk":
            guard let data = Data(base64Encoded: try c.decode(String.self, forKey: .dataBase64)) else {
                throw BridgeError.invalidPayload("uploadChunk: dataBase64 is not base64")
            }
            self = .uploadChunk(id: try c.decode(String.self, forKey: .id), data: data)
        case "finishUpload": self = .finishUpload(id: try c.decode(String.self, forKey: .id))
        case "cancelUpload": self = .cancelUpload(id: try c.decode(String.self, forKey: .id))
        case "openAsset":
            self = .openAsset(url: try c.decode(String.self, forKey: .url), name: try c.decodeIfPresent(String.self, forKey: .name))
        case "openPage":
            self = .openPage(id: try c.decode(String.self, forKey: .id), block: try c.decodeIfPresent(String.self, forKey: .block))
        case "openInSplit":
            self = .openInSplit(id: try c.decode(String.self, forKey: .id))
        case "splitDropHover":
            self = .splitDropHover(active: try c.decode(Bool.self, forKey: .active))
        case "openLink": self = .openLink(url: try c.decode(String.self, forKey: .url))
        case "suggestReading": self = .suggestReading(text: try c.decode(String.self, forKey: .text))
        case "linkPreview": self = .linkPreview(url: try c.decode(String.self, forKey: .url))
        case "drawingLibrary": self = .drawingLibrary
        case "saveDrawingLibrary": self = .saveDrawingLibrary(items: try c.decode(JSONValue.self, forKey: .items))
        default: throw BridgeError.unknownType(type)
        }
    }

    /// Decodes a `WKScriptMessage.body` (Foundation dictionaries/arrays bridged from JS).
    public static func decode(scriptMessageBody body: Any) throws -> BridgeMessage {
        try JSONDecoder().decode(BridgeMessage.self, from: jsonData(from: body))
    }
}

extension Snapshot {
    /// Decodes the return value of `window.hikki.flush()`.
    public static func decode(scriptResult body: Any) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: jsonData(from: body))
    }
}

private func jsonData(from body: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(body) else { throw BridgeError.notJSON }
    return try JSONSerialization.data(withJSONObject: body)
}

/// The editor's AI request: an `action` preset (`improve`, `fix`, `shorter`, `longer`, `tone:<tone>`,
/// `translate:<language>`, `explain`, `summarize`), `custom` with an `instruction`, or `diagram` (a drawing's Text to
/// diagram: the `instruction` as Mermaid, no units); the selected `units` as inline HTML; `answer` for prose instead of replacement blocks; nearby text as context. Page text: never logged.
public struct AIRequestPayload: Decodable, Equatable, Sendable {
    public struct Unit: Decodable, Equatable, Sendable {
        public var key: String
        public var html: String

        public init(key: String, html: String) {
            self.key = key
            self.html = html
        }
    }

    public struct Context: Decodable, Equatable, Sendable {
        public var title: String
        public var before: String
        public var after: String
        /// The suggestion being refined by a follow-up.
        public var previous: String?

        public init(title: String, before: String, after: String, previous: String? = nil) {
            self.title = title
            self.before = before
            self.after = after
            self.previous = previous
        }
    }

    /// A file the question is about (the block menu's Ask AI on a picture or a PDF): a workspace asset the app reads.
    public struct Media: Decodable, Equatable, Sendable {
        public enum Kind: String, Decodable, Sendable { case image, pdf }
        /// `hikki-editor://assets/<name>`.
        public var url: String
        public var kind: Kind
        public var name: String?

        public init(url: String, kind: Kind, name: String? = nil) {
            self.url = url
            self.kind = kind
            self.name = name
        }
    }

    public var id: String
    public var action: String
    public var instruction: String?
    public var answer: Bool
    public var units: [Unit]
    public var context: Context
    public var media: Media?
    /// A model picked for this request in the page's AI panel (a catalog id or "auto"); nil: the default.
    public var model: String?

    public init(
        id: String, action: String, instruction: String? = nil, answer: Bool, units: [Unit],
        context: Context, media: Media? = nil, model: String? = nil
    ) {
        self.media = media
        self.model = model
        self.id = id
        self.action = action
        self.instruction = instruction
        self.answer = answer
        self.units = units
        self.context = context
    }
}

/// What the cover's sheet opens on: the cover's actions (Change cover, Remove) or the picker.
public enum CoverSheetMode: String, Sendable, Equatable, Decodable {
    case actions, picker
}

/// What an icon picker is for: the page's icon, or a callout's (which also picks its background).
public enum IconSheetKind: String, Sendable, Equatable, Decodable {
    case page, callout
}
