import { Extension, mergeAttributes, Node } from '@tiptap/core'
import type { Node as PMNode, ResolvedPos } from '@tiptap/pm/model'
import { Plugin, PluginKey, TextSelection, type Transaction } from '@tiptap/pm/state'
import type { EditorView, NodeView } from '@tiptap/pm/view'

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    columns: {
      /** Inserts `count` empty columns (2–4) at the caret, caret in the first. */
      insertColumns: (count: number) => ReturnType
    }
  }
}

export const MIN_COLUMNS = 2
export const MAX_COLUMNS = 5
/** No column narrower than this share of the row while resizing. */
const MIN_SHARE = 10

/** A stored width as a share in percent, or null when it isn't a sane number. */
export function columnWidth(value: unknown): number | null {
  const width = typeof value === 'number' ? value : Number.NaN
  return Number.isFinite(width) && width > 0 && width <= 100 ? width : null
}

/** One column: any blocks. `width` is its share of the row in percent (null = equal shares). */
export const Column = Node.create({
  name: 'column',
  content: 'block+',
  isolating: true,
  defining: true,

  addAttributes() {
    return {
      width: {
        default: null,
        parseHTML: (el) => {
          return columnWidth(Number.parseFloat(el.getAttribute('data-width') ?? ''))
        },
        renderHTML: (attrs) => {
          // Only a number reaches the style: stored content (a synced or imported file) could carry
          // anything in this attribute, and a string would inject CSS.
          const width = columnWidth(attrs.width)
          return width
            ? { 'data-width': String(width), style: `flex: ${width} 1 0%` }
            : { style: 'flex: 1 1 0%' }
        }
      }
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="column"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'column', class: 'hk-col' }), 0]
  }
})

export const ColumnsKey = new PluginKey('columns')

/**
 * Side-by-side columns (Notion): "/2 columns"…, or drag a block onto another block's left/right edge.
 * Column widths are dragged on the gutters. A row left with one column unwraps into plain blocks, and
 * Backspace in an empty column removes it.
 */
export const Columns = Node.create({
  name: 'columns',
  group: 'block',
  content: `column{${MIN_COLUMNS},${MAX_COLUMNS}}`,
  isolating: true,
  defining: true,

  parseHTML() {
    return [{ tag: 'div[data-type="columns"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'columns', class: 'hk-cols' }), 0]
  },

  addCommands() {
    return {
      insertColumns:
        (count) =>
        ({ state, tr, dispatch }) => {
          // No rows inside a column (Notion doesn't nest them either).
          const { $from: at } = tr.selection
          for (let d = at.depth; d > 0; d--) if (at.node(d).type.name === 'column') return false
          const n = Math.min(MAX_COLUMNS, Math.max(MIN_COLUMNS, Math.round(count)))
          const { column, paragraph } = state.schema.nodes
          const node = this.type.create(
            null,
            Array.from({ length: n }, () => column.create(null, paragraph.create()))
          )
          if (dispatch) {
            const { $from } = tr.selection
            // Replace the (empty) current paragraph, or insert after the current block.
            const parentEmpty = $from.depth >= 1 && $from.parent.content.size === 0
            const from = parentEmpty ? $from.before() : $from.after(1)
            const to = parentEmpty ? $from.after() : from
            tr.replaceWith(from, to, node)
            tr.setSelection(TextSelection.near(tr.doc.resolve(from + 3)))
          }
          return true
        }
    }
  },

  addNodeView() {
    return ({ node, getPos, view }) =>
      new ColumnsView(node, view, getPos as () => number | undefined)
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: ColumnsKey,
        // A row with a single column (after a deletion or a drag out) becomes plain blocks again.
        appendTransaction: (transactions, _old, state) => {
          if (!transactions.some((t) => t.docChanged)) return null
          let tr: Transaction | null = null
          state.doc.descendants((node, pos) => {
            if (node.type.name !== 'columns' || node.childCount !== 1) return true
            tr ??= state.tr
            const at = tr.mapping.map(pos)
            tr.replaceWith(at, at + node.nodeSize, node.firstChild!.content)
            return false
          })
          return tr
        },
        props: {
          handleDOMEvents: {
            dragover: (view, event) => {
              const target = sideDropTarget(view, event)
              showSideIndicator(target)
              return false
            },
            dragleave: (view, event) => {
              if (!view.dom.contains(event.relatedTarget as globalThis.Node | null))
                showSideIndicator(null)
              return false
            },
            drop: () => {
              showSideIndicator(null)
              return false
            }
          },
          handleDrop: (view, event, _slice, moved) => {
            if (!moved) return false
            const target = sideDropTarget(view, event)
            showSideIndicator(null)
            return target ? dropBeside(view, target) : false
          }
        }
      })
    ]
  }
})

// MARK: - Backspace

/**
 * Its own extension so it can run before Tiptap's core Backspace (which would select the column before);
 * a high priority on the node itself would reorder the schema and change the default block.
 */
