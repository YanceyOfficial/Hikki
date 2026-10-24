import type { AIAction } from '../extensions/ai-review'
import { unitAtPos } from '../extensions/block-units'
import { blockLabel, pageLinkHref } from '../extensions/page-links'
import { setKeyboardBar } from '../extensions/selection-menu'
import { AI_GROUPS } from './ai-actions'
import type { BridgeContext } from './bridge-types'
import {
  selectAroundCaret,
  selectBlockAtCaret,
  touchBlockAction,
  touchBlockColor,
  touchBlockInfo,
  touchBlockMenu,
  touchComment,
  touchCommentQuote,
  touchInsertBlock,
  touchInsertMedia,
  touchMoveBlock,
  touchRun,
  touchSetColor,
  touchState,
  touchTurnInto,
  touchTurnIntoMenu,
  type TouchBlock,
  type TouchBlockAction,
  type TouchBlockGroup,
  type TouchBlockInfo,
  type TouchCommentScope,
  type TouchMedia,
  type TouchState,
  type TouchTool
} from './touch-tools'

/** What the phone's native AI / link field acts on (`touchPrepare`). */
export type TouchTarget = {
  quote: string
  href: string | null
  presets: { id: string; label: string }[]
}

/**
 * The phone's keyboard bar (native `KeyboardToolbar`): its panels' contents and tools, run on the open page
 * (`touch-tools.ts` does the work; this checks there is a page and that it may change).
 */
export class TouchBridge {
  constructor(private readonly context: BridgeContext) {}

  /** May the page change (an editor, not locked or read-only)? Its editor when so. */
  private writable() {
    const editor = this.context.editor()
    return editor && !this.context.frozen() ? editor : null
  }

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
    const editor = this.context.editor()
    return editor ? touchState(editor) : null
  }

  touchInsertBlock(id: string): boolean {
    const editor = this.writable()
    return !!editor && touchInsertBlock(editor, id)
  }

  touchTurnInto(id: string): boolean {
    const editor = this.writable()
    return !!editor && touchTurnInto(editor, id)
  }

  touchRun(tool: TouchTool): boolean {
    const editor = this.writable()
    return !!editor && touchRun(editor, tool)
  }

  touchSetColor(kind: 'text' | 'background', color: string | null): boolean {
    const editor = this.writable()
    return !!editor && touchSetColor(editor, kind, color)
  }

  /**
   * The bar's AI or link (a native field over the keyboard): the selection — or, with none, what the page selects
   * now: the caret's whole block (`block`, AI's) or the word at the caret (`word`, a link's) — it will act on, the
   * link there, and AI's presets as the selection menu offers them. Null: nothing to act on.
   */
  touchPrepare(scope: 'word' | 'block' = 'word'): TouchTarget | null {
    const editor = this.writable()
    if (!editor) return null
    if (!(scope === 'block' ? selectBlockAtCaret(editor) : selectAroundCaret(editor))) return null
    const { from, to } = editor.state.selection
    return {
      quote: editor.state.doc.textBetween(from, to, ' ').trim().slice(0, 200),
      href: (editor.getAttributes('link').href as string | undefined) ?? null,
      presets: AI_GROUPS.flatMap((group) =>
        group.actions.map((action) => ({ id: action.id, label: action.label() }))
      )
    }
  }

  /** The native AI field's request: a preset, or the user's words, on the selection `touchPrepare` made. */
  touchAI(action: AIAction): boolean {
    const editor = this.writable()
    if (!editor || editor.state.selection.empty) return false
    return editor.commands.aiRun(action)
  }

  /** The native link field: a link on the selection (null removes the one there). */
  touchLink(href: string | null): boolean {
    const editor = this.writable()
    if (!editor) return false
    const chain = editor.chain().focus().extendMarkRange('link')
    return (href ? chain.setLink({ href }) : chain.unsetLink()).run()
  }

  /** Files the phone's photo / file sheet stored, as blocks at the caret. */
  touchInsertMedia(items: TouchMedia[]): boolean {
    const editor = this.writable()
    return !!editor && touchInsertMedia(editor, items)
  }

  /** The native comment field: what it quotes, then its Send (`touch-tools.ts`). */
  touchCommentQuote(scope: TouchCommentScope): string | null {
    const editor = this.context.editor()
    return editor ? touchCommentQuote(editor, scope) : null
  }

  touchComment(scope: TouchCommentScope, body: string): boolean {
    const editor = this.context.editor()
    return !!editor && touchComment(editor, scope, body)
  }

  touchBlockInfo(): TouchBlockInfo | null {
    const editor = this.context.editor()
    return editor ? touchBlockInfo(editor) : null
  }

  touchBlockAction(action: TouchBlockAction): boolean {
    const editor = this.context.editor()
    return (
      !!editor &&
      (action === 'comment' || !this.context.frozen()) &&
      touchBlockAction(editor, action)
    )
  }

  touchMoveBlock(target: string): Promise<boolean> {
    const editor = this.writable()
    return editor ? touchMoveBlock(editor, target) : Promise.resolve(false)
  }

  touchBlockColor(kind: 'text' | 'background', color: string | null): boolean {
    const editor = this.writable()
    return !!editor && touchBlockColor(editor, kind, color)
  }

  /** The ⋯ sheet's Copy link: the block's link and its text (the native side puts both on the clipboard). */
  touchBlockLink(): { href: string; label: string } | null {
    const editor = this.context.editor()
    const { docId, title } = this.context.page.get()
    const unit = editor ? unitAtPos(editor.state, editor.state.selection.from) : null
    const blockId = unit?.node.attrs.id as string | null | undefined
    if (!unit || !docId || !blockId) return null
    return {
      href: pageLinkHref(docId, blockId),
      label: blockLabel(unit.node) ?? title
    }
  }
}
