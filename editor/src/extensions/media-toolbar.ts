import { Extension } from '@tiptap/core'
import { BubbleMenuPlugin } from '@tiptap/extension-bubble-menu'
import { NodeSelection, PluginKey } from '@tiptap/pm/state'
import { createRoot, type Root } from 'react-dom/client'

import { renderMediaToolbar } from '../components/media-toolbar'
import type { MediaHost } from './media'

export const MediaToolbarKey = new PluginKey('mediaToolbar')

/** Tiptap's BubbleMenu over a selected image; the toolbar it shows is components/media-toolbar.tsx. */
export function mediaToolbarExtension(host: MediaHost | null) {
  return Extension.create<
    Record<string, never>,
    { element: HTMLDivElement | null; root: Root | null }
  >({
    name: 'mediaToolbar',
    addStorage: () => ({ element: null, root: null }),
    addProseMirrorPlugins() {
      const element = document.createElement('div')
      element.className = 'hk-media-toolbar fixed top-0 left-0 z-40 w-max'
      this.storage.element = element
      return [
        BubbleMenuPlugin({
          pluginKey: MediaToolbarKey,
          editor: this.editor,
          element,
          appendTo: () => document.body,
          options: {
            strategy: 'fixed',
            placement: 'top',
            offset: 8,
            flip: { padding: 8 },
            shift: { padding: 8 }
          },
          shouldShow: ({ editor, state }) =>
            editor.isEditable &&
            state.selection instanceof NodeSelection &&
            state.selection.node.type.name === 'image'
        })
      ]
    },
    onCreate() {
      const element = this.storage.element
      if (!element) return
      const root = createRoot(element)
      renderMediaToolbar(root, { editor: this.editor, host })
      this.storage.root = root
    },
    onDestroy() {
      const { root, element } = this.storage
      queueMicrotask(() => root?.unmount())
      element?.remove()
    }
  })
}
