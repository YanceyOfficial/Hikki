import type { Editor } from '@tiptap/core'
import { undo } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import type { AIStreamEvent } from '../src/core/protocol'
import {
  aiReviewOpen,
  revealBelow,
  handleAIEvent,
  type AIHost,
  type AIReviewStyle,
  type AIRequestMessage
} from '../src/extensions/ai-review'
import { SelectionMenuKey } from '../src/extensions/selection-menu'

let host: HTMLElement
let editor: Editor
let requests: AIRequestMessage[]
let cancelled: string[]
let ai: AIHost
let style: AIReviewStyle

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
  style = 'inline'
  ai = {
    style: () => style,
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

  it('style B shows the edit as before/after lines in the bar, not in the page', () => {
    style = 'diff'
    editor.commands.aiRun({ id: 'improve' })
    expect(requests[0].explain).toBeUndefined()
    send({ type: 'text', delta: reply({ 'p1:0': 'the fast fox' }) })
    send({ type: 'done' })
    expect(host.querySelector('.hk-ai-del, .hk-ai-ins')).toBeNull()
    expect(host.querySelector('.hk-ai-subject')).not.toBeNull()
    const diff = document.querySelector('[data-testid="ai-review-diff"]')!
    expect([...diff.querySelectorAll('mark')].map((m) => m.textContent)).toEqual([
      'quick ',
      'fast '
    ])
    expect(editor.commands.aiAccept()).toBe(true)
    expect(text()).toBe('the fast fox')
  })

  it('style C asks for reasons and lists each change with its reason', () => {
    style = 'bubble'
    editor.commands.aiRun({ id: 'improve' })
    expect(requests[0].explain).toBe(true)
    send({
      type: 'text',
      delta: JSON.stringify({
        blocks: [{ id: 'p1:0', html: 'the fast fox' }],
        notes: [{ from: 'quick', to: 'fast', why: 'shorter word' }, { why: 'no change named' }]
      })
    })
    send({ type: 'done' })
    expect(host.querySelector('.hk-ai-del, .hk-ai-ins')).toBeNull()
    const items = [...document.querySelectorAll('[data-testid="ai-review-bubble"] li')]
    expect(items.map((li) => li.textContent)).toEqual(['quickfast· shorter word'])
    document.querySelector<HTMLButtonElement>('[data-testid="ai-accept"]')!.click()
    expect(text()).toBe('the fast fox')
  })

  it('style C without notes lists the changes from the diff', () => {
    style = 'bubble'
    editor.commands.aiRun({ id: 'improve' })
    send({ type: 'text', delta: reply({ 'p1:0': 'the fast fox' }) })
    send({ type: 'done' })
    const items = [...document.querySelectorAll('[data-testid="ai-review-bubble"] li')]
    expect(items.map((li) => li.textContent)).toEqual(['quick fast '])
  })

  it('hides the formatting menu and marks the range itself while AI holds it', () => {
    const metas: unknown[] = []
    editor.on('transaction', ({ transaction }) => metas.push(transaction.getMeta(SelectionMenuKey)))
    editor.commands.aiRun({ id: 'improve' })
    expect(metas).toContain('hide')
    expect(editor.view.dom.classList.contains('hk-ai-open')).toBe(true)
    send({ type: 'text', delta: reply({ 'p1:0': 'the fast fox' }) })
    send({ type: 'done' })
    // Style A: the range stays marked under the changes.
    expect(host.querySelector('.hk-ai-subject')).not.toBeNull()
    editor.commands.aiDiscard()
    expect(editor.view.dom.classList.contains('hk-ai-open')).toBe(false)
  })

  it('scrolls the page just enough to show a bar below the window', () => {
    const calls: ScrollToOptions[] = []
    const original = window.scrollBy
    window.scrollBy = ((options: ScrollToOptions) =>
      void calls.push(options)) as typeof window.scrollBy
    const bar = document.createElement('div')
    document.body.append(bar)
    bar.getBoundingClientRect = () => new DOMRect(0, 0, 100, 150)
    // The selection ends 50px above the window's bottom: the 150px bar needs 100 more, plus the margin.
    revealBelow(bar, window.innerHeight - 50)
    expect(calls[0]?.top).toBe(100 + 24)
    revealBelow(bar, 10)
    expect(calls).toHaveLength(1)
    window.scrollBy = original
    bar.remove()
  })
})
