import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { PAINT_LIMIT, selectedTextRects, visibleBlocks } from '../src/extensions/selection-paint'

let host: HTMLElement
let editor: Editor

const item = (text: string) => ({
  type: 'listItem',
  content: [{ type: 'paragraph', content: [{ type: 'text', text }] }]
})

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  editor = createEditor(host, {
    type: 'doc',
    content: [
      { type: 'orderedList', content: [item('山田さん'), item('ワットさん'), item('タワポンさん')] }
    ]
  })
})
afterEach(() => {
  editor.destroy()
  host.remove()
})

const painted = () =>
  [...host.querySelectorAll('.hk-selection')].map((el) => el.textContent).join('|')

describe('selection paint', () => {
  it('paints a selection across list items on the text only', () => {
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(true)
    editor.commands.setTextSelection({ from: 4, to: editor.state.doc.content.size - 4 })
    expect(painted()).toBe('田さん|ワットさん|タワポンさ')
    // Nothing outside the text: no list item or list carries the mark.
    expect(host.querySelector('li.hk-selection, ol.hk-selection')).toBeNull()
  })

  it('leaves a selection longer than the limit to the browser (ISSUE-261: ⌘A on a long page hung)', () => {
    editor.destroy()
    const line = { type: 'paragraph', content: [{ type: 'text', text: 'x'.repeat(1000) }] }
    editor = createEditor(host, {
      type: 'doc',
      content: Array.from({ length: Math.ceil(PAINT_LIMIT / 1000) + 2 }, () => line)
    })
    editor.commands.selectAll()
    // Nothing in the page's DOM changes: no text wrapped, the root's class as it was (a class change on the root
    // of a long page restyled every element under it). The layer draws the blocks in view instead.
    expect(host.querySelectorAll('.hk-selection')).toHaveLength(0)
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(true)
    expect(host.querySelector('.hk-selection-layer')).not.toBeNull()
    // A selection within the limit is painted on the text again.
    editor.commands.setTextSelection({ from: 1, to: 500 })
    expect(host.querySelectorAll('.hk-selection')).toHaveLength(1)
  })

  it('draws only the blocks in view of a long selection, found without walking the page', () => {
    const blocks = Array.from({ length: 1000 }, (_, i) => ({
      top: i * 30 - 600,
      bottom: i * 30 - 570
    }))
    // The first block whose foot is in view, through the last whose top is.
    expect(visibleBlocks(blocks, 700)).toEqual([19, 44])
    expect(visibleBlocks(blocks.slice(0, 10), 700)).toEqual([10, 10])
    expect(visibleBlocks([], 700)).toEqual([0, 0])
  })

  it('paints select-all, and nothing for a caret', () => {
    editor.commands.selectAll()
    expect(painted()).toBe('山田さん|ワットさん|タワポンさん')
    editor.commands.setTextSelection(3)
    expect(painted()).toBe('')
  })

  it('leaves the paint to the browser while a mouse drag selects, then paints on release', () => {
    editor.view.dom.dispatchEvent(new MouseEvent('mousedown', { button: 0, bubbles: true }))
    editor.commands.selectAll()
    expect(painted()).toBe('')
    // The browser still doesn't paint: the drag layer does (below).
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(true)
    window.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }))
    expect(painted()).toBe('山田さん|ワットさん|タワポンさん')
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(true)
  })

  it('the drag layer measures the selected text only — never the list numbers or the items around it', () => {
    const measured: string[] = []
    const original = Range.prototype.getClientRects
    Range.prototype.getClientRects = function (this: Range) {
      measured.push(this.toString())
      return [new DOMRect(110, 220, 50, 20)] as unknown as DOMRectList
    }
    try {
      const texts = [...host.querySelectorAll('li p')].map((p) => p.firstChild as Text)
      const range = document.createRange()
      range.setStart(texts[0], 1)
      range.setEnd(texts[2], 3)
      const rects = selectedTextRects(range, editor.view.dom, new DOMRect(100, 200, 500, 500))
      expect(measured).toEqual(['田さん', 'ワットさん', 'タワポ'])
      expect(rects[0]).toMatchObject({ x: 10, y: 20, width: 50, height: 20 })
    } finally {
      Range.prototype.getClientRects = original
    }
  })
})
