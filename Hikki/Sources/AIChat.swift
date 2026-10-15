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

/// A conversation with AI (Ask AI): the turns, the model picked for it, web search on or off, and the page it is
/// about. One per window; the answer streams into the last message. Page text goes to the model only as context, and
/// nothing of it is logged.
@MainActor
@Observable
final class AIChat {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        /// Files sent with a question (shown in its bubble; sent with that turn only).
        var attachments: [ChatAttachment] = []
        var citations: [AICitation] = []
        /// A web search under way (its query, when the provider says it).
        var searching: String?
        var error: String?
    }

    var messages: [Message] = []
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
        openPageID = id
        pageID = id
        extraPageIDs.removeAll { $0 == id }
    }

    /// Other pages the user @-mentioned, in the order added.
    var extraPageIDs: [String] = []
    /// The passage selected in that page (follows the selection; cleared from the composer to ask without it).
    var selection: String?
    /// Files to send with the next question.
    var attachments: [ChatAttachment] = []
    /// Why the last file couldn't be attached (shown under the composer until the next attempt).
    var attachError: String?
    private(set) var isStreaming = false
    @ObservationIgnored private var task: Task<Void, Never>?

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
        draft = ""
        attachError = nil
        messages.append(Message(role: .user, text: question, attachments: attachments))
        attachments = []
        messages.append(Message(role: .assistant, text: ""))
        let turns: [AIMessage] = messages.dropLast().map { message in
            message.role == .assistant
                ? .assistant(message.text)
                : AIMessage(role: .user, parts: [.text(message.text)] + message.attachments.map(\.part))
        }
        let pages = ([pageID].compactMap { $0 } + extraPageIDs)
            .compactMap { try? store?.document(id: $0) }
            .map { (title: $0.title, text: $0.plainText) }
        switch AIService.connect(modelChoice) {
        case .failure(let error):
            finish(error: error)
        case .success(let (model, client)):
            let request = AIPrompts.chat(
                turns, pages: pages, selection: selection, model: model, webSearch: webSearch, language: AIService.appLanguage)
            Log.info(
                "AI chat", category: "ai",
                context: [
                    "model": model.id, "turns": "\(turns.count)", "pages": "\(pages.count)",
                    "files": "\(messages[messages.count - 2].attachments.count)",
                ])
            isStreaming = true
            task = Task { [weak self] in
                do {
                    for try await event in client.stream(request) {
                        guard let self, !Task.isCancelled else { return }
                        self.apply(event)
                    }
                    self?.finish(error: nil)
                } catch {
                    let failure = error as? AIError ?? .invalidResponse
                    self?.finish(error: failure == .cancelled ? nil : failure)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
        if let last = messages.indices.last { messages[last].searching = nil }
    }

    /// A new conversation (same page and model).
    func clear() {
        stop()
        messages = []
    }

    private func apply(_ event: AIEvent) {
        guard !messages.isEmpty else { return }
        let last = messages.count - 1
        switch event {
        case .text(let delta):
            messages[last].text += delta
            messages[last].searching = nil
        case .searching(let query):
            messages[last].searching = query ?? ""
        case .citation(let citation):
            // Only web pages, once each (the model's search supplies them).
            guard let url = URL(string: citation.url), url.scheme == "https" || url.scheme == "http",
                !messages[last].citations.contains(citation)
            else { return }
            messages[last].citations.append(citation)
        case .finished:
            break
        }
    }

    private func finish(error: AIError?) {
        isStreaming = false
        task = nil
        guard let last = messages.indices.last else { return }
        messages[last].searching = nil
        if let error {
            messages[last].error = AIService.message(for: error)
            if let code = error.errorCode { Incident.report(code, error, category: "ai") }
        } else if messages[last].text.isEmpty {
            messages[last].error = AIService.message(for: .invalidResponse)
        }
    }
}

/// Ask AI on iPhone: the conversation (`AIChatView`) in a sheet, with close, a new chat and the model menu on top.
struct AIChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var chat: AIChat

    var body: some View {
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

/// A new chat (once there is one) — the sheet's toolbar, the side panel's header. The model is picked in the
/// composer.
struct AIChatActions: View {
    @Bindable var chat: AIChat

    var body: some View {
        if !chat.messages.isEmpty {
            Button {
                chat.clear()
            } label: {
                IconLabel("app:ai.newChat", icon: .notePencil)
            }
            .help("app:ai.newChat")
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
                    ForEach(chat.messages) { message in
                        ChatBubble(message: message, isStreaming: chat.isStreaming && message == chat.messages.last)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s3)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
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
                if !contextPages.isEmpty || chat.selection != nil {
                    ScrollView(.horizontal) {
                        HStack(spacing: Spacing.s1_5) {
                            ForEach(contextPages) { page in
                                ContextChip(label: "app:ai.chat.removePage", remove: { remove(page.id) }) {
                                    PageIcon(page.icon, size: TextSize.sm.rawValue)
                                    Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                                }
                            }
                            if let selection = chat.selection {
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
        TextField("app:ai.chat.placeholder", text: $chat.draft, axis: .vertical)
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
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    let name = provider.suggestedName ?? String(localized: "app:ai.attach.photo")
                    Task { @MainActor in chat.attach(data, type: type, name: name) }
                }
            }
        }
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.attachments.isEmpty
    }

    private var sendButton: some View {
        Button {
            if chat.isStreaming { chat.stop() } else { chat.send(store: model.store) }
        } label: {
            IconView(chat.isStreaming ? .stop : .arrowUp, size: TextSize.base.rawValue)
                .foregroundStyle(ColorTone.standard.onFill)
                .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
                .background(ColorTone.standard.fill, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!chat.isStreaming && !canSend)
        .opacity(!chat.isStreaming && !canSend ? 0.4 : 1)
        .accessibilityLabel(Text(chat.isStreaming ? "app:ai.stop" : "app:ai.send"))
        .accessibilityIdentifier("ai-chat-send")
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

    private func platformImage(_ data: Data) -> Image? {
        #if os(iOS)
            UIImage(data: data).map(Image.init(uiImage:))
        #else
            NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
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

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: Spacing.s1_5) {
                if !message.attachments.isEmpty {
                    HStack(spacing: Spacing.s1_5) {
                        ForEach(message.attachments) { AttachmentThumbnail(attachment: $0) }
                    }
                }
                if !message.text.isEmpty { userText }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Spacing.s12)
        case .assistant:
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                if !message.text.isEmpty {
                    Text(AIMarkdown.attributed(message.text))
                        .font(.hk(.base))
                        .textSelection(.enabled)
                }
                if isStreaming && (message.text.isEmpty || message.searching != nil) {
                    working
                }
                if let error = message.error {
                    Text(verbatim: error).font(.hk(.sm)).foregroundStyle(.red)
                }
                if !message.citations.isEmpty {
                    FlowLayout(spacing: Spacing.s1_5) {
                        ForEach(Array(message.citations.enumerated()), id: \.offset) { index, citation in
                            if let url = URL(string: citation.url) {
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
                if !isStreaming && !message.text.isEmpty {
                    Button {
                        #if os(iOS)
                            UIPasteboard.general.string = message.text
                        #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        #endif
                    } label: {
                        IconLabel("app:ai.copy", icon: .copy).labelStyle(.iconOnly)
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: Size.iconButton + Spacing.s1, height: Size.iconButton + Spacing.s1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var userText: some View {
        Text(verbatim: message.text)
            .font(.hk(.sm))
            .padding(.horizontal, Spacing.s3_5)
            .padding(.vertical, Spacing.s2_5)
            .background(Theme.muted, in: .rect(cornerRadius: Radius.xl + Spacing.s2))
    }

    private var working: some View {
        HStack(spacing: Spacing.s2) {
            ProgressView().controlSize(.small)
            if let query = message.searching {
                Text(query.isEmpty ? "app:ai.searching" : "app:ai.searchingFor \(query)")
            } else {
                Text("app:ai.thinking")
            }
        }
        .font(.hk(.sm))
        .foregroundStyle(Theme.mutedForeground)
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
