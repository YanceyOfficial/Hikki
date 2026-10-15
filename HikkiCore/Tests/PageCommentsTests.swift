import Foundation
import Testing

@testable import HikkiCore

struct PageCommentsTests {
    private func store() -> (PageComments, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "comments-\(UUID().uuidString)")
        return (PageComments(root: root, author: "Yancey", device: "Mac"), root)
    }

    @Test func aThreadStartsRepliesResolvesAndIsDeleted() throws {
        let (comments, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let t0 = Date(timeIntervalSince1970: 1_000)
        try comments.create(pageId: "p", threadId: "t", quote: "そうです", body: "  样态  ", now: t0)
        try comments.reply(pageId: "p", threadId: "t", body: "例：おいしそう", now: t0.addingTimeInterval(60))
        var threads = try comments.threads(of: "p")
        #expect(threads.count == 1)
        #expect(threads[0].quote == "そうです")
        #expect(threads[0].comments.map(\.body) == ["样态", "例：おいしそう"])
        #expect(threads[0].comments[0].author == "Yancey" && threads[0].comments[0].device == "Mac")

        try comments.setResolved(true, pageId: "p", threadId: "t")
        #expect(try comments.threads(of: "p")[0].resolvedAt != nil)

        let first = threads[0].comments[0].id
        try comments.delete(pageId: "p", threadId: "t", commentId: first)
        threads = try comments.threads(of: "p")
        #expect(threads[0].comments.map(\.body) == ["例：おいしそう"])
        try comments.delete(pageId: "p", threadId: "t")
        #expect(try comments.threads(of: "p").isEmpty)
        // The tombstone stays in the file.
        #expect(try String(contentsOf: comments.url(for: "p"), encoding: .utf8).contains("deletedAt"))
    }

    @Test func emptyCommentsAndUnknownThreadsAreRefused() throws {
        let (comments, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PageComments.Failure.emptyComment) {
            try comments.create(pageId: "p", threadId: "t", quote: "", body: "   ")
        }
        #expect(throws: PageComments.Failure.unknownThread) { try comments.reply(pageId: "p", threadId: "x", body: "hi") }
        #expect(try comments.threads(of: "nothing").isEmpty)
    }

    @Test func twoDevicesVersionsMergeWithoutLosingAComment() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func comment(_ id: String, _ seconds: Double, deleted: Bool = false) -> PageComment {
            PageComment(
                id: id, body: id, author: nil, device: nil, createdAt: t0.addingTimeInterval(seconds),
                deletedAt: deleted ? t0.addingTimeInterval(500) : nil)
        }
        let mac = [
            CommentThread(
                id: "t", quote: "q", createdAt: t0, updatedAt: t0.addingTimeInterval(10), comments: [comment("a", 0), comment("mac", 10)]),
            CommentThread(id: "only-mac", quote: "q", createdAt: t0, updatedAt: t0, comments: [comment("m", 0)]),
        ]
        let phone = [
            CommentThread(
                id: "t", quote: "q", createdAt: t0, updatedAt: t0.addingTimeInterval(20), resolvedAt: t0.addingTimeInterval(20),
                comments: [comment("a", 0, deleted: true), comment("phone", 20)])
        ]
        let merged = PageComments.merge(mac, phone)
        #expect(merged.map(\.id).sorted() == ["only-mac", "t"])
        let thread = merged.first { $0.id == "t" }!
        #expect(thread.comments.map(\.id) == ["a", "mac", "phone"])
        #expect(thread.comments[0].deletedAt != nil)
        // The newer state (resolved on the phone) wins.
        #expect(thread.resolvedAt != nil)
        #expect(thread.visibleComments.map(\.id) == ["mac", "phone"])
    }
}
