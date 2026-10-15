import HikkiAI
import HikkiCore
import HikkiUI
import Observation
import SwiftUI

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
    private(set) var isStreaming = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Sends `text` (or the draft), with the page's title and text as context.
    func send(_ text: String? = nil, store: DocumentStore?) {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }
        draft = ""
        messages.append(Message(role: .user, text: question))
        messages.append(Message(role: .assistant, text: ""))
        let turns: [AIMessage] = messages.dropLast().map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        let page = pageID.flatMap { try? store?.document(id: $0) }.map { (title: $0.title, text: $0.plainText) }
        switch AIService.connect(modelChoice) {
        case .failure(let error):
            finish(error: error)
        case .success(let (model, client)):
            let request = AIPrompts.chat(turns, page: page, model: model, webSearch: webSearch, language: AIService.appLanguage)
            Log.info("AI chat", category: "ai", context: ["model": model.id, "turns": "\(turns.count)", "page": page == nil ? "0" : "1"])
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
        messages[messages.count - 1].searching = nil
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
            Log.warn("AI chat failed: \(AIService.code(error))", category: "ai")
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

/// A new chat (once there is one) and the model menu — the sheet's toolbar, the side panel's header.
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
        AIModelMenu(chat: chat)
    }
}

/// The conversation: the turns, suggestions to start one about the open page, and the composer — the page as a
/// removable chip, web search on or off. Shared by the iPhone sheet and the Mac/iPad side panel.
struct AIChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var chat: AIChat
    @FocusState private var composing: Bool

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

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if chat.messages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.s2) {
                        ForEach(suggestions, id: \.key) { suggestion in
                            Button {
                                chat.send(String(localized: suggestion), store: model.store)
                            } label: {
                                Text(suggestion)
                                    .font(.hk(.sm))
                                    .foregroundStyle(Theme.subtleForeground)
                                    .padding(.horizontal, Spacing.s3_5)
                                    .frame(height: Size.iconButton + Spacing.s1_5)
                                    .background(Theme.muted, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            VStack(alignment: .leading, spacing: Spacing.s1_5) {
                TextField("app:ai.chat.placeholder", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.hk(.base))
                    .lineLimit(1...6)
                    .focused($composing)
                    .submitLabel(.send)
                    .onSubmit { chat.send(store: model.store) }
                    .accessibilityIdentifier("ai-chat-field")
                HStack(spacing: Spacing.s1) {
                    if let page = contextPage {
                        Button {
                            chat.pageID = nil
                        } label: {
                            HStack(spacing: Spacing.s1) {
                                PageIcon(page.icon, size: TextSize.sm.rawValue)
                                Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                                    .lineLimit(1)
                                IconView(.x, size: TextSize.x2s.rawValue).foregroundStyle(Theme.placeholder)
                            }
                            .font(.hk(.md))
                            .foregroundStyle(Theme.subtleForeground)
                            .padding(.horizontal, Spacing.s2_5)
                            .frame(height: Size.iconButton + Spacing.s0_5)
                            .background(Theme.muted, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("app:ai.chat.removePage"))
                    }
                    Toggle(isOn: $chat.webSearch) {
                        IconLabel("app:ai.chat.web", icon: .globe).labelStyle(.iconOnly)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.plain)
                    .foregroundStyle(chat.webSearch ? AnyShapeStyle(ColorTone.standard.ink) : AnyShapeStyle(Theme.mutedForeground))
                    .frame(width: Size.iconButton + Spacing.s2, height: Size.iconButton + Spacing.s2)
                    .accessibilityIdentifier("ai-chat-web")
                    Spacer(minLength: Spacing.s1)
                    sendButton
                }
            }
            .padding(.leading, Spacing.s4)
            .padding(.trailing, Spacing.s2_5)
            .padding(.vertical, Spacing.s2_5)
            .background(Theme.muted, in: .rect(cornerRadius: Radius.xl * 2))
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .padding(.top, Spacing.s1)
        .background(Theme.background)
    }

    private var sendButton: some View {
        Button {
            if chat.isStreaming { chat.stop() } else { chat.send(store: model.store) }
        } label: {
            IconView(chat.isStreaming ? .stop : .arrowUp, size: TextSize.base.rawValue)
                .foregroundStyle(ColorTone.standard.onFill)
                .frame(width: Size.iconButton + Spacing.s2, height: Size.iconButton + Spacing.s2)
                .background(ColorTone.standard.fill, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!chat.isStreaming && chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(!chat.isStreaming && chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        .accessibilityLabel(Text(chat.isStreaming ? "app:ai.stop" : "app:ai.send"))
        .accessibilityIdentifier("ai-chat-send")
    }
}

/// Notion's model menu: Auto, the recommended models, then the rest under "Other models".
struct AIModelMenu: View {
    @Bindable var chat: AIChat

    var body: some View {
        Menu {
            Picker(selection: $chat.modelChoice) {
                Text("app:ai.model.auto").tag(AIModelCatalog.autoID)
                Section("app:ai.model.recommended") {
                    ForEach(AIModelCatalog.recommended) { Text(verbatim: $0.displayName).tag($0.id) }
                }
                Section("app:ai.model.other") {
                    ForEach(AIModelCatalog.others) { Text(verbatim: $0.displayName).tag($0.id) }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Text(modelName).font(.hk(.sm))
        }
        .fixedSize()
        .accessibilityIdentifier("ai-chat-model")
    }

    private var modelName: LocalizedStringKey {
        if let model = AIModelCatalog.model(id: chat.modelChoice) { return "\(model.displayName)" }
        return "app:ai.model.auto"
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
            Text(verbatim: message.text)
                .font(.hk(.base))
                .padding(.horizontal, Spacing.s3_5)
                .padding(.vertical, Spacing.s2_5)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.xl + Spacing.s2))
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
