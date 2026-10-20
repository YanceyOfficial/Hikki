#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's open comment thread (HikkiUI's `CommentThreadSheet`) over the page that opened it: the thread read
    /// from the comment store, read again whenever the page's comments change; its actions run in the page as the
    /// page's own (`EditorController.commentAction` — deleting a thread takes its mark away too), which writes the
    /// store and hands the thread back. It closes when the thread is gone or resolved, here or on another device.
    struct CommentThreadHost: View {
        @Environment(AppModel.self) private var model
        let thread: EditorController.OpenThread
        let editor: EditorController
        @State private var shown: CommentThread?

        var body: some View {
            CommentThreadSheet(
                quote: shown?.quote ?? "", comments: comments, onAction: act, onClose: editor.closeThread
            )
            .task(id: thread) { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .pageCommentsChanged)) { note in
                let id = note.userInfo?["id"] as? String
                if id == nil || id == thread.docId { reload() }
            }
        }

        private var comments: [CommentThreadComment] {
            (shown?.comments ?? []).map { comment in
                CommentThreadComment(
                    id: comment.id, author: comment.author,
                    // Where it was written, when that was another device.
                    device: comment.device == editor.deviceName ? nil : comment.device, createdAt: comment.createdAt,
                    edited: comment.editedAt != nil, text: comment.plainBody, body: comment.body)
            }
        }

        private func reload() {
            let threads = (try? model.comments?.threads(of: thread.docId)) ?? []
            guard let found = threads.first(where: { $0.id == thread.threadId }), found.resolvedAt == nil else {
                // Loaded once and gone since (deleted, resolved): nothing left to show.
                if shown != nil { editor.closeThread() }
                return
            }
            shown = found
        }

        private func act(_ action: CommentThreadAction) {
            let id = thread.threadId
            switch action {
            case .reply(let text): editor.commentAction(.reply(text), threadId: id)
            case .resolve: editor.commentAction(.resolve(true), threadId: id)
            case .delete(let commentId, let wholeThread):
                editor.commentAction(.delete(commentId: wholeThread ? nil : commentId), threadId: id)
            case .edit(let commentId, let body): editor.commentAction(.edit(commentId: commentId, body: body), threadId: id)
            case .copyLink:
                UIPasteboard.general.url = PageLink.url(for: thread.docId, block: id)
                Toasts.shared.show(.success, String(localized: "app:comments.linkCopied"))
            }
        }
    }
#endif
