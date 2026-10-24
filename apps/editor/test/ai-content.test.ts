import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  fragmentText,
  isHandoff,
  OBJECT_CHAR,
  parseEditAdded,
  parseEditNotes,
  parseEditReply,
  parseInline,
  sanitizeInlineHTML,
  selectionUnits,
  textBetween
} from '../src/lib/ai-content'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  editor = createEditor(host, {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        attrs: { id: 'p1' },
        content: [
          { type: 'text', text: 'Hello ' },
          { type: 'text', text: 'bold', marks: [{ type: 'bold' }] },
          { type: 'text', text: ' world' }
        ]
      },
      { type: 'codeBlock', attrs: { id: 'c1' }, content: [{ type: 'text', text: 'code()' }] },
      { type: 'paragraph', attrs: { id: 'p2' }, content: [{ type: 'text', text: 'いいえ😀です' }] }
    ]
  })
})
afterEach(() => {
  editor.destroy()
  host.remove()
})

describe('selectionUnits', () => {
  it('takes the selected part of each text block, keeping its formatting, skipping code', () => {
    editor.commands.setTextSelection({ from: 3, to: editor.state.doc.content.size - 1 })
    const units = selectionUnits(editor.state)
    expect(units.map((u) => u.key)).toEqual(['p1:0', 'p2:1'])
    expect(units[0].text).toBe('llo bold world')
    expect(units[0].html).toBe('llo <strong>bold</strong> world')
    expect(units[1].text).toBe('いいえ😀です')
    expect(editor.state.doc.textBetween(units[1].from, units[1].to)).toBe('いいえ😀です')
  })
})

describe('textBetween', () => {
  it('maps every code point to its document position (an emoji is one character, two positions wide)', () => {
    const p2 = editor.state.doc.child(2)
    let start = 0
    editor.state.doc.forEach((node, offset) => {
      if (node === p2) start = offset + 1
    })
    const { text, positions } = textBetween(editor.state.doc, start, start + p2.content.size)
    expect([...text]).toHaveLength(6)
    expect(positions).toEqual([start, start + 1, start + 2, start + 3, start + 5, start + 6])
  })
})

describe('sanitizeInlineHTML / parseInline', () => {
  it('keeps inline formatting and safe links, drops scripts and unwraps the rest', () => {
    const clean = sanitizeInlineHTML(
      '<p>Hi <b onclick="x()">there</b><script>alert(1)</script> <a href="javascript:evil()">bad</a> <a href="https://ok.example">ok</a><img src=x onerror=y></p>'
    )
    expect(clean.innerHTML).toBe('Hi <b>there</b> bad <a href="https://ok.example">ok</a>')
  })

  it('parses into schema content, whatever the model sent', () => {
    const fragment = parseInline(editor.schema, 'Fixed <em>this</em><div><h1>and that</h1></div>')
    expect(fragment).not.toBeNull()
    expect(fragmentText(fragment!)).toBe('Fixed thisand that')
    expect(parseInline(editor.schema, '')?.size).toBe(0)
    expect(OBJECT_CHAR).toBe('￼')
  })
})

describe('parseEditReply', () => {
  it('reads the blocks, fenced or with words around them, keeping only known keys', () => {
    const reply =
      'Sure!\n```json\n{"blocks":[{"id":"p1:0","html":"Hi"},{"id":"zz","html":"x"},{"id":"p2:1","html":5}]}\n```'
    expect(parseEditReply(reply, ['p1:0', 'p2:1'])).toEqual(new Map([['p1:0', 'Hi']]))
  })

  it('gives nothing for prose, broken JSON or the wrong shape', () => {
    expect(parseEditReply('I cannot help with that.', ['a'])).toBeNull()
    expect(parseEditReply('{"blocks": [', ['a'])).toBeNull()
    expect(parseEditReply('{"text":"hi"}', ['a'])).toBeNull()
    expect(parseEditReply('x'.repeat(300_000), ['a'])).toBeNull()
  })
})

