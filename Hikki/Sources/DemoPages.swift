#if DEBUG
    import Foundation
    import HikkiCore

    /// DEBUG hook: HIKKI_DEMO_PAGES=1 fills an empty workspace with a small tree of pages (screenshots, design
    /// checks on a simulator). Never touches a workspace that has pages. Ids are fixed per title (a hash), so
    /// HIKKI_OPEN_TABS can open one.
    enum DemoPages {
        static func seed(_ store: DocumentStore) {
            guard ProcessInfo.processInfo.environment["HIKKI_DEMO_PAGES"] != nil, (try? store.pages().isEmpty) == true else {
                return
            }
            let now = Date.now
            func page(_ title: String, _ icon: String?, parent: String? = nil, minutesAgo: Double, text: [String] = []) -> String? {
                let id = "demo-" + String(title.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } & 0xFFFF_FFFF, radix: 16)
                guard let record = try? store.create(id: id, parentId: parent, now: now) else { return nil }
                let paragraphs = text.map { line -> JSONValue in
                    .object(["type": .string("paragraph"), "content": .array([.object(["type": .string("text"), "text": .string(line)])])])
                }
                let edited = now.addingTimeInterval(-minutesAgo * 60)
                let body = text.joined(separator: "\n")
                _ = try? store.saveContent(
                    Snapshot(
                        docId: record.id, content: .object(["type": .string("doc"), "content": .array(paragraphs)]), title: title,
                        text: body, wordCount: WordCount.count(title: title, text: body)),
                    now: edited)
                try? store.setIcon(icon, for: record.id, now: edited)
                return record.id
            }
            let japanese = page("日本語を勉強する", "🇯🇵", minutesAgo: 420)
            _ = page("N5 文法", nil, parent: japanese, minutesAgo: 300)
            _ = page("N4 文法", "🍀", parent: japanese, minutesAgo: 49, text: ["練習B · 〜そうです", "雨が降りそうです。", "山へ行くんですか。"])
            _ = page("N3 文法", nil, parent: japanese, minutesAgo: 310)
            let homework = page("课后习题", "🙋", parent: japanese, minutesAgo: 430)
            _ = page("初级下", "📝", parent: homework, minutesAgo: 240)
            _ = page("文法专栏", "📚", parent: japanese, minutesAgo: 320)
            let travel = page("Travel", "✈️", minutesAgo: 2000)
            // A cover too: screenshots of a page's top (the cover runs under the iPhone's bar).
            if let kyoto = page("Kyoto in spring", "🌸", parent: travel, minutesAgo: 2100, text: ["Philosopher's Path at dawn."]) {
                try? store.setCover("gradient:dusk", for: kyoto, now: now.addingTimeInterval(-2100 * 60))
            }
            _ = page("Career Planning", "🌱", minutesAgo: 290)
            _ = page("English Learning", "🏴", minutesAgo: 360)
            _ = page("OKRs", "🎯", minutesAgo: 3000)
            _ = page("Immigration Planning", "🧭", minutesAgo: 330)
            if let japanese { try? store.setFavorite(true, for: japanese) }
        }
    }
#endif
