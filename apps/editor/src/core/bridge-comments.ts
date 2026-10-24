import {
  commentsState,
  setThreads,
  threadRange,
  type CommentsHost,
  type ThreadItem
} from '../extensions/comments'
import { pageLinkHref, type PageLinksHost } from '../extensions/page-links'
import { openTogglesAround } from '../extensions/toggle'
import type { BridgeContext } from './bridge-types'
import type { ToNativeMessage } from './protocol'

/** What the native thread sheet asks of the page (`commentAction`). */
export type CommentAction =
  | { type: 'reply'; threadId: string; body: string }
  | { type: 'resolve'; threadId: string; resolved: boolean }
  | { type: 'delete'; threadId: string; commentId?: string }
  | { type: 'edit'; threadId: string; commentId: string; body: string }

type CommentMessage =
  | { type: 'commentCreate'; threadId: string; quote: string; body: string; blockId?: string }
  | { type: 'commentReply'; threadId: string; body: string }
  | { type: 'commentResolve'; threadId: string; resolved: boolean }
  | { type: 'commentDelete'; threadId: string; commentId?: string }
  | { type: 'commentEdit'; threadId: string; commentId: string; body: string }

/**
 * Comments between the page and the native store: the editor's threads come from `setComments`, what the user writes
 * goes back as comment messages, and on a phone the open thread is drawn natively (`setNativeComments`).
 */
export class CommentsBridge {
  /** This device's name ("Mac", "iPhone"), from `setComments`. */
  private device: string | null = null
  /** The phone draws an open thread natively (`setNativeComments`): the page's own sheet stays shut. */
  private nativeComments = false
  /** The thread last reported open (`commentThread`). */
  private reportedThread: string | null = null

  constructor(
    private readonly context: BridgeContext,
    private readonly pageLinks: PageLinksHost
  ) {}

  /** Comments on passages: written to the native store, which sends the page's threads back (`setComments`). */
  readonly host: CommentsHost = {
    create: (threadId, quote, body, blockId) =>
      this.sendComment({
        type: 'commentCreate',
        threadId,
        quote,
        body,
        ...(blockId ? { blockId } : {})
      }),
    reply: (threadId, body) => this.sendComment({ type: 'commentReply', threadId, body }),
    resolve: (threadId, resolved) =>
      this.sendComment({ type: 'commentResolve', threadId, resolved }),
    remove: (threadId, commentId) =>
      this.sendComment({ type: 'commentDelete', threadId, ...(commentId ? { commentId } : {}) }),
    edit: (threadId, commentId, body) =>
      this.sendComment({ type: 'commentEdit', threadId, commentId, body }),
    device: () => this.device,
    nativeThreads: () => this.nativeComments,
    pages: () => this.pageLinks.pages(),
    openPage: (pageId) => this.pageLinks.open({ pageId, blockId: null }),
    link: (threadId) => {
      const docId = this.context.page.get().docId
      return docId ? pageLinkHref(docId, threadId) : null
    }
  }

  private sendComment(message: CommentMessage): void {
    const docId = this.context.page.get().docId
    if (docId) void this.context.send({ ...message, docId } as ToNativeMessage)
  }

  /** `window.hikki.setNativeComments`: the native side shows open threads in its own sheet. */
  setNativeComments(on: boolean): void {
    this.nativeComments = on
  }

  /** After every transaction: the open thread, when the native side draws it and it changed. */
  reportThread(): void {
    const editor = this.context.editor()
    const docId = this.context.page.get().docId
    if (!this.nativeComments || !editor || !docId) return
    const threadId = commentsState(editor.state)?.active ?? null
    if (threadId === this.reportedThread) return
    this.reportedThread = threadId
    void this.context.send({ type: 'commentThread', docId, threadId })
  }

  /** `window.hikki.commentAction`: the native thread sheet's actions, run as the page's own (deleting a thread also
   * removes its mark; resolving or deleting the open thread closes it). Closing the sheet is `openComment(null)`.
   * Returns whether it was done. */
  commentAction(action: CommentAction): boolean {
    const editor = this.context.editor()
    if (!editor) return false
    const commands = editor.commands
    switch (action.type) {
      case 'reply':
        if (!action.body.trim()) return false
        this.host.reply(action.threadId, action.body.trim())
        return true
      case 'resolve':
        return commands.commentResolve(action.threadId, action.resolved)
      case 'delete':
        return action.commentId
          ? commands.commentDeleteReply(action.threadId, action.commentId)
          : commands.commentDelete(action.threadId)
      case 'edit':
        return commands.commentEdit(action.threadId, action.commentId, action.body)
    }
  }

  /** `window.hikki.setComments`: the page's threads from the native store (after loading it, and after each change). */
  setComments(docId: string, threads: ThreadItem[], device: string | null): void {
    this.device = device
    const editor = this.context.editor()
    if (editor && docId === this.context.page.get().docId) setThreads(editor, threads)
  }

  /** `window.hikki.openComment`: a thread picked in the side panel — open, and its passage in view. */
  openComment(threadId: string | null): void {
    const editor = this.context.editor()
    if (!editor) return
    if (threadId === null) {
      editor.commands.commentOpen(null)
      return
    }
    const range = threadRange(editor.state, threadId)
    editor.commands.commentOpen(threadId)
    if (range) {
      openTogglesAround(editor, range.from)
      const dom = editor.view.domAtPos(range.from).node
      ;(dom instanceof Element ? dom : dom.parentElement)?.scrollIntoView({ block: 'center' })
    }
  }
}
