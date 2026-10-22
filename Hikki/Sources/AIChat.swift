import HikkiAI
import HikkiCore
import HikkiUI
import Observation
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import PhotosUI
#endif

/// A file attached to a question (a picture or a PDF), ready for the model.
struct ChatAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let part: AIMessage.Part

    /// The picture's data, for its thumbnail; nil for a document.
    var imageData: Data? {
        if case .image(let data, _) = part { data } else { nil }
    }
}

/// A picture's bytes as an image to draw.
enum PlatformImage {
    static func image(_ data: Data) -> Image? {
        #if os(iOS)
            UIImage(data: data).map(Image.init(uiImage:))
        #else
            NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

/// A conversation with AI (Ask AI): the turns, the model picked for it, web search on or off, and the page it is
/// about. One per window; the answer streams into the last message. Page text goes to the model only as context, and
/// nothing of it is logged.
///
/// Each page has one conversation, kept in the workspace folder (`PageChats`: `ai/<page id>.json`, synced like the
/// page): moving to another page shows that page's, New chat empties it (Undo puts it back). One asked from Home,
/// about no page, isn't kept. A long one is compacted (`ChatCompaction`): its older turns go to the model as a summary.
@MainActor
@Observable
final class AIChat {
    struct Message: Identifiable, Equatable {
        typealias Role = ChatTurn.Role
        var id = UUID().uuidString.lowercased()
        let role: Role
        var text: String
        var sentAt = Date()
        /// Files sent with a question (shown in its bubble; sent with that turn only).
        var attachments: [ChatAttachment] = []
        /// Names of files sent with a question in an earlier session (the files themselves aren't kept).
        var attachmentNames: [String] = []
        var citations: [AICitation] = []
        /// Pictures the answer's web search found.
        var images: [ChatImage] = []
        /// Changes the answer proposes to the page, with how each was reviewed.
        var changes: [AIPageChange] = []
        /// Pictures the answer makes (OpenAI's image model), with how far each got.
        var pictures: [ChatPicture] = []
        /// Where in the page the answer's pictures go (the chat was opened for pictures from there).
        var picturePlace: PicturePlace?
        /// A web search under way (its query, when the provider says it).
        var searching: String?
        /// The model's thinking and searches so far (the timeline above the answer).
        var thinking: ChatThinking?
        var error: String?
    }

    /// How many pictures a web search may bring.
    static let imageResults = 6

    var messages: [Message] = []
    /// What the conversation's older turns said, sent in their place (`ChatCompaction`).
    private(set) var summary: ChatSummary?
    /// The older turns are being summarized before the question goes.
    private(set) var isCompacting = false
    /// Where conversations are kept (nil until the workspace folder is known).
    @ObservationIgnored var chatStore: () -> PageChats? = { AppModel.current?.chats }
    /// The window's page editor: the open page's blocks for an answer to change, and its changes offered there.
    @ObservationIgnored weak var editor: EditorController?
    /// The page blocks the answer being written was given (its changes may name only these).
    @ObservationIgnored private var askedBlocks: Set<String>?
    var draft = ""
    var webSearch = true
    /// "auto" or a catalog id; starts from Settings → AI's default.
    var modelChoice = UserDefaults.standard.string(forKey: AIPreferences.modelKey) ?? AIModelCatalog.autoID
    /// The page the chat is about (cleared from the composer to ask without it).
    var pageID: String?
    /// The page open beside the chat (offered first by @, even after its chip was removed).
    private(set) var openPageID: String?

    /// The chat now sits beside `id`: it becomes the page asked about (mentions of other pages stay).
    func show(page id: String?) {
        guard id != openPageID else { return }
        // An answer still arriving belongs to the page it was asked on: it stops, and what came is kept there.
        if isStreaming { stop() }
        // So do its pictures (kept as stopped there, with Try again).
        stopPictures()
        openPageID = id
        pageID = id
        extraPageIDs.removeAll { $0 == id }
        load()
    }

    /// The open page's kept conversation (none for no page).
    private func load() {
        guard let id = openPageID, let chats = chatStore() else {
            messages = []
            summary = nil
            return
        }
        do {
            let conversation = try chats.conversation(of: id, retention: AIPreferences.chatRetention)
            messages = conversation.turns.map(Message.init)
            summary = conversation.summary
            offerChanges()
        } catch {
            messages = []
            summary = nil
            Log.warn("AI chat not read: \(error)", category: "ai", context: ["docId": id])
        }
    }

    /// Keeps turns of the open page's conversation.
    private func keep(_ kept: [Message]) {
        guard let id = openPageID, let chats = chatStore(), !kept.isEmpty else { return }
        do {
            try chats.save(kept.map(\.turn), pageId: id)
        } catch {
            Log.warn("AI chat not kept: \(error)", category: "ai", context: ["docId": id])
        }
    }

    /// Other pages the user @-mentioned, in the order added.
    var extraPageIDs: [String] = []
    /// The passage last selected in the window's page (follows the selection; cleared from the composer to ask without
    /// it), with the page it was selected in.
    var selection: EditorSelection?
    /// The passage that goes with the question: only one selected in the page asked about.
    var contextSelection: String? { selection?.text(in: pageID) }
    /// Files to send with the next question.
    var attachments: [ChatAttachment] = []
    /// Why the last file couldn't be attached (shown under the composer until the next attempt).
    var attachError: String?
    private(set) var isStreaming = false
    /// The answer streaming in (one at a time; a stopped one ends silently).
    @ObservationIgnored private let run = AIStreamRun()

    /// Adds a file to the next question: a picture (scaled down) or a PDF; anything else is refused with a reason.
    func attach(_ data: Data, type: UTType, name: String) {
        attachError = nil
        guard attachments.count < AIAttachments.maxCount else {
            attachError = String(localized: "app:ai.attach.tooMany")
            return
        }
        do {
            attachments.append(ChatAttachment(name: name, part: try AIAttachments.part(data, type: type, name: name)))
        } catch AIAttachments.Failure.tooLarge {
            attachError = String(localized: "app:ai.attach.tooLarge")
        } catch AIAttachments.Failure.unsupported {
            attachError = String(localized: "app:ai.attach.unsupported")
        } catch {
            attachError = String(localized: "app:ai.attach.unreadable")
        }
    }

    /// A file on disk (picked or dropped), read and attached.
    func attach(fileAt url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            attachError = String(localized: "app:ai.attach.unreadable")
            return
        }
        attach(data, type: UTType(filenameExtension: url.pathExtension) ?? .data, name: url.lastPathComponent)
    }

    /// Adds a page the user @-mentioned (the open one back, if it was removed).
    func mention(_ id: String) {
        if id == openPageID {
            pageID = id
        } else if !extraPageIDs.contains(id) {
            extraPageIDs.append(id)
        }
    }

    /// Sends `text` (or the draft) with the attached files, the open page, the @-mentioned pages and the selection as
    /// context.
    func send(_ text: String? = nil, store: DocumentStore?) {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !attachments.isEmpty, !isStreaming else { return }
        // A question sent for the user (a suggestion, a handoff from the page) leaves what they were typing alone.
        if text == nil { draft = "" }
        attachError = nil
        let asked = Message(role: .user, text: question, attachments: attachments)
        // Set up for pictures, the answer's go where the page asked for them; else where the last ones went.
        let place = pictureSetup?.place ?? messages.last(where: { $0.picturePlace != nil })?.picturePlace
        let pictureRequest = pictureSetup.map { (shape: $0.shape, detailed: $0.detailed) }
        pictureSetup = nil
        messages.append(asked)
        keep([asked])
        attachments = []
        messages.append(Message(role: .assistant, text: "", picturePlace: place))
        let pages = ([pageID].compactMap { $0 } + extraPageIDs)
            .compactMap { try? store?.document(id: $0) }
            .map { (title: $0.title, text: $0.plainText) }
        switch AIService.connect(modelChoice) {
        case .failure(let error):
            finish(error: error)
        case .success(let (model, client)):
            isStreaming = true
            Task { [weak self] in
                let blocks = await self?.openPageBlocks()
                await self?.compactIfNeeded(model: model, client: client)
                self?.ask(pages: pages, blocks: blocks, model: model, client: client, pictureRequest: pictureRequest)
            }
        }
    }

    /// The open page's blocks with their ids, when it is the page asked about and its editor has it: the answer may
    /// then propose changes to it.
    private func openPageBlocks() async -> [[String: String]]? {
        guard let page = pageID, page == openPageID, let blocks = await editor?.aiPageBlocks(for: page), !blocks.isEmpty
        else { return nil }
        return blocks
    }

    /// The turns since the summary, as the model gets them (the answer being written left out).
    private var turnsToSend: [Message] {
        let asked = messages.dropLast()
        guard let through = summary?.through, let index = asked.firstIndex(where: { $0.id == through }) else {
            return Array(asked)
        }
        return Array(asked[asked.index(after: index)...])
    }

    /// A long conversation's older turns become (part of) its summary before the question goes; if that fails the
    /// question goes with everything, as before.
    private func compactIfNeeded(model: AIModel, client: any AIClient) async {
        let turns = turnsToSend
        guard let cut = ChatCompaction.cut(turns.map { (isUser: $0.role == .user, text: $0.text) }) else { return }
        let older = turns[..<cut]
        let page = openPageID
        isCompacting = true
        defer { isCompacting = false }
        let request = AIPrompts.summarizeChat(
            older.map { (isUser: $0.role == .user, text: $0.text) }, previous: summary?.text, model: model)
        var text = ""
        do {
            for try await event in client.stream(request) {
                if case .text(let delta) = event { text += delta }
            }
        } catch {
            Log.warn("AI chat not compacted: \(error)", category: "ai", context: ["turns": "\(older.count)"])
            return
        }
        guard isStreaming, openPageID == page, let last = older.last, !text.isEmpty else { return }
        let compacted = ChatSummary(text: text, through: last.id, createdAt: .now)
        summary = compacted
        Log.info("AI chat compacted", category: "ai", context: ["turns": "\(older.count)"])
        if let id = openPageID, let chats = chatStore() { try? chats.setSummary(compacted, pageId: id) }
    }

    private func ask(
        pages: [(title: String, text: String)], blocks: [[String: String]]?, model: AIModel, client: any AIClient,
        pictureRequest: (shape: PictureShape, detailed: Bool)?
    ) {
        // Stopped (or moved to another page) while compacting.
        guard isStreaming else { return }
        askedBlocks = blocks.map { Set($0.compactMap { $0["id"] }) }
        let turns: [AIMessage] = turnsToSend.map { message in
            // An answer's pictures are named by id, so a later answer can change one.
            guard message.role == .user else {
                let made = message.pictures.filter { $0.status == .done }.map { AIPictures.reference(id: $0.id, prompt: $0.prompt) }
                return .assistant(made.isEmpty ? message.text : message.text + "\n\n" + made.joined(separator: "\n"))
            }
            var parts: [AIMessage.Part] = [.text(message.text)] + message.attachments.map(\.part)
            if !message.attachmentNames.isEmpty {
                parts.append(.text("(Files attached then, not available now: \(message.attachmentNames.joined(separator: ", ")))"))
            }
            return AIMessage(role: .user, parts: parts)
        }
        var request = AIPrompts.chat(
            turns, summary: summary?.text, pages: pages, openPageBlocks: blocks.map { AIPageEdits.pageJSON($0) },
            selection: contextSelection, model: model, webSearch: webSearch, language: AIService.appLanguage,
            pictures: canMakePictures, pictureRequest: pictureRequest)
        // The model thinks first; its thinking streams into the answer's timeline.
        request.reasoning = true
        // A search may bring pictures too, shown under the answer (OpenAI's search; Anthropic's has none).
        if webSearch { request.imageResults = Self.imageResults }
        Log.info(
            "AI chat", category: "ai",
            context: [
                "model": model.id, "turns": "\(turns.count)", "pages": "\(pages.count)",
                "files": "\(messages[messages.count - 2].attachments.count)", "summary": summary == nil ? "no" : "yes",
                "blocks": "\(blocks?.count ?? 0)",
            ])
        run.start(
            client.stream(request), onEvent: { [weak self] event in self?.apply(event) },
            onEnd: { [weak self] error in self?.finish(error: error) })
    }

    /// A picture can go into the page the chat sits beside.
    var canAddPictures: Bool { openPageID != nil && editor != nil }

    /// A picture the answer's search found, added to the open page at its caret.
    func addPicture(_ image: ChatImage) {
        guard let url = image.webURL, let editor else { return }
        Task { await editor.insertWebImage(url, caption: image.caption) }
    }

    func stop() {
        stopPictures()
        run.stop()
        isStreaming = false
        guard let last = messages.indices.last else { return }
        messages[last].searching = nil
        // What arrived of a stopped answer stays.
        if messages[last].role == .assistant, !messages[last].text.isEmpty { keep([messages[last]]) }
    }

    /// New chat (same page and model): the conversation empties; the toast's Undo brings it back.
    func clear() {
        stop()
        let cleared = messages
        let clearedSummary = summary
        messages = []
        summary = nil
        guard !cleared.isEmpty else { return }
        let page = openPageID
        if let page { editor?.offerAIChanges([], for: page) }
        var previous: ChatConversation?
        if let page, let chats = chatStore() {
            do {
                previous = try chats.clear(pageId: page)
            } catch {
                Log.warn("AI chat not cleared: \(error)", category: "ai", context: ["docId": page])
            }
        }
        Toasts.shared.show(.info, String(localized: "app:ai.chatCleared"), actionTitle: "app:format.undo") { [weak self] in
            guard let self else { return }
            if let page, let previous, let chats = self.chatStore() { try? chats.restore(previous, pageId: page) }
            guard self.openPageID == page else { return }
            if page != nil, previous != nil {
                self.load()
            } else {
                self.messages = cleared + self.messages
                self.summary = clearedSummary
                self.offerChanges()
            }
        }
    }

    // MARK: - Pictures

    /// The composer set up for pictures (the page asked for them: "/" AI pictures, a selection's or a picture's Make):
    /// where they go, and the shape and model the user picked for them. Sent with the next question, then cleared.
    struct PictureSetup: Equatable {
        var place: PicturePlace
        var shape: PictureShape = .wide
        var detailed = false
        /// It changes a picture in the page (attached to the question): adding replaces it.
        var changing: Bool { place.replace }
    }

    var pictureSetup: PictureSetup?
    /// Pictures can be made: there is an OpenAI key (the image model is OpenAI's).
    var canMakePictures: Bool { AIPreferences.key(.openAI) != nil }
    /// Pictures being made — waiting, or drawing two at a time — and the rough versions they have shown (not kept).
    private(set) var pictureQueue = PictureQueue(lanes: 2)
    private(set) var roughPictures: [String: Data] = [:]
    @ObservationIgnored private var pictureRequests: [String: PictureRequest] = [:]
    @ObservationIgnored private var pictureRuns: [String: Task<Void, Never>] = [:]
    /// Made pictures, read once from their files.
    @ObservationIgnored private var pictureImages: [String: Image] = [:]
    /// Pictures went into the page (the iPhone sheet closes on it).
    @ObservationIgnored var onPicturesAdded: (() -> Void)?
    var isMakingPictures: Bool { !pictureQueue.isEmpty }

    /// The pictures a finished answer asks for: it may change an earlier one by id, or the picture attached to the
    /// question.
    private func proposedPictures(answer index: Int) -> [ChatPicture] {
        var known = Set(messages.flatMap(\.pictures).filter { $0.status == .done }.map(\.id))
        if attachedPicture(before: index) != nil { known.insert(AIPictures.attached) }
        let id = messages[index].id
        return AIPictures.pictures(in: messages[index].text, known: known).enumerated().map { n, spec in
            ChatPicture(id: "\(id)-\(n)", prompt: spec.prompt, shape: spec.shape.rawValue, detailed: spec.detailed, from: spec.from)
        }
    }

    /// The picture attached to the question an answer replies to.
    private func attachedPicture(before index: Int) -> (data: Data, mimeType: String)? {
        guard index > 0 else { return nil }
        for attachment in messages[index - 1].attachments {
            if case .image(let data, let mimeType) = attachment.part { return (data, mimeType) }
        }
        return nil
    }

    /// Where a picture is (and its index), in whichever answer has it.
    private func picturePosition(_ id: String) -> (message: Int, picture: Int)? {
        for (m, message) in messages.enumerated() {
            if let p = message.pictures.firstIndex(where: { $0.id == id }) { return (m, p) }
        }
        return nil
    }

    /// The file a made picture is (a workspace asset).
    private func pictureFile(_ asset: String?) -> URL? {
        guard let asset, asset.hasPrefix(AssetStore.urlPrefix) else { return nil }
        return AppModel.current?.assets.file(named: String(asset.dropFirst(AssetStore.urlPrefix.count)))
    }

    /// What a picture changes, read for the image model: the attached picture, or an earlier made one. Gone (the
    /// attachment isn't kept past a restart): it is made anew from its words.
    private func source(of picture: ChatPicture, answer index: Int) -> (data: Data, mimeType: String)? {
        guard let from = picture.from else { return nil }
        if from == AIPictures.attached { return attachedPicture(before: index) }
        guard let done = messages.flatMap(\.pictures).first(where: { $0.id == from }), let file = pictureFile(done.asset),
            let data = try? Data(contentsOf: file)
        else { return nil }
        return (data, UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "image/jpeg")
    }

    /// Makes an answer's pictures (or one again): queued, two at a time.
    private func makePictures(_ ids: [String], answer: String) {
        guard let index = messages.firstIndex(where: { $0.id == answer }) else { return }
        for id in ids {
            guard let p = messages[index].pictures.firstIndex(where: { $0.id == id }) else { continue }
            let picture = messages[index].pictures[p]
            let shape = PictureShape(rawValue: picture.shape) ?? .wide
            messages[index].pictures[p].status = .making
            messages[index].pictures[p].error = nil
            pictureRequests[id] = PictureRequest(
                prompt: picture.prompt, shape: shape, detailed: picture.detailed, source: source(of: picture, answer: index))
        }
        if !ids.isEmpty { Log.info("AI pictures", category: "ai", context: ["count": "\(ids.count)"]) }
        start(pictureQueue.add(ids))
    }

    private func start(_ ids: [String]) {
        for id in ids {
            guard let request = pictureRequests.removeValue(forKey: id) else { continue }
            pictureRuns[id] = Task { [weak self] in await self?.makePicture(id, request) }
        }
    }

    private func makePicture(_ id: String, _ request: PictureRequest) async {
        var failure: Error?
        var made = false
        do {
            guard let base = AIPreferences.base(.openAI) else { throw AIError.badBaseURL(.openAI) }
            let client = try OpenAIPictureClient.make(key: AIPreferences.key(.openAI), base: base)
            for try await event in client.make(request) {
                switch event {
                case .partial(let data):
                    roughPictures[id] = data
                case .done(let data, let fileExtension):
                    guard let assets = AppModel.current?.assets else { throw AIError.cancelled }
                    let src: String
                    do {
                        src = try assets.save(data, fileExtension: fileExtension, maxBytes: data.count)
                    } catch {
                        Incident.report(.aiPictureSaveFailed, error, category: "ai")
                        updatePicture(id) {
                            $0.status = .failed
                            $0.error = Self.saveFailed
                        }
                        made = true
                        continue
                    }
                    made = true
                    updatePicture(id) {
                        $0.status = .done
                        $0.asset = src
                    }
                }
            }
        } catch {
            failure = error
        }
        // Stopped: `stopPictures` already marked and kept it (and a Try again since may be drawing it anew).
        if Task.isCancelled { return }
        if failure as? AIError == .cancelled {
            updatePicture(id) { $0.status = .stopped }
        } else if !made {
            let error = failure as? AIError ?? .invalidResponse
            if let code = error.errorCode { Incident.report(code, error, category: "ai") }
            updatePicture(id) {
                $0.status = .failed
                $0.error = error.legacyName
            }
        }
        roughPictures[id] = nil
        pictureRuns[id] = nil
        if let (m, _) = picturePosition(id) { keep([messages[m]]) }
        start(pictureQueue.finished(id))
    }

    private func updatePicture(_ id: String, _ change: (inout ChatPicture) -> Void) {
        guard let (m, p) = picturePosition(id) else { return }
        change(&messages[m].pictures[p])
    }

    /// Pictures being made stop (Stop, New chat, another page): they say so, with Try again.
    private func stopPictures() {
        let stopped = pictureQueue.stopAll()
        pictureRuns.values.forEach { $0.cancel() }
        pictureRuns = [:]
        pictureRequests = [:]
        roughPictures = [:]
        for id in stopped { updatePicture(id) { if $0.status == .making { $0.status = .stopped } } }
        let touched = Set(stopped.compactMap { picturePosition($0)?.message })
        if !touched.isEmpty { keep(touched.sorted().map { messages[$0] }) }
    }

    /// Try again: the picture is made once more (a made one is replaced on its tile).
    func retryPicture(_ id: String) {
        guard let (m, _) = picturePosition(id), !pictureQueue.contains(id) else { return }
        makePictures([id], answer: messages[m].id)
    }

    /// What a tile shows: the made picture, or the rough version so far.
    func pictureImage(_ picture: ChatPicture) -> Image? {
        if let rough = roughPictures[picture.id] { return PlatformImage.image(rough) }
        guard picture.status == .done, let asset = picture.asset else { return nil }
        if let image = pictureImages[asset] { return image }
        guard let file = pictureFile(asset), let data = try? Data(contentsOf: file), let image = PlatformImage.image(data) else {
            return nil
        }
        pictureImages[asset] = image
        return image
    }

    /// Made pictures put into the page the chat sits beside, where the answer's pictures go; marked added there.
    func addPictures(_ ids: [String], answer: String) {
        guard let page = openPageID, let editor, let m = messages.firstIndex(where: { $0.id == answer }) else { return }
        let pictures = messages[m].pictures.filter { ids.contains($0.id) && $0.status == .done && $0.asset != nil }
        guard !pictures.isEmpty else { return }
        let place = messages[m].picturePlace
        let items = pictures.map { ["src": $0.asset ?? "", "alt": String($0.prompt.prefix(200))] }
        Task { [weak self] in
            guard await editor.insertPictures(docId: page, items: items, place: place), let self else { return }
            Log.info("AI pictures added", category: "ai", context: ["count": "\(items.count)"])
            for picture in pictures { self.updatePicture(picture.id) { $0.added = true } }
            if let m = self.messages.firstIndex(where: { $0.id == answer }) { self.keep([self.messages[m]]) }
            self.onPicturesAdded?()
        }
    }

    /// A made picture as the page's cover.
    func useAsCover(_ id: String) {
        guard let page = openPageID, let editor, let (m, p) = picturePosition(id), let asset = messages[m].pictures[p].asset
        else { return }
        Task { await editor.applyCover(asset, docId: page) }
    }

    /// `ChatPicture.error` for a picture made but not stored.
    static let saveFailed = "saveFailed"

    /// Why a picture wasn't made, in the user's words (its error's name, as kept).
    static func pictureFailure(_ picture: ChatPicture) -> String {
        if picture.status == .stopped { return String(localized: "app:ai.pictures.stopped") }
        let error: AIError? =
            switch picture.error {
            case "missingKey": .missingKey(.openAI)
            case "badBaseURL": .badBaseURL(.openAI)
            case "unauthorized": .unauthorized
            case "rateLimited": .rateLimited
            case "unavailable": .unavailable
            case "offline": .offline
            case "rejected": .rejected("")
            case "refused": .refused
            case Self.saveFailed: nil
            default: .invalidResponse
            }
        return error.map(AIService.message(for:)) ?? String(localized: "app:ai.pictures.saveFailed")
    }

    // MARK: - Changes to the page

    /// The changes a finished answer proposes, checked against the blocks it was given.
    private func proposedChanges(in message: Message, blocks: Set<String>) -> [AIPageChange] {
        AIPageEdits.changes(in: message.text, blocks: blocks).enumerated().compactMap { index, change in
            guard let kind = AIPageChange.Kind(rawValue: change.kind) else { return nil }
            return AIPageChange(
                id: "\(message.id)-\(index)", kind: kind, block: change.block, after: change.after, html: change.html,
                blockType: change.type, title: change.title, why: change.why)
        }
    }

    /// Every change of the open page's conversation goes to its editor (the pending ones are shown there).
    private func offerChanges() {
        guard let page = openPageID else { return }
        editor?.offerAIChanges(messages.flatMap(\.changes), for: page)
    }

    /// The change shown in the page now (its card is marked).
    var focusedChange: String? {
        guard let focused = editor?.focusedAIChange, focused.docId == openPageID else { return nil }
        return focused.id
    }

    func focusChange(_ id: String) { editor?.focusAIChange(id) }
    func approveChange(_ id: String) { editor?.resolveAIChange(id, approve: true) }
    func skipChange(_ id: String) { editor?.resolveAIChange(id, approve: false) }
    func approveAllChanges() { editor?.approveAllAIChanges() }

    /// The page reports a verdict (or a change gone stale): the card follows, and is kept.
    func changeReviewed(
        docId: String, id: String, status: AIPageChange.Status, before: String?, after: String?
    ) {
        guard docId == openPageID,
            let m = messages.firstIndex(where: { $0.changes.contains { $0.id == id } }),
            let c = messages[m].changes.firstIndex(where: { $0.id == id })
        else { return }
        messages[m].changes[c].status = status
        messages[m].changes[c].reviewedAt = .now
        if let before { messages[m].changes[c].beforeText = before }
        if let after { messages[m].changes[c].afterText = after }
        keep([messages[m]])
    }

    private func apply(_ event: AIEvent) {
        guard !messages.isEmpty else { return }
        let last = messages.count - 1
        switch event {
        case .text(let delta):
            // The first words end the thinking: the timeline keeps how long it took.
            if messages[last].text.isEmpty, messages[last].thinking != nil, messages[last].thinking?.seconds == nil {
                messages[last].thinking?.seconds = Date.now.timeIntervalSince(messages[last].sentAt)
            }
            messages[last].text += delta
            messages[last].searching = nil
        case .reasoningStep:
            messages[last].thinking = ChatTimeline.step(.thinking, in: messages[last].thinking)
        case .reasoning(let delta):
            messages[last].thinking = ChatTimeline.thought(delta, in: messages[last].thinking)
        case .searching(let query):
            messages[last].searching = query ?? ""
            messages[last].thinking = ChatTimeline.searched(query, in: messages[last].thinking)
        case .citation(let citation):
            // Only web pages, once each (the model's search supplies them).
            guard ChatCitation(url: citation.url, title: nil).webURL != nil,
                !messages[last].citations.contains(citation)
            else { return }
            messages[last].citations.append(citation)
        case .image(let image):
            let picture = ChatImage(url: image.url, thumbnail: image.thumbnail, source: image.source, caption: image.caption)
            guard picture.webURL != nil, !messages[last].images.contains(where: { $0.url == picture.url }) else { return }
            messages[last].images.append(picture)
        case .finished:
            break
        }
    }

    private func finish(error: AIError?) {
        isStreaming = false
        guard let last = messages.indices.last else { return }
        messages[last].searching = nil
        if messages[last].role == .assistant, !messages[last].text.isEmpty {
            messages[last].sentAt = .now
            if error == nil, let blocks = askedBlocks { messages[last].changes = proposedChanges(in: messages[last], blocks: blocks) }
            if error == nil { messages[last].pictures = proposedPictures(answer: last) }
            keep([messages[last]])
            if !messages[last].changes.isEmpty { offerChanges() }
            makePictures(messages[last].pictures.map(\.id), answer: messages[last].id)
        }
        askedBlocks = nil
        if let error {
            messages[last].error = AIService.message(for: error)
            if let code = error.errorCode { Incident.report(code, error, category: "ai") }
        } else if messages[last].text.isEmpty {
            messages[last].error = AIService.message(for: .invalidResponse)
        }
    }
}

extension AIChat.Message {
    /// A kept turn, shown again.
    init(_ turn: ChatTurn) {
        self.init(
            id: turn.id, role: turn.role, text: turn.text, sentAt: turn.sentAt, attachmentNames: turn.attachments,
            citations: turn.citations.filter { $0.webURL != nil }.map { AICitation(url: $0.url, title: $0.title) },
            images: (turn.images ?? []).filter { $0.webURL != nil }, changes: turn.changes ?? [],
            // One being made when the chat was left (or on another device) isn't being made here.
            pictures: (turn.pictures ?? []).map(\.restored),
            picturePlace: turn.picturePlace, thinking: turn.thinking)
    }