export const ColumnsKeymap = Extension.create({
  name: 'columnsKeymap',
  priority: 1000,
  addKeyboardShortcuts() {
    return {
      Backspace: ({ editor }) => removeEmptyColumn(editor.view)
    }
  }
})

/** In an empty column (one empty paragraph), Backspace at its start removes the column. */
function removeEmptyColumn(view: EditorView): boolean {
  const { state } = view
  const { $from, empty } = state.selection
  if (!empty || $from.parentOffset !== 0 || $from.parent.content.size !== 0) return false
  const column = $from.node(-1)
  if (column?.type.name !== 'column' || column.childCount !== 1) return false
  const columnPos = $from.before(-1)
  const row = $from.node(-2)
  const rowPos = $from.before(-2)
  const tr = state.tr
  if (row.childCount > MIN_COLUMNS) {
    tr.delete(columnPos, columnPos + column.nodeSize)
    // Caret to the end of the column before (or the start of the one after).
    tr.setSelection(TextSelection.near(tr.doc.resolve(Math.max(0, columnPos - 1)), -1))
  } else {
    // A row can't have one column (the schema refuses the step): the other column's blocks replace it.
    const other = row.child($from.index(-2) === 0 ? 1 : 0)
    tr.replaceWith(rowPos, rowPos + row.nodeSize, other.content)
    tr.setSelection(
      TextSelection.near(
        tr.doc.resolve(Math.min(rowPos + other.content.size, tr.doc.content.size)),
        -1
      )
    )
  }
  view.dispatch(tr.scrollIntoView())
  return true
}

// MARK: - Drag a block beside another

export type SideTarget = { pos: number; node: PMNode; side: 'left' | 'right'; rect: DOMRect }

/** The dragged blocks: the drag handle selects a block range (NodeRangeSelection) or a node. */
function draggedRange(view: EditorView): { from: number; to: number } | null {
  if (!view.dragging) return null
  const { from, to } = view.state.selection
  const $from = view.state.doc.resolve(from)
  if (from === to || !$from.nodeAfter?.isBlock) return null
  return { from, to }
}

/** The top-level block under the pointer, if the pointer is near its left or right edge. */
function sideDropTarget(view: EditorView, event: DragEvent): SideTarget | null {
  const dragged = draggedRange(view)
  if (!dragged) return null
  const at = view.posAtCoords({ left: event.clientX, top: event.clientY })
  if (!at) return null
  const $pos = view.state.doc.resolve(at.inside >= 0 ? at.inside : at.pos)
  const top = topLevelBlock($pos)
  if (!top) return null
  const { pos, node } = top
  // Not beside itself, and not when the row is already full.
  if (pos >= dragged.from && pos < dragged.to) return null
  if (node.type.name === 'columns' && node.childCount >= MAX_COLUMNS) return null
  const dom = view.nodeDOM(pos)
  if (!(dom instanceof HTMLElement)) return null
  const rect = dom.getBoundingClientRect()
  const edge = Math.min(80, Math.max(24, rect.width * 0.15))
  if (event.clientX < rect.left + edge) return { pos, node, side: 'left', rect }
  if (event.clientX > rect.right - edge) return { pos, node, side: 'right', rect }
  return null
}

function topLevelBlock($pos: ResolvedPos): { pos: number; node: PMNode } | null {
  if ($pos.depth < 1) {
    const node = $pos.nodeAfter
    return node ? { pos: $pos.pos, node } : null
  }
  return { pos: $pos.before(1), node: $pos.node(1) }
}

export function dropBeside(view: EditorView, target: SideTarget): boolean {
  const { state } = view
  const { from, to } = state.selection
  const { column, columns } = state.schema.nodes
  const content = state.doc.slice(from, to).content
  // A row can't go inside a column of another row.
  let hasRow = false
  content.forEach((n) => {
    if (n.type.name === 'columns') hasRow = true
  })
  if (hasRow || content.childCount === 0) return false
  const newColumn = column.create(null, content)
  const tr = state.tr.delete(from, to)
  const pos = tr.mapping.map(target.pos)
  const node = tr.doc.nodeAt(pos)
  if (!node) return false
  if (node.type.name === 'columns') {
    // Another column on that side of an existing row; widths reset to equal shares.
    const cols: PMNode[] = []
    node.forEach((c) => cols.push(c.type.create({ ...c.attrs, width: null }, c.content)))
    const next = target.side === 'left' ? [newColumn, ...cols] : [...cols, newColumn]
    tr.replaceWith(pos, pos + node.nodeSize, columns.create(node.attrs, next))
  } else {
    const existing = column.create(null, node)
    const pair = target.side === 'left' ? [newColumn, existing] : [existing, newColumn]
    tr.replaceWith(pos, pos + node.nodeSize, columns.create(null, pair))
  }
  view.dispatch(tr.scrollIntoView())
  return true
}

