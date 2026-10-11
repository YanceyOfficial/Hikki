import type { Editor } from '@tiptap/core'
import type { Transaction } from '@tiptap/pm/state'

import { activeCommands, createEditor, runCommand } from './editor'
import { runFind, type FindMode } from './extensions/find'
import { plainText, wordCount } from './extract'
import { normalizeBody } from './normalize'
import { collectHeadings, type HeadingItem } from './page/headings'
import { Store } from './page/store'
import {
  COMMANDS,
  type Command,
  type PagePayload,
  type Snapshot,
  type ToNativeMessage
} from './protocol'

export interface Transport {
  post(message: ToNativeMessage): Promise<unknown>
}

export type PageState = {
  docId: string | null
  title: string
  icon: string | null
  cover: string | null
  headings: HeadingItem[]
  /** Bumped when the caret should move into the title (EdgeNavigation, native Rename). */
  focusTitleRequest: number
  /** With the latest request: select the whole title (Rename) instead of a caret at its end. */
  selectTitle: boolean
  /**
   * The stored content didn't fit the schema (corrupt, or written by a newer Hikki): the page is shown
   * as far as possible but never saved, so the original stays intact on disk.
   */
  readOnly: boolean
}

type Options = {
  debounceMs: number
  /** Continuous typing still saves at least this often (the debounce alone would wait for a pause). */
  maxWaitMs?: number
}

/**
 * Edits the user made, as opposed to housekeeping the editor does by itself (UniqueID stamping block ids
 * on load, a remote reload) — those are marked not to enter the undo history and must not count as
 * editing the page.
 */
const isUserEdit = (transaction: Transaction) => transaction.getMeta('addToHistory') !== false

const MAX_TITLE_LENGTH = 500

/**
 * Owns the live page: header state (title/icon/cover) and the Tiptap body editor, and talks to the
 * native shell. One editor instance per page: loadDocument() destroys and recreates it so undo
 * history never leaks between pages.
 */
export class EditorBridge {
  readonly page = new Store<PageState>({
    docId: null,
    title: '',
    icon: null,
    cover: null,
    headings: [],
    focusTitleRequest: 0,
    selectTitle: false,
    readOnly: false
  })
  private editor: Editor | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  /** When the oldest unsaved edit was made (for maxWaitMs); null when nothing is pending. */
  private pendingSince: number | null = null
  /** True between a user edit and the snapshot that reports it. Viewing a page must never save it. */
  private dirty = false
  private lastActive = ''
  /** Settings → Editor → Check spelling; applied to every page's editor. */
  private spellcheck = true

  constructor(
    private readonly host: HTMLElement,
    private readonly transport: Transport,
    private readonly options: Options = { debounceMs: 400, maxWaitMs: 2000 }
  ) {}

  loadDocument(payload: PagePayload): void {
    // Never drop a pending edit of the previous page.
    this.flushPending()
    this.editor?.destroy()
    this.host.replaceChildren()
    this.lastActive = ''
    this.markSaved()
    const { body, title } = normalizeBody(payload.content, payload.title ?? '')
    let contentError: Error | null = null
    const editor = createEditor(this.host, body, {
      spellcheck: this.spellcheck,
      onExitTop: () => this.requestTitleFocus(),
      onContentError: (error) => {
        contentError = error
      }
    })
    if (contentError) {
      editor.setEditable(false)
      // IDs and the reason only — never page content.
      console.warn(`page opened read-only: content doesn't fit the schema (${payload.id})`)
    }
    editor.on('update', ({ transaction }) => {
      this.page.set({ headings: collectHeadings(editor) })
      if (isUserEdit(transaction)) this.scheduleChanged()
    })
    editor.on('selectionUpdate', () => this.reportActive())
    editor.on('transaction', () => this.reportActive())
    this.editor = editor
    this.page.set({
      docId: payload.id,
      title,
      icon: payload.icon,
      cover: payload.cover,
      headings: collectHeadings(editor),
      readOnly: contentError !== null
    })
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
      headings: collectHeadings(editor)
    })
    return true
  }

  // MARK: header

  setTitle(title: string): void {
    if (this.page.get().readOnly) return
    const clean = title.replace(/[\r\n]+/g, ' ').slice(0, MAX_TITLE_LENGTH)
    if (clean === this.page.get().title) return
    this.page.set({ title: clean })
    this.scheduleChanged()
  }

  setIcon(icon: string | null): void {
    const { docId } = this.page.get()
    if (!docId) return
    this.page.set({ icon })
    void this.send({ type: 'setIcon', docId, icon })
  }

  setCover(cover: string | null): void {
    const { docId } = this.page.get()
    if (!docId) return
    this.page.set({ cover })
    void this.send({ type: 'setCover', docId, cover })
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
    if (!this.editor || !(COMMANDS as readonly string[]).includes(command)) return false
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
    const content = this.editor.getJSON()
    const text = plainText(content)
    return { docId, title: title.trim(), content, text, wordCount: wordCount(`${title}\n${text}`) }
  }

  focus(): void {
    this.editor?.commands.focus()
  }

  /** Find in page (⌘F etc., or the native Edit menu). Returns whether there was an editor to search. */
  find(mode: FindMode): boolean {
    if (!this.editor) return false
    runFind(this.editor, mode)
    return true
  }

  setSpellcheck(on: boolean): void {
    this.spellcheck = on
    this.editor?.view.dom.setAttribute('spellcheck', String(on))
  }

  /**
   * Caret to the start of the body (ArrowDown from the title). Focus is moved synchronously:
   * Tiptap's focus() waits a frame, and keystrokes typed in that gap would still land in the title.
   */
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

  scrollToHeading(pos: number): void {
    if (!this.editor) return
    const dom = this.editor.view.nodeDOM(pos)
    if (dom instanceof HTMLElement) dom.scrollIntoView({ behavior: 'smooth', block: 'start' })
    this.editor.commands.setTextSelection(pos + 1)
  }

  private requestTitleFocus(select = false): void {
    this.page.set({ focusTitleRequest: this.page.get().focusTitleRequest + 1, selectTitle: select })
  }

  /** Native "Rename": the title gets focus with its text selected, ready to be typed over. */
  focusTitle(): void {
    this.requestTitleFocus(true)
  }

  private scheduleChanged(): void {
    if (this.page.get().readOnly) return
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
