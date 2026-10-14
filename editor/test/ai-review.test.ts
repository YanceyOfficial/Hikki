import type { Editor } from '@tiptap/core'
import { undo } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import type { AIStreamEvent } from '../src/core/protocol'
import {
  aiReviewOpen,
  handleAIEvent,
  type AIHost,
  type AIRequestMessage
} from '../src/extensions/ai-review'

let host: HTMLElement
let editor: Editor
let requests: AIRequestMessage[]
let cancelled: string[]
let ai: AIHost

const text = () => editor.state.doc.textContent
type Unsent<T> = T extends unknown ? Omit<T, 'id'> : never
const send = (event: Unsent<AIStreamEvent>) =>
  handleAIEvent(editor, ai, { id: requests.at(-1)!.id, ...event } as AIStreamEvent)
const reply = (blocks: Record<string, string>) =>
  JSON.stringify({ blocks: Object.entries(blocks).map(([id, html]) => ({ id, html })) })

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  requests = []
  cancelled = []
  ai = {
    request: (message) => requests.push(message),
    cancel: (id) => cancelled.push(id),
    title: () => 'Notes'
  }
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
})
afterEach(() => {
  editor.destroy()
  host.remove()
  document.querySelectorAll('.hk-ai-review').forEach((el) => el.remove())
})

describe('AI review (style A)', () => {
  it('asks with the selection and context, and shows it working', () => {
    expect(editor.commands.aiRun({ id: 'improve' })).toBe(true)
    expect(requests).toHaveLength(1)
    expect(requests[0]).toMatchObject({
      action: 'improve',
      answer: false,
      units: [{ key: 'p1:0', html: 'the quick fox' }],
      context: { title: 'Notes' }
    })
    expect(aiReviewOpen(editor)).toBe(true)
    expect(host.querySelector('.hk-ai-thinking')).not.toBeNull()
  })

  it('draws the edit in the page and accepts it as one undo step', () => {
    editor.commands.aiRun({ id: 'improve' })
    const answer = reply({ 'p1:0': 'the fast fox' })
    send({ type: 'text', delta: answer.slice(0, 10) })
    send({ type: 'text', delta: answer.slice(10) })
    send({ type: 'done' })
    expect(host.querySelector('.hk-ai-del')?.textContent).toBe('quick ')
    expect(host.querySelector('.hk-ai-ins')?.textContent).toBe('fast ')
    expect(text()).toBe('the quick fox')

    expect(editor.commands.aiAccept()).toBe(true)
    expect(text()).toBe('the fast fox')
    expect(aiReviewOpen(editor)).toBe(false)
    expect(host.querySelector('.hk-ai-del, .hk-ai-ins')).toBeNull()
    undo(editor.state, editor.view.dispatch)
    expect(text()).toBe('the quick fox')
  })

  it('turns an unreadable reply into an error, never an edit', () => {
    editor.commands.aiRun({ id: 'fix' })
    send({ type: 'text', delta: 'Sorry, I can’t help with that.' })
    send({ type: 'done' })
    expect(editor.commands.aiAccept()).toBe(false)
    expect(document.querySelector('[data-testid="ai-review"]')?.textContent).toContain(
      'couldn’t be read'
    )
    expect(text()).toBe('the quick fox')
  })

  it('keeps only web citations from the model', () => {
    editor.commands.aiRun({ id: 'explain' })
    expect(requests[0].answer).toBe(true)
    send({ type: 'citation', url: 'javascript:alert(1)' })
    send({ type: 'citation', url: 'not a url' })
    send({ type: 'citation', url: 'https://example.com/a', title: 'A' })
    send({ type: 'text', delta: 'An animal.' })
    send({ type: 'done' })
    const links = [...document.querySelectorAll('[data-testid="ai-review"] a')]
    expect(links.map((a) => a.getAttribute('href'))).toEqual(['https://example.com/a'])
  })

  it('closes (and cancels) when the page changes, and ignores stale events', async () => {
    editor.commands.aiRun({ id: 'improve' })
    const id = requests[0].id
    editor.commands.insertContentAt(1, 'x')
    await Promise.resolve()
    expect(aiReviewOpen(editor)).toBe(false)
    expect(cancelled).toEqual([id])
    send({ type: 'text', delta: reply({ 'p1:0': 'gone' }) })
    send({ type: 'done' })
    expect(aiReviewOpen(editor)).toBe(false)
  })

  it('a follow-up on an answer stays an answer, about the same text', async () => {
    editor.commands.aiRun({ id: 'explain' })
    send({ type: 'text', delta: 'Foxes are quick.' })
    send({ type: 'done' })
    // The selection moves away meanwhile: the follow-up is still about the first text.
    editor.commands.setTextSelection(1)
    const input = document.querySelector<HTMLInputElement>('[data-testid="ai-review"] input')!
    const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!
    setValue.call(input, 'Why?')
    input.dispatchEvent(new Event('input', { bubbles: true }))
    await new Promise((resolve) => setTimeout(resolve, 0))
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    expect(requests).toHaveLength(2)
    expect(requests[1]).toMatchObject({
      action: 'ask',
      instruction: 'Why?',
      answer: true,
      units: [{ key: 'p1:0' }],
      context: { previous: 'Foxes are quick.' }
    })
  })
})
