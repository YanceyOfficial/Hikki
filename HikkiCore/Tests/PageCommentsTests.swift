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
        #expect(try String(contentsOf: try comments.url(for: "p"), encoding: .utf8).contains("deletedAt"))
    }

    @Test func aCommentIsEditedAndTheNewerEditWinsAMerge() throws {
        let (comments, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let t0 = Date(timeIntervalSince1970: 1_000)
        try comments.create(pageId: "p", threadId: "t", quote: "q", body: "传闻", now: t0)
        let id = try comments.threads(of: "p")[0].comments[0].id
        try comments.edit(pageId: "p", threadId: "t", commentId: id, body: " 样态 ", now: t0.addingTimeInterval(30))
        let edited = try comments.threads(of: "p")[0].comments[0]
        #expect(edited.body == "样态" && edited.editedAt == t0.addingTimeInterval(30) && edited.createdAt == t0)
        #expect(throws: PageComments.Failure.emptyComment) { try comments.edit(pageId: "p", threadId: "t", commentId: id, body: " ") }
        #expect(throws: PageComments.Failure.unknownThread) { try comments.edit(pageId: "p", threadId: "t", commentId: "x", body: "a") }

        // Two devices edited the same comment: the later edit's words stay, whichever side it is on.
        func version(_ body: String, editedAt seconds: Double?) -> [CommentThread] {
            [
                CommentThread(
                    id: "t", quote: "q", createdAt: t0, updatedAt: t0.addingTimeInterval(seconds ?? 0),
                    comments: [
                        PageComment(
                            id: "c", body: body, author: nil, device: nil, createdAt: t0,
                            editedAt: seconds.map { t0.addingTimeInterval($0) })
                    ])
            ]
        }
        #expect(PageComments.merge(version("mac", editedAt: 50), version("phone", editedAt: 90))[0].comments[0].body == "phone")
        #expect(PageComments.merge(version("mac", editedAt: 90), version("phone", editedAt: 50))[0].comments[0].body == "mac")
        #expect(PageComments.merge(version("original", editedAt: nil), version("edited", editedAt: 10))[0].comments[0].body == "edited")
    }

    @Test func aMentionReadsAsAtTitleInPlainText() {
        let comment = PageComment(
            id: "c", body: "see [@Kyoto in spring](hikki://page/A1-b2) and [@x](https://e.com)", author: nil, device: nil,
            createdAt: .now)
        #expect(comment.plainBody == "see @Kyoto in spring and [@x](https://e.com)")
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

    @Test func aPageIdThatWouldLeaveTheFolderIsRefused() throws {
        let (comments, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        for id in ["../pages/x", "a/b", "..", ""] {
            #expect(throws: PageFiles.PageFileError.self) {
                try comments.create(pageId: id, threadId: "t", quote: "", body: "hi")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "pages").path))
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
