import type { Editor } from '@tiptap/core'
import { undo } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { installErrorForwarding } from '../src/core/errors'
import type { AIStreamEvent, ToNativeMessage } from '../src/core/protocol'
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
let handoffs: { instruction: string; selection: string }[]

const text = () => editor.state.doc.textContent
type Unsent<T> = T extends unknown ? Omit<T, 'id'> : never
const send = (event: Unsent<AIStreamEvent>) =>
  handleAIEvent(editor, ai, { id: requests.at(-1)!.id, ...event } as AIStreamEvent)
const reply = (
  blocks: Record<string, string>,
  notes?: string[],
  added?: { type: string; html: string }[]
) =>
  JSON.stringify({
    blocks: Object.entries(blocks).map(([id, html]) => ({ id, html })),
    ...(notes ? { notes } : {}),
    ...(added ? { added } : {})
  })
const review = () => document.querySelector<HTMLElement>('[data-testid="ai-review"]')
const button = (label: string) =>
  [...(review()?.querySelectorAll('button') ?? [])].find((b) => b.textContent?.includes(label)) as
    | HTMLButtonElement
    | undefined
const tick = () =>
  new Promise<void>((resolve) => {
    setTimeout(resolve, 0)
  })
const inserts = () => [
  ...document.querySelectorAll<HTMLButtonElement>('[data-testid="ai-note-insert"]')
]

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  requests = []
  cancelled = []
  handoffs = []
  style = 'inline'
  ai = {
    style: () => style,
    handoff: (request) => handoffs.push(request),
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

  it('a model picked for the request goes with it, and with its follow-ups', async () => {
    editor.commands.aiRun({ id: 'explain', model: 'claude-opus-5-5' })
    expect(requests[0]).toMatchObject({ action: 'explain', model: 'claude-opus-5-5' })
    send({ type: 'text', delta: 'Foxes are quick.' })
    send({ type: 'done' })
    const input = document.querySelector<HTMLInputElement>('[data-testid="ai-review"] input')!
    const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!
    setValue.call(input, 'Why?')
    input.dispatchEvent(new Event('input', { bubbles: true }))
    await tick()
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    expect(requests[1]).toMatchObject({ action: 'ask', model: 'claude-opus-5-5' })
    editor.commands.aiRun({ id: 'improve' })
    expect(requests[2]).not.toHaveProperty('model')
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

  it('puts what the model says in a card under the edit, never into it, and keeps it past Accept', async () => {
    editor.commands.aiRun({ id: 'custom', instruction: 'Fix it and tell me why' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the fast fox' }, ['“fast” is the **plainer** word.'])
    })
    send({ type: 'done' })
    // The edit in the page, the note in its card (drawn as Markdown).
    expect(host.querySelector('.hk-ai-ins')?.textContent).toBe('fast ')
    const card = document.querySelector('[data-testid="ai-notes"]')!
    expect(card.querySelector('strong')?.textContent).toBe('plainer')
    expect(document.querySelector('[data-testid="ai-accept"]')).not.toBeNull()

    document.querySelector<HTMLButtonElement>('[data-testid="ai-accept"]')!.click()
    expect(text()).toBe('the fast fox')
    await tick()
    // Accepted: the notes stay (nothing left to accept), and closing them leaves the page as it is.
    expect(aiReviewOpen(editor)).toBe(true)
    expect(document.querySelector('[data-testid="ai-accept"]')).toBeNull()
    expect(document.querySelector('[data-testid="ai-notes"]')?.textContent).toContain('plainer')
    expect(button('Retry')).toBeUndefined()
    document.querySelector<HTMLButtonElement>('[data-testid="ai-close"]')!.click()
    expect(aiReviewOpen(editor)).toBe(false)
    expect(text()).toBe('the fast fox')
  })

  it('style B shows the notes card under the diff too', () => {
    style = 'diff'
    editor.commands.aiRun({ id: 'custom', instruction: 'Fix and explain' })
    send({ type: 'text', delta: reply({ 'p1:0': 'the fast fox' }, ['Shorter.']) })
    send({ type: 'done' })
    expect(document.querySelector('[data-testid="ai-review-diff"]')).not.toBeNull()
    expect(document.querySelector('[data-testid="ai-notes"]')?.textContent).toContain('Shorter.')
  })

  it('a check that changes nothing shows its verdict alone, not "Nothing to change"', () => {
    editor.commands.aiRun({ id: 'custom', instruction: 'Check the grammar' })
    // Some models drop the unchanged blocks altogether.
    send({
      type: 'text',
      delta: JSON.stringify({ blocks: [], notes: ['The grammar is correct.'] })
    })
    send({ type: 'done' })
    expect(review()?.textContent).not.toContain('Nothing to change')
    expect(document.querySelector('[data-testid="ai-notes"]')?.textContent).toContain(
      'The grammar is correct.'
    )
    expect(document.querySelector('[data-testid="ai-accept"]')).toBeNull()
    expect(editor.commands.aiAccept()).toBe(false)
    expect(button('Retry')).toBeDefined()
  })

  it('inserts a note below the selection as blocks, keeping the edit under review', async () => {
    editor.commands.aiRun({ id: 'custom', instruction: 'Translate and comment' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the fast fox' }, ['- first remark', '- second remark'])
    })
    send({ type: 'done' })
    inserts()[1].click()
    await tick()
    inserts()[0].click()
    await tick()
    // In the order inserted, after the selection's block; each button now says so.
    // (The page keeps an empty paragraph at its end.)
    expect(editor.getJSON().content?.map((node) => node.type)).toEqual([
      'paragraph',
      'bulletList',
      'bulletList',
      'paragraph'
    ])
    expect(inserts().every((b) => b.disabled && b.textContent?.includes('Inserted'))).toBe(true)
    // The edit is still there to accept, and accepting it doesn't insert anything more.
    expect(aiReviewOpen(editor)).toBe(true)
    expect(host.querySelector('.hk-ai-ins')?.textContent).toBe('fast ')
    expect(editor.commands.aiAccept()).toBe(true)
    expect(editor.state.doc.child(0).textContent).toBe('the fast fox')
    expect(editor.state.doc.childCount).toBe(4)
    expect(editor.state.doc.child(1).textContent).toBe('second remark')
    expect(editor.state.doc.child(2).textContent).toBe('first remark')
  })

  it('shows the blocks the model adds as ghosts after the selection and accepts them with the edit in one step', () => {
    editor.commands.aiRun({ id: 'custom', instruction: '在文末补充说明和例句' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the fast fox' }, undefined, [
        { type: 'heading2', html: 'Explanation' },
        { type: 'paragraph', html: 'A <strong>bold</strong> start<br>and a second line' },
        { type: 'bullet', html: 'one' },
        { type: 'bullet', html: 'two' },
        { type: 'numbered', html: 'first' },
        { type: 'quote', html: 'said <script>alert(1)</script>so' }
      ])
    })
    send({ type: 'done' })
    // Ghosts in the page, after the paragraph, with their marks and breaks (never flat text) and their kind.
    const ghosts = [...host.querySelectorAll<HTMLElement>('.hk-ai-ghost')]
    expect(ghosts).toHaveLength(6)
    expect(ghosts[0].dataset.level).toBe('2')
    expect(ghosts[0].textContent).toBe('Explanation')
    expect(ghosts[1].querySelector('strong')?.textContent).toBe('bold')
    expect(ghosts[1].querySelector('br')).not.toBeNull()
    expect(ghosts[2].dataset.marker).toBe('•')
    expect(ghosts[4].dataset.marker).toBe('1.')
    expect(ghosts[5].dataset.kind).toBe('quote')
    expect(ghosts[5].querySelector('script')).toBeNull()
    expect(ghosts[0].compareDocumentPosition(host.querySelector('p')!)).toBe(
      Node.DOCUMENT_POSITION_PRECEDING
    )
    // The bar counts them: one change in the text and six blocks.
    expect(review()?.textContent).toContain('7 changes')
    expect(text()).toBe('the quick fox')

    expect(editor.commands.aiAccept()).toBe(true)
    expect(editor.getJSON().content?.map((node) => node.type)).toEqual([
      'paragraph',
      'heading',
      'paragraph',
      'bulletList',
      'orderedList',
      'blockquote',
      'paragraph'
    ])
    const doc = editor.state.doc
    expect(doc.child(0).textContent).toBe('the fast fox')
    expect(doc.child(1).attrs.level).toBe(2)
    expect(doc.child(2).toJSON().content).toEqual([
      { type: 'text', text: 'A ' },
      { type: 'text', text: 'bold', marks: [{ type: 'bold' }] },
      { type: 'text', text: ' start' },
      { type: 'hardBreak' },
      { type: 'text', text: 'and a second line' }
    ])
    expect(doc.child(3).childCount).toBe(2)
    expect(doc.child(5).textContent).toBe('said so')
    expect(aiReviewOpen(editor)).toBe(false)
    expect(host.querySelector('.hk-ai-ghost')).toBeNull()
    // One undo takes the edit and the added blocks together.
    undo(editor.state, editor.view.dispatch)
    expect(text()).toBe('the quick fox')
    expect(editor.state.doc.childCount).toBe(1)
  })

  it('added blocks alone are a review too, and a preset’s reply may not add any', () => {
    editor.commands.aiRun({ id: 'custom', instruction: 'Add an example' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the quick fox' }, undefined, [
        { type: 'paragraph', html: 'Example.' }
      ])
    })
    send({ type: 'done' })
    expect(host.querySelectorAll('.hk-ai-ghost')).toHaveLength(1)
    expect(review()?.textContent).toContain('1 change')
    expect(document.querySelector('[data-testid="ai-accept"]')).not.toBeNull()
    expect(editor.commands.aiAccept()).toBe(true)
    expect(editor.state.doc.child(1).textContent).toBe('Example.')

    editor.commands.setTextSelection({ from: 1, to: 14 })
    editor.commands.aiRun({ id: 'improve' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the quick fox' }, undefined, [
        { type: 'paragraph', html: 'Sneaked in.' }
      ])
    })
    send({ type: 'done' })
    expect(host.querySelector('.hk-ai-ghost')).toBeNull()
    expect(review()?.textContent).toContain('Nothing to change')
    expect(editor.commands.aiAccept()).toBe(false)
  })

  it('a note inserted after accepting lands below the added blocks', async () => {
    editor.commands.aiRun({ id: 'custom', instruction: 'Add an example and tell me why' })
    send({
      type: 'text',
      delta: reply(
        { 'p1:0': 'the fast fox' },
        ['Because.'],
        [{ type: 'paragraph', html: 'Example.' }]
      )
    })
    send({ type: 'done' })
    document.querySelector<HTMLButtonElement>('[data-testid="ai-accept"]')!.click()
    await tick()
    inserts()[0].click()
    await tick()
    expect(editor.state.doc.child(0).textContent).toBe('the fast fox')
    expect(editor.state.doc.child(1).textContent).toBe('Example.')
    expect(editor.state.doc.child(2).textContent).toBe('Because.')
  })

  it('style B lists the added blocks as + lines after the selection’s', () => {
    style = 'diff'
    editor.commands.aiRun({ id: 'custom', instruction: 'Add two examples' })
    send({
      type: 'text',
      delta: reply({ 'p1:0': 'the fast fox' }, undefined, [
        { type: 'paragraph', html: 'One <em>example</em>.' },
        { type: 'heading3', html: 'More' }
      ])
    })
    send({ type: 'done' })
    expect(host.querySelector('.hk-ai-ghost')).toBeNull()
    const diff = document.querySelector('[data-testid="ai-review-diff"]')!
    const added = [...diff.querySelectorAll('[data-testid="ai-review-added"]')]
    expect(added.map((row) => row.textContent)).toEqual(['+One example.', '+More'])
    expect(diff.textContent).toContain('3 changes in 1 of 1 lines')
    expect(diff.textContent).toContain('2 new blocks below')
    expect(editor.commands.aiAccept()).toBe(true)
    expect(editor.state.doc.child(1).textContent).toBe('One example.')
    expect(editor.state.doc.child(2).type.name).toBe('heading')
  })

  it('copies a note’s Markdown with one click', async () => {
    const copied: string[] = []
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: (value: string) => (copied.push(value), Promise.resolve()) }
    })
    editor.commands.aiRun({ id: 'custom', instruction: 'Check it' })
    send({ type: 'text', delta: reply({ 'p1:0': 'the quick fox' }, ['Correct: *fine*.']) })
    send({ type: 'done' })
    button('Copy')!.click()
    expect(copied).toEqual(['Correct: *fine*.'])
    await tick()
    expect(button('Copied')).toBeDefined()
  })

  it('a copy the clipboard refuses is reported, not swallowed', async () => {
    const reports: ToNativeMessage[] = []
    const quiet = Object.assign(new EventTarget(), {
      console: { ...console, warn: () => {}, error: () => {} }
    }) as unknown as Window & typeof globalThis
    installErrorForwarding({ post: (m) => Promise.resolve(void reports.push(m)) }, quiet)
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: () => Promise.reject(new Error('denied')) }
    })
    editor.commands.aiRun({ id: 'custom', instruction: 'Check it' })
    send({ type: 'text', delta: reply({ 'p1:0': 'the quick fox' }, ['Correct: *fine*.']) })
    send({ type: 'done' })
    button('Copy')!.click()
    await tick()
    expect(reports).toContainEqual(expect.objectContaining({ type: 'reportError', code: 3004 }))
  })

  it('hands a request in the user’s words to the chat when the model says so', () => {
    editor.commands.aiRun({ id: 'custom', instruction: '  Research this and write a report  ' })
    send({ type: 'text', delta: '{"handoff":{"reason":"research"}}' })
    send({ type: 'done' })
    expect(handoffs).toEqual([
      { instruction: 'Research this and write a report', selection: 'the quick fox' }
    ])
    expect(aiReviewOpen(editor)).toBe(false)
    expect(review()).toBeNull()
    expect(cancelled).toEqual([])
    expect(text()).toBe('the quick fox')
  })

  it('holds back a question’s answer while it may be a handoff', () => {
    editor.commands.aiRun({ id: 'ask', instruction: 'Plan a whole course around this' })
    send({ type: 'text', delta: '{"hand' })
    expect(document.querySelector('[data-testid="ai-answer"]')).toBeNull()
    send({ type: 'text', delta: 'off":{}}' })
    send({ type: 'done' })
    expect(handoffs).toHaveLength(1)

    // A plain answer streams as before.
    editor.commands.setTextSelection({ from: 1, to: 14 })
    editor.commands.aiRun({ id: 'ask', instruction: 'What is it?' })
    send({ type: 'text', delta: 'An animal.' })
    send({ type: 'done' })
    expect(handoffs).toHaveLength(1)
    expect(document.querySelector('[data-testid="ai-answer"]')?.textContent).toBe('An animal.')
  })

  it('never hands off a preset, nor without a chat to hand to', () => {
    editor.commands.aiRun({ id: 'improve' })
    send({ type: 'text', delta: '{"handoff":{}}' })
    send({ type: 'done' })
    expect(handoffs).toEqual([])
    expect(review()?.textContent).toContain('couldn’t be read')

    delete ai.handoff
    editor.commands.aiRun({ id: 'custom', instruction: 'Write a book' })
    send({ type: 'text', delta: '{"handoff":{}}' })
    send({ type: 'done' })
    expect(handoffs).toEqual([])
    expect(review()?.textContent).toContain('couldn’t be read')
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

  it('draws an answer as page blocks and inserts it below as blocks, without media or unsafe links', () => {
    editor.commands.aiRun({ id: 'explain' })
    send({
      type: 'text',
      delta:
        '## Two uses\n\n- **Hearsay**: plain form\n- *Appearance*: stem\n\n![x](https://tracker.example/p.png) [bad](javascript:alert(1)) [ok](https://example.com)'
    })
    send({ type: 'done' })
    const card = document.querySelector('[data-testid="ai-answer"]')!
    expect(card.querySelector('h2')?.textContent).toBe('Two uses')
    expect([...card.querySelectorAll('li')].map((li) => li.textContent)).toEqual([
      'Hearsay: plain form',
      'Appearance: stem'
    ])
    expect(card.querySelector('strong')?.textContent).toBe('Hearsay')
    expect(card.querySelector('img')).toBeNull()
    expect([...card.querySelectorAll('a')].map((a) => a.getAttribute('href'))).toEqual([
      'https://example.com'
    ])

    const insert = [...document.querySelectorAll('[data-testid="ai-review"] button')].find((b) =>
      b.textContent?.includes('Insert below')
    ) as HTMLButtonElement
    insert.click()
    const types = editor.getJSON().content?.map((node) => node.type)
    expect(types).toEqual(['paragraph', 'heading', 'bulletList', 'paragraph'])
  })
})
