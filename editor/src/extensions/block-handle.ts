import type { Node as PMNode } from '@tiptap/pm/model'
import DragHandle from '@tiptap/extension-drag-handle'

/** Every body block is draggable (the page title lives outside the editor). */
export function isDraggableBlock(node: PMNode | null): boolean {
  return node !== null
}

/**
 * Notion-style ⋮⋮ grip beside the hovered block for drag-to-reorder.
 * Only for fine pointers (mouse/trackpad, incl. iPad with a trackpad): on touch the grip would fight the
 * system text-selection handles, so touch reordering needs its own design later.
 */
export function blockHandleExtensions(finePointer: boolean = matchMedia?.('(pointer: fine)').matches ?? false) {
  if (!finePointer) return []
  let grip: HTMLElement | null = null
  return [
    DragHandle.configure({
      render: () => {
        grip = document.createElement('div')
        grip.className = 'hk-drag-handle'
        grip.setAttribute('aria-label', 'Drag to move block')
        grip.innerHTML =
          '<svg viewBox="0 0 10 16" width="10" height="16" aria-hidden="true"><g fill="currentColor">' +
          '<circle cx="2" cy="2" r="1.5"/><circle cx="8" cy="2" r="1.5"/><circle cx="2" cy="8" r="1.5"/>' +
          '<circle cx="8" cy="8" r="1.5"/><circle cx="2" cy="14" r="1.5"/><circle cx="8" cy="14" r="1.5"/></g></svg>'
        return grip
      },
      onNodeChange: ({ node }) => {
        grip?.classList.toggle('hk-hidden', !isDraggableBlock(node))
      },
    }),
  ]
}