    /// The turn as it is kept.
    var turn: ChatTurn {
        ChatTurn(
            id: id, role: role, text: text, sentAt: sentAt, attachments: attachmentNames + attachments.map(\.name),
            citations: citations.map { ChatCitation(url: $0.url, title: $0.title) }, changes: changes.isEmpty ? nil : changes,
            thinking: thinking.flatMap(ChatTimeline.kept), images: images.isEmpty ? nil : images,
            pictures: pictures.isEmpty ? nil : pictures, picturePlace: picturePlace)
    }
}

/// Ask AI on iPhone: the conversation (`AIChatView`) in a sheet, with close, a new chat and the model menu on top.
struct AIChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var chat: AIChat

    var body: some View {
        screen.screenTitle(String(localized: "app:ai.ask"))
    }

    @ViewBuilder private var screen: some View {
        NavigationStack {
            AIChatView(chat: chat)
                .navigationTitle(Text("app:ai.ask"))
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            IconLabel("app:common.close", icon: .x)
                        }
                        .accessibilityIdentifier("ai-chat-close")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        AIChatActions(chat: chat)
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}

/// A new chat (once there is one) — the sheet's toolbar, the side panel's header; its tooltip names the shortcut
/// (⇧⌘N, File → New AI Chat). The model is picked in the composer.
struct AIChatActions: View {
    @Bindable var chat: AIChat

