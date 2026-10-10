import gripSvg from '@phosphor-icons/core/assets/bold/dots-six-vertical-bold.svg?raw'
import DragHandle from '@tiptap/extension-drag-handle'
import type { Node as PMNode } from '@tiptap/pm/model'

import { t } from '../i18n'

/** Every body block is draggable (the page title lives outside the editor). */
export function isDraggableBlock(node: PMNode | null): boolean {
  return node !== null
}

/**
 * Notion-style ⋮⋮ grip beside the hovered block for drag-to-reorder.
 * Only for fine pointers (mouse/trackpad, incl. iPad with a trackpad): on touch the grip would fight the
 * system text-selection handles, so touch reordering needs its own design later.
 */
export function blockHandleExtensions(
  finePointer: boolean = matchMedia?.('(pointer: fine)').matches ?? false
) {
  if (!finePointer) return []
  let grip: HTMLElement | null = null
  return [
    DragHandle.configure({
      render: () => {
        grip = document.createElement('div')
        // Hidden until the pointer is over a block — otherwise it sits at the editor's top-left on load.
        grip.className = 'hk-drag-handle hk-hidden'
        grip.setAttribute('aria-label', t('editor.dragBlock'))
        // Phosphor's dots-six-vertical (same icon set as the native app), sized to the row.
        grip.innerHTML = gripSvg.replace('<svg ', '<svg width="16" height="16" aria-hidden="true" ')
        return grip
      },
      onNodeChange: ({ node }) => {
        grip?.classList.toggle('hk-hidden', !isDraggableBlock(node))
      }
    })
  ]
}
