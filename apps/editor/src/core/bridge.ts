import type { Editor, JSONContent } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { Transaction } from '@tiptap/pm/state'

import { setBlockLinkBuilder } from '../components/block-menu'
import { dismissAllLayers, FloatingLayer } from '../components/floating'
import { renderTouchDock } from '../components/touch-dock'
import type { AIChangesHost } from '../extensions/ai-changes'
import { handleAIEvent, type AIHost, type AIReviewStyle } from '../extensions/ai-review'
import {
  commentRanges,
  SAVE_META,
  setThreads,
  type CommentsHost,
  type ThreadItem
} from '../extensions/comments'
import { runFind, type FindMode } from '../extensions/find'
import { UploadsKey, type MediaHost } from '../extensions/media'
import { pageLinkHref, type PageIndexEntry, type PageLinksHost } from '../extensions/page-links'
import { notifyPageIndexChanged } from '../extensions/page-mention'
import { rubySegmentsFrom, type RubyHost } from '../extensions/ruby'
import { setKeyboardBar } from '../extensions/selection-menu'
import type { SplitDropHost, SplitDropMode } from '../extensions/split-drop'
import { openTogglesAround } from '../extensions/toggle'
import { pageBlocks, type AIPageBlock } from '../lib/ai-content'
import { linkCardFrom } from '../lib/embeds'
import { sheetPresence } from '../lib/sheet-presence'
import { activeCommands, createEditor, runCommand } from './editor'
import { plainText, wordCount } from './extract'
import {
  activeHeadingIndex,
  collectHeadings,
  outlineItems,
  sameOutline,
  type OutlineItem
} from './headings'
import { t } from './i18n'
import { normalizeBody } from './normalize'
import {
  COMMANDS,
  type AIChangeInput,
  type AIStreamEvent,
  type Command,
  type PagePayload,
  type Snapshot,
  type ToNativeMessage
} from './protocol'
import { Store } from './store'
import {
  selectAroundCaret,
  touchBlockMenu,
  touchInsertBlock,
  touchRun,
  touchSetColor,
  touchState,
  touchTurnInto,
  touchTurnIntoMenu,
  type TouchBlock,
  type TouchBlockGroup,
  type TouchState,
  type TouchTool
} from './touch-tools'

export interface Transport {
  post(message: ToNativeMessage): Promise<unknown>
}

export type PageState = {
  docId: string | null
  title: string
  icon: string | null
  cover: string | null
  /** Changes only when a heading's id, level or text does (not on every keystroke). */
  headings: OutlineItem[]
  /** Bumped when the caret should move into the title (EdgeNavigation, native Rename). */
  focusTitleRequest: number
  /** With the latest request: select the whole title (Rename) instead of a caret at its end. */
  selectTitle: boolean
  /**
   * A new, empty page puts the caret in its title when it loads. Off for the split pane's editor: its page loading
   * must not take the keyboard from the page being typed in beside it.
   */
  autoFocus: boolean
  /**
   * The stored content didn't fit the schema (corrupt, or written by a newer Hikki): the page is shown
   * as far as possible but never saved, so the original stays intact on disk.
   */
  readOnly: boolean
  /** Locked by the user (Page → Lock): read-only until unlocked, unlike `readOnly` it can be lifted live. */
  locked: boolean
  /** The native inspector shows the outline: the page's own hover rail steps aside. */
  railHidden: boolean
  /** The heading the reader is in (index into `headings`, -1 above the first): the rail and the inspector mark it. */
  activeHeading: number
}

type Options = {
  debounceMs: number
  /** Continuous typing still saves at least this often (the debounce alone would wait for a pause). */
  maxWaitMs?: number
}

/**
 * Edits the user made, as opposed to housekeeping the editor does by itself (UniqueID stamping block ids
 * on load, a remote reload) — those are marked not to enter the undo history and must not count as
 * editing the page. A change kept out of undo that is still the user's (a comment's mark, `SAVE_META`) counts.
 */
const isUserEdit = (transaction: Transaction) =>
  transaction.getMeta('addToHistory') !== false || transaction.getMeta(SAVE_META) === true

const MAX_TITLE_LENGTH = 500
/** Where a heading counts as reached: this far below the toolbar (the top of the reading area). */
const ACTIVE_LINE = 96

/**
 * Owns the live page: header state (title/icon/cover) and the Tiptap body editor, and talks to the
 * native shell. One editor instance per page: loadDocument() destroys and recreates it so undo
 * history never leaks between pages.
 */
/** Longest selected text sent to the native side (Ask AI's context). */
const SELECTION_LIMIT = 4000

