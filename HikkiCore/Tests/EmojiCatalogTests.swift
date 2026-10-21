import Foundation
import Testing

@testable import HikkiCore

struct EmojiCatalogTests {
    private let messages = Data(
        """
        {"groups":[{"key":"animals-nature","message":"animals & nature","order":3},
        {"key":"smileys-emotion","message":"smileys & emotion","order":0},{"key":"component","message":"component","order":2}]}
        """.utf8)
    private let data = Data(
        """
        [{"emoji":"😀","hexcode":"1F600","label":"grinning face","tags":["face","grin"],"group":0,"order":2,"version":1},
        {"emoji":"😃","hexcode":"1F603","label":"grinning face with big eyes","tags":["happy"],"group":0,"order":1,"version":1},
        {"emoji":"🐶","hexcode":"1F436","label":"dog face","tags":["pet"],"group":3,"order":5,"version":1},
        {"emoji":"🏻","hexcode":"1F3FB","label":"light skin tone","group":2,"order":9,"version":1},
        {"emoji":"🫨","hexcode":"1FAE8","label":"shaking face","group":0,"order":3,"version":17},
        {"emoji":"🇦","hexcode":"1F1E6","label":"regional indicator A","version":0}]
        """.utf8)

    @Test func groupsInEmojibasesOrderWithoutComponentsOrTooNewEmoji() throws {
        let categories = try EmojiCatalog.categories(data: data, messages: messages, english: nil)
        #expect(categories.map(\.key) == ["smileys-emotion", "animals-nature"])
        #expect(categories[0].label == "Smileys & emotion")
        #expect(categories[0].emojis.map(\.emoji) == ["😃", "😀"])
        #expect(categories[1].emojis.map(\.emoji) == ["🐶"])
    }

    @Test func searchesNamesFirstThenKeywordsInBothLanguages() throws {
        let chinese = Data(
            """
            [{"emoji":"😀","hexcode":"1F600","label":"嘿嘿","tags":["笑"],"group":0,"order":2,"version":1},
            {"emoji":"🐶","hexcode":"1F436","label":"狗脸","group":3,"order":5,"version":1}]
            """.utf8)
        let categories = try EmojiCatalog.categories(data: chinese, messages: messages, english: data)
        #expect(EmojiCatalog.search(categories, "狗").map(\.emoji) == ["🐶"])
        // English still finds it in a Chinese catalog.
        #expect(EmojiCatalog.search(categories, " Dog ").map(\.emoji) == ["🐶"])
        let english = try EmojiCatalog.categories(data: data, messages: messages, english: nil)
        // "grin…" names come before a tag match ("happy" is only a tag of 😃, "face" a tag of 😀).
        #expect(EmojiCatalog.search(english, "face").map(\.emoji) == ["😃", "😀", "🐶"])
        #expect(EmojiCatalog.search(english, "grinning face w").map(\.emoji) == ["😃"])
        #expect(EmojiCatalog.search(english, "  ").isEmpty)
    }

    @Test func recentsKeepTheNewestOnceUpToTheLimit() {
        #expect(EmojiCatalog.remember("🐶", in: ["😀", "🐶"]) == ["🐶", "😀"])
        let full = (0..<EmojiCatalog.recentLimit).map { String($0) }
        #expect(EmojiCatalog.remember("🐶", in: full).count == EmojiCatalog.recentLimit)
        #expect(EmojiCatalog.remember("🐶", in: full).first == "🐶")
        #expect(EmojiCatalog.locale(for: "zh-Hans") == "zh")
        #expect(EmojiCatalog.locale(for: "en") == "en")
    }

    /// The real data the app ships (emojibase-data, as the editor installs it) reads, in both languages.
    @Test func readsTheEditorsBundledData() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../apps/editor/node_modules/emojibase-data").standardizedFileURL
        for locale in ["en", "zh"] {
            let categories = try EmojiCatalog.load(from: folder, locale: locale)
            #expect(categories.count == 9)
            #expect(categories.reduce(0) { $0 + $1.emojis.count } > 1500)
        }
    }
}
