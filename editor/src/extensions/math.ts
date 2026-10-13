import type { Editor } from '@tiptap/core'
import Mathematics, { BlockMath, InlineMath } from '@tiptap/extension-mathematics'

import 'katex/dist/katex.min.css'

import { FloatingLayer } from '../components/floating'
import { renderMathEditor } from '../components/math-editor'

export type MathKind = 'inline' | 'block'

let open: FloatingLayer | null = null

function close(editor?: Editor) {
  open?.destroy()
  open = null
  editor?.commands.focus()
}

/**
 * Edits the formula at `pos` in a small panel under it (live KaTeX preview). Replaces Tiptap's default
 * `prompt()`, which would block the web view. An emptied formula is removed.
 */
export function openMathEditor(editor: Editor, pos: number, kind: MathKind): void {
  close()
  const node = editor.state.doc.nodeAt(pos)
  const dom = editor.view.nodeDOM(pos)
  if (!node || !(dom instanceof HTMLElement)) return
  const layer = new FloatingLayer('hk-math-editor w-[360px] max-w-[calc(100vw-16px)] p-2')
  open = layer
  const commit = (latex: string) => {
    // The update commands read `pos`, not the chain's selection.
    if (!latex.trim()) editor.chain().setNodeSelection(pos).deleteSelection().run()
    else if (kind === 'inline') editor.commands.updateInlineMath({ latex, pos })
    else editor.commands.updateBlockMath({ latex, pos })
    close(editor)
  }
  renderMathEditor(
    layer,
    {
      initial: node.attrs.latex as string,
      multiline: kind === 'block',
      onDone: commit,
      onCancel: () => {
        // A formula that was never written (just inserted) goes away again.
        if (!(node.attrs.latex as string).trim())
          editor.chain().setNodeSelection(pos).deleteSelection().run()
        close(editor)
      }
    },
    () => dom.getBoundingClientRect()
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
