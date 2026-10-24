import type { Editor } from '@tiptap/core'
import Mathematics, { BlockMath, InlineMath } from '@tiptap/extension-mathematics'

import 'katex/dist/katex.min.css'

import { FloatingLayer } from '../components/floating'
import { renderMathEditor } from '../components/math-editor'
import { followNode, type BlockUnit, type Followed } from './block-units'

export type MathKind = 'inline' | 'block'

let open: { layer: FloatingLayer; formula: Followed<BlockUnit> } | null = null

function close(editor?: Editor) {
  open?.formula.stop()
  open?.layer.destroy()
  open = null
  if (editor && !editor.isDestroyed) editor.commands.focus()
}

/**
 * Edits the formula at `pos` in a panel under it (source beside a live KaTeX preview). Replaces Tiptap's default
 * `prompt()`, which would block the web view. An emptied formula is removed.
 */
export function openMathEditor(editor: Editor, pos: number, kind: MathKind): void {
  close()
  const node = editor.state.doc.nodeAt(pos)
  const dom = editor.view.nodeDOM(pos)
  if (!node || !(dom instanceof HTMLElement)) return
  // The formula where it is now: an edit meanwhile (a remote reload) may have moved it; gone, the panel goes.
  const formula = followNode(editor, pos, () => close())
  const at = () => formula.current?.pos ?? null
  const cancel = () => {
    // A formula that was never written (just inserted) goes away again.
    const now = at()
    if (now !== null && !(node.attrs.latex as string).trim())
      editor.chain().setNodeSelection(now).deleteSelection().run()
    close(editor)
  }
  // Escape or a press outside cancels (the layers' bus).
  const layer = new FloatingLayer('hk-math-editor w-[640px] max-w-[calc(100vw-16px)] p-2', {
    onDismiss: cancel
  })
  open = { layer, formula }
  const commit = (latex: string) => {
    const now = at()
    // The update commands read `pos`, not the chain's selection.
    if (now === null) return close(editor)
    formula.stop()
    if (!latex.trim()) editor.chain().setNodeSelection(now).deleteSelection().run()
    else if (kind === 'inline') editor.commands.updateInlineMath({ latex, pos: now })
    else editor.commands.updateBlockMath({ latex, pos: now })
    close(editor)
  }
  renderMathEditor(
    layer,
    {
      initial: node.attrs.latex as string,
      multiline: kind === 'block',
      onDone: commit
    },
    () => {
      const now = at()
      const el = now === null ? null : editor.view.nodeDOM(now)
      return el instanceof HTMLElement ? el.getBoundingClientRect() : dom.getBoundingClientRect()
    }
  )
}

/** Inline (`$$x$$`) and block (`$$$x$$$`) formulas, rendered by KaTeX; click one to edit it. */
export function mathExtension() {
  const katexOptions = { throwOnError: false, strict: 'ignore' as const }
  // The editor isn't known yet while extensions are resolved; the click handlers look it up later.
  const holder: { editor: Editor | null } = { editor: null }
  const edit = (pos: number, kind: MathKind) => {
    const { editor } = holder
    if (editor?.isEditable) openMathEditor(editor, pos, kind)
  }
  return Mathematics.extend({
    addExtensions() {
      return [
        BlockMath.configure({
          katexOptions: { ...katexOptions, displayMode: true },
          onClick: (_node, pos) => edit(pos, 'block')
        }),
        InlineMath.configure({ katexOptions, onClick: (_node, pos) => edit(pos, 'inline') })
      ]
    },
    onBeforeCreate() {
      holder.editor = this.editor
    },
    onDestroy() {
      holder.editor = null
      close()
    }
  })
}