describe('parseEditAdded', () => {
  it('reads the added blocks in order, unknown types as paragraphs, blanks and junk dropped, capped', () => {
    const reply = JSON.stringify({
      blocks: [],
      added: [
        { type: 'heading2', html: 'て形＋いるところです', extra: 1 },
        { type: 'paragraph', html: 'A <strong>b</strong><br>c' },
        { type: 'bullet', html: 'one' },
        { type: 'numbered', html: 'two' },
        { type: 'quote', html: 'said' },
        { type: 'table', html: 'as a paragraph' },
        { html: 'no type' },
        { type: 'paragraph', html: '   ' },
        { type: 'paragraph' },
        'text',
        null,
        { type: 'paragraph', html: 7 }
      ]
    })
    expect(parseEditAdded(reply)).toEqual([
      { type: 'heading2', html: 'て形＋いるところです' },
      { type: 'paragraph', html: 'A <strong>b</strong><br>c' },
      { type: 'bullet', html: 'one' },
      { type: 'numbered', html: 'two' },
      { type: 'quote', html: 'said' },
      { type: 'paragraph', html: 'as a paragraph' },
      { type: 'paragraph', html: 'no type' }
    ])
    const many = JSON.stringify({
      added: Array.from({ length: 30 }, (_, i) => ({ type: 'paragraph', html: `p${i}` }))
    })
    expect(parseEditAdded(many)).toHaveLength(20)
  })

  it('gives nothing when there is no list, or no JSON', () => {
    expect(parseEditAdded('{"blocks":[]}')).toEqual([])
    expect(parseEditAdded('{"added":"a paragraph"}')).toEqual([])
    expect(parseEditAdded('{"added":{"html":"x"}}')).toEqual([])
    expect(parseEditAdded('nothing here')).toEqual([])
  })
})

describe('parseEditNotes', () => {
  it('keeps the notes as trimmed Markdown strings, anything else dropped, capped', () => {
    const reply = JSON.stringify({
      blocks: [{ id: 'p1:0', html: 'x' }],
      notes: [
        '  第三句语法正确：**主谓一致**。 ',
        '',
        '   ',
        { from: 'a', to: 'b', why: 'old shape' },
        5,
        null
      ]
    })
    expect(parseEditNotes(reply)).toEqual(['第三句语法正确：**主谓一致**。'])
    // Fenced, with words around it, as models do.
    expect(parseEditNotes('Here:\n```json\n{"blocks":[],"notes":["Correct."]}\n```')).toEqual([
      'Correct.'
    ])
    expect(parseEditNotes('{"blocks":[]}')).toEqual([])
    expect(parseEditNotes('{"notes":"not a list"}')).toEqual([])
    expect(parseEditNotes('nope')).toEqual([])
    const many = JSON.stringify({ notes: Array.from({ length: 20 }, () => 'a'.repeat(5000)) })
    expect(parseEditNotes(many)).toHaveLength(10)
    expect(parseEditNotes(many)[0]).toHaveLength(4000)
  })
})

describe('isHandoff', () => {
  it('is a handoff only when the reply is one, never an edit that mentions it', () => {
    expect(isHandoff('{"handoff":{"reason":"needs research"}}')).toBe(true)
    expect(isHandoff('```json\n{"handoff": {}}\n```')).toBe(true)
    expect(isHandoff('{"handoff":true}')).toBe(true)
    expect(isHandoff('{"blocks":[{"id":"p1:0","html":"x"}],"handoff":{}}')).toBe(false)
    expect(isHandoff('{"handoff":"yes"}')).toBe(false)
    expect(isHandoff('{"handoff":[]}')).toBe(false)
    expect(isHandoff('The word "handoff" in prose.')).toBe(false)
    expect(isHandoff('{"blocks":[]}')).toBe(false)
  })
})
