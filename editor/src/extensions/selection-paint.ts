import { Extension } from '@tiptap/core'
import { AllSelection, Plugin, PluginKey, TextSelection } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

/** Plugin state: whether a mouse drag is selecting (the browser paints meanwhile). */
export const SelectionPaintKey = new PluginKey<{ dragging: boolean }>('selectionPaint')

/**
 * The page paints a text selection itself, on the text only (as the AI range is): the browser's own paint covers
 * whole line boxes across blocks — list numbers, the gaps between items — and looks broken there. Not while the
 * mouse is still dragging: re-drawing the text under the pointer would cut the browser's drag-selection short, so the
 * browser paints until the button is released. Fields inside the page keep the browser's selection; table cell
 * selections keep their own style.
 */
export const SelectionPaint = Extension.create({
  name: 'selectionPaint',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: SelectionPaintKey,
        state: {
          init: () => ({ dragging: false }),
          apply: (tr, value) => {
            const dragging = tr.getMeta(SelectionPaintKey) as boolean | undefined
            return dragging === undefined ? value : { dragging }
          }
        },
        view: (view) => {
          const release = () => {
            if (SelectionPaintKey.getState(view.state)?.dragging)
              view.dispatch(view.state.tr.setMeta(SelectionPaintKey, false))
          }
          window.addEventListener('mouseup', release, true)
          return { destroy: () => window.removeEventListener('mouseup', release, true) }
        },
        props: {
          handleDOMEvents: {
            mousedown: (view, event) => {
              if (event.button === 0) view.dispatch(view.state.tr.setMeta(SelectionPaintKey, true))
              return false
            }
          },
          attributes: (state): Record<string, string> =>
            SelectionPaintKey.getState(state)?.dragging ? {} : { class: 'hk-own-selection' },
          decorations: (state) => {
            const { selection } = state
            if (selection.empty || SelectionPaintKey.getState(state)?.dragging) return null
            if (!(selection instanceof TextSelection) && !(selection instanceof AllSelection))
              return null
            return DecorationSet.create(state.doc, [
              Decoration.inline(selection.from, selection.to, { class: 'hk-selection' })
            ])
          }
        }
      })
    ]
  }
})