    var body: some View {
        if !chat.messages.isEmpty {
            Button {
                chat.clear()
            } label: {
                IconLabel("app:ai.newChat", icon: .notePencil)
            }
            .help(Text(verbatim: String(localized: "app:ai.newChat") + "  " + Shortcut.newChat.display))
            .accessibilityIdentifier("ai-chat-new")
        }
    }
}

/// The conversation: the turns, suggestions to start one about the open page, and the composer — the page as a
/// removable chip, web search on or off. Shared by the iPhone sheet and the Mac/iPad side panel.
struct AIChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var chat: AIChat
    @FocusState private var composing: Bool
    @State private var mentionIndex = 0
    @State private var pickingFiles = false
    @State private var dropTargeted = false
    @State private var layerTargeted = false
    #if os(iOS)
        @State private var pickingPhotos = false
        @State private var photoItems: [PhotosPickerItem] = []
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s5) {
                    // Notion's: who answers and when the conversation began, over it.
                    if let first = chat.messages.first {
                        Text("app:ai.chat.header \(first.sentAt.formatted(date: .omitted, time: .shortened))")
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(chat.messages) { message in
                        ChatBubble(
                            message: message, isStreaming: chat.isStreaming && message == chat.messages.last,
                            isCompacting: chat.isCompacting, chat: chat
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s3)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) {
                if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .overlay {
                if chat.messages.isEmpty { empty }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    // MARK: Parts

    private var contextPage: PageSummary? { chat.pageID.flatMap(model.tree.page) }

    private var empty: some View {
        VStack(spacing: Spacing.s4) {
            AIGlyph(size: Spacing.s10)
            Text(contextPage == nil ? "app:ai.chat.empty" : "app:ai.chat.emptyPage")
                .font(.hk(.base))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.s8)
    }

    private var suggestions: [LocalizedStringResource] {
        contextPage == nil
            ? ["app:ai.suggest.brainstorm", "app:ai.suggest.explain"]
            : ["app:ai.suggest.summarize", "app:ai.suggest.quiz", "app:ai.suggest.keyPoints"]
    }

    /// Notion's composer: a card on the page's surface — the attached files, then what the question is about as
    /// chips (the open page, @-mentioned pages, the selected passage), the field, then attach, web search, the model
    /// and send along the bottom. Typing @ offers pages to add; files can be dropped or pasted on it.
    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let query = mentionQuery {
                MentionList(query: query, chat: chat, highlighted: $mentionIndex) { pick($0) }
            } else if chat.messages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.s1_5) {
                        ForEach(suggestions, id: \.key) { suggestion in
                            Button {
                                chat.send(String(localized: suggestion), store: model.store)
                            } label: {
                                Text(suggestion).modifier(ChipStyle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if !chat.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Spacing.s2) {
                            ForEach(chat.attachments) { attachment in
                                AttachmentThumbnail(attachment: attachment) {
                                    chat.attachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                        .padding(.top, Spacing.s1)
                    }
                    .scrollIndicators(.hidden)
                }
                if let setup = chat.pictureSetup { pictureChips(setup) }
                if !contextPages.isEmpty || chat.contextSelection != nil {
                    ScrollView(.horizontal) {
                        HStack(spacing: Spacing.s1_5) {
                            ForEach(contextPages) { page in
                                ContextChip(label: "app:ai.chat.removePage", remove: { remove(page.id) }) {
                                    PageIcon(page.icon, size: TextSize.sm.rawValue)
                                    Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                                }
                            }
                            if let selection = chat.contextSelection {
                                ContextChip(label: "app:ai.chat.removeSelection", remove: { chat.selection = nil }) {
                                    IconView(.textT, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
                                    // The passage's own words, shown as-is.
                                    Text(verbatim: selection.replacingOccurrences(of: "\n", with: " "))
                                        .frame(maxWidth: Size.recentCard + Spacing.s12, alignment: .leading)
                                }
                                .accessibilityIdentifier("ai-chat-selection")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                field
                HStack(spacing: Spacing.s1) {
                    attachButton
                    Toggle(isOn: $chat.webSearch) {
                        IconLabel("app:ai.chat.web", icon: .globe).labelStyle(.iconOnly)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.plain)
                    .foregroundStyle(chat.webSearch ? AnyShapeStyle(ColorTone.standard.ink) : AnyShapeStyle(Theme.mutedForeground))
                    .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
                    .background(chat.webSearch ? ColorTone.standard.selectionFill : .clear, in: .circle)
                    .help("app:ai.chat.web")
                    .accessibilityIdentifier("ai-chat-web")
                    Spacer(minLength: Spacing.s1)
                    AIModelMenu(chat: chat).foregroundStyle(Theme.subtleForeground)
                        .padding(.trailing, Spacing.s2)
                    sendButton
                }
            }
            .padding(Spacing.s3)
            .background(Theme.background, in: .rect(cornerRadius: Radius.xl + Spacing.s1))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl + Spacing.s1)
                    .strokeBorder(
                        dropTargeted || layerTargeted ? ColorTone.standard.fill : Theme.border,
                        lineWidth: dropTargeted || layerTargeted ? 2 : 1)
            )
            .shadow(color: Theme.border, radius: Spacing.s2, y: Spacing.s0_5)
            .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $dropTargeted) { providers in
                receive(providers)
                return true
            }
            // The field is a native text view that takes drops itself (it would type the file's path): while
            // something is dragged over the card, a clear layer on top of everything takes the drop instead. It
            // exists only during the drag, so clicks and typing never meet it.
            .overlay {
                if dropTargeted || layerTargeted {
                    Color.clear
                        .contentShape(.rect(cornerRadius: Radius.xl + Spacing.s1))
                        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $layerTargeted) { providers in
                            receive(providers)
                            return true
                        }
                }
            }
            if let error = chat.attachError {
                Text(verbatim: error).font(.hk(.xs)).foregroundStyle(.red).padding(.horizontal, Spacing.s1)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.bottom, Spacing.s3)
        .padding(.top, Spacing.s1)
        .background(Theme.background)
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(chat.attach(fileAt:)) }
        }
        #if os(iOS)
            .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: AIAttachments.maxCount, matching: .images)
            .onChange(of: photoItems) { _, items in
                for item in items {
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            chat.attach(data, type: .image, name: String(localized: "app:ai.attach.photo"))
                        }
                    }
                }
                photoItems = []
            }
        #endif
    }

    /// The question field: a little smaller than body text, as Notion's; Return sends, or picks a page while the @ list
    /// is open (arrows move in it).
    private var field: some View {
        TextField(
            chat.pictureSetup == nil ? "app:ai.chat.placeholder" : "app:ai.pictures.placeholder", text: $chat.draft,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.hk(.sm))
        .lineLimit(2...8)
        .focused($composing)
        .submitLabel(.send)
        .onSubmit { mentionQuery == nil ? chat.send(store: model.store) : pickHighlighted() }
        // While an input method is composing, its candidates own these keys.
        .onKeyPress(.downArrow) { TextComposition.isActive ? .ignored : moveMention(1) }
        .onKeyPress(.upArrow) { TextComposition.isActive ? .ignored : moveMention(-1) }
        .onKeyPress(.return) {
            guard mentionQuery != nil, !TextComposition.isActive else { return .ignored }
            pickHighlighted()
            return .handled
        }
        .onKeyPress(.escape) {
            guard mentionQuery != nil, !TextComposition.isActive else { return .ignored }
            if let range = chat.draft.range(of: "@", options: .backwards) { chat.draft.removeSubrange(range) }
            return .handled
        }
        .onChange(of: mentionQuery) { mentionIndex = 0 }
        #if os(macOS)
            .onPasteCommand(of: [.fileURL, .image, .pdf]) { receive($0) }
        #endif
        .accessibilityIdentifier("ai-chat-field")
    }

    /// Set up for pictures (opened from the page for them): what is asked for, its shape and the detailed model.
    private func pictureChips(_ setup: AIChat.PictureSetup) -> some View {
        HStack(spacing: Spacing.s1_5) {
            ContextChip(label: "app:ai.pictures.cancel", remove: { chat.pictureSetup = nil }) {
                IconView(.images, size: TextSize.sm.rawValue).foregroundStyle(ColorTone.standard.ink)
                Text(setup.changing ? "app:ai.pictures.changing" : "app:ai.pictures.asking")
            }
            .accessibilityIdentifier("ai-pictures-setup")
            Menu {
                Picker("app:ai.pictures.shape", selection: Binding(get: { setup.shape }, set: { chat.pictureSetup?.shape = $0 })) {
                    ForEach(PictureShape.allCases, id: \.self) { shape in Text(Self.shapeName(shape)).tag(shape) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(Self.shapeName(setup.shape)).modifier(ChipStyle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("ai-pictures-shape")
            Toggle(isOn: Binding(get: { setup.detailed }, set: { chat.pictureSetup?.detailed = $0 })) {
                Text("app:ai.pictures.detailed")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .modifier(ChipStyle())
            .background(setup.detailed ? ColorTone.standard.selectionFill : .clear, in: .capsule)
            .help("app:ai.pictures.detailedHint")
            .accessibilityIdentifier("ai-pictures-detailed")
        }
    }

    private static func shapeName(_ shape: PictureShape) -> LocalizedStringKey {
        switch shape {
        case .wide: "app:ai.pictures.wide"
        case .square: "app:ai.pictures.square"
        case .tall: "app:ai.pictures.tall"
        }
    }

    private var attachButton: some View {
        #if os(iOS)
            Menu {
                Button {
                    pickingPhotos = true
                } label: {
                    IconLabel("app:ai.attach.photos", icon: .image)
                }
                Button {
                    pickingFiles = true
                } label: {
                    IconLabel("app:ai.attach.files", icon: .folderSimple)
                }
            } label: {
                attachGlyph
            }
            .accessibilityIdentifier("ai-chat-attach")
        #else
            Button {
                pickingFiles = true
            } label: {
                attachGlyph
            }
            .buttonStyle(.plain)
            .help("app:ai.attach")
            .accessibilityIdentifier("ai-chat-attach")
        #endif
    }

    private var attachGlyph: some View {
        IconView(.plus, size: TextSize.lg.rawValue)
            .foregroundStyle(Theme.subtleForeground)
            .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
            .contentShape(.circle)
            .accessibilityLabel(Text("app:ai.attach"))
    }

    // MARK: Context

    /// The open page (unless removed) and the @-mentioned ones.
    private var contextPages: [PageSummary] {
        ([chat.pageID].compactMap { $0 } + chat.extraPageIDs).compactMap(model.tree.page)
    }

    private func remove(_ id: String) {
        if id == chat.pageID { chat.pageID = nil } else { chat.extraPageIDs.removeAll { $0 == id } }
    }

    /// What follows an @ at the end of the draft (at its start or after a space), while a page is being picked.
    private var mentionQuery: String? {
        guard let match = chat.draft.firstMatch(of: #/(?:^|\s)@([^\s@]*)$/#) else { return nil }
        return String(match.1)
    }

    private func pick(_ id: String) {
        if let range = chat.draft.range(of: "@", options: .backwards) { chat.draft.removeSubrange(range.lowerBound...) }
        chat.mention(id)
        composing = true
    }

    private func pickHighlighted() {
        guard let query = mentionQuery else { return }
        let ids = MentionList.candidates(query: query, chat: chat, pages: model.tree.all).map(\.id)
        if ids.indices.contains(mentionIndex) { pick(ids[mentionIndex]) }
    }

    private func moveMention(_ step: Int) -> KeyPress.Result {
        guard let query = mentionQuery else { return .ignored }
        let count = MentionList.candidates(query: query, chat: chat, pages: model.tree.all).count
        guard count > 0 else { return .handled }
        mentionIndex = (mentionIndex + step + count) % count
        return .handled
    }

    /// Dropped or pasted files: file URLs read from disk, pictures and PDFs as data.
    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in chat.attach(fileAt: url) }
                }
            } else if let type = [UTType.pdf, .image].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                let name = provider.suggestedName ?? String(localized: "app:ai.attach.photo")
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in chat.attach(data, type: type, name: name) }
                }
            }
        }
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.attachments.isEmpty
    }

    private var sendButton: some View {
        // Pictures being made stop with it too.
        let working = chat.isStreaming || chat.isMakingPictures
        return Button {
            if working { chat.stop() } else { chat.send(store: model.store) }
        } label: {
            IconView(working ? .stop : .arrowUp, size: TextSize.base.rawValue)
        }
        .buttonStyle(SendButtonStyle())
        .disabled(!working && !canSend)
        .accessibilityLabel(Text(working ? "app:ai.stop" : "app:ai.send"))
        .accessibilityIdentifier("ai-chat-send")
    }
}