export class EditorBridge {
  readonly page = new Store<PageState>({
    docId: null,
    title: '',
    icon: null,
    cover: null,
    headings: [],
    focusTitleRequest: 0,
    selectTitle: false,
    autoFocus: true,
    readOnly: false,
    locked: false,
    railHidden: false,
    activeHeading: -1
  })
  private editor: Editor | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  /** When the oldest unsaved edit was made (for maxWaitMs); null when nothing is pending. */
  private pendingSince: number | null = null
  /** True between a user edit and the snapshot that reports it. Viewing a page must never save it. */
  private dirty = false
  private lastActive = ''
  private pageInfoTimer: ReturnType<typeof setTimeout> | null = null
  private selectionTimer: ReturnType<typeof setTimeout> | null = null
  /** The last selected text sent (so a selection is reported once, and its clearing once). */
  private sentSelection = ''
  /** Settings → Editor → Check spelling; applied to every page's editor. */
  private spellcheck = true
  private aiReviewStyle: AIReviewStyle = 'inline'

  constructor(
    private readonly host: HTMLElement,
    private readonly transport: Transport,
    private readonly options: Options = { debounceMs: 400, maxWaitMs: 2000 }
  ) {
    // A bottom sheet open or not: the native bars beside the page step aside meanwhile.
    sheetPresence((open) => void this.send({ type: 'sheet', open }))
    // The heading the reader is in follows the scroll (once a frame at most).
    let queued = false
    window.addEventListener(
      'scroll',
      () => {
        if (queued) return
        queued = true
        requestAnimationFrame(() => {
          queued = false
          this.updateActiveHeading()
          this.reportScroll()
        })
      },
      { passive: true }
    )
    // The reader scrolls by themselves: the scroll-spy takes over from a jump.
    const release = () => {
      this.pinnedHeading = null
    }
    for (const type of ['wheel', 'touchmove', 'keydown'] as const) {
      window.addEventListener(type, release, { passive: true, capture: true })
    }
  }

  private scrollTimer: ReturnType<typeof setTimeout> | null = null

  /** Where the page is scrolled, at most every 250 ms (the last position always goes out). */
  private reportScroll(): void {
    if (this.scrollTimer) return
    this.scrollTimer = setTimeout(() => this.sendScroll(), 250)
  }

  /** Sends where the open page is scrolled now (also before another page replaces it: its last place counts). */
  private sendScroll(): void {
    if (this.scrollTimer) clearTimeout(this.scrollTimer)
    this.scrollTimer = null
    const { docId } = this.page.get()
    if (!docId) return
    const top = Math.round((document.scrollingElement ?? document.documentElement).scrollTop)
    void this.send({ type: 'scroll', docId, top })
  }

  /** A tab shown again: back to where it was (after the page has laid out). */
  restoreScroll(top: number): void {
    requestAnimationFrame(() =>
      requestAnimationFrame(() =>
        window.scrollTo({ top: Math.max(0, top), left: 0, behavior: 'instant' })
      )
    )
  }

  /** A heading jumped to from an outline: marked until the reader scrolls (wheel, touch, keys) by themselves. */
  private pinnedHeading: number | null = null

  /** The last id sent as `activeHeading` (the native inspector follows it). */
  private lastActiveHeading: string | null | undefined = undefined

