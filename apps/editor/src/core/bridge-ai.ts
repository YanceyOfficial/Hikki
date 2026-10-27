import type { AIChangesHost } from '../extensions/ai-changes'
import { handleAIEvent, type AIHost, type AIReviewStyle } from '../extensions/ai-review'
import { pageBlocks, type AIPageBlock } from '../lib/ai-content'
import type { BridgeContext } from './bridge-types'
import { DiagramRequests } from './diagram'
import { insertPictures, type PictureItem, type PicturePlace } from './pictures'
import type { AIChangeInput, AIStreamEvent } from './protocol'

/**
 * AI between the page and the native AI service: Ask AI on the selection (`aiRequest` out, `aiEvent` back), the
 * changes an Ask AI answer proposes to the page (the chat's cards), pictures the chat made, and a drawing's Text to
 * diagram.
 */
export class AIBridge {
  private reviewStyle: AIReviewStyle = 'inline'
  /** Text to diagram requests in flight (a drawing's AI), apart from the page's own AI review. */
  private readonly diagrams = new DiagramRequests((message) => void this.context.send(message))

  constructor(private readonly context: BridgeContext) {}

  /** AI on the selection: requests go to the native AI service; its answer comes back through `aiEvent`. */
  readonly host: AIHost = {
    request: (message) => void this.context.send({ type: 'aiRequest', ...message }),
    cancel: (id) => void this.context.send({ type: 'aiCancel', id }),
    title: () => this.context.page.get().title,
    style: () => this.reviewStyle,
    handoff: ({ instruction, selection }) => {
      const { docId } = this.context.page.get()
      if (docId) void this.context.send({ type: 'aiHandoff', docId, instruction, selection })
    }
  }

  /** Changes Ask AI proposed to the page: each verdict (and the change in view) goes to the chat's cards. */
  readonly changesHost: AIChangesHost = {
    report: (id, status, before, after) => {
      const docId = this.context.page.get().docId
      if (docId)
        void this.context.send({
          type: 'aiChange',
          docId,
          id,
          status,
          ...(before === undefined ? {} : { before }),
          ...(after === undefined ? {} : { after })
        })
    },
    focused: (id) => {
      const docId = this.context.page.get().docId
      if (docId) void this.context.send({ type: 'aiChangeFocus', docId, ...(id ? { id } : {}) })
    }
  }

  /** A drawing's Text to diagram: Mermaid for `prompt`, from the native AI. */
  diagram(prompt: string): Promise<string> {
    return this.diagrams.request(prompt, this.context.page.get().title)
  }

  /** `window.hikki.aiChanges`: the changes an Ask AI answer proposes to this page (ignored for another page);
   * `focusFirst` once the answer has ended, so the first pending change comes into view. */
  aiChanges(docId: string, changes: AIChangeInput[], focusFirst = false): boolean {
    const editor = this.context.editor()
    if (!editor || docId !== this.context.page.get().docId) return false
    return editor.commands.aiSetChanges(changes, { focusFirst })
  }

  /** `window.hikki.aiFocusChange`: a card picked in the chat — its change shown in the page. */
  aiFocusChange(id: string): boolean {
    return this.context.editor()?.commands.aiFocusChange(id) ?? false
  }

  /** `window.hikki.aiResolveChange`: a card's own approve / skip. */
  aiResolveChange(id: string, verdict: 'approve' | 'skip'): boolean {
    if (this.context.frozen()) return false
    return this.context.editor()?.commands.aiResolveChange(id, verdict) ?? false
  }

  /** `window.hikki.aiApproveAll`: every pending change, one undo step. */
  aiApproveAll(): boolean {
    if (this.context.frozen()) return false
    return this.context.editor()?.commands.aiApproveAllChanges() ?? false
  }

  /** `window.hikki.aiPageBlocks`: the open page's text blocks with their ids, for Ask AI to propose changes by. */
  aiPageBlocks(docId: string): AIPageBlock[] | null {
    const editor = this.context.editor()
    if (!editor || docId !== this.context.page.get().docId) return null
    return pageBlocks(editor.state)
  }

  /** `window.hikki.insertPictures`: pictures the chat made, on the page they were asked for (`insertPictures`). */
  insertPictures(docId: string, items: PictureItem[], place: PicturePlace): boolean {
    const editor = this.context.editor()
    if (this.context.page.get().docId !== docId || this.context.frozen() || !editor) return false
    return insertPictures(editor, items, place)
  }

  /** Settings → AI → Review style: how the next edit is shown. Anything but `diff` — the retired `bubble` card among
   * them — reviews in the page. */
  setAIReviewStyle(style: string): void {
    this.reviewStyle = style === 'diff' ? 'diff' : 'inline'
  }

  /** `window.hikki.aiEvent`: one event of an AI request's answer. */
  aiEvent(event: AIStreamEvent): void {
    if (this.diagrams.handle(event)) return
    const editor = this.context.editor()
    if (editor) handleAIEvent(editor, this.host, event)
  }

  /** Selects `terms` as a search result would and runs an AI action on them, as the selection menu does. */
  demoAI(terms: string[], action: string): boolean {
    const editor = this.context.editor()
    if (!editor || this.context.frozen() || !editor.commands.revealText(terms, null)) return false
    return editor.commands.aiRun({ id: action })
  }
}
