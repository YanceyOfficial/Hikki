import { Extension, isTextSelection } from '@tiptap/core'
import { BubbleMenuPlugin } from '@tiptap/extension-bubble-menu'
import { PluginKey } from '@tiptap/pm/state'
import { createRoot, type Root } from 'react-dom/client'

import { TooltipProvider } from '@/components/ui/tooltip'

import { IconProvider } from '../ui/icons'
import { SelectionMenu } from '../ui/selection-menu'
import { SlashCommandKey } from './slash-command'

export const SelectionMenuKey = new PluginKey('selectionMenu')

const coarsePointer = () => window.matchMedia?.('(pointer: coarse)').matches ?? false

/**
 * Formatting menu over a non-empty text selection (Tiptap's BubbleMenu positions it; React draws it).
 * Above the selection with a mouse; below it on touch, where the system's edit menu takes the top.
 */
export const SelectionMenuExtension = Extension.create<
  Record<string, never>,
  { element: HTMLDivElement | null; root: Root | null }
>({
  name: 'selectionMenu',

  addStorage() {
    return { element: null, root: null }
  },

  addProseMirrorPlugins() {
    const element = document.createElement('div')
    // Sized to its content before the first measurement (a full-width block would be shifted to the edge).
    element.className = 'hk-selection-menu fixed top-0 left-0 z-40 w-max'
    this.storage.element = element
    const below = coarsePointer()
    // The menu (hk-pop, inside) pops from the selection's side.
    element.style.setProperty('--hk-pop-origin', below ? 'top left' : 'bottom left')
    element.style.setProperty('--hk-pop-dy', below ? '-2px' : '2px')
    return [
      BubbleMenuPlugin({
        pluginKey: SelectionMenuKey,
        editor: this.editor,
        element,
        updateDelay: 120,
        appendTo: () => document.body,
        options: {
          strategy: 'fixed',
          placement: below ? 'bottom-start' : 'top-start',
          offset: 8,
          flip: { padding: 8 },
          shift: { padding: 8 }
        },
        shouldShow: ({ editor, view, state, from, to }) => {
          if (!editor.isEditable || from === to || !isTextSelection(state.selection)) return false
          // Keep showing while the menu itself has focus (link input).
          if (!view.hasFocus() && !element.contains(document.activeElement)) return false
          if (state.doc.textBetween(from, to, ' ').trim() === '') return false
          if (editor.isActive('codeBlock')) return false
          // Not while the "/" menu is open.
          if (SlashCommandKey.getState(state)?.active) return false
          return true
        }
      })
    ]
  },

  onCreate() {
    const element = this.storage.element
    if (!element) return
    const root = createRoot(element)
    root.render(
      <IconProvider>
        <TooltipProvider delay={500}>
          <SelectionMenu editor={this.editor} />
        </TooltipProvider>
      </IconProvider>
    )
    this.storage.root = root
  },

  onDestroy() {
    const { root, element } = this.storage
    // Unmount after the current render pass (destroy can run inside one).
    queueMicrotask(() => root?.unmount())
    element?.remove()
    this.storage.root = null
    this.storage.element = null
  }
})
