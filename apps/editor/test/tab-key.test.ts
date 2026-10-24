import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { doc, stripIds } from './helpers'

describe('Tab in the page', () => {
  let host: HTMLElement
  let editor: Editor

  beforeEach(() => {
    host = document.createElement('div')
    document.body.append(host)
  })
  afterEach(() => {
    editor.destroy()
    host.remove()
  })

  /** A Tab keydown through ProseMirror's handlers; false when one of them took it (preventDefault). */
  const press = (shiftKey = false) =>
    editor.view.dom.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Tab',
        code: 'Tab',
        shiftKey,
        bubbles: true,
        cancelable: true
      })
    )

  it('never leaves the editor from a paragraph (the browser would move focus and scroll to the top)', () => {
    editor = createEditor(host, doc('one', 'two'))
    editor.commands.setTextSelection(6)
    const before = stripIds(editor.getJSON())
    expect(press()).toBe(false)
    expect(press(true)).toBe(false)
    expect(stripIds(editor.getJSON())).toEqual(before)
  })

  it('still nests a list item under the one above', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        {
          type: 'bulletList',
          content: ['a', 'b'].map((text) => ({
            type: 'listItem',
            content: [{ type: 'paragraph', content: [{ type: 'text', text }] }]
          }))
        }
      ]
    })
    // Inside "b".
    editor.commands.setTextSelection(9)
    expect(press()).toBe(false)
    const list: any = editor.getJSON().content?.[0]
    expect(list.content).toHaveLength(1)
    expect(list.content[0].content[1].type).toBe('bulletList')
  })
})
