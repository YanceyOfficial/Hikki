import type { Editor } from '@tiptap/core'
import Mathematics, { BlockMath, InlineMath } from '@tiptap/extension-mathematics'

import 'katex/dist/katex.min.css'

import { FloatingLayer } from '../components/floating'
import { renderMathEditor } from '../components/math-editor'
import { openNativeMathSheet } from '../lib/math-sheet'
import { followNode, type BlockUnit, type Followed } from './block-units'

export type MathKind = 'inline' | 'block'

/** The formula being edited: in the page's panel (`layer`), or in the native sheet (none). */
let open: { layer: FloatingLayer | null; formula: Followed<BlockUnit> } | null = null

function close(editor?: Editor) {
  open?.formula.stop()
  open?.layer?.destroy()
  open = null
  if (editor && !editor.isDestroyed) editor.commands.focus()
}

/**
 * Edits the formula at `pos` in a panel under it (source beside a live KaTeX preview). Replaces Tiptap's default
 * `prompt()`, which would block the web view. An emptied formula is removed. Where the native side draws the sheet
 * (a phone, `setNativeMath`), the page shows the formula as typed there — a preview outside the undo history — and
 * takes Done as the edit; Cancel puts the formula back as it was.
 */
export function openMathEditor(editor: Editor, pos: number, kind: MathKind): void {
  close()
  const node = editor.state.doc.nodeAt(pos)
  const dom = editor.view.nodeDOM(pos)
  if (!node || !(dom instanceof HTMLElement)) return
  const original = node.attrs.latex as string
  // The formula where it is now: an edit meanwhile (a remote reload) may have moved it; gone, the panel goes.
  const formula = followNode(editor, pos, () => close())
  const at = () => formula.current?.pos ?? null
  /** The formula as typed so far, shown in the page without an undo step (the edit is Done's). */
  const preview = (latex: string) => {
    const now = at()
    const current = now === null || editor.isDestroyed ? null : editor.state.doc.nodeAt(now)
    if (now === null || !current || current.attrs.latex === latex) return
    const tr = editor.state.tr.setNodeMarkup(now, undefined, { ...current.attrs, latex })
    tr.setMeta('addToHistory', false)
    editor.view.dispatch(tr)
  }
  const cancel = () => {
    // A formula that was never written (just inserted) goes away again; one previewed goes back as it was.
    const now = at()
    if (now === null || editor.isDestroyed) return close()
    if (original.trim()) preview(original)
    else editor.chain().setNodeSelection(now).deleteSelection().run()
    close(editor)
  }
  const commit = (latex: string) => {
    const now = at()
    // The update commands read `pos`, not the chain's selection.
    if (now === null || editor.isDestroyed) return close()
    formula.stop()
    // A preview may already show the text: the formula goes back as it was first (outside undo, as the preview
    // went in), so the edit below is a real change — one that is saved and undone. Without this, Done on the
    // previewed text changed nothing, and the page file kept the formula as it was.
    preview(original)
    if (!latex.trim()) editor.chain().setNodeSelection(now).deleteSelection().run()
    else if (kind === 'inline') editor.commands.updateInlineMath({ latex, pos: now })
    else editor.commands.updateBlockMath({ latex, pos: now })
    close(editor)
  }
  if (
    openNativeMathSheet(
      { latex: original, kind },
      { onPreview: preview, onDone: commit, onCancel: cancel }
    )
  ) {
    open = { layer: null, formula }
    // The formula stays unselected under the card: the system's selection handles sat over its preview.
    editor.commands.setTextSelection(pos + node.nodeSize)
    keepAboveComposer(dom.closest('[data-id]') ?? dom)
    return
  }
  // Escape or a press outside cancels (the layers' bus).
  const layer = new FloatingLayer(
    'hk-math-editor w-(--layout-panel-math) max-w-(--layout-viewport-max) p-2',
    {
      onDismiss: cancel
    }
  )
  open = { layer, formula }
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

/** How far under the toolbar a formula lands when scrolled up for the native composer (CSS px). */
const COMPOSER_MARGIN = 24
/** The part of the window the composer and the keyboard leave free above them, roughly. */
const COMPOSER_FREE = 0.4

/**
 * The native composer and the keyboard cover the page's lower half: a formula's block lower than that, or under the
 * toolbar, is scrolled to just under the toolbar — where the preview of its typing stays in view (`scrollIntoView`
 * at `start` put it under the toolbar's glass).
 */
function keepAboveComposer(block: Element): void {
  if (typeof window.scrollBy !== 'function') return
  const inset =
    Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue('--hk-inset-top')
    ) || 0
  const { top } = block.getBoundingClientRect()
  const lowest = window.innerHeight * COMPOSER_FREE
  if (top >= inset + COMPOSER_MARGIN && top <= lowest) return
  window.scrollBy({ top: top - inset - COMPOSER_MARGIN, behavior: 'smooth' })
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