/// The composer's round send button: a solid tone fill with a white arrow when it can send, muted grey when it
/// can't — never the label dimmed over the fill, which read as pale pink in light mode. The colours are resolved
/// against the environment so a vibrant panel (the inspector) can't wash them out either.
private struct SendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.self) private var environment

    func makeBody(configuration: Configuration) -> some View {
        let fill = isEnabled ? ColorTone.standard.fill : Theme.muted
        let ink = isEnabled ? ColorTone.standard.onFill : Theme.mutedForeground
        configuration.label
            .foregroundStyle(Color(ink.resolve(in: environment)))
            .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
            .background(Color(fill.resolve(in: environment)), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.easeOut(), value: configuration.isPressed)
            .contentShape(.circle)
    }
}

/// Typing @ in the composer: the open page first ("Current page"), then other pages matching what follows the @
/// ("Link to page"), each with where it sits; a few at most, the rest counted.
private struct MentionList: View {
    let query: String
    let chat: AIChat
    @Binding var highlighted: Int
    let pick: (String) -> Void
    @Environment(AppModel.self) private var model

    static let limit = 6

    /// The pages offered, in order: the open page (when it matches and isn't added), then others by last edit.
    static func candidates(query: String, chat: AIChat, pages: [PageSummary]) -> [PageSummary] {
        let added = Set([chat.pageID].compactMap { $0 } + chat.extraPageIDs)
        let matches = { (page: PageSummary) in query.isEmpty || page.title.localizedStandardContains(query) }
        let current = pages.first { $0.id == chat.openPageID && !added.contains($0.id) && matches($0) }
        let others =
            pages
            .filter { $0.id != chat.openPageID && !added.contains($0.id) && matches($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return ([current].compactMap { $0 } + others).prefix(limit).map { $0 }
    }

    var body: some View {
        let all = model.tree.all
        let shown = Self.candidates(query: query, chat: chat, pages: all)
        let total = all.filter { $0.id != chat.openPageID && (query.isEmpty || $0.title.localizedStandardContains(query)) }.count
        VStack(alignment: .leading, spacing: Spacing.s0) {
            if shown.isEmpty {
                Text("app:ai.mention.none").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground).padding(Spacing.s2)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, page in
                if index == 0, page.id == chat.openPageID {
                    header("app:ai.mention.current")
                }
                if page.id != chat.openPageID, index == 0 || shown[index - 1].id == chat.openPageID {
                    header("app:ai.mention.link")
                }
                Button {
                    pick(page.id)
                } label: {
                    HStack(spacing: Spacing.s2_5) {
                        PageIcon(page.icon, size: TextSize.base.rawValue)
                        VStack(alignment: .leading, spacing: Spacing.px) {
                            Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                                .font(.hk(.sm))
                                .foregroundStyle(Theme.foreground)
                            let path = model.tree.path(to: page.id).dropLast().map(\.title).joined(separator: " › ")
                            if !path.isEmpty {
                                Text(verbatim: path).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1_5)
                    .background(index == highlighted ? Theme.accent : .clear, in: .rect(cornerRadius: Radius.md))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
                .accessibilityIdentifier("ai-mention-\(page.title)")
            }
            let more = total - shown.filter { $0.id != chat.openPageID }.count
            if more > 0 {
                Text("app:ai.mention.more \(more.formatted())")
                    .font(.hk(.xs))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1)
            }
        }
        .padding(Spacing.s1_5)
        .background(Theme.popover, in: .rect(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.border))
        .shadow(color: Theme.border, radius: Spacing.s3, y: Spacing.s1)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.hk(.xs, .medium))
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s1_5)
            .padding(.bottom, Spacing.s0_5)
    }
}

/// A file waiting to be sent: a picture's thumbnail, or a document's icon and name; × removes it.
private struct AttachmentThumbnail: View {
    let attachment: ChatAttachment
    var remove: (() -> Void)?

