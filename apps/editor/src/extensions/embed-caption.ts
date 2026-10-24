import type { Editor } from '@tiptap/core'

import { renderCaptionPanel } from '../components/caption-panel'
import { FloatingLayer } from '../components/floating'
import { t } from '../core/i18n'
import { followNode } from './block-units'

/** Longest caption kept (characters). */
export const MAX_CAPTION = 500

/**
 * The caption line under an embed (or a link card): shown when the block has one, gone when it has none. A press on
 * it opens the caption panel (`onEdit`) — and nothing else (a link card would otherwise open its page).
 */
export function syncCaption(dom: HTMLElement, caption: string | null, onEdit: () => void): void {
  let line = dom.querySelector<HTMLElement>(':scope > .hk-embed-caption')
  const text = caption?.trim() ?? ''
  if (!text) {
    line?.remove()
    return
  }
  if (!line) {
    line = document.createElement('div')
    line.className = 'hk-embed-caption'
    line.setAttribute('role', 'button')
    line.tabIndex = 0
    line.setAttribute('aria-label', t('blockMenu.caption'))
    line.addEventListener('click', (event) => {
      event.stopPropagation()
      onEdit()
    })
    line.addEventListener('keydown', (event) => {
      event.stopPropagation()
      if (event.key === 'Enter') onEdit()
    })
  }
  dom.append(line)
  line.textContent = text
}

let open: { layer: FloatingLayer; stop: () => void } | null = null

function close() {
  open?.stop()
  open?.layer.destroy()
  open = null
}

/**
 * The panel that writes an embed's caption (the block menu's Caption, or a press on the caption), under the block:
 * Return saves (an empty one removes it), Escape or a press outside cancels.
 */
export function openCaptionPanel(editor: Editor, pos: number | undefined): void {
  close()
  if (pos === undefined || !editor.isEditable) return
  const node = editor.state.doc.nodeAt(pos)
  if (!node || !('caption' in node.attrs)) return
  const at = followNode(editor, pos, () => close())
  const cancel = () => {
    close()
    if (!editor.isDestroyed) editor.commands.focus()
  }
  const layer = new FloatingLayer('w-(--layout-panel-caption) max-w-(--layout-viewport-max) p-2', {
    onDismiss: cancel
  })
  open = { layer, stop: () => at.stop() }
  renderCaptionPanel(
    layer,
    {
      initial: (node.attrs.caption as string | null) ?? '',
      onSave: (value) => {
        const now = at.current
        close()
        if (!now || editor.isDestroyed) return
        const caption = value.trim().slice(0, MAX_CAPTION) || null
        if (caption !== (now.node.attrs.caption ?? null))
          editor.view.dispatch(
            editor.state.tr.setNodeMarkup(now.pos, undefined, { ...now.node.attrs, caption })
          )
        editor.commands.focus()
      }
    },
    () => {
      const dom = at.current ? editor.view.nodeDOM(at.current.pos) : null
      if (!(dom instanceof HTMLElement)) return null
      const box = dom.getBoundingClientRect()
      return new DOMRect(box.left, box.top, box.width, box.height)
    }
  )
}
