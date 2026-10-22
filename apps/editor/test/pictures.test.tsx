import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { undoDepth } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AIPanel } from '../src/components/ai-panel'
import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import { insertPictures } from '../src/core/pictures'
import type { PicturesRequest } from '../src/extensions/ai-review'
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
let asked: PicturesRequest[]

function open(content: object[]) {
  editor = createEditor(
    host,
    { type: 'doc', content },
    {
      ai: {
        request: () => {},
        cancel: () => {},
        title: () => 'Trip to Kyoto',
        pictures: (request) => asked.push(request)
      }
    }
  )
}
const blocks = () =>
  (stripIds(editor.getJSON()).content as { type: string; attrs?: Record<string, unknown> }[]).map(
    (n) => (n.type === 'image' ? `image:${String(n.attrs?.src)}:${String(n.attrs?.alt)}` : n.type)
  )

beforeEach(() => {
  asked = []
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
  it('"/" AI pictures asks for this line', () => {
    open([para('a', 'Day 1'), para('b')])
    editor.commands.setTextSelection(editor.state.doc.content.size - 1)
    const type = BLOCK_TYPES.find((b) => b.id === 'aiPictures')
    expect(type?.group).toBe('ai')
    type?.after?.(editor)
    expect(asked).toEqual([{ blockId: 'b', mode: 'after' }])
  })

  it('a selection asks with its words, going after the block it ends in; an image asks to be changed', () => {
    open([para('a', 'Day 1'), para('c', 'Day 2'), image('i', asset('old'))])
    editor.commands.setTextSelection({ from: 1, to: 13 })
    expect(editor.commands.aiPictures('selection')).toBe(true)
    expect(editor.commands.aiPictures(14)).toBe(true)
    expect(asked).toEqual([
      { blockId: 'c', mode: 'after', selection: 'Day 1\nDay 2' },
      { blockId: 'i', mode: 'replace', url: asset('old') }
    ])
    // Nothing selected, or no picture there: nothing to ask.
    editor.commands.setTextSelection(3)
    expect(editor.can().aiPictures('selection')).toBe(false)
    expect(editor.can().aiPictures(1)).toBe(false)
    // `can()` never asks.
    expect(asked).toHaveLength(2)
  })

  it('"/" says when pictures need an OpenAI key', () => {
    const type = BLOCK_TYPES.find((b) => b.id === 'aiPictures')
    expect(type?.description()).toBe('Needs an OpenAI key (Settings → AI)')
    setAIModels({ choice: 'auto', auto: 'GPT-6.1 Sol', groups: [], pictures: true })
    expect(type?.description()).toBe('Describe them in the AI panel')
  })

  it('the AI panel offers what it can make, after its actions', () => {
    const onMake = vi.fn()
    render(
      <AIPanel
        onRun={() => {}}
        onCancel={() => {}}
        autoFocus={false}
        makes={['diagram', 'pictures']}
        onMake={onMake}
      />
    )
    expect(screen.getByText('Make')).toBeTruthy()
    fireEvent.click(screen.getByTestId('ai-make-pictures'))
    expect(onMake).toHaveBeenCalledWith('pictures')
    expect(screen.queryByTestId('ai-make-changePicture')).toBeNull()
    cleanup()
    render(<AIPanel onRun={() => {}} onCancel={() => {}} autoFocus={false} />)
    expect(screen.queryByText('Make')).toBeNull()
  })
})
