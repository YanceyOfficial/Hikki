import Foundation

/// The models the user starred (Notion's model menu): in the order starred, catalog models only, each once. Stored as
/// one comma-separated string (a UserDefaults value the app keeps under `AIPreferences.favoritesKey`).
public struct AIModelFavorites: Equatable, Sendable {
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { AIModelCatalog.model(id: $0) != nil && seen.insert($0).inserted }
    }

    /// From the stored string; ids no longer in the catalog drop out.
    public init(stored: String) {
        self.init(ids: stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    public var stored: String { ids.joined(separator: ",") }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Stars a model (it goes last among the favourites) or takes its star away.
    public mutating func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else if AIModelCatalog.model(id: id) != nil {
            ids.append(id)
        }
    }

    public func toggling(_ id: String) -> AIModelFavorites {
        var copy = self
        copy.toggle(id)
        return copy
    }
}

extension AIModelCatalog {
    /// A group of the model menu under "Auto".
    public struct Section: Equatable, Identifiable, Sendable {
        public enum Kind: String, Sendable {
            case favorites, recommended, other
        }

        public let kind: Kind
        public let models: [AIModel]

        public var id: Kind { kind }
    }

    /// The menu under "Auto": the starred models first ("Favorites", in the order starred), then the recommended
    /// ones and the other models that aren't starred — each model once; empty groups left out.
    public static func sections(favorites: AIModelFavorites) -> [Section] {
        let starred = favorites.ids.compactMap(model(id:))
        let groups: [Section] = [
            Section(kind: .favorites, models: starred),
            Section(kind: .recommended, models: recommended.filter { !favorites.contains($0.id) }),
            Section(kind: .other, models: others.filter { !favorites.contains($0.id) }),
        ]
        return groups.filter { !$0.models.isEmpty }
    }
}