    var body: some View {
        Group {
            if let data = attachment.imageData, let image = platformImage(data) {
                image.resizable().scaledToFill()
            } else {
                VStack(spacing: Spacing.s1) {
                    IconView(.fileText, size: TextSize.x2l.rawValue).foregroundStyle(Theme.subtleForeground)
                    Text(verbatim: attachment.name).font(.hk(.x2s)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                }
                .padding(Spacing.s1)
            }
        }
        .frame(width: Spacing.s16, height: Spacing.s16)
        .background(Theme.muted)
        .clipShape(.rect(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border))
        .overlay(alignment: .topTrailing) {
            if let remove {
                Button(action: remove) {
                    IconView(.x, size: TextSize.x2s.rawValue)
                        .foregroundStyle(Theme.primaryForeground)
                        .frame(width: Spacing.s5, height: Spacing.s5)
                        .background(Theme.primary.opacity(0.75), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(Spacing.s1)
                .accessibilityLabel(Text("app:ai.attach.remove"))
            }
        }
        .accessibilityLabel(Text(verbatim: attachment.name))
    }

    private func platformImage(_ data: Data) -> Image? { PlatformImage.image(data) }
}

/// A context chip in the composer (the page, the selected passage): a hairline capsule, removable.
private struct ContextChip<Content: View>: View {
    let label: LocalizedStringKey
    let remove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            content.lineLimit(1)
            Button(action: remove) {
                IconView(.x, size: TextSize.x2s.rawValue).foregroundStyle(Theme.placeholder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
        }
        .modifier(ChipStyle())
    }
}

/// The composer's chips (context, suggestions): small text in a hairline capsule.
private struct ChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.hk(.md))
            .foregroundStyle(Theme.subtleForeground)
            .padding(.horizontal, Spacing.s2_5)
            .frame(height: Size.iconButton)
            .overlay(Capsule().strokeBorder(Theme.border))
    }
}

/// Notion's model menu (`AIModelButton`): Auto, the starred models, the recommended ones, then the rest under "Other
/// models". The pick is also the default (Settings → AI), so the page's own Ask AI runs on the same model; a change
/// made in Settings reaches the open chat.
struct AIModelMenu: View {
    @Bindable var chat: AIChat
    @AppStorage(AIPreferences.modelKey) private var defaultModel = AIModelCatalog.autoID