/** A vertical line at the edge the block would land beside. */
function showSideIndicator(target: SideTarget | null) {
  let line = document.querySelector<HTMLElement>('.hk-side-drop')
  document.body.classList.toggle('hk-side-dropping', !!target)
  if (!target) {
    line?.remove()
    return
  }
  if (!line) {
    line = document.createElement('div')
    line.className = 'hk-side-drop'
    document.body.append(line)
  }
  const x = target.side === 'left' ? target.rect.left - 4 : target.rect.right + 2
  Object.assign(line.style, {
    left: `${x}px`,
    top: `${target.rect.top}px`,
    height: `${target.rect.height}px`
  })
}

// MARK: - Resizing

class ColumnsView implements NodeView {
  dom: HTMLElement
  contentDOM: HTMLElement
  private gutters: HTMLElement
  private node: PMNode
  private observer: ResizeObserver | null = null

  constructor(
    node: PMNode,
    private readonly view: EditorView,
    private readonly getPos: () => number | undefined
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.className = 'hk-cols-wrapper'
    this.contentDOM = document.createElement('div')
    this.contentDOM.className = 'hk-cols'
    this.contentDOM.dataset.type = 'columns'
    this.gutters = document.createElement('div')
    this.gutters.className = 'hk-col-gutters'
    this.gutters.contentEditable = 'false'
    this.dom.append(this.contentDOM, this.gutters)
    if (typeof ResizeObserver !== 'undefined') {
      this.observer = new ResizeObserver(() => this.placeGutters())
      this.observer.observe(this.contentDOM)
    }
    requestAnimationFrame(() => this.placeGutters())
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    this.node = node
    requestAnimationFrame(() => this.placeGutters())
    return true
  }

  /** One handle on each boundary between columns. */
  private placeGutters() {
    const children = Array.from(this.contentDOM.children) as HTMLElement[]
    const count = Math.max(0, children.length - 1)
    while (this.gutters.children.length > count) this.gutters.lastChild?.remove()
    while (this.gutters.children.length < count) {
      const handle = document.createElement('div')
      handle.className = 'hk-col-gutter'
      handle.addEventListener('pointerdown', (e) => this.startResize(e, handle))
      this.gutters.append(handle)
    }
    const base = this.dom.getBoundingClientRect().left
    Array.from(this.gutters.children).forEach((handle, i) => {
      const left = children[i].getBoundingClientRect().right
      const right = children[i + 1].getBoundingClientRect().left
      ;(handle as HTMLElement).style.left = `${(left + right) / 2 - base}px`
      ;(handle as HTMLElement).dataset.index = String(i)
    })
  }

  private startResize(event: PointerEvent, handle: HTMLElement) {
    if (!this.view.editable) return
    event.preventDefault()
    const index = Number(handle.dataset.index)
    const children = Array.from(this.contentDOM.children) as HTMLElement[]
    const widths = children.map((c) => c.getBoundingClientRect().width)
    const total = widths.reduce((a, b) => a + b, 0)
    const shares = widths.map((w) => (w / total) * 100)
    const pair = shares[index] + shares[index + 1]
    const startX = event.clientX
    handle.setPointerCapture(event.pointerId)
    handle.classList.add('is-dragging')

    const apply = () => children.forEach((c, i) => (c.style.flex = `${shares[i]} 1 0%`))
    const onMove = (e: PointerEvent) => {
      const delta = ((e.clientX - startX) / total) * 100
      const left = Math.min(
        pair - MIN_SHARE,
        Math.max(MIN_SHARE, (widths[index] / total) * 100 + delta)
      )
      shares[index] = left
      shares[index + 1] = pair - left
      apply()
      this.placeGutters()
    }
    const onUp = () => {
      handle.removeEventListener('pointermove', onMove)
      handle.classList.remove('is-dragging')
      this.commit(shares)
    }
    handle.addEventListener('pointermove', onMove)
    handle.addEventListener('pointerup', onUp, { once: true })
    handle.addEventListener('pointercancel', onUp, { once: true })
  }

  private commit(shares: number[]) {
    const pos = this.getPos()
    if (pos === undefined) return
    const tr = this.view.state.tr
    let offset = pos + 1
    this.node.forEach((child, _o, i) => {
      tr.setNodeMarkup(offset, undefined, {
        ...child.attrs,
        width: Math.round(shares[i] * 10) / 10
      })
      offset += child.nodeSize
    })
    this.view.dispatch(tr)
  }

  ignoreMutation(mutation: MutationRecord | { type: 'selection'; target: globalThis.Node }) {
    // Gutters are ours; so are the flex styles set on the columns while dragging.
    if (this.gutters.contains(mutation.target)) return true
    return mutation.type === 'attributes' && mutation.target.parentNode === this.contentDOM
  }

  stopEvent(event: Event) {
    return this.gutters.contains(event.target as globalThis.Node)
  }

  destroy() {
    this.observer?.disconnect()
  }
}
