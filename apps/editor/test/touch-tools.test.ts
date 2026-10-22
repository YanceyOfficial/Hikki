import { TextHOneIcon, ListMagnifyingGlassIcon } from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  phosphorName,
  selectAroundCaret,
  selectBlockAtCaret,
  touchBlockAction,
  touchBlockColor,
  touchBlockInfo,
  touchBlockMenu,
  touchComment,
  touchCommentQuote,
  touchInsertBlock,
  touchInsertMedia,
  touchRun,
  touchSetColor,
  touchState,
  touchTurnInto,
  touchTurnIntoMenu
} from '../src/core/touch-tools'
import { commentsState } from '../src/extensions/comments'
import { stripIds } from './helpers'

let host: HTMLElement
let editor: Editor

const para = (text?: string) =>
  text ? { type: 'paragraph', content: [{ type: 'text', text }] } : { type: 'paragraph' }

function open(content: object[]) {
  editor = createEditor(host, { type: 'doc', content })
}
const types = () => (stripIds(editor.getJSON()).content as { type: string }[]).map((n) => n.type)
const texts = () =>
  (stripIds(editor.getJSON()).content as { content?: { text: string }[] }[]).map(
    (n) => n.content?.[0]?.text ?? ''
  )

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

  it('link acts on the word at the caret', () => {
    open([para('make this bold')])
    editor.commands.setTextSelection(8)
    expect(selectAroundCaret(editor)).toBe(true)
    const { from, to } = editor.state.selection
    expect(editor.state.doc.textBetween(from, to)).toBe('this')
  })

  it("AI acts on the caret's whole block when nothing is selected, as a comment does", () => {
    open([para('make this bold'), para('and this')])
    editor.commands.setTextSelection(8)
    expect(selectBlockAtCaret(editor)).toBe(true)
    let { from, to } = editor.state.selection
    expect(editor.state.doc.textBetween(from, to)).toBe('make this bold')
    // A selection already made is left alone.
    editor.commands.setTextSelection({ from: 6, to: 10 })
    expect(selectBlockAtCaret(editor)).toBe(true)
    ;({ from, to } = editor.state.selection)
    expect(editor.state.doc.textBetween(from, to)).toBe('this')
    // Nothing to act on in an empty block.
    open([para('')])
    editor.commands.setTextSelection(1)
    expect(selectBlockAtCaret(editor)).toBe(false)
  })

  it('moves, duplicates and deletes the block at the caret', () => {
    open([para('one'), para('two'), para('three')])
    editor.commands.setTextSelection(7) // in "two"
    expect(touchRun(editor, 'moveUp')).toBe(true)
    expect(texts()).toEqual(['two', 'one', 'three'])
    expect(touchRun(editor, 'moveDown')).toBe(true)
    expect(touchRun(editor, 'moveDown')).toBe(true)
    expect(texts()).toEqual(['one', 'three', 'two'])
    expect(touchRun(editor, 'duplicate')).toBe(true)
    expect(texts()).toEqual(['one', 'three', 'two', 'two'])
    expect(touchRun(editor, 'delete')).toBe(true)
    expect(texts()).toEqual(['one', 'three', 'two'])
  })

  it('the emoji tool types ":" — spaced from the word before it — and the suggestion takes over', () => {
    open([para('hi')])
    editor.commands.setTextSelection(3)
    expect(touchRun(editor, 'emoji')).toBe(true)
    expect(texts()).toEqual(['hi :'])
  })

  it("the ⋯ sheet describes the caret's block and acts on it", () => {
    open([
      { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Plan it' }] },
      para('next')
    ])
    editor.commands.setTextSelection(2)
    expect(touchBlockInfo(editor)).toMatchObject({
      turnInto: 'heading2',
      colorable: true,
      comment: true,
      ai: true,
      words: 2,
      characters: 7,
      textColor: null
    })
    expect(touchBlockColor(editor, 'background', 'blue')).toBe(true)
    expect(touchBlockColor(editor, 'text', 'not-a-colour')).toBe(true)
    expect(touchBlockInfo(editor)).toMatchObject({ backgroundColor: 'blue', textColor: null })

    expect(touchBlockAction(editor, 'insertBelow')).toBe(true)
    expect(texts()).toEqual(['Plan it', '', 'next'])
    expect(editor.state.selection.$from.parent.textContent).toBe('')

    editor.commands.setTextSelection(2)
    expect(touchBlockAction(editor, 'selectText')).toBe(true)
    const { from, to } = editor.state.selection
    expect(editor.state.doc.textBetween(from, to)).toBe('Plan it')
  })
})

describe('the native comment field', () => {
  const created: string[] = []
  function openWithComments(content: object[]) {
    created.length = 0
    editor = createEditor(
      host,
      { type: 'doc', content },
      {
        comments: {
          create: (_id, quote, body) => created.push(`${quote}|${body}`),
          reply: () => {},
          resolve: () => {},
          remove: () => {},
          edit: () => {},
          device: () => 'iPhone',
          pages: () => [],
          openPage: () => {},
          link: () => null
        }
      }
    )
  }

  it('comments on the selection in one step, leaving no draft or open thread for the page sheet', () => {
    openWithComments([para('Hello world')])
    editor.commands.setTextSelection({ from: 7, to: 12 })
    expect(touchCommentQuote(editor, 'selection')).toBe('world')
    expect(touchComment(editor, 'selection', 'Nice')).toBe(true)
    expect(created).toEqual(['world|Nice'])
    const plugin = commentsState(editor.state)
    expect(plugin?.draft).toBeNull()
    expect(plugin?.active).toBeNull()
    expect(editor.state.doc.rangeHasMark(7, 12, editor.schema.marks.comment)).toBe(true)
  })

  it("comments on the caret's whole block without a selection, and refuses an empty body", () => {
    openWithComments([para('First'), para('Second line')])
    editor.commands.setTextSelection(10)
    expect(touchCommentQuote(editor, 'selection')).toBe('Second line')
    expect(touchComment(editor, 'selection', '  ')).toBe(false)
    expect(touchComment(editor, 'block', 'Why?')).toBe(true)
    expect(created).toEqual(['Second line|Why?'])
  })
})

describe('touchInsertMedia', () => {
  const photo = { src: 'hikki-editor://assets/a1.jpg', name: 'IMG_0001.jpg', size: 2048 }
  const scan = { src: 'hikki-editor://assets/b2.pdf', name: 'Scan.pdf', size: 4096 }

  it('replaces an empty line with the files, each as its kind, the caret after them', () => {
    open([para('Intro'), para()])
    editor.commands.setTextSelection(8)
    expect(touchInsertMedia(editor, [photo, scan])).toBe(true)
    expect(types()).toEqual(['paragraph', 'image', 'fileAttachment', 'paragraph'])
    expect(editor.state.selection.$from.parent.type.name).toBe('paragraph')
  })

  it("goes below the caret's block, and refuses what isn't a stored file", () => {
    open([para('Intro'), para('After')])
    editor.commands.setTextSelection(3)
    expect(touchInsertMedia(editor, [{ ...photo, src: 'javascript:alert(1)' }])).toBe(false)
    expect(touchInsertMedia(editor, [photo])).toBe(true)
    expect(types()).toEqual(['paragraph', 'image', 'paragraph'])
  })
})