    var body: some View {
        AIModelButton(selection: choice) {
            Text(AIPreferences.modelName(chat.modelChoice)).font(.hk(.sm))
        }
        // Quiet text in the composer's row, not a button of its own.
        .fixedSize()
        .accessibilityIdentifier("ai-chat-model")
        .onChange(of: defaultModel) { _, model in chat.modelChoice = model }
    }

    private var choice: Binding<String> {
        Binding(
            get: { chat.modelChoice },
            set: { model in
                chat.modelChoice = model
                defaultModel = model
            })
    }
}

/// One turn: the user's in a bubble on the right; the answer as text with its sources, a working line while it
/// streams, an error in its place when it failed.
private struct ChatBubble: View {
    let message: AIChat.Message
    let isStreaming: Bool
    var isCompacting = false
    /// Where an answer's changes to the page are reviewed.
    var chat: AIChat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// The pictures the answer's search found (web addresses only, however they got here).
    private var pictures: some View {
        let shown = message.images.compactMap { image in
            image.thumbnailURL.map { ImageResultItem(id: image.url, thumbnail: $0, caption: image.caption, source: image.sourceURL) }
        }
        let byID = Dictionary(message.images.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        return ImageResultStrip(
            items: shown,
            onAdd: chat?.canAddPictures == true ? { item in if let image = byID[item.id] { chat?.addPicture(image) } } : nil,
            onOpen: { item in if let source = item.source { openURL(source) } },
            onCopy: { item in
                #if os(iOS)
                    UIPasteboard.general.string = item.id
                #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.id, forType: .string)
                #endif
            },
            load: { try await WebImage.fetch($0).data })
    }

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: Spacing.s1_5) {
                if !message.attachments.isEmpty {
                    HStack(spacing: Spacing.s1_5) {
                        ForEach(message.attachments) { AttachmentThumbnail(attachment: $0) }
                    }
                }
                // Files sent in an earlier session: their names (the files aren't kept).
                if !message.attachmentNames.isEmpty {
                    HStack(spacing: Spacing.s1) {
                        IconView(.paperclip, size: TextSize.xs.rawValue)
                        Text(verbatim: message.attachmentNames.joined(separator: ", ")).lineLimit(1)
                    }
                    .font(.hk(.xs))
                    .foregroundStyle(Theme.mutedForeground)
                }
                if !message.text.isEmpty { userText }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Spacing.s12)
        case .assistant:
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                // How the answer was worked out, over it: live while the model thinks, folded once it answers.
                if let timeline { timeline }
                // The changes block never shows as text: the cards below stand for it.
                if !prose.isEmpty { AnswerText(text: prose, isStreaming: isStreaming) }
                if isStreaming,
                    isCompacting || AIPageEdits.hasChanges(message.text) || AIPictures.hasPictures(message.text)
                        || !message.text.isEmpty && message.searching != nil
                {
                    working
                }
                if let chat, !message.changes.isEmpty { changeReview(chat) }
                if let chat, !message.pictures.isEmpty { pictureTiles(chat) }
                if let error = message.error {
                    Text(verbatim: error).font(.hk(.sm)).foregroundStyle(.red)
                }
                if !message.citations.isEmpty {
                    FlowLayout(spacing: Spacing.s1_5) {
                        ForEach(Array(message.citations.enumerated()), id: \.offset) { index, citation in
                            // Web pages only, however the citation got here (a kept turn is read from a synced file).
                            if let url = ChatCitation(url: citation.url, title: nil).webURL {
                                Link(destination: url) {
                                    Text(verbatim: "\(index + 1) · \(citation.title ?? url.host() ?? citation.url)")
                                        .lineLimit(1)
                                        .font(.hk(.xs))
                                        .foregroundStyle(Theme.subtleForeground)
                                        .padding(.horizontal, Spacing.s2_5)
                                        .padding(.vertical, Spacing.s1)
                                        .background(Theme.muted, in: .capsule)
                                }
                            }
                        }
                    }
                }
                if !message.images.isEmpty { pictures }
                if !isStreaming && !message.text.isEmpty {
                    HStack(spacing: Spacing.s1) {
                        Button {
                            #if os(iOS)
                                UIPasteboard.general.string = prose
                            #else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(prose, forType: .string)
                            #endif
                        } label: {
                            IconLabel("app:ai.copy", icon: .copy).labelStyle(.iconOnly)
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
                        }
                        .buttonStyle(.plain)
                        Text(message.sentAt, format: .dateTime.hour().minute())
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var prose: String { message.role == .assistant ? AIPageEdits.prose(message.text) : message.text }

    private func changeReview(_ chat: AIChat) -> some View {
        let items = message.changes.map(ChangeReviewItem.make)
        let reviewed = message.changes.filter { $0.status.isReviewed }
            .sorted { ($0.reviewedAt ?? .distantPast) < ($1.reviewedAt ?? .distantPast) }
            .map(ChangeReviewItem.make)
        return AIChangeReview(
            items: items, reviewed: reviewed, activeID: chat.focusedChange, onFocus: chat.focusChange,
            onApprove: chat.approveChange, onSkip: chat.skipChange, onApproveAll: chat.approveAllChanges)
    }

    /// The pictures the answer makes, as tiles forming in place; made ones go into the page where it asked for them.
    private func pictureTiles(_ chat: AIChat) -> some View {
        let replacing = message.picturePlace?.replace == true
        let items = message.pictures.map { picture in
            let shape = PictureShape(rawValue: picture.shape) ?? .wide
            let state: PictureTileItem.State =
                switch picture.status {
                case .making: chat.pictureQueue.drawing.contains(picture.id) ? .forming : .waiting
                case .done: .done
                case .stopped, .failed: .failed(AIChat.pictureFailure(picture))
                }
            return PictureTileItem(
                id: picture.id, state: state, image: chat.pictureImage(picture),
                aspect: shape.aspect, description: picture.prompt, added: picture.added == true)
        }
        return PictureTiles(
            items: items, replacing: replacing,
            onAdd: chat.canAddPictures ? { chat.addPictures([$0], answer: message.id) } : nil,
            onCover: chat.canAddPictures ? { chat.useAsCover($0) } : nil,
            onRetry: chat.retryPicture,
            onAddAll: chat.canAddPictures
                ? { chat.addPictures(message.pictures.filter { $0.added != true }.map(\.id), answer: message.id) } : nil)
    }

    private var userText: some View {
        Text(verbatim: message.text)
            .font(.hk(.sm))
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2_5)
            .background(Theme.muted, in: .capsule)
    }

    /// The model at work: the line shimmers; with Reduce Motion it stands still, so a spinner says it's busy.
    /// The timeline, when there is something in it — or the model is still working on its first words.
    private var timeline: ThinkingTimeline? {
        let steps = message.thinking?.steps ?? []
        let live = isStreaming && message.text.isEmpty && !isCompacting
        guard !steps.isEmpty || live else { return nil }
        let rows = steps.enumerated().map { index, step in
            switch step.kind {
            case .search:
                return ThinkingTimeline.Step(id: index, kind: .search, title: Self.searchTitle(step.text, done: true))
            case .thinking:
                let (title, detail) = Self.split(step.text)
                return ThinkingTimeline.Step(
                    id: index, kind: .thinking, title: title ?? String(localized: "app:ai.thought"), detail: detail)
            }
        }
        return ThinkingTimeline(header: Self.header(message.thinking, live: live), isStreaming: live, steps: rows)
    }

    /// While live, the step the model is on; afterwards how long it thought (or that it searched).
    private static func header(_ thinking: ChatThinking?, live: Bool) -> String {
        let steps = thinking?.steps ?? []
        if live {
            switch steps.last?.kind {
            case .search: return searchTitle(steps.last?.text ?? "", done: false)
            case .thinking: return AIThinking.title(of: steps.last?.text ?? "") ?? String(localized: "app:ai.thinking")
            case nil: return String(localized: "app:ai.thinking")
            }
        }
        guard steps.contains(where: { $0.kind == .thinking }) else { return String(localized: "app:ai.searchedWeb") }
        guard let seconds = thinking?.seconds, seconds >= 1 else { return String(localized: "app:ai.thought") }
        let duration = Duration.seconds(Int(seconds.rounded())).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return String(localized: "app:ai.thoughtFor \(duration)")
    }

    private static func searchTitle(_ query: String, done: Bool) -> String {
        switch (query.isEmpty, done) {
        case (true, true): String(localized: "app:ai.searchedWeb")
        case (true, false): String(localized: "app:ai.searching")
        case (false, true): String(localized: "app:ai.searchedFor \(query)")
        case (false, false): String(localized: "app:ai.searchingFor \(query)")
        }
    }

    /// A stretch of thinking as its row shows it: the title it opens with, then the rest (inline Markdown).
    private static func split(_ text: String) -> (String?, AttributedString) {
        let title = AIThinking.title(of: text)
        var rest = AIThinking.body(of: text)
        // No bold title: the first line was the title.
        if rest == text.trimmingCharacters(in: .whitespacesAndNewlines), let title, rest.hasPrefix(title) {
            rest = String(rest.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (title, (try? AttributedString(markdown: rest, options: options)) ?? AttributedString(rest))
    }

    private var working: some View {
        HStack(spacing: Spacing.s2) {
            if reduceMotion { ProgressView().controlSize(.small) }
            if let query = message.searching {
                ShimmerText(query.isEmpty ? "app:ai.searching" : "app:ai.searchingFor \(query)")
            } else if AIPageEdits.hasChanges(message.text) {
                ShimmerText("app:ai.changes.preparing")
            } else if AIPictures.hasPictures(message.text) {
                ShimmerText("app:ai.pictures.preparing")
            } else {
                ShimmerText(isCompacting ? "app:ai.compacting" : "app:ai.thinking")
            }
        }
        .font(.hk(.sm))
    }
}

/// A kept change as HikkiUI's review card: the block's words marked as the review left them.
enum ChangeReviewItem {
    static func make(_ change: AIPageChange) -> AIChangeReview.Item {
        AIChangeReview.Item(
            id: change.id, kind: AIChangeReview.Kind(rawValue: change.kind.rawValue) ?? .rewrite, title: change.title,
            why: change.why, state: status(change.status), runs: runs(change))
    }

    static func status(_ status: AIPageChange.Status) -> AIChangeReview.Status {
        switch status {
        case .pending: .pending
        case .approved: .approved
        case .skipped: .skipped
        case .edited: .edited
        case .stale: .stale
        }
    }

    /// Approved: the new words green in the block as it reads now (a deleted block struck through); skipped: what
    /// was proposed, unmarked.
    static func runs(_ change: AIPageChange) -> [VersionDiffView.Run] {
        let before = change.beforeText ?? ""
        let after = change.afterText ?? ""
        switch change.status {
        case .pending, .stale: return []
        case .skipped: return after.isEmpty ? (before.isEmpty ? [] : [.init(before, .same)]) : [.init(after, .same)]
        case .approved, .edited:
            switch change.kind {
            case .delete: return [.init(before, .removed)]
            case .insert: return [.init(after, .added)]
            case .move: return [.init(after, .same)]
            case .rewrite:
                return PageDiff.words(old: before, new: after).compactMap { run in
                    switch run.change {
                    case .same: .init(run.text, .same)
                    case .added: .init(run.text, .added)
                    case .removed: nil
                    }
                }
            }
        }
    }
}

/// Lays out chips left to right, wrapping to new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
