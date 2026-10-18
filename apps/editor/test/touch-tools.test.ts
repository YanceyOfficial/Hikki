import { TextHOneIcon, ListMagnifyingGlassIcon } from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  phosphorName,
  selectAroundCaret,
  touchBlockMenu,
  touchInsertBlock,
  touchRun,
  touchSetColor,
  touchState,
  touchTurnInto,
  touchTurnIntoMenu
} from '../src/core/touch-tools'
import { stripIds } from './helpers'

let host: HTMLElement
let editor: Editor

const para = (text?: string) =>
  text ? { type: 'paragraph', content: [{ type: 'text', text }] } : { type: 'paragraph' }

function open(content: object[]) {
  editor = createEditor(host, { type: 'doc', content })
}
const types = () => (stripIds(editor.getJSON()).content as { type: string }[]).map((n) => n.type)

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  if (editor && !editor.isDestroyed) editor.destroy()
  host.remove()
})

describe('the phone keyboard bar', () => {
  it('names icons as the native icon set does', () => {
    expect(phosphorName(TextHOneIcon)).toBe('text-h-one')
    expect(phosphorName(ListMagnifyingGlassIcon)).toBe('list-magnifying-glass')
  })

  it('offers the "/" catalog, the embed services folded into Embed', () => {
    open([para('hi')])
    const groups = touchBlockMenu()
    expect(groups[0].blocks[0]).toMatchObject({ id: 'paragraph', icon: 'text-t' })
    const embeds = groups.find((g) => g.id === 'embeds')
    expect(embeds?.blocks.map((b) => b.id)).toEqual(['embed'])
    expect(touchTurnIntoMenu().map((b) => b.id)).toContain('heading1')
    expect(touchTurnIntoMenu().map((b) => b.id)).not.toContain('divider')
  })

  it('+ turns an empty line into the block, else adds it below (after a whole list)', () => {
    open([para('one'), para()])
    editor.commands.setTextSelection(6)
    expect(touchInsertBlock(editor, 'heading2')).toBe(true)
    // (Tiptap keeps an empty line after a last heading.)
    expect(types().slice(0, 2)).toEqual(['paragraph', 'heading'])

    editor.commands.setTextSelection(2)
    touchInsertBlock(editor, 'divider')
    expect(types().slice(0, 2)).toEqual(['paragraph', 'horizontalRule'])
    editor.destroy()

    open([
      {
        type: 'bulletList',
        content: [{ type: 'listItem', content: [para('item')] }]
      }
    ])
    editor.commands.setTextSelection(4)
    touchInsertBlock(editor, 'heading1')
    expect(types().slice(0, 2)).toEqual(['bulletList', 'heading'])
  })

  it('Aa turns the block into another, sets marks and colours, and reports them', () => {
    open([para('hello world')])
    editor.commands.setTextSelection({ from: 1, to: 6 })
    touchTurnInto(editor, 'heading3')
    touchRun(editor, 'bold')
    touchRun(editor, 'underline')
    touchSetColor(editor, 'text', 'red')
    touchSetColor(editor, 'background', 'not-a-colour')
    const state = touchState(editor)
    expect(state).toMatchObject({
      block: 'heading3',
      textColor: 'red',
      bgColor: null,
      selection: true
    })
    expect(state.marks).toEqual(['bold', 'underline'])
  })

  it('@ starts a mention, spaced from the word before it', () => {
    open([para('see')])
    editor.commands.setTextSelection(4)
    touchRun(editor, 'mention')
    expect(editor.state.doc.textContent).toBe('see @')
  })

  it('AI and link act on the word at the caret', () => {
    open([para('make this bold')])
    editor.commands.setTextSelection(8)
    expect(selectAroundCaret(editor)).toBe(true)
    const { from, to } = editor.state.selection
    expect(editor.state.doc.textBetween(from, to)).toBe('this')
  })
})
