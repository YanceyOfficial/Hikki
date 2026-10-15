import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'

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
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(false)
    window.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }))
    expect(painted()).toBe('山田さん|ワットさん|タワポンさん')
    expect(editor.view.dom.classList.contains('hk-own-selection')).toBe(true)
  })
})
