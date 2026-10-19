import HikkiAI
import HikkiCore
import HikkiUI
import SwiftUI

/// Settings → AI: the providers' API keys (in the Keychain; each sent only to the origin it was entered for), an
/// optional base URL per provider, and the model AI uses by default. The models are a fixed list (`AIModelCatalog`).
enum AIPreferences {
    /// The model chosen: an id from the catalog or "auto". Settings → AI and the chat's model menu both set it, and
    /// the page's own AI (Ask AI in the selection and block menus) runs on it too.
    static let modelKey = "ai.model"
    /// The starred models, comma-separated in the order starred (`AIModelFavorites`).
    static let favoritesKey = "ai.favoriteModels"
    /// How an AI edit is reviewed: `inline` (A, default) or `diff` (B) — `ReviewStyleThumbnail.Sketch`; a stored
    /// `bubble` (the retired card style) reads as `inline`.
    static let reviewStyleKey = "ai.reviewStyle"
    /// How long each page's AI conversation is kept (`ChatRetention`: days30, days90 — the default — or forever).
    static let chatRetentionKey = "ai.chatRetention"

    static var chatRetention: ChatRetention {
        UserDefaults.standard.string(forKey: chatRetentionKey).flatMap(ChatRetention.init) ?? .default
    }

    /// The base URL typed for a provider (blank: its own API) — `AIEndpoint` reads it.
    static func baseURLKey(_ provider: AIProvider) -> String { "ai.baseURL.\(provider.rawValue)" }

    static func baseText(_ provider: AIProvider, _ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: baseURLKey(provider)) ?? ""
    }

    /// The base requests go to, or nil when what was typed isn't a usable URL.
    static func base(_ provider: AIProvider, _ defaults: UserDefaults = .standard) -> URL? {
        AIEndpoint.base(baseText(provider, defaults), for: provider)
    }

    static func keyAccount(_ provider: AIProvider, base: URL?) -> String? {
        AIEndpoint.keyAccount(provider, base: base)
    }

    /// The key for the provider's current base.
    static func key(_ provider: AIProvider) -> String? {
        keyAccount(provider, base: base(provider)).flatMap(Keychain.read).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A model choice's name: the model's, or "Auto".
    static func modelName(_ choice: String) -> LocalizedStringKey {
        if let model = AIModelCatalog.model(id: choice) { return "\(model.displayName)" }
        return "app:ai.model.auto"
    }

    /// The providers that have a key for their current base.
    static var available: Set<AIProvider> {
        Set(AIProvider.allCases.filter { key($0) != nil })
    }
}

struct AISettingsSection: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AIPreferences.modelKey) private var model = AIModelCatalog.autoID
    @AppStorage(AIPreferences.reviewStyleKey) private var reviewStyle = ReviewStyleThumbnail.Sketch.inline.rawValue
    @AppStorage(AIPreferences.chatRetentionKey) private var retention = ChatRetention.default.rawValue
    @State private var confirmingDelete = false

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.s2) {
                ForEach(ReviewStyleThumbnail.Sketch.allCases, id: \.self) { sketch in
                    ThumbnailOption(title(sketch), isSelected: ReviewStyleThumbnail.Sketch(stored: reviewStyle) == sketch) {
                        withAnimation(Motion.easeOut()) { reviewStyle = sketch.rawValue }
                    } thumbnail: {
                        ReviewStyleThumbnail(sketch)
                    }
                    .accessibilityIdentifier("settings-ai-review-\(sketch.rawValue)")
                }
            }
        } header: {
            Text("app:ai.settings.review")
        } footer: {
            Text(detail(ReviewStyleThumbnail.Sketch(stored: reviewStyle)))
        }
        Section {
            LabeledContent("app:ai.settings.model") {
                AIModelButton(selection: $model) {
                    HStack(spacing: Spacing.s1) {
                        Text(AIPreferences.modelName(model))
                        IconView(.caretUpDown, size: TextSize.xs.rawValue).foregroundStyle(Theme.mutedForeground)
                    }
                }
                .accessibilityIdentifier("settings-ai-model")
            }
        } header: {
            Text("app:ai.settings.models")
        } footer: {
            Text("app:ai.settings.models.detail")
        }
        Section {
            Picker("app:ai.settings.history.keep", selection: $retention) {
                ForEach(ChatRetention.allCases, id: \.self) { choice in
                    if let days = choice.days {
                        Text("app:settings.trash.days \(days.formatted())").tag(choice.rawValue)
                    } else {
                        Text("app:settings.trash.forever").tag(choice.rawValue)
                    }
                }
            }
            .accessibilityIdentifier("settings-ai-history-keep")
            .onChange(of: retention) { _, _ in
                let retention = AIPreferences.chatRetention
                if let chats = app.chats { Task.detached(priority: .utility) { chats.prune(retention) } }
            }
            Button("app:ai.settings.history.deleteAll", role: .destructive) { confirmingDelete = true }
                .disabled(app.chats == nil)
                .accessibilityIdentifier("settings-ai-history-delete")
                .confirmationDialog("app:ai.settings.history.deleteAll.confirm", isPresented: $confirmingDelete) {
                    Button("app:common.delete", role: .destructive) {
                        app.chats?.removeEverything()
                        Toasts.shared.show(.success, String(localized: "app:ai.settings.history.deleted"))
                    }
                } message: {
                    Text("app:trash.cannotUndo")
                }
        } header: {
            Text("app:ai.settings.history")
        } footer: {
            Text("app:ai.settings.history.detail")
        }
        ForEach(AIProvider.allCases, id: \.self) { provider in
            AIKeySection(provider: provider)
        }
    }

    private func title(_ sketch: ReviewStyleThumbnail.Sketch) -> LocalizedStringKey {
        switch sketch {
        case .inline: "app:ai.review.inline"
        case .diff: "app:ai.review.diff"
        }
    }

    private func detail(_ sketch: ReviewStyleThumbnail.Sketch) -> LocalizedStringKey {
        switch sketch {
        case .inline: "app:ai.review.inline.detail"
        case .diff: "app:ai.review.diff.detail"
        }
    }
}

