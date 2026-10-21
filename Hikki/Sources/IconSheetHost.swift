#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's icon picker (HikkiUI's `IconPickerSheet`) for the page's icon or a callout's (`iconSheet`): the
    /// emojibase catalog the editor ships, in the app's language, recently picked first; picks go back to the page as
    /// its own (`EditorController.applyIcon` / `applyIconColor`).
    struct IconSheetHost: View {
        let request: EditorController.IconRequest
        let editor: EditorController
        @State private var catalog = EmojiShelf.shared.categories
        @State private var failed = false
        @State private var recents = EmojiShelf.recents
        /// A callout's background as picked meanwhile (the sheet stays open for it).
        @State private var color: String?

        var body: some View {
            IconPickerSheet(
                title: "app:icon.title",
                sections: catalog?.map { category in
                    IconPickerSection(id: category.key, title: category.label, emojis: category.emojis.map(Self.item))
                },
                failed: failed,
                recents: recentItems,
                current: request.icon,
                search: { query in EmojiCatalog.search(catalog ?? [], query).map(Self.item) },
                onPick: pick,
                onRandom: { if let emoji = catalog?.flatMap(\.emojis).randomElement() { pick(emoji.emoji) } },
                onRemove: request.kind == .page && request.icon != nil ? { send(nil) } : nil,
                color: request.kind == .callout
                    ? (
                        selected: color,
                        onPick: { next in
                            color = next
                            Task { await editor.applyIconColor(next, id: request.id) }
                        }
                    ) : nil
            )
            .onAppear { color = request.color }
            .task {
                guard catalog == nil else { return }
                do {
                    catalog = try await EmojiShelf.shared.load()
                } catch {
                    failed = true
                    Log.error("emoji catalog unreadable", category: "icons", context: ["error": "\(error)"])
                }
            }
        }

        /// The recent picks with their names once the catalog is in.
        private var recentItems: [IconPickerEmoji] {
            let names = Dictionary((catalog ?? []).flatMap(\.emojis).map { ($0.emoji, $0.label) }) { first, _ in first }
            return recents.map { IconPickerEmoji(emoji: $0, label: names[$0] ?? $0) }
        }

        private static func item(_ entry: EmojiEntry) -> IconPickerEmoji {
            IconPickerEmoji(emoji: entry.emoji, label: entry.label)
        }

        private func pick(_ emoji: String) {
            EmojiShelf.recents = EmojiCatalog.remember(emoji, in: EmojiShelf.recents)
            send(emoji)
        }

        private func send(_ icon: String?) {
            let id = request.id
            Task { await editor.applyIcon(icon, id: id) }
        }
    }

    /// The emoji catalog, read once per run off the main thread (about a megabyte of JSON), and the recent picks.
    @MainActor final class EmojiShelf {
        static let shared = EmojiShelf()
        private(set) var categories: [EmojiCategory]?

        /// The recently picked emoji, newest first (`EmojiCatalog.remember`).
        static var recents: [String] {
            get { UserDefaults.standard.stringArray(forKey: "emoji.recent") ?? [] }
            set { UserDefaults.standard.set(newValue, forKey: "emoji.recent") }
        }

        func load() async throws -> [EmojiCategory] {
            if let categories { return categories }
            let folder = Bundle.main.url(forResource: "Editor", withExtension: nil)?.appending(path: "emojibase")
            let locale = EmojiCatalog.locale(for: EditorController.appLocale)
            let loaded = try await Self.read(folder, locale: locale)
            categories = loaded
            return loaded
        }

        @concurrent private static func read(_ folder: URL?, locale: String) async throws -> [EmojiCategory] {
            guard let folder else { throw CocoaError(.fileNoSuchFile) }
            return try EmojiCatalog.load(from: folder, locale: locale)
        }
    }
#endif
