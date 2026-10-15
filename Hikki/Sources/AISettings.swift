import HikkiAI
import HikkiUI
import SwiftUI

/// Settings → AI: the providers' API keys (in the Keychain; each sent only to the origin it was entered for), an
/// optional base URL per provider, and the model AI uses by default. The models are a fixed list (`AIModelCatalog`).
enum AIPreferences {
    /// The model chosen: an id from the catalog or "auto".
    static let modelKey = "ai.model"
    /// How an AI edit is reviewed: `inline` (A, default), `diff` (B) or `bubble` (C) — `ReviewStyleThumbnail.Sketch`.
    static let reviewStyleKey = "ai.reviewStyle"

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

    /// The providers that have a key for their current base.
    static var available: Set<AIProvider> {
        Set(AIProvider.allCases.filter { key($0) != nil })
    }
}

struct AISettingsSection: View {
    @AppStorage(AIPreferences.modelKey) private var model = AIModelCatalog.autoID
    @AppStorage(AIPreferences.reviewStyleKey) private var reviewStyle = ReviewStyleThumbnail.Sketch.inline.rawValue

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.s2) {
                ForEach(ReviewStyleThumbnail.Sketch.allCases, id: \.self) { sketch in
                    ThumbnailOption(title(sketch), isSelected: reviewStyle == sketch.rawValue) {
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
            Text(detail(ReviewStyleThumbnail.Sketch(rawValue: reviewStyle) ?? .inline))
        }
        Section {
            Picker("app:ai.settings.model", selection: $model) {
                Text("app:ai.model.auto").tag(AIModelCatalog.autoID)
                Divider()
                ForEach(AIModelCatalog.all) { model in
                    Text(verbatim: "\(model.displayName) · \(model.provider.name)").tag(model.id)
                }
            }
            .accessibilityIdentifier("settings-ai-model")
        } header: {
            Text("app:ai.settings.models")
        } footer: {
            Text("app:ai.settings.models.detail")
        }
        ForEach(AIProvider.allCases, id: \.self) { provider in
            AIKeySection(provider: provider)
        }
    }

    private func title(_ sketch: ReviewStyleThumbnail.Sketch) -> LocalizedStringKey {
        switch sketch {
        case .inline: "app:ai.review.inline"
        case .diff: "app:ai.review.diff"
        case .bubble: "app:ai.review.bubble"
        }
    }

    private func detail(_ sketch: ReviewStyleThumbnail.Sketch) -> LocalizedStringKey {
        switch sketch {
        case .inline: "app:ai.review.inline.detail"
        case .diff: "app:ai.review.diff.detail"
        case .bubble: "app:ai.review.bubble.detail"
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
