import type { Editor } from '@tiptap/core'

import { activeCommands, createEditor, runCommand } from './editor'
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
  /** Bumped when the caret should move into the title (EdgeNavigation). */
  focusTitleRequest: number
}

type Options = { debounceMs: number }

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
    focusTitleRequest: 0
  })
  private editor: Editor | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  /** True between a user edit and the snapshot that reports it. Viewing a page must never save it. */
  private dirty = false
  private lastActive = ''

  constructor(
    private readonly host: HTMLElement,
    private readonly transport: Transport,
    private readonly options: Options = { debounceMs: 400 }
  ) {}

  loadDocument(payload: PagePayload): void {
    // Never drop a pending edit of the previous page.
    this.flushPending()
    this.editor?.destroy()
    this.host.replaceChildren()
    this.lastActive = ''
    this.dirty = false
    const { body, title } = normalizeBody(payload.content, payload.title ?? '')
    const editor = createEditor(this.host, body, { onExitTop: () => this.requestTitleFocus() })
    editor.on('update', () => {
      this.page.set({ headings: collectHeadings(editor) })
      this.scheduleChanged()
    })
    editor.on('selectionUpdate', () => this.reportActive())
    editor.on('transaction', () => this.reportActive())
    this.editor = editor
    this.page.set({
      docId: payload.id,
      title,
      icon: payload.icon,
      cover: payload.cover,
      headings: collectHeadings(editor)
    })
  }

  // MARK: header

  setTitle(title: string): void {
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
    this.dirty = false
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

  private requestTitleFocus(): void {
    this.page.set({ focusTitleRequest: this.page.get().focusTitleRequest + 1 })
  }

  private scheduleChanged(): void {
    this.dirty = true
    this.clearTimer()
    this.timer = setTimeout(() => this.flushPending(), this.options.debounceMs)
  }

  private flushPending(): void {
    if (!this.timer) return
    this.clearTimer()
    this.dirty = false
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
