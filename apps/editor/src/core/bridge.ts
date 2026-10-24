import type { Editor, JSONContent } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { Transaction } from '@tiptap/pm/state'

import { threadRange, type ThreadItem } from '../extensions/comments'
import { closeDrawing, finishDrawing, type DrawingEditorHost } from '../extensions/drawing'
import { runFind, type FindMode } from '../extensions/find'
import { localAssetSrc, UploadsKey, type MediaHost } from '../extensions/media'
import { setMoveBlockHost } from '../extensions/move-block'
import { pageLinkHref, type PageIndexEntry, type PageLinksHost } from '../extensions/page-links'
import { notifyPageIndexChanged } from '../extensions/page-mention'
import { rubySegmentsFrom, type RubyHost } from '../extensions/ruby'
import type { SplitDropHost, SplitDropMode } from '../extensions/split-drop'
import type { DateSheetChange } from '../lib/date-sheet'
import { dismissAllLayers } from '../lib/dismiss-bus'
import { setDrawingsReadOnly } from '../lib/drawing-mode'
import { linkCardFrom } from '../lib/embeds'
import { sheetPresence } from '../lib/sheet-presence'
import { withBlockIds } from './block-ids'
import { setBlockLinkBuilder } from './block-link'
import { AIBridge } from './bridge-ai'
import { CommentsBridge, type CommentAction } from './bridge-comments'
import { SheetsBridge } from './bridge-sheets'
import { TouchBridge } from './bridge-touch'
import type { BridgeContext, PageState, Transport } from './bridge-types'
import { activeCommands, createEditor, runCommand } from './editor'
import { plainText, wordCount } from './extract'
import { outlineItems } from './headings'
import { t } from './i18n'
import { SAVE_META } from './meta'
import { normalizeBody } from './normalize'
import { OutlineSpy } from './outline-spy'
import { PageSaver, type SaverOptions } from './page-saver'
import {
  COMMANDS,
  type Command,
  type PagePayload,
  type Snapshot,
  type ToNativeMessage
} from './protocol'
import { readableContent } from './readable'
import { Store } from './store'
import { saveAsset, uploadFile } from './uploads'

export type { CommentAction } from './bridge-comments'
export type { TouchTarget } from './bridge-touch'
export type { PageState, Transport } from './bridge-types'
export { extensionOf } from './uploads'

/**
 * Edits the user made, as opposed to housekeeping the editor does by itself (UniqueID stamping block ids
 * on load, a remote reload) — those are marked not to enter the undo history and must not count as
 * editing the page. A change kept out of undo that is still the user's (a comment's mark, `SAVE_META`) counts.
 */
const isUserEdit = (transaction: Transaction) =>
  transaction.getMeta('addToHistory') !== false || transaction.getMeta(SAVE_META) === true

