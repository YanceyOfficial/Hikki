import Foundation
import Testing

@testable import HikkiCore

struct PageChatsTests {
    private func store() -> (PageChats, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "chats-\(UUID().uuidString)")
        return (PageChats(root: root), root)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func turn(_ id: String, _ role: ChatTurn.Role = .user, text: String = "words", at seconds: Double) -> ChatTurn {
        ChatTurn(id: id, role: role, text: text, sentAt: t0.addingTimeInterval(seconds))
    }

    @Test func aConversationIsKeptPerPage() throws {
        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try chats.conversation(of: "p", now: t0) == ChatConversation())
        try chats.save([turn("q", text: "总结一下", at: 0), turn("a", .assistant, text: "…", at: 1)], pageId: "p")
        // The finished answer replaces what was kept of it.
        try chats.save([turn("a", .assistant, text: "三个要点", at: 1)], pageId: "p")
        try chats.save([turn("other", at: 2)], pageId: "q")
        let conversation = try chats.conversation(of: "p", now: t0)
        #expect(conversation.turns.map(\.id) == ["q", "a"])
        #expect(conversation.turns.map(\.text) == ["总结一下", "三个要点"])
        #expect(try chats.conversation(of: "q", now: t0).turns.map(\.id) == ["other"])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "ai/p.json").path))
    }

    @Test func newChatClearsAndUndoPutsItBack() throws {
        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        try chats.save([turn("q", at: 0), turn("a", .assistant, at: 1)], pageId: "p")
        try chats.setSummary(ChatSummary(text: "earlier", through: "q", createdAt: t0), pageId: "p")
        let previous = try chats.clear(pageId: "p", now: t0.addingTimeInterval(10))
        #expect(previous.turns.map(\.id) == ["q", "a"])
        #expect(try chats.conversation(of: "p", now: t0).turns.isEmpty)
        #expect(try chats.conversation(of: "p", now: t0).summary == nil)
        // The cleared words aren't kept in the file.
        #expect(try !String(contentsOf: chats.url(for: "p"), encoding: .utf8).contains("\"q\""))
        // Said after New chat, then undone: both kept.
        try chats.save([turn("new", at: 20)], pageId: "p")
        try chats.restore(previous, pageId: "p")
        let restored = try chats.conversation(of: "p", now: t0)
        #expect(restored.turns.map(\.id) == ["q", "a", "new"])
        #expect(restored.summary?.text == "earlier")
    }

    @Test func aClearedTurnFromAnotherDeviceDoesNotComeBack() {
        let phone = PageChats.File(format: 1, pageId: "p", clearedAt: nil, turns: [turn("old", at: 0)])
        let mac = PageChats.File(
            format: 1, pageId: "p", clearedAt: t0.addingTimeInterval(5), turns: [turn("new", at: 9)])
        let merged = PageChats.merge(phone, mac)
        #expect(merged.clearedAt == t0.addingTimeInterval(5))
        #expect(merged.turns.map(\.id).sorted() == ["new", "old"])  // the file write drops "old"
        // An answer kept while it was still arriving loses to its finished words.
        let partial = PageChats.File(format: 1, pageId: "p", turns: [turn("a", .assistant, text: "三", at: 1)])
        let full = PageChats.File(format: 1, pageId: "p", turns: [turn("a", .assistant, text: "三个要点", at: 1)])
        #expect(PageChats.merge(full, partial).turns.map(\.text) == ["三个要点"])
        #expect(PageChats.merge(partial, full).turns.map(\.text) == ["三个要点"])
    }

    @Test func aChangeReviewedOnOneDeviceStaysReviewed() {
        func answer(_ statuses: [AIPageChange.Status]) -> ChatTurn {
            var turn = turn("a", .assistant, text: "改好了", at: 1)
            turn.changes = statuses.enumerated().map { index, status in
                AIPageChange(id: "a-\(index)", kind: .rewrite, block: "b\(index)", html: "x", title: "t", status: status)
            }
            return turn
        }
        let mac = PageChats.File(format: 1, pageId: "p", turns: [answer([.approved, .pending])])
        let phone = PageChats.File(format: 1, pageId: "p", turns: [answer([.pending, .skipped])])
        #expect(PageChats.merge(mac, phone).turns[0].changes?.map(\.status) == [.approved, .skipped])
        #expect(PageChats.merge(phone, mac).turns[0].changes?.map(\.status) == [.approved, .skipped])
    }

    @Test func onlyWebPagesAreCitationLinks() {
        #expect(ChatCitation(url: "https://kyoto.travel/autumn", title: nil).webURL != nil)
        #expect(ChatCitation(url: "HTTP://example.com", title: nil).webURL != nil)
        for url in ["file:///etc/hosts", "javascript:alert(1)", "hikki://page/x", "x-apple-reminder://", "https:nohost", "not a url"] {
            #expect(ChatCitation(url: url, title: nil).webURL == nil, "\(url)")
        }
    }

    @Test func picturesShowOnlyFromTheWebAndAreKept() throws {
        let picture = ChatImage(
            url: "https://cdn.example/gg.jpg", thumbnail: "file:///etc/hosts", source: "javascript:alert(1)", caption: "Bridge")
        // A thumbnail or a page that isn't on the web is left out; the picture itself stands in for its thumbnail.
        #expect(picture.thumbnailURL?.absoluteString == "https://cdn.example/gg.jpg")
        #expect(picture.sourceURL == nil)
        #expect(ChatImage(url: "file:///etc/hosts").webURL == nil)

        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        var answer = turn("a", .assistant, text: "Here", at: 0)
        answer.images = [picture]
        try chats.save([answer], pageId: "p")
        #expect(try chats.conversation(of: "p", now: t0).turns.first?.images == [picture])
        // A longer copy of the answer from a device that kept no pictures keeps these.
        var longer = turn("a", .assistant, text: "Here it is", at: 0)
        longer.images = nil
        let mac = PageChats.File(format: 1, pageId: "p", clearedAt: nil, turns: [answer])
        let phone = PageChats.File(format: 1, pageId: "p", clearedAt: nil, turns: [longer])
        #expect(PageChats.merge(mac, phone).turns.first?.images == [picture])
    }

    @Test func madePicturesAreKeptAndAMadeOneWinsAMerge() throws {
        func answer(_ pictures: [ChatPicture]) -> ChatTurn {
            var turn = turn("a", .assistant, text: "Three pictures", at: 1)
            turn.pictures = pictures
            turn.picturePlace = PicturePlace(blockId: "b2")
            return turn
        }
        let making = ChatPicture(id: "a-0", prompt: "Pagoda", shape: "wide")
        var made = making
        made.status = .done
        made.asset = "hikki-editor://assets/pagoda.jpg"
        var stopped = ChatPicture(id: "a-1", prompt: "Bamboo", shape: "tall", status: .stopped)
        var added = stopped
        added.added = true
        added.status = .stopped
        stopped.added = nil

        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        try chats.save([answer([made, stopped])], pageId: "p")
        let kept = try chats.conversation(of: "p", now: t0).turns.first
        #expect(kept?.pictures == [made, stopped])
        #expect(kept?.picturePlace == PicturePlace(blockId: "b2"))

        // The device still making it loses to the one that made it; added on either stays added.
        let mac = PageChats.File(format: 1, pageId: "p", turns: [answer([making, added])])
        let phone = PageChats.File(format: 1, pageId: "p", turns: [answer([made, stopped])])
        for merged in [PageChats.merge(mac, phone), PageChats.merge(phone, mac)] {
            #expect(merged.turns[0].pictures?.map(\.status) == [.done, .stopped])
            #expect(merged.turns[0].pictures?[0].asset == made.asset)
            #expect(merged.turns[0].pictures?[1].added == true)
        }
    }

    @Test func oldTurnsGoAfterTheRetention() throws {
        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let day = 86_400.0
        try chats.save([turn("old", at: 0), turn("recent", at: 80 * day)], pageId: "p")
        try chats.save([turn("ancient", at: 0)], pageId: "q")
        let now = t0.addingTimeInterval(100 * day)
        #expect(try chats.conversation(of: "p", retention: .days30, now: now).turns.map(\.id) == ["recent"])
        #expect(try chats.conversation(of: "p", retention: .forever, now: now).turns.count == 2)
        chats.prune(.days90, now: now)
        #expect(try chats.conversation(of: "p", retention: .forever, now: now).turns.map(\.id) == ["recent"])
        // A file left with nothing goes.
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "ai/q.json").path))
        chats.prune(.forever, now: now)
        #expect(try chats.conversation(of: "p", retention: .forever, now: now).turns.count == 1)
    }

    @Test func deletingRemovesTheFiles() throws {
        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        try chats.save([turn("q", at: 0)], pageId: "p")
        try chats.save([turn("q", at: 0)], pageId: "r")
        chats.removeAll(pageId: "p")
        #expect(try chats.conversation(of: "p", now: t0).turns.isEmpty)
        #expect(try chats.conversation(of: "r", now: t0).turns.count == 1)
        chats.removeEverything()
        #expect(try chats.conversation(of: "r", now: t0).turns.isEmpty)
    }

    @Test func aPageIdThatWouldLeaveTheFolderIsRefused() {
        let (chats, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try chats.save([turn("q", at: 0)], pageId: "../pages/x") }
    }
}
