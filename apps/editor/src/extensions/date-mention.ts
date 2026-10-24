import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import { createRoot } from 'react-dom/client'

import { dateChipState, renderDateChip, renderDatePopover } from '../components/date-chip'
import { FloatingLayer } from '../components/floating'
import i18n from '../core/i18n'
import { openNativeDateSheet } from '../lib/date-sheet'
import { dateLong, dateText, type DateMentionAttrs } from '../lib/dates'
import { followNode, type BlockUnit, type Followed } from './block-units'

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    dateMention: {
      /** Puts a date chip (and a space after it) over `range`, as "@" does when a date is picked. */
      insertDateMention: (
        range: { from: number; to: number },
        attrs: Partial<DateMentionAttrs> & Pick<DateMentionAttrs, 'date'>
      ) => ReturnType
    }
  }
}

/** Chips read relative to now ("Today", red once a reminder has rung): they redraw every minute and on a new language. */
const clock = new EventTarget()
let ticking: ReturnType<typeof setInterval> | null = null
let chips = 0

function watchClock(redraw: () => void): () => void {
  clock.addEventListener('tick', redraw)
  i18n.on('languageChanged', redraw)
  if (chips++ === 0) ticking = setInterval(() => clock.dispatchEvent(new Event('tick')), 60_000)
  return () => {
    clock.removeEventListener('tick', redraw)
    i18n.off('languageChanged', redraw)
    if (--chips === 0 && ticking) {
      clearInterval(ticking)
      ticking = null
    }
  }
}

/** Redraws every chip now (tests; the app coming back from the background). */
export function tickDateChips(): void {
  clock.dispatchEvent(new Event('tick'))
}

export function attrsOf(node: { attrs: Record<string, unknown> }): DateMentionAttrs {
  const a = node.attrs
  return {
    id: (a.id as string | null) ?? null,
    date: a.date as string,
    time: (a.time as string | null) ?? null,
    remind: typeof a.remind === 'number' ? a.remind : null,
    done: a.done === true,
    snoozed: (a.snoozed as string | null) ?? null
  }
}

/** The chip being edited (the popover's, or the native sheet's until it answers) and the popover, if the page draws it. */
let open: { layer: FloatingLayer | null; chip: Followed<BlockUnit> } | null = null

function close(editor?: Editor) {
  open?.chip.stop()
  open?.layer?.destroy()
  const hadLayer = !!open?.layer
  open = null
  if (!hadLayer) return
  if (editor && !editor.isDestroyed) editor.commands.focus()
}

/** Changes the chip `chip` follows (a new day, a reminder…); null removes it. One undo step each. */
function change(
  editor: Editor,
  chip: Followed<BlockUnit>,
  patch: Partial<DateMentionAttrs> | null
) {
  const at = chip.current
  if (!at || !editor.isEditable) return
  const { tr } = editor.state
  if (patch === null) tr.delete(at.pos, at.pos + at.node.nodeSize)
  else tr.setNodeMarkup(at.pos, undefined, { ...at.node.attrs, ...patch })
  editor.view.dispatch(tr)
}

/** Opens the chip at `pos` for editing: the native sheet where there is one (a phone), else the page's popover. */
export function openDateMention(editor: Editor, pos: number): void {
  close()
  const node = editor.state.doc.nodeAt(pos)
  if (!node || node.type.name !== 'dateMention' || !editor.isEditable) return
  const chip = followNode(editor, pos, () => close())
  const native = openNativeDateSheet(attrsOf(node), (next) => {
    change(editor, chip, next && { ...next, snoozed: null })
    close()
  })
  if (native) {
    open = { layer: null, chip }
    return
  }
  const layer = new FloatingLayer(
    'hk-date-popover w-(--layout-panel-date) max-w-(--layout-viewport-max) p-1.5',
    {
      onDismiss: () => close(editor)
    }
  )
  open = { layer, chip }
  const anchor = () => {
    const now = chip.current?.pos
    const el = now === undefined ? null : editor.view.nodeDOM(now)
    return el instanceof HTMLElement ? el.getBoundingClientRect() : null
  }
  const draw = () => {
    const current = chip.current
    if (!current) return
    renderDatePopover(
      layer,
      {
        attrs: attrsOf(current.node),
        onChange: (patch) => {
          change(editor, chip, patch)
          draw()
        },
        onRemove: () => {
          change(editor, chip, null)
          close(editor)
        }
      },
      anchor
    )
  }
  draw()
}