/// Notion's model menu behind a button (the chat's composer, Settings → AI): Auto, the starred models under
/// "Favorites", then the recommended and the other ones; a star on each row stars or unstars it (kept in
/// `AIPreferences.favoritesKey`). Picking a model closes the popover; starring leaves it open.
struct AIModelButton<Label: View>: View {
    @Binding var selection: String
    @ViewBuilder let label: Label
    @AppStorage(AIPreferences.favoritesKey) private var favoritesStored = ""
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ModelPickerList(
                autoID: AIModelCatalog.autoID, autoTitle: "app:ai.model.auto", autoDetail: "app:ai.model.auto.detail",
                groups: groups, selection: selection,
                onSelect: { id in
                    selection = id
                    open = false
                },
                onToggleFavorite: { id in
                    withAnimation(Motion.easeOut()) { favoritesStored = favorites.toggling(id).stored }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var favorites: AIModelFavorites { AIModelFavorites(stored: favoritesStored) }

    private var groups: [ModelPickerList.Group] {
        let favorites = favorites
        return AIModelCatalog.sections(favorites: favorites).map { section in
            ModelPickerList.Group(
                id: section.kind.rawValue, title: Self.title(section.kind),
                items: section.models.map {
                    ModelPickerList.Item(
                        id: $0.id, name: $0.displayName, detail: $0.provider.name, isFavorite: favorites.contains($0.id))
                })
        }
    }

    private static func title(_ kind: AIModelCatalog.Section.Kind) -> LocalizedStringKey {
        switch kind {
        case .favorites: "app:ai.model.favorites"
        case .recommended: "app:ai.model.recommended"
        case .other: "app:ai.model.other"
        }
    }
}

/// One provider's key: typed once, kept in the Keychain; the field shows dots, never the key.
private struct AIKeySection: View {
    let provider: AIProvider
    @State private var key = ""
    @State private var baseText = ""

    /// The base as typed, or nil while it isn't a usable URL (the key field waits for one).
    private var base: URL? { AIEndpoint.base(baseText, for: provider) }
    private var account: String? { AIPreferences.keyAccount(provider, base: base) }

    var body: some View {
        Section {
            SecureField("app:ai.settings.key", text: $key, prompt: Text(prompt))
                .accessibilityIdentifier("settings-ai-key-\(provider.rawValue)")
                .disabled(account == nil)
                .onChange(of: key) { _, value in
                    guard let account else { return }
                    Keychain.write(value.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
                }
            TextField(
                "app:ai.settings.baseURL", text: $baseText,
                prompt: Text(verbatim: AIEndpoint.defaultBase(provider).absoluteString)
            )
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("settings-ai-base-\(provider.rawValue)")
            .onChange(of: baseText) { _, value in
                UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AIPreferences.baseURLKey(provider))
                // Another address has its own key (none yet, unless typed for it before).
                key = account.flatMap(Keychain.read) ?? ""
            }
            LabeledContent("app:ai.settings.status") {
                Text(status).foregroundStyle(problem ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.subtleForeground))
            }
        } header: {
            Text(verbatim: provider.name)
        } footer: {
            switch provider {
            case .anthropic: Text("app:ai.settings.anthropic.detail")
            case .openAI: Text("app:ai.settings.openai.detail")
            }
        }
        .onAppear {
            baseText = AIPreferences.baseText(provider)
            key = account.flatMap(Keychain.read) ?? ""
        }
    }

    private var problem: Bool { base.map { !AIEndpoint.mayCarryKey($0) } ?? true }

    private var status: LocalizedStringKey {
        guard let base else { return "app:ai.settings.status.badURL" }
        if !AIEndpoint.mayCarryKey(base) { return "app:ai.settings.status.insecure" }
        return key.isEmpty ? "app:ai.settings.status.none" : "app:ai.settings.status.saved"
    }

    private var prompt: LocalizedStringKey {
        switch provider {
        case .anthropic: "app:ai.settings.anthropic.prompt"
        case .openAI: "app:ai.settings.openai.prompt"
        }
    }
}