const MAX_TITLE_LENGTH = 500

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
  private lastActive = ''
  private pageInfoTimer: ReturnType<typeof setTimeout> | null = null
  private selectionTimer: ReturnType<typeof setTimeout> | null = null
  /** The last selected text sent (so a selection is reported once, and its clearing once). */
  private sentSelection = ''
  private sentCaret: number | null = null
  /** Settings → Editor → Check spelling; applied to every page's editor. */
  private spellcheck = true

  /** What the bridge's parts share of it (bridge-types.ts). */
  private readonly context: BridgeContext
  private readonly saver: PageSaver
  private readonly outline: OutlineSpy
  private readonly comments: CommentsBridge
  private readonly sheets: SheetsBridge
  /** The phone's keyboard bar (`window.hikki.touch*`, bridge-touch.ts). */
  readonly touch: TouchBridge
  /** AI on the selection, Ask AI's changes, the chat's pictures (`window.hikki.ai*`, bridge-ai.ts). */
  readonly ai: AIBridge

  constructor(
    private readonly host: HTMLElement,
    private readonly transport: Transport,
    options: SaverOptions = { debounceMs: 400, maxWaitMs: 2000 }
  ) {
    this.context = {
      page: this.page,
      editor: () => this.editor,
      frozen: () => this.frozen,
      send: (message) => this.send(message),
      transport
    }
    this.saver = new PageSaver(this.context, options, () => this.snapshot())
    this.outline = new OutlineSpy(this.context)
    this.comments = new CommentsBridge(this.context, this.pageLinks)
    this.sheets = new SheetsBridge(this.context)
    this.touch = new TouchBridge(this.context)
    this.ai = new AIBridge(this.context)
    // A bottom sheet open or not: the native bars beside the page step aside meanwhile.
    sheetPresence((open) => void this.send({ type: 'sheet', open }))
  }

  /** `window.hikki.restoreScroll`: a tab shown again, back to where it was (`OutlineSpy.restoreScroll`). */
  restoreScroll(top: number): void {
    this.outline.restoreScroll(top)
  }

  loadDocument(loaded: PagePayload): void {
    // Menus and panels belong to the page being replaced.
    dismissAllLayers()
    // A drawing open over the page puts its last strokes into it first.
    closeDrawing()
    // Never drop a pending edit of the previous page (one whose save failed included), nor where it was last scrolled to.
    this.saver.flushPending(true)
    // Words of this page that never reached the app are newer than what it sent: shown, and saved as an edit.
    const undelivered = this.saver.takeUndelivered(loaded.id)
    const payload = undelivered
      ? { ...loaded, title: undelivered.title, content: undelivered.content }
      : loaded
    this.outline.flushScroll()
    // Another page starts at its top (the web view's scroll would otherwise carry over from the last one).
    if (payload.id !== this.page.get().docId)
      window.scrollTo({ top: 0, left: 0, behavior: 'instant' })
    this.editor?.destroy()
    this.host.replaceChildren()
    this.lastActive = ''
    this.saver.startSession()
    const { body: stored, title } = normalizeBody(payload.content, payload.title ?? '')
    // Pages from before block ids get theirs in one walk (the editor's own stamping of a big page is quadratic).
    const body = withBlockIds(stored)
    let contentError: Error | null = null
    setBlockLinkBuilder((blockId) => {
      const { docId, title: pageTitle } = this.page.get()
      if (!docId) return null
      return {
        href: pageLinkHref(docId, blockId),
        pageLabel: pageTitle.trim() || t('page.untitled')
      }
    })
    setMoveBlockHost({
      pages: () => this.pageIndex,
      currentPageId: () => this.page.get().docId,
      move: async (target, blocks, text, words) => {
        const { docId } = this.page.get()
        if (!docId || this.frozen) return false
        const reply = await this.transport.post({
          type: 'moveBlocks',
          docId,
          target,
          blocks,
          text,
          words
        })
        // WebKit hands a Swift Bool back as a number.
        return reply === true || reply === 1
      }
    })
    const editor = createEditor(this.host, body, {
      spellcheck: this.spellcheck,
      media: this.media,
      pageLinks: this.pageLinks,
      splitDrop: this.splitDropHost,
      ai: this.ai.host,
      aiChanges: this.ai.changesHost,
      comments: this.comments.host,
      drawing: this.drawingHost,
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
    if (contentError) {
      // Tiptap's fallback is an empty page: show what fits instead — unknown blocks as their text. Display only:
      // the page is read-only and never saved, so the stored content stays as it is.
      editor.commands.setContent(readableContent(body, editor.schema), { emitUpdate: false })
      // IDs and the reason only — never page content.
      console.warn(`page opened read-only: content doesn't fit the schema (${payload.id})`)
    }
    editor.on('update', ({ transaction }) => {
      this.outline.refreshOutline(editor)
      this.reportPageInfo()
      // Measured once a frame, after the browser's own layout (not inside the keystroke's dispatch).
      this.outline.scheduleActiveHeading()
      if (isUserEdit(transaction)) this.saver.scheduleChanged()
    })
    editor.on('selectionUpdate', () => {
      this.reportActive()
      this.reportSelection()
    })
    editor.on('transaction', () => {
      this.reportActive()
      this.comments.reportThread()
    })
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
    this.outline.pageLoaded()
    if (undelivered && !contentError && !locked) this.saver.scheduleChanged()
  }

  /** Page → Lock / Unlock while the page is open. */
  setLocked(locked: boolean): void {
    // Words typed before the lock are saved now, as they stand — not by a debounce that would land after it.
    if (locked) this.saver.flushPending(true)
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
    if (!editor || payload.id !== docId || this.saver.dirty || readOnly) return false
    // A file still uploading lands where its placeholder stands; replacing the document would misplace it.
    if (UploadsKey.getState(editor.state)?.pending.length) return false
    const { body: stored, title } = normalizeBody(payload.content, payload.title ?? '')
    // Pages from before block ids get theirs in one walk (the editor's own stamping of a big page is quadratic).
    const body = withBlockIds(stored)
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
    this.saver.scheduleChanged()
    this.reportPageInfo()
  }

  setIcon(icon: string | null): void {
    const { docId, icon: previous } = this.page.get()
    if (!docId || this.frozen) return
    this.page.set({ icon })
    // The native side says why in a toast; the page only puts the old one back (while it still shows the page).
    void this.send({ type: 'setIcon', docId, icon }).then((stored) => {
      if (!stored && this.page.get().docId === docId && this.page.get().icon === icon)
        this.page.set({ icon: previous })
    })
  }

  setCover(cover: string | null): void {
    const { docId, cover: previous } = this.page.get()
    if (!docId || this.frozen) return
    this.page.set({ cover })
    void this.send({ type: 'setCover', docId, cover }).then((stored) => {
      if (!stored && this.page.get().docId === docId && this.page.get().cover === cover)
        this.page.set({ cover: previous })
    })
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

  // MARK: comments (bridge-comments.ts)

  /** `window.hikki.setNativeComments`: the native side shows open threads in its own sheet. */
  setNativeComments(on: boolean): void {
    this.comments.setNativeComments(on)
  }

  /** `window.hikki.commentAction`: the native thread sheet's actions, run as the page's own. */
  commentAction(action: CommentAction): boolean {
    return this.comments.commentAction(action)
  }

  /** `window.hikki.setComments`: the page's threads from the native store. */
  setComments(docId: string, threads: ThreadItem[], device: string | null): void {
    this.comments.setComments(docId, threads, device)
  }

  /** `window.hikki.openComment`: a thread picked in the side panel — open, and its passage in view. */
  openComment(threadId: string | null): void {
    this.comments.openComment(threadId)
  }

  /** Drawings: their pictures and previews are stored like any upload; Text to diagram asks the native AI. */
  readonly drawingHost: DrawingEditorHost = {
    upload: (blob, extension) =>
      this.uploadFile(new File([blob], `drawing.${extension}`, { type: blob.type })),
    read: async (src) => {
      // Only this workspace's files: a drawing's stored references never send a request anywhere else.
      const local = localAssetSrc(src)
      if (!local) throw new Error('not a workspace file')
      const response = await fetch(local)
      if (!response.ok) throw new Error(`read ${response.status}`)
      return response.blob()
    },
    diagram: (prompt) => this.ai.diagram(prompt),
    openLink: (url) => void this.send({ type: 'openLink', url }),
    fullScreen: (open) => void this.send({ type: 'fullScreen', open }),
    library: () =>
      this.drawingLibrary
        ? {
            load: async () => {
              const reply = await this.transport.post({ type: 'drawingLibrary' })
              if (reply === null || typeof reply !== 'object' || !('items' in reply))
                throw new Error('library unreadable')
              return reply.items
            },
            save: (items) => void this.send({ type: 'saveDrawingLibrary', items })
          }
        : null
  }

  /** Whether the app keeps Excalidraw's Library (the Mac). */
  private drawingLibrary = false

  /** `window.hikki.setDrawings`: a Library where the app keeps one, read-only on a phone-sized screen. */
  setDrawings({ library, readOnly }: { library: boolean; readOnly: boolean }): void {
    this.drawingLibrary = library
    setDrawingsReadOnly(readOnly)
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
    if (!threadRange(editor.state, blockId)) return false
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

  /** Uploads and attachments for the editor's media blocks. */
  readonly media: MediaHost = {
    upload: (file, onProgress) => this.uploadFile(file, onProgress),
    openAsset: (url, name) => void this.send({ type: 'openAsset', url, name: name ?? null })
  }

  /**
   * Sends a file to the native side in chunks (one base64 message per chunk instead of one huge one) and
   * resolves to its asset URL. A failure cancels the upload, so no partial file is kept.
   */
  uploadFile(
    file: Blob & { name?: string },
    onProgress: (fraction: number) => void = () => {}
  ): Promise<string> {
    return uploadFile(this.transport, file, onProgress)
  }
  /** Hands an image to the native side for storage; resolves to the URL to reference it by. */
  saveAsset(file: Blob, fileExtension: string): Promise<string> {
    return saveAsset(this.transport, file, fileExtension)
  }

  // MARK: editor

  exec(command: string): boolean {
    // Commands run on a non-editable editor too, so a locked page refuses them here.
    if (!this.editor || this.frozen || !(COMMANDS as readonly string[]).includes(command))
      return false
    return runCommand(this.editor, command as Command)
  }

  /** Closes an open drawing as its Done does (preview included), ahead of a page switch's flush. */
  finishDrawing(): Promise<void> {
    return finishDrawing()
  }

  /** `window.hikki.flush`: the pending edit for the app to save, or null when the page wasn't edited (PageSaver). */
  flush(): Snapshot | null {
    return this.saver.flush()
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

  // MARK: sheets (bridge-sheets.ts)

  onCoverRequest(listener: () => void): () => void {
    return this.sheets.onCoverRequest(listener)
  }

  /** `window.hikki.editCover`: the page ⋯ menu's Cover… — the cover's sheet opens (false on a locked page). */
  editCover(): boolean {
    return this.sheets.editCover()
  }

  setNativeCover(on: boolean): void {
    this.sheets.setNativeCover(on)
  }

  /** The cover's sheet where the native side draws it (true), or false: the page header opens its own. */
  requestCoverSheet(mode: 'actions' | 'picker'): boolean {
    return this.sheets.requestCoverSheet(mode)
  }

  setNativeIcons(on: boolean): void {
    this.sheets.setNativeIcons(on)
  }

  applyIcon(id: string, icon: string | null): boolean {
    return this.sheets.applyIcon(id, icon)
  }

  applyIconColor(id: string, color: string | null): boolean {
    return this.sheets.applyIconColor(id, color)
  }

  setNativeDates(on: boolean): void {
    this.sheets.setNativeDates(on)
  }

  applyDate(id: string, change: DateSheetChange): boolean {
    return this.sheets.applyDate(id, change)
  }

  /** `window.hikki.applyCover`: the native sheet's pick (null: Remove), on the page it was opened for — as the page
   * header's own pick. Returns whether it was taken (not another page now, not locked). */
  applyCover(docId: string, cover: string | null): boolean {
    if (this.page.get().docId !== docId || this.frozen) return false
    this.setCover(cover)
    return true
  }

  /** Find in page (⌘F etc., or the native Edit menu). Returns whether there was an editor to search. */
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
    const editor = this.editor
    // A selection left behind stays painted with no keyboard to act on it, iOS's edit menu still over it: it
    // collapses to its end (Notion's).
    if (editor && !editor.state.selection.empty)
      editor.commands.setTextSelection(editor.state.selection.to)
    editor?.commands.blur()
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    window.getSelection()?.removeAllRanges()
  }

  /**
   * iOS's text size (Settings → Display → Text Size, Dynamic Type) as a factor on the page's words — the title and
   * the body, not the UI around them (`--hk-text-scale`). Clamped: the accessibility sizes go past what a column of
   * text can take.
   */
  setTextScale(scale: number): void {
    const clamped = Number.isFinite(scale) ? Math.min(2, Math.max(0.85, scale)) : 1
    document.documentElement.style.setProperty('--hk-text-scale', String(clamped))
  }

  // MARK: the outline (outline-spy.ts)

  /** The page's hover rail: to the heading at this place in the outline. */
  scrollToHeading(index: number): void {
    this.outline.scrollToHeading(index)
  }

  /** The inspector's outline: to a heading by its block id. */
  jumpToHeading(id: string): boolean {
    return this.outline.jumpToHeading(id)
  }

  /** The native inspector shows the outline itself: the page's hover rail steps aside meanwhile. */
  setOutlineRail(visible: boolean): void {
    this.outline.setOutlineRail(visible)
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
      const caret = empty ? from : null
      const docId = this.page.get().docId
      if ((text === this.sentSelection && caret === this.sentCaret) || !docId) return
      this.sentSelection = text
      this.sentCaret = caret
      void this.send({ type: 'selection', docId, text, caret })
    }, 200)
  }

  private requestTitleFocus(select = false): void {
    this.page.set({ focusTitleRequest: this.page.get().focusTitleRequest + 1, selectTitle: select })
  }

  /** Native "Rename": the title gets focus with its text selected, ready to be typed over. */
  focusTitle(): void {
    this.requestTitleFocus(true)
  }

  private reportActive(): void {
    if (!this.editor) return
    const active = activeCommands(this.editor)
    const key = active.join(',')
    if (key === this.lastActive) return
    this.lastActive = key
    void this.send({ type: 'activeFormats', active })
  }

  /** Posts a message; false when the native side refused it (logged here: nothing can be routed through the
   * transport that just failed). */
  private async send(message: ToNativeMessage): Promise<boolean> {
    try {
      await this.transport.post(message)
      return true
    } catch (error) {
      console.error('[hikki] bridge post failed', message.type, error)
      return false
    }
  }
}
