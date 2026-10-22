import Foundation

/// The model menu of the page's own AI (the inline AI panel: one request on another model): Auto, then the chat
/// menu's sections with only the models whose provider has a key, and the default each request runs on unless the
/// panel picks another.
public struct PageModelMenu: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
        public let kind: AIModelCatalog.Section.Kind
        public let models: [AIModel]
    }

    /// "auto" or a model id: the chosen default when its provider has a key, else "auto".
    public let choice: String
    /// The model Auto runs on now (nil: no provider has a key, and the panel offers no choice).
    public let auto: AIModel?
    public let groups: [Group]
    /// Pictures can be made (they need an OpenAI key, whichever model the chat runs on).
    public let pictures: Bool

    public init(choice: String?, favorites: AIModelFavorites, available: Set<AIProvider>) {
        let chosen = choice.flatMap(AIModelCatalog.model(id:)).flatMap { available.contains($0.provider) ? $0 : nil }
        self.choice = chosen?.id ?? AIModelCatalog.autoID
        auto = AIModelCatalog.auto(available: available)
        pictures = available.contains(.openAI)
        groups = AIModelCatalog.sections(favorites: favorites).compactMap { section in
            let models = section.models.filter { available.contains($0.provider) }
            return models.isEmpty ? nil : Group(kind: section.kind, models: models)
        }
    }

    /// As the editor reads it (`AIModelMenu` in protocol.ts).
    public var payload: [String: Any] {
        [
            "choice": choice, "auto": auto?.displayName ?? NSNull(), "pictures": pictures,
            "groups": groups.map { group in
                [
                    "kind": group.kind.rawValue,
                    "models": group.models.map { ["id": $0.id, "name": $0.displayName] },
                ] as [String: Any]
            },
        ]
    }
}
