import { act } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { handleAIEvent, type AIHost, type AIRequestMessage } from '../src/extensions/ai-review'

/** Counts how often an answer's Markdown is drawn (and still draws it). */
const parses = vi.hoisted(() => ({ count: 0 }))
vi.mock('../src/core/convert', async (original) => {
  const actual = await original<typeof import('../src/core/convert')>()
  return {
    ...actual,
    markdownDOM: (...args: Parameters<typeof actual.markdownDOM>) => {
      parses.count++
      return actual.markdownDOM(...args)
    }
  }
})

let host: HTMLElement
let editor: Editor
let requests: AIRequestMessage[]
let ai: AIHost

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  requests = []
  ai = {
    style: () => 'inline',
    request: (message) => requests.push(message),
    cancel: () => {},
    title: () => 'Notes'
  }
  // Blocks with ids (as stored): stamping them would count as a change of the page, which closes the review.
  editor = createEditor(
    host,
    {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          attrs: { id: 'p1' },
          content: [{ type: 'text', text: 'the quick fox' }]
        }
      ]
    },
    { ai }
  )
  editor.commands.setTextSelection({ from: 1, to: 14 })
  editor.commands.aiRun({ id: 'explain' })
  parses.count = 0
})
afterEach(() => {
  editor.destroy()
  host.remove()
  document.querySelectorAll('.hk-ai-review').forEach((el) => el.remove())
})

const nextFrame = () =>
  act(async () => {
    await new Promise((resolve) => requestAnimationFrame(() => resolve(null)))
  })

describe('a streamed AI answer', () => {
  it('is drawn once per frame, however many pieces arrive in it', async () => {
    const id = requests[0].id
    for (let i = 0; i < 100; i++)
      handleAIEvent(editor, ai, { id, type: 'text', delta: `word${i} ` })
    await nextFrame()
    expect(parses.count).toBe(1)
    expect(document.querySelector('[data-testid="ai-answer"]')?.textContent).toContain('word99')
    // The end of the stream draws at once.
    act(() => handleAIEvent(editor, ai, { id, type: 'done' }))
    expect(document.querySelector('[data-testid="ai-review"]')?.textContent).toContain(
      'Insert below'
    )
  })
})
