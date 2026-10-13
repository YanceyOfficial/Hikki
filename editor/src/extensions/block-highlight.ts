import { Plugin, PluginKey, type EditorState, type Transaction } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

export type BlockRange = { from: number; to: number }
type Highlights = { source: BlockRange | null; menu: BlockRange | null }
type Meta = Partial<Highlights>

export const BlockHighlightKey = new PluginKey<Highlights>('blockHighlight')

/**
 * Block-level highlights drawn as node decorations — a class set on the node's DOM would be dropped on the
 * next redraw (it flashed) and ProseMirror redraws some blocks more often than others. `source`: the block
 * being dragged (dimmed); `menu`: the block whose menu is open (tinted). Every block type gets the same look.
 */
export const BlockHighlight = new Plugin<Highlights>({
  key: BlockHighlightKey,
  state: {
    init: () => ({ source: null, menu: null }),
    apply(tr, value) {
      const meta = tr.getMeta(BlockHighlightKey) as Meta | undefined
      const mapped = tr.docChanged
        ? { source: mapRange(tr, value.source), menu: mapRange(tr, value.menu) }
        : value
      return meta ? { ...mapped, ...meta } : mapped
    }
  },
  props: {
    decorations(state) {
      const { source, menu } = BlockHighlightKey.getState(state) ?? { source: null, menu: null }
      const decorations = [
        ...nodeDecoration(state, source, 'hk-dragging-source'),
        ...nodeDecoration(state, menu, 'hk-block-selected')
      ]
      return decorations.length ? DecorationSet.create(state.doc, decorations) : null
    }
  }
})

/**
 * Follows the block through an edit. Plain mapping, not `mapResult().deleted`: a step that reopens the
 * block's end (text inserted at a table's edge) marks the boundary deleted although the block is intact;
 * `nodeDecoration` checks coverage anyway, and a block that is gone maps to an empty range.
 */
function mapRange(tr: Transaction, range: BlockRange | null): BlockRange | null {
  if (!range) return null
  const from = tr.mapping.map(range.from, 1)
  const to = tr.mapping.map(range.to, -1)
  return from < to ? { from, to } : null
}

/** A node decoration only when the range still covers exactly one node (an invalid one throws). */
function nodeDecoration(
  state: EditorState,
  range: BlockRange | null,
  className: string
): Decoration[] {
  const node = range ? state.doc.nodeAt(range.from) : null
  if (!range || !node || range.from + node.nodeSize !== range.to) return []
  return [Decoration.node(range.from, range.to, { class: className })]
}

/** Sets (or clears, with null) one of the highlights. */
export function setBlockHighlight(
  view: { state: EditorState; dispatch: (tr: Transaction) => void },
  meta: Meta
): void {
  view.dispatch(view.state.tr.setMeta(BlockHighlightKey, meta))
}
