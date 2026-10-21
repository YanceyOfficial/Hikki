import Foundation

/// One emoji as the icon picker lists it: the character, its name (in the app's language) and what a search matches —
/// its name and tags, and the English ones too.
public struct EmojiEntry: Sendable, Hashable, Identifiable {
    public let emoji: String
    public let label: String
    /// Lowercased name and tags, both languages, for search.
    public let keywords: String
    public var id: String { emoji }

    public init(emoji: String, label: String, keywords: String) {
        self.emoji = emoji
        self.label = label
        self.keywords = keywords
    }
}

/// A group of the picker ("Smileys & emotion"), in emojibase's order.
public struct EmojiCategory: Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let emojis: [EmojiEntry]
    public var id: String { key }
}

/// The emoji catalog behind the native icon picker — the same emojibase data the editor ships (`Editor/emojibase/
/// <locale>/{data,messages}.json` in the app's bundle) read the way `apps/editor/src/lib/emoji-data.ts` reads it:
/// grouped and ordered as emojibase says, skin-tone components left out, emoji newer than the system fonts draw
/// (`maxVersion`) dropped.
public enum EmojiCatalog {
    /// Newer emoji may draw as empty boxes on current system fonts.
    static let maxVersion = 16.0
    /// How many recently picked emoji the picker keeps.
    public static let recentLimit = 27

    private struct Raw: Decodable {
        let emoji: String
        let hexcode: String
        let label: String
        let tags: [String]?
        let group: Int?
        let order: Int?
        let version: Double?
    }

    private struct Messages: Decodable {
        struct Group: Decodable {
            let key: String
            let message: String
            let order: Int
        }
        let groups: [Group]
    }

    /// The catalog in `locale` ("en" or "zh") from the bundle's emojibase folder; search also matches English names.
    public static func load(from folder: URL, locale: String) throws -> [EmojiCategory] {
        let read = { (path: String) in try Data(contentsOf: folder.appending(path: path)) }
        return try categories(
            data: read("\(locale)/data.json"), messages: read("\(locale)/messages.json"),
            english: locale == "en" ? nil : read("en/data.json"))
    }

    /// The emojibase locale for an app language ("zh-Hans" → "zh"); everything else reads English.
    public static func locale(for language: String) -> String {
        language.hasPrefix("zh") ? "zh" : "en"
    }

    static func categories(data: Data, messages: Data, english: Data?) throws -> [EmojiCategory] {
        let decoder = JSONDecoder()
        let emojis = try decoder.decode([Raw].self, from: data)
        let groups = try decoder.decode(Messages.self, from: messages).groups
            .filter { $0.key != "component" }
            .sorted { $0.order < $1.order }
        var extra: [String: String] = [:]
        if let english {
            for raw in try decoder.decode([Raw].self, from: english) {
                extra[raw.hexcode] = ([raw.label] + (raw.tags ?? [])).joined(separator: " ")
            }
        }
        var byGroup: [Int: [Raw]] = [:]
        for raw in emojis {
            guard let group = raw.group, (raw.version ?? 0) <= maxVersion else { continue }
            byGroup[group, default: []].append(raw)
        }
        return groups.compactMap { group in
            let members = (byGroup[group.order] ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            guard !members.isEmpty else { return nil }
            return EmojiCategory(
                key: group.key, label: group.message.prefix(1).uppercased() + group.message.dropFirst(),
                emojis: members.map { raw in
                    EmojiEntry(
                        emoji: raw.emoji, label: raw.label,
                        keywords: ([raw.label] + (raw.tags ?? []) + [extra[raw.hexcode] ?? ""]).joined(separator: " ")
                            .lowercased())
                })
        }
    }

    /// Names starting with the query first, then names or keywords containing it; the catalog's order within each.
    public static func search(_ categories: [EmojiCategory], _ query: String, limit: Int = 240) -> [EmojiEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var prefix: [EmojiEntry] = []
        var rest: [EmojiEntry] = []
        for entry in categories.lazy.flatMap(\.emojis) {
            if entry.label.lowercased().hasPrefix(needle) {
                prefix.append(entry)
            } else if entry.keywords.contains(needle) {
                rest.append(entry)
            }
        }
        return Array((prefix + rest).prefix(limit))
    }

    /// The recent list after a pick: it goes first, once, the oldest falling off past `recentLimit`.
    public static func remember(_ emoji: String, in recents: [String]) -> [String] {
        Array(([emoji] + recents.filter { $0 != emoji }).prefix(recentLimit))
    }
}
