import HikkiAI
import HikkiUI
import SwiftUI

/// Settings → AI: the providers' API keys (in the Keychain, one per provider; sent only to that provider) and the
/// model AI uses by default. The models are a fixed list (`AIModelCatalog`).
enum AIPreferences {
    /// The model chosen: an id from the catalog or "auto".
    static let modelKey = "ai.model"
    /// How an AI edit is reviewed: `inline` (A, default), `diff` (B) or `bubble` (C) — `ReviewStyleThumbnail.Sketch`.
    static let reviewStyleKey = "ai.reviewStyle"

    static func keyAccount(_ provider: AIProvider) -> String { "ai.key.\(provider.rawValue)" }

    static func key(_ provider: AIProvider) -> String? {
        Keychain.read(keyAccount(provider)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The providers that have a key.
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

    var body: some View {
        Section {
            SecureField("app:ai.settings.key", text: $key, prompt: Text(prompt))
                .accessibilityIdentifier("settings-ai-key-\(provider.rawValue)")
                .onAppear { key = AIPreferences.key(provider) ?? "" }
                .onChange(of: key) { _, value in
                    Keychain.write(value.trimmingCharacters(in: .whitespacesAndNewlines), for: AIPreferences.keyAccount(provider))
                }
            LabeledContent("app:ai.settings.status") {
                Text(key.isEmpty ? "app:ai.settings.status.none" : "app:ai.settings.status.saved")
                    .foregroundStyle(Theme.subtleForeground)
            }
        } header: {
            Text(verbatim: provider.name)
        } footer: {
            switch provider {
            case .anthropic: Text("app:ai.settings.anthropic.detail")
            case .openAI: Text("app:ai.settings.openai.detail")
            }
        }
    }

    private var prompt: LocalizedStringKey {
        switch provider {
        case .anthropic: "app:ai.settings.anthropic.prompt"
        case .openAI: "app:ai.settings.openai.prompt"
        }
    }
}