/** An attribute kept as `data-<name>` in copied HTML. */
const data = (name: string, parse: (v: string | null) => unknown = (v) => v) => ({
  default: null,
  parseHTML: (el: HTMLElement) => parse(el.getAttribute(`data-${name}`)),
  renderHTML: (attrs: Record<string, unknown>) =>
    attrs[name] === null || attrs[name] === false ? {} : { [`data-${name}`]: String(attrs[name]) }
})

/**
 * A date in a line (Notion's "Date or reminder"): an inline chip that reads relative to today, optionally with a time
 * and a reminder (`lib/dates.ts`). "@" inserts it (page-mention.ts offers dates first); a click opens its popover,
 * or on a phone the native sheet. Stored as attributes only; copied out, it's the date in full.
 */
export const DateMention = Node.create({
  name: 'dateMention',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: false,

  addAttributes() {
    return {
      id: data('id'),
      date: data('date'),
      time: data('time'),
      remind: data('remind', (v) => (v === null || Number.isNaN(Number(v)) ? null : Number(v))),
      done: { ...data('done', (v) => v === 'true'), default: false },
      snoozed: data('snoozed')
    }
  },

  parseHTML() {
    return [{ tag: 'time[data-type="date"]' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    const attrs = attrsOf(node)
    return [
      'time',
      mergeAttributes(HTMLAttributes, {
        'data-type': 'date',
        datetime: dateText(attrs).replace(' ', 'T')
      }),
      dateLong(attrs)
    ]
  },

  renderText({ node }) {
    return dateLong(attrsOf(node))
  },

  renderMarkdown(node: { attrs?: Record<string, unknown> }) {
    return dateText(attrsOf({ attrs: node.attrs ?? {} }))
  },

  addCommands() {
    return {
      insertDateMention:
        (range, attrs) =>
        ({ chain }) =>
          chain()
            .focus()
            .insertContentAt(range, [
              {
                type: this.name,
                attrs: { id: crypto.randomUUID(), time: null, remind: null, done: false, ...attrs }
              },
              { type: 'text', text: ' ' }
            ])
            .run()
    }
  },

  addNodeView() {
    return ({ node: initial, editor, getPos }) => {
      let node = initial
      const dom = document.createElement('span')
      dom.className = 'hk-date'
      dom.contentEditable = 'false'
      dom.dataset.testid = 'date-chip'
      const root = createRoot(dom)
      const draw = () => {
        const attrs = attrsOf(node)
        dom.dataset.state = dateChipState(attrs)
        dom.title = dateLong(attrs)
        renderDateChip(root, attrs)
      }
      draw()
      const unwatch = watchClock(draw)
      // A press opens the chip without moving the caret (or raising a phone's keyboard).
      dom.addEventListener('mousedown', (e) => e.preventDefault())
      dom.addEventListener('click', (e) => {
        e.preventDefault()
        const pos = getPos()
        if (typeof pos === 'number') openDateMention(editor, pos)
      })
      return {
        dom,
        update: (next) => {
          if (next.type !== node.type) return false
          node = next
          draw()
          return true
        },
        stopEvent: (e) => e.type === 'mousedown' || e.type === 'click',
        ignoreMutation: () => true,
        destroy: () => {
          unwatch()
          // React can't unmount a root while it renders: after this turn.
          queueMicrotask(() => root.unmount())
        }
      }
    }
  },

  onDestroy() {
    close()
  }
})