  /**
   * Which heading the reader is in: the last one whose top has passed a line a little below the toolbar, or the last
   * once scrolled to the end. Kept in the page state (the rail) and sent to the native inspector when it changes.
   */
  private updateActiveHeading(): void {
    const editor = this.editor
    const { docId } = this.page.get()
    if (!editor || !docId) return
    const headings = collectHeadings(editor)
    const tops = headings.map((h) => {
      const dom = editor.view.nodeDOM(h.pos)
      return dom instanceof HTMLElement ? dom.getBoundingClientRect().top : Number.POSITIVE_INFINITY
    })
    const inset =
      Number.parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue('--hk-inset-top')
      ) || 0
    const scroller = document.scrollingElement ?? document.documentElement
    const atBottom =
      scroller.scrollTop > 0 && scroller.scrollTop + window.innerHeight >= scroller.scrollHeight - 2
    const index =
      this.pinnedHeading !== null && this.pinnedHeading < headings.length
        ? this.pinnedHeading
        : activeHeadingIndex(tops, inset + ACTIVE_LINE, atBottom)
    if (index !== this.page.get().activeHeading) this.page.set({ activeHeading: index })
    const id = index >= 0 ? (headings[index]?.id ?? null) : null
    if (id === this.lastActiveHeading) return
    this.lastActiveHeading = id
    void this.send({ type: 'activeHeading', docId, id })
  }

  loadDocument(payload: PagePayload): void {
    // Menus and panels belong to the page being replaced.
    dismissAllLayers()
    // Never drop a pending edit of the previous page, nor where it was last scrolled to.
    this.flushPending()
    if (this.scrollTimer) this.sendScroll()
    // Another page starts at its top (the web view's scroll would otherwise carry over from the last one).
    if (payload.id !== this.page.get().docId)
      window.scrollTo({ top: 0, left: 0, behavior: 'instant' })
    this.editor?.destroy()
    this.host.replaceChildren()
    this.lastActive = ''
    this.markSaved()
    const { body, title } = normalizeBody(payload.content, payload.title ?? '')
    let contentError: Error | null = null
    setBlockLinkBuilder((blockId) => {
      const { docId, title: pageTitle } = this.page.get()
      if (!docId) return null
      return {
        href: pageLinkHref(docId, blockId),
        pageLabel: pageTitle.trim() || t('page.untitled')
      }
    })
    const editor = createEditor(this.host, body, {
      spellcheck: this.spellcheck,
      media: this.media,
      pageLinks: this.pageLinks,
      splitDrop: this.splitDropHost,
      ai: this.aiHost,
      aiChanges: this.aiChangesHost,
      comments: this.commentsHost,
      ruby: this.ruby,
      linkPreview: async (url) =>
        linkCardFrom(await this.transport.post({ type: 'linkPreview', url })),
      onExitTop: () => this.requestTitleFocus(),
      onContentError: (error) => {
        contentError = error
      }
    })
    const locked = payload.locked === true
    if (contentError || locked) editor.setEditable(false)
    // IDs and the reason only — never page content.
    if (contentError)
      console.warn(`page opened read-only: content doesn't fit the schema (${payload.id})`)
    editor.on('update', ({ transaction }) => {
      this.refreshOutline(editor)
      this.reportPageInfo()
      // Measured once a frame, after the browser's own layout (not inside the keystroke's dispatch).
      this.scheduleActiveHeading()
      if (isUserEdit(transaction)) this.scheduleChanged()
    })
    editor.on('selectionUpdate', () => {
      this.reportActive()
      this.reportSelection()
    })
    editor.on('transaction', () => this.reportActive())
    this.editor = editor
    this.page.set({
      docId: payload.id,
      title,
      icon: payload.icon,
      cover: payload.cover,
      headings: outlineItems(editor),
      readOnly: contentError !== null,
      locked
    })
    this.reportPageInfo(true)
    this.lastActiveHeading = undefined
    this.pinnedHeading = null
    requestAnimationFrame(() => this.updateActiveHeading())
  }

  /** Page → Lock / Unlock while the page is open. */
  setLocked(locked: boolean): void {
    this.page.set({ locked })
    this.editor?.setEditable(!locked && !this.page.get().readOnly)
  }

  /** Nothing about the page may change: its content doesn't fit the schema, or the user locked it. */
  private get frozen(): boolean {
    const { readOnly, locked } = this.page.get()
    return readOnly || locked
  }

  /**
   * The open page changed on disk (another device, via the workspace folder). Applied in place —
   * caret and scroll kept — unless the user has unsaved edits, which win and will be saved over it.
   * Returns whether it was applied.
   */
  reload(payload: PagePayload): boolean {
    const editor = this.editor
    const { docId, readOnly } = this.page.get()
    if (!editor || payload.id !== docId || this.dirty || readOnly) return false
    // A file still uploading lands where its placeholder stands; replacing the document would misplace it.
    if (UploadsKey.getState(editor.state)?.pending.length) return false
    const { body, title } = normalizeBody(payload.content, payload.title ?? '')
    const { from, to } = editor.state.selection
    // Not an edit of this page: no undo step, no save. An invalid body leaves the page as it is.
    let applied = false
    try {
      applied = editor
        .chain()
        .setMeta('addToHistory', false)
        .setContent(body, { emitUpdate: true })
        .run()
    } catch {
      applied = false
    }
    if (!applied) {
      console.warn(`remote page change not applied: content doesn't fit the schema (${payload.id})`)
      return false
    }
    const end = editor.state.doc.content.size
    editor.commands.setTextSelection({ from: Math.min(from, end), to: Math.min(to, end) })
    this.page.set({
      title,
      icon: payload.icon,
      cover: payload.cover,
      headings: outlineItems(editor)
    })
    return true
  }

  // MARK: header

  setTitle(title: string): void {
    if (this.frozen) return
    const clean = title.replace(/[\r\n]+/g, ' ').slice(0, MAX_TITLE_LENGTH)
    if (clean === this.page.get().title) return
    this.page.set({ title: clean })
    this.scheduleChanged()
    this.reportPageInfo()
  }

  setIcon(icon: string | null): void {
    const { docId } = this.page.get()
    if (!docId || this.frozen) return
    this.page.set({ icon })
    void this.send({ type: 'setIcon', docId, icon })
  }

  setCover(cover: string | null): void {
    const { docId } = this.page.get()
    if (!docId || this.frozen) return
    this.page.set({ cover })
    void this.send({ type: 'setCover', docId, cover })
  }

  /** The sidebar's pages (`window.hikki.setPages`): how links to other pages get their titles. */
  private pageIndex: PageIndexEntry[] = []

  setPages(pages: PageIndexEntry[]): void {
    this.pageIndex = pages
    // "@" mention chips show the pages' current titles and icons.
    notifyPageIndexChanged()
  }

  /** What a page dropped on the right edge does (`window.hikki.setSplitDrop`): open beside, replace the right side, show here. */
  private splitDrop: SplitDropMode = 'off'

  setSplitDrop(mode: SplitDropMode): void {
    this.splitDrop = mode
  }

  readonly splitDropHost: SplitDropHost = {
    mode: () => this.splitDrop,
    open: (pageId) => void this.send({ type: 'openInSplit', id: pageId }),
    hover: (active) => void this.send({ type: 'splitDropHover', active })
  }

  /** AI on the selection: requests go to the native AI service; its answer comes back through `aiEvent`. */
  readonly aiHost: AIHost = {
    request: (message) => void this.send({ type: 'aiRequest', ...message }),
    cancel: (id) => void this.send({ type: 'aiCancel', id }),
    title: () => this.page.get().title,
    style: () => this.aiReviewStyle
  }

  /** Changes Ask AI proposed to the page: each verdict (and the change in view) goes to the chat's cards. */
  readonly aiChangesHost: AIChangesHost = {
    report: (id, status, before, after) => {
      const docId = this.page.get().docId
      if (docId)
        void this.send({
          type: 'aiChange',
          docId,
          id,
          status,
          ...(before === undefined ? {} : { before }),
          ...(after === undefined ? {} : { after })
        })
    },
    focused: (id) => {
      const docId = this.page.get().docId
      if (docId) void this.send({ type: 'aiChangeFocus', docId, ...(id ? { id } : {}) })
    }
  }

  /** `window.hikki.aiChanges`: the changes an Ask AI answer proposes to this page (ignored for another page). */
  aiChanges(docId: string, changes: AIChangeInput[]): boolean {
    const editor = this.editor
    if (!editor || docId !== this.page.get().docId) return false
    return editor.commands.aiSetChanges(changes)
  }

  /** `window.hikki.aiFocusChange`: a card picked in the chat — its change shown in the page. */
  aiFocusChange(id: string): boolean {
    return this.editor?.commands.aiFocusChange(id) ?? false
  }

  /** `window.hikki.aiResolveChange`: a card's own approve / skip. */
  aiResolveChange(id: string, verdict: 'approve' | 'skip'): boolean {
    if (this.frozen) return false
    return this.editor?.commands.aiResolveChange(id, verdict) ?? false
  }

  /** `window.hikki.aiApproveAll`: every pending change, one undo step. */
  aiApproveAll(): boolean {
    if (this.frozen) return false
    return this.editor?.commands.aiApproveAllChanges() ?? false
  }

  // MARK: the phone's keyboard bar (native `KeyboardToolbar`): its panels' contents and tools.

  /** `window.hikki.setKeyboardBar`: the native bar is up on this device — the selection's floating menu stays away. */
  setKeyboardBar(on: boolean): void {
    setKeyboardBar(on)
  }

  touchBlockMenu(): TouchBlockGroup[] {
    return touchBlockMenu()
  }

  touchTurnIntoMenu(): TouchBlock[] {
    return touchTurnIntoMenu()
  }

  touchState(): TouchState | null {
    return this.editor ? touchState(this.editor) : null
  }

  touchInsertBlock(id: string): boolean {
    return !this.frozen && !!this.editor && touchInsertBlock(this.editor, id)
  }

  touchTurnInto(id: string): boolean {
    return !this.frozen && !!this.editor && touchTurnInto(this.editor, id)
  }

  touchRun(tool: TouchTool): boolean {
    return !this.frozen && !!this.editor && touchRun(this.editor, tool)
  }

  touchSetColor(kind: 'text' | 'background', color: string | null): boolean {
    return !this.frozen && !!this.editor && touchSetColor(this.editor, kind, color)
  }

  private touchDock: FloatingLayer | null = null

  /** The bar's AI or link: a field docked above the keyboard, acting on the selection (or the word at the caret). */
  touchOpen(kind: 'ai' | 'link'): boolean {
    const editor = this.editor
    if (!editor || this.frozen || !selectAroundCaret(editor)) return false
    this.touchDock?.destroy()
    const close = () => {
      layer.destroy()
      if (this.touchDock === layer) this.touchDock = null
    }
    const layer = new FloatingLayer('hk-touch-dock', { onDismiss: close })
    this.touchDock = layer
    if (kind === 'ai') {
      renderTouchDock(layer, {
        kind,
        onClose: close,
        onRun: (action) => {
          close()
          editor.commands.aiRun(action)
        }
      })
    } else {
      renderTouchDock(layer, {
        kind,
        href: (editor.getAttributes('link').href as string | undefined) ?? null,
        onClose: close,
        onApply: (href) => {
          close()
          editor.chain().focus().extendMarkRange('link').setLink({ href }).run()
        },
        onRemove: () => {
          close()
          editor.chain().focus().extendMarkRange('link').unsetLink().run()
        }
      })
    }
    return true
  }

  /** `window.hikki.aiPageBlocks`: the open page's text blocks with their ids, for Ask AI to propose changes by. */
  aiPageBlocks(docId: string): AIPageBlock[] | null {
    const editor = this.editor
    if (!editor || docId !== this.page.get().docId) return null
    return pageBlocks(editor.state)
  }

  /** Comments on passages: written to the native store, which sends the page's threads back (`setComments`). */
  readonly commentsHost: CommentsHost = {
    create: (threadId, quote, body) =>
      this.sendComment({ type: 'commentCreate', threadId, quote, body }),
    reply: (threadId, body) => this.sendComment({ type: 'commentReply', threadId, body }),
    resolve: (threadId, resolved) =>
      this.sendComment({ type: 'commentResolve', threadId, resolved }),
    remove: (threadId, commentId) =>
      this.sendComment({ type: 'commentDelete', threadId, ...(commentId ? { commentId } : {}) }),
    edit: (threadId, commentId, body) =>
      this.sendComment({ type: 'commentEdit', threadId, commentId, body }),
    device: () => this.device,
    pages: () => this.pageLinks.pages(),
    openPage: (pageId) => this.pageLinks.open({ pageId, blockId: null }),
    link: (threadId) => {
      const docId = this.page.get().docId
      return docId ? pageLinkHref(docId, threadId) : null
    }
  }

  /** This device's name ("Mac", "iPhone"), from `setComments`. */
  private device: string | null = null

  private sendComment(
    message:
      | { type: 'commentCreate'; threadId: string; quote: string; body: string }
      | { type: 'commentReply'; threadId: string; body: string }
      | { type: 'commentResolve'; threadId: string; resolved: boolean }
      | { type: 'commentDelete'; threadId: string; commentId?: string }
      | { type: 'commentEdit'; threadId: string; commentId: string; body: string }
  ): void {
    const docId = this.page.get().docId
    if (docId) void this.send({ ...message, docId } as ToNativeMessage)
  }

  /** `window.hikki.setComments`: the page's threads from the native store (after loading it, and after each change). */
  setComments(docId: string, threads: ThreadItem[], device: string | null): void {
    this.device = device
    if (this.editor && docId === this.page.get().docId) setThreads(this.editor, threads)
  }

  /** `window.hikki.openComment`: a thread picked in the side panel — open, and its passage in view. */
  openComment(threadId: string): void {
    const editor = this.editor
    if (!editor) return
    const range = commentRanges(editor.state.doc).get(threadId)?.[0]
    editor.commands.commentOpen(threadId)
    if (range) {
      openTogglesAround(editor, range.from)
      const dom = editor.view.domAtPos(range.from).node
      ;(dom instanceof Element ? dom : dom.parentElement)?.scrollIntoView({ block: 'center' })
    }
  }

  /** Settings → AI → Review style: how the next edit is shown. */
  setAIReviewStyle(style: AIReviewStyle): void {
    if (style === 'inline' || style === 'diff' || style === 'bubble') this.aiReviewStyle = style
  }

  /** `window.hikki.aiEvent`: one event of an AI request's answer. */
  aiEvent(event: AIStreamEvent): void {
    if (this.editor) handleAIEvent(this.editor, this.aiHost, event)
  }

  /** Page links in the body: labels from the index, clicks routed to the native side. */
  readonly pageLinks: PageLinksHost = {
    pages: () => this.pageIndex,
    currentPageId: () => this.page.get().docId,
    untitled: () => t('page.untitled'),
    open: ({ pageId, blockId }) =>
      void this.send({ type: 'openPage', id: pageId, ...(blockId ? { block: blockId } : {}) }),
    openExternal: (url) => void this.send({ type: 'openLink', url })
  }

  /** Furigana suggestions from the native tokenizer (Settings has nothing to configure: it's offline). */
  readonly ruby: RubyHost = {
    suggestReading: async (text) =>
      rubySegmentsFrom(await this.transport.post({ type: 'suggestReading', text }))
  }

  /** Arrived by a link to a block: scroll there (false when the block isn't in this page). */
  scrollToBlock(blockId: string): boolean {
    const editor = this.editor
    if (!editor) return false
    if (editor.commands.scrollToBlock(blockId)) return true
    // A link to a discussion ("Copy link to discussion") names a thread: open it.
    if (!commentRanges(editor.state.doc).has(blockId)) return false
    this.openComment(blockId)
    return true
  }

  /** Arrived from a search result: its block, the words selected (false when neither is in this page). */
  revealText(terms: string[], blockId: string | null): boolean {
    const editor = this.editor
    if (!editor) return false
    return (
      editor.commands.revealText(terms, blockId) ||
      (!!blockId && editor.commands.scrollToBlock(blockId))
    )
  }

  /** Selects `terms` as a search result would and runs an AI action on them, as the selection menu does. */
  demoAI(terms: string[], action: string): boolean {
    const editor = this.editor
    if (!editor || this.frozen || !editor.commands.revealText(terms, null)) return false
    return editor.commands.aiRun({ id: action })
  }

  /** Uploads and attachments for the editor's media blocks. */
  readonly media: MediaHost = {
    upload: (file, onProgress) => this.uploadFile(file, onProgress),
    openAsset: (url, name) => void this.send({ type: 'openAsset', url, name: name ?? null })
  }

  /**
   * Sends a file to the native side in chunks (one base64 message per chunk instead of one huge one) and
   * resolves to its asset URL. A failure cancels the upload, so no partial file is kept.
   */
  async uploadFile(
    file: Blob & { name?: string },
    onProgress: (fraction: number) => void = () => {}
  ): Promise<string> {
    const fileExtension = extensionOf(file)
    const id = await this.transport.post({ type: 'beginUpload', fileExtension, size: file.size })
    if (typeof id !== 'string') throw new Error('beginUpload: native side returned no id')
    try {
      for (let offset = 0; offset < file.size; offset += UPLOAD_CHUNK) {
        const dataBase64 = await blobToBase64(file.slice(offset, offset + UPLOAD_CHUNK))
        await this.transport.post({ type: 'uploadChunk', id, dataBase64 })
        onProgress(Math.min(1, (offset + UPLOAD_CHUNK) / file.size))
      }
      const url = await this.transport.post({ type: 'finishUpload', id })
      if (typeof url !== 'string') throw new Error('finishUpload: native side returned no URL')
      return url
    } catch (error) {
      void this.send({ type: 'cancelUpload', id })
      throw error
    }
  }

  /** Hands an image to the native side for storage; resolves to the URL to reference it by. */
  async saveAsset(file: Blob, fileExtension: string): Promise<string> {
    const dataBase64 = await blobToBase64(file)
    const url = await this.transport.post({ type: 'saveAsset', fileExtension, dataBase64 })
    if (typeof url !== 'string') throw new Error('saveAsset: native side returned no URL')
    return url
  }

  // MARK: editor

  exec(command: string): boolean {
    // Commands run on a non-editable editor too, so a locked page refuses them here.
    if (!this.editor || this.frozen || !(COMMANDS as readonly string[]).includes(command))
      return false
    return runCommand(this.editor, command as Command)
  }

  /**
   * Returns the pending (unsaved) snapshot and cancels the debounce, or null when nothing changed —
   * the native side calls this on page switch / backgrounding and saves whatever it gets.
   */
  flush(): Snapshot | null {
    this.clearTimer()
    if (!this.dirty) return null
    this.markSaved()
    return this.snapshot()
  }

  snapshot(): Snapshot | null {
    const { docId, title } = this.page.get()
    if (!this.editor || !docId) return null
    const { content, text } = this.contentOf(this.editor)
    return { docId, title: title.trim(), content, text, wordCount: wordCount(`${title}\n${text}`) }
  }

  /** Documents are immutable: each one is turned into JSON and text once, shared by saves and the page info. */
  private readonly converted = new WeakMap<PMNode, { content: JSONContent; text: string }>()

  private contentOf(editor: Editor): { content: JSONContent; text: string } {
    const doc = editor.state.doc
    let known = this.converted.get(doc)
    if (!known) {
      const content = editor.getJSON()
      known = { content, text: plainText(content) }
      this.converted.set(doc, known)
    }
    return known
  }

  focus(): void {
    this.editor?.commands.focus()
  }

  /** Find in page (⌘F etc., or the native Edit menu). Returns whether there was an editor to search. */
  /** Listeners for `editCover` (the page header opens its cover sheet). */
  private readonly coverRequests = new Set<() => void>()

  onCoverRequest(listener: () => void): () => void {
    this.coverRequests.add(listener)
    return () => {
      this.coverRequests.delete(listener)
    }
  }

  /** `window.hikki.editCover`: the page ⋯ menu's Cover… — the cover's sheet opens (false on a locked page). */
  editCover(): boolean {
    if (!this.editor || this.frozen || this.page.get().readOnly) return false
    for (const listener of this.coverRequests) listener()
    return this.coverRequests.size > 0
  }

  find(mode: FindMode): boolean {
    if (!this.editor) return false
    runFind(this.editor, mode)
    return true
  }

  /** `window.hikki.setAutoFocus`: whether a loading empty page takes the caret (see `autoFocus`). */
  setAutoFocus(on: boolean): void {
    this.page.set({ autoFocus: on })
  }

  setSpellcheck(on: boolean): void {
    this.spellcheck = on
    this.editor?.view.dom.setAttribute('spellcheck', String(on))
  }

  /**
   * Caret to the start of the body (ArrowDown from the title). Focus is moved synchronously:
   * Tiptap's focus() waits a frame, and keystrokes typed in that gap would still land in the title.
   */
  /**
   * A press in the empty space below the last block (Notion's): the caret goes to an empty line at the end — the last
   * block when it already is an empty paragraph, otherwise a new one. False on a read-only or locked page.
   */
  focusEnd(): boolean {
    const editor = this.editor
    if (!editor || !editor.isEditable) return false
    const { doc } = editor.state
    const last = doc.lastChild
    if (last && last.type.name === 'paragraph' && last.content.size === 0) {
      editor
        .chain()
        .setTextSelection(doc.content.size - 1)
        .focus()
        .run()
    } else {
      editor
        .chain()
        .insertContentAt(doc.content.size, { type: 'paragraph' })
        .setTextSelection(editor.state.doc.content.size + 1)
        .focus()
        .run()
    }
    return true
  }

  focusBodyStart(): void {
    if (!this.editor) return
    this.editor.commands.setTextSelection(1)
    this.editor.view.focus()
  }

  /** Enter in the title: like Notion, start a fresh first line unless the body already begins with an empty one. */
  enterFromTitle(): void {
    if (!this.editor) return
    const first = this.editor.state.doc.firstChild
    if (!(first?.type.name === 'paragraph' && first.content.size === 0)) {
      this.editor.commands.insertContentAt(0, { type: 'paragraph' })
    }
    this.focusBodyStart()
  }

  /** Drops DOM focus so the software keyboard goes away (native "hide keyboard" button). */
  blur(): void {
    this.editor?.commands.blur()
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
  }

  /** The page's hover rail: to the heading at this place in the outline (where it is now, looked up again). */
  scrollToHeading(index: number): void {
    const editor = this.editor
    const heading = editor ? collectHeadings(editor)[index] : undefined
    if (!editor || !heading) return
    openTogglesAround(editor, heading.pos)
    const dom = editor.view.nodeDOM(heading.pos)
    if (dom instanceof HTMLElement) dom.scrollIntoView({ behavior: 'smooth', block: 'start' })
    editor.commands.setTextSelection(heading.pos + 1)
    // The heading jumped to is the one marked (a short page can't scroll it up to the line), until the reader scrolls.
    this.pinnedHeading = index
    this.updateActiveHeading()
  }

  /** The inspector's outline: to a heading by its block id, as the rail does (`scrollToHeading`). */
  jumpToHeading(id: string): boolean {
    if (!this.editor) return false
    const index = collectHeadings(this.editor).findIndex((h) => h.id === id)
    if (index < 0) return false
    this.scrollToHeading(index)
    return true
  }

  /** The outline goes to the page state only when it reads differently (its readers re-render on a change). */
  private refreshOutline(editor: Editor): void {
    const headings = outlineItems(editor)
    if (!sameOutline(headings, this.page.get().headings)) this.page.set({ headings })
  }

  private activeHeadingFrame = 0

  private scheduleActiveHeading(): void {
    if (this.activeHeadingFrame) return
    this.activeHeadingFrame = requestAnimationFrame(() => {
      this.activeHeadingFrame = 0
      this.updateActiveHeading()
    })
  }

  /** The native inspector shows the outline itself: the page's hover rail steps aside meanwhile. */
  setOutlineRail(visible: boolean): void {
    this.page.set({ railHidden: !visible })
  }

  /**
   * The outline and size of the open page for the native inspector: at once on load (`now`), otherwise at
   * most every 300 ms while it changes. Words count CJK characters one each (as the saved word count does);
   * characters come from Tiptap's CharacterCount, the title added.
   */
  private reportPageInfo(now = false): void {
    if (this.pageInfoTimer) {
      if (!now) return
      clearTimeout(this.pageInfoTimer)
      this.pageInfoTimer = null
    }
    const send = () => {
      this.pageInfoTimer = null
      const editor = this.editor
      const { docId, title, headings } = this.page.get()
      if (!editor || !docId) return
      const storage = editor.storage.characterCount as { characters: () => number }
      void this.send({
        type: 'pageInfo',
        docId,
        headings,
        words: wordCount(`${title}\n${this.contentOf(editor).text}`),
        characters: storage.characters() + title.length
      })
    }
    if (now) send()
    else this.pageInfoTimer = setTimeout(send, 300)
  }

  /** The selected text, for Ask AI's context — after the selection settles, only when it changed. */
  private reportSelection(): void {
    if (this.selectionTimer) clearTimeout(this.selectionTimer)
    this.selectionTimer = setTimeout(() => {
      const editor = this.editor
      if (!editor) return
      const { from, to, empty } = editor.state.selection
      const text = empty
        ? ''
        : editor.state.doc.textBetween(from, to, '\n', ' ').trim().slice(0, SELECTION_LIMIT)
      const docId = this.page.get().docId
      if (text === this.sentSelection || !docId) return
      this.sentSelection = text
      void this.send({ type: 'selection', docId, text })
    }, 200)
  }

  private requestTitleFocus(select = false): void {
    this.page.set({ focusTitleRequest: this.page.get().focusTitleRequest + 1, selectTitle: select })
  }

  /** Native "Rename": the title gets focus with its text selected, ready to be typed over. */
  focusTitle(): void {
    this.requestTitleFocus(true)
  }

  private scheduleChanged(): void {
    if (this.frozen) return
    this.dirty = true
    const now = Date.now()
    this.pendingSince ??= now
    this.clearTimer()
    const { debounceMs, maxWaitMs = Infinity } = this.options
    const wait = Math.max(0, Math.min(debounceMs, this.pendingSince + maxWaitMs - now))
    this.timer = setTimeout(() => this.flushPending(), wait)
  }

  private flushPending(): void {
    if (!this.timer) return
    this.clearTimer()
    this.markSaved()
    const snapshot = this.snapshot()
    if (snapshot) void this.send({ type: 'changed', snapshot })
  }

  private reportActive(): void {
    if (!this.editor) return
    const active = activeCommands(this.editor)
    const key = active.join(',')
    if (key === this.lastActive) return
    this.lastActive = key
    void this.send({ type: 'activeFormats', active })
  }

  private clearTimer(): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  /** Called whenever the pending edit is handed over (debounce fired, flush, page switch). */
  private markSaved(): void {
    this.dirty = false
    this.pendingSince = null
  }

  private async send(message: ToNativeMessage): Promise<void> {
    try {
      await this.transport.post(message)
    } catch (error) {
      // Can't route through the transport that just failed.
      console.error('[hikki] bridge post failed', message.type, error)
    }
  }
}

/** Raw bytes per upload message (base64 adds a third). */
const UPLOAD_CHUNK = 768 * 1024

const MIME_EXTENSIONS: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a'
}

/** The file's extension (from its name, else its type; "bin" when neither says). */
export function extensionOf(file: { name?: string; type: string }): string {
  const fromName = file.name?.includes('.') ? file.name.split('.').pop()?.toLowerCase() : undefined
  if (fromName && /^[a-z0-9]{1,10}$/u.test(fromName)) return fromName
  return MIME_EXTENSIONS[file.type] ?? 'bin'
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.addEventListener('load', () =>
      resolve(String(reader.result).replace(/^data:[^,]*,/u, ''))
    )
    reader.addEventListener('error', () => reject(reader.error))
    reader.readAsDataURL(blob)
  })
}
