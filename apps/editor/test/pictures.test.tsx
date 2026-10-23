import { cleanup, render, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { undoDepth } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { AIPanel } from '../src/components/ai-panel'
import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import { insertPictures } from '../src/core/pictures'
import { setAIModels } from '../src/lib/ai-models'
import { stripIds } from './helpers'

const asset = (name: string) => `hikki-editor://assets/${name}.jpg`
const para = (id: string, text?: string) => ({
  type: 'paragraph',
  attrs: { id },
  ...(text ? { content: [{ type: 'text', text }] } : {})
})
const image = (id: string, src: string) => ({ type: 'image', attrs: { id, src, alt: 'old' } })

let host: HTMLElement
let editor: Editor

function open(content: object[]) {
  editor = createEditor(
    host,
    { type: 'doc', content },
    {
      ai: {
        request: () => {},
        cancel: () => {},
        title: () => 'Trip to Kyoto'
      }
    }
  )
}
const blocks = () =>
  (stripIds(editor.getJSON()).content as { type: string; attrs?: Record<string, unknown> }[]).map(
    (n) => (n.type === 'image' ? `image:${String(n.attrs?.src)}:${String(n.attrs?.alt)}` : n.type)
  )

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  cleanup()
  setAIModels(null)
  if (editor && !editor.isDestroyed) editor.destroy()
  host.remove()
})

describe('pictures from the chat', () => {
  it('take the empty line they were asked from, with what they show as their description, in one undo step', () => {
    open([para('a', 'Day 1'), para('b'), para('c', 'Day 2')])
    const before = undoDepth(editor.state)
    const items = [
      { src: asset('torii'), alt: 'Torii gates' },
      { src: asset('bamboo'), alt: 'Bamboo grove' }
    ]
    expect(insertPictures(editor, items, { blockId: 'b', replace: false })).toBe(true)
    expect(blocks()).toEqual([
      'paragraph',
      `image:${asset('torii')}:Torii gates`,
      `image:${asset('bamboo')}:Bamboo grove`,
      'paragraph'
    ])
    expect(undoDepth(editor.state)).toBe(before + 1)
  })

  it('go after a line with words, or right after a block without text', () => {
    open([para('a', 'Day 1'), image('i', asset('old')), para('c', 'Day 2')])
    insertPictures(editor, [{ src: asset('n1'), alt: 'One' }], { blockId: 'a', replace: false })
    insertPictures(editor, [{ src: asset('n2'), alt: 'Two' }], { blockId: 'i', replace: false })
    expect(blocks()).toEqual([
      'paragraph',
      `image:${asset('n1')}:One`,
      'paragraph',
      `image:${asset('old')}:old`,
      `image:${asset('n2')}:Two`,
      'paragraph'
    ])
  })

  it('replace the picture they change, and only a picture', () => {
    open([para('a', 'Day 1'), image('i', asset('old'))])
    insertPictures(editor, [{ src: asset('night'), alt: 'At night' }], {
      blockId: 'i',
      replace: true
    })
    expect(blocks()).toEqual(['paragraph', `image:${asset('night')}:At night`, 'paragraph'])
    // The block is a line now (the picture was turned into one meanwhile): they go after it instead.
    open([para('i', 'Words')])
    insertPictures(editor, [{ src: asset('x'), alt: 'X' }], { blockId: 'i', replace: true })
    expect(blocks()).toEqual(['paragraph', `image:${asset('x')}:X`, 'paragraph'])
  })

  it('go in at the caret when their place is gone, and never from outside the workspace', () => {
    open([para('a', 'Day 1'), para('c', 'Day 2')])
    editor.commands.setTextSelection(3)
    insertPictures(editor, [{ src: asset('n'), alt: 'N' }], { blockId: 'gone', replace: false })
    expect(blocks()).toEqual(['paragraph', `image:${asset('n')}:N`, 'paragraph'])
    expect(insertPictures(editor, [{ src: 'https://evil.example/x.jpg', alt: 'x' }], null)).toBe(
      false
    )
    expect(insertPictures(editor, [{ src: 'file:///etc/hosts', alt: 'x' }], null)).toBe(false)
  })

  it("don't go into a page that can't be edited", () => {
    open([para('a', 'Day 1')])
    editor.setEditable(false)
    expect(insertPictures(editor, [{ src: asset('n'), alt: 'N' }], null)).toBe(false)
  })
})

describe('asking for pictures', () => {
  it('only the chat makes them: no "/" row and no Make in Ask AI', () => {
    expect(BLOCK_TYPES.some((b) => b.id === 'aiPictures')).toBe(false)
    render(<AIPanel onRun={() => {}} onCancel={() => {}} autoFocus={false} />)
    expect(screen.queryByText('Make')).toBeNull()
    expect(screen.queryByTestId('ai-make-pictures')).toBeNull()
  })
})
