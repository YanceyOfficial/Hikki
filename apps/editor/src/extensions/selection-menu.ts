import { Extension, isTextSelection } from '@tiptap/core'
import { BubbleMenuPlugin } from '@tiptap/extension-bubble-menu'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { createRoot, type Root } from 'react-dom/client'

import { renderSelectionMenu } from '../components/selection-menu'
import { matches, TOUCH } from '../lib/device'
import { aiReviewOpen } from './ai-review'
import { commentsState } from './comments'
import { SlashCommandKey } from './slash-command'

export const SelectionMenuKey = new PluginKey('selectionMenu')

/**
 * A right-click selects the word under the pointer (WebKit) and opens the system's context menu; the formatting
 * menu must not come up over it (ISSUE-241). `suppressed` from the right-click until the next left press or key.
 */
export const SelectionMenuContextKey = new PluginKey<{ suppressed: boolean }>(
  'selectionMenuContext'
)

const coarsePointer = () => matches(TOUCH)

/** On a phone the native keyboard bar does this menu's job (`window.hikki.setKeyboardBar`); the menu stays away. */
let keyboardBar = false
export function setKeyboardBar(on: boolean): void {
  keyboardBar = on
}

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
    element.style.setProperty('--hk-pop-dy', below ? '-4px' : '4px')
    return [
      new Plugin<{ suppressed: boolean }>({
        key: SelectionMenuContextKey,
        state: {
          init: () => ({ suppressed: false }),
          apply: (tr, value) => {
            const suppressed = tr.getMeta(SelectionMenuContextKey) as boolean | undefined
            return suppressed === undefined ? value : { suppressed }
          }
        },
        props: {
          handleDOMEvents: {
            contextmenu: (view) => {
              // The word the right-click selects arrives as a later selection change; a menu already up goes now.
              view.dispatch(
                view.state.tr
                  .setMeta(SelectionMenuContextKey, true)
                  .setMeta(SelectionMenuKey, 'hide')
              )
              return false
            },
            mousedown: (view, event) => {
              if (event.button === 0 && SelectionMenuContextKey.getState(view.state)?.suppressed)
                view.dispatch(view.state.tr.setMeta(SelectionMenuContextKey, false))
              return false
            },
            keydown: (view) => {
              if (SelectionMenuContextKey.getState(view.state)?.suppressed)
                view.dispatch(view.state.tr.setMeta(SelectionMenuContextKey, false))
              return false
            }
          }
        }
      }),
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
          // Tiptap's destroy() leaves the debounced update's timer running.
          if (editor.isDestroyed) return false
          if (keyboardBar) return false
          if (!editor.isEditable || from === to || !isTextSelection(state.selection)) return false
          // Not over the system's context menu (a right-click's word selection).
          if (SelectionMenuContextKey.getState(state)?.suppressed) return false
          // Keep showing while the menu itself has focus (link input).
          if (!view.hasFocus() && !element.contains(document.activeElement)) return false
          if (state.doc.textBetween(from, to, ' ').trim() === '') return false
          if (editor.isActive('codeBlock')) return false
          // Not while the "/" menu is open.
          if (SlashCommandKey.getState(state)?.active) return false
          // Not while AI works on the selection or shows its review.
          if (aiReviewOpen(editor)) return false
          // Nor while a comment on the selection is being written.
          if (commentsState(state)?.draft) return false
          return true
        }
      })
    ]
  },

  onCreate() {
    const element = this.storage.element
    if (!element) return
    const root = createRoot(element)
    renderSelectionMenu(root, this.editor)
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
