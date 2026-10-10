import type { Editor } from '@tiptap/core'
import { activeCommands, createEditor, runCommand } from './editor'
import { deriveTitle, plainText, wordCount } from './extract'
import { COMMANDS, type Command, type DocPayload, type Snapshot, type ToNativeMessage } from './protocol'

export interface Transport {
  post(message: ToNativeMessage): Promise<unknown>
}

type Options = { debounceMs: number }

/**
 * Owns the live Tiptap editor and talks to the native shell.
 * One editor instance per document: loadDocument() destroys and recreates it so
 * undo history never leaks between documents.
 */
export class EditorBridge {
  private editor: Editor | null = null
  private docId: string | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  private lastActive = ''

  constructor(
    private readonly host: HTMLElement,
    private readonly transport: Transport,
    private readonly options: Options = { debounceMs: 400 },
  ) {}

  loadDocument(doc: DocPayload): void {
    // Never drop a pending edit of the previous document.
    this.flushPending()
    this.editor?.destroy()
    this.host.replaceChildren()
    this.docId = doc.id
    this.lastActive = ''
    const editor = createEditor(this.host, doc.content)
    editor.on('update', () => this.scheduleChanged())
    editor.on('selectionUpdate', () => this.reportActive())
    editor.on('transaction', () => this.reportActive())
    this.editor = editor
  }

  exec(command: string): boolean {
    if (!this.editor || !(COMMANDS as readonly string[]).includes(command)) return false
    return runCommand(this.editor, command as Command)
  }

  /** Synchronously returns the current snapshot and cancels the pending debounce (native saves it). */
  flush(): Snapshot | null {
    this.clearTimer()
    return this.snapshot()
  }

  snapshot(): Snapshot | null {
    if (!this.editor || !this.docId) return null
    const content = this.editor.getJSON()
    const text = plainText(content)
    return { docId: this.docId, content, title: deriveTitle(content), text, wordCount: wordCount(text) }
  }

  focus(): void {
    this.editor?.commands.focus()
  }

  /** Drops DOM focus so the software keyboard goes away (native "hide keyboard" button). */
  blur(): void {
    this.editor?.commands.blur()
  }

  private scheduleChanged(): void {
    this.clearTimer()
    this.timer = setTimeout(() => this.flushPending(), this.options.debounceMs)
  }

  private flushPending(): void {
    if (!this.timer) return
    this.clearTimer()
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
