import type { Editor } from '@tiptap/core'
import { undo } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import type { AIChangeInput, AIChangeStatus } from '../src/core/protocol'
import type { AIChangesHost } from '../src/extensions/ai-changes'
import { pageBlocks } from '../src/lib/ai-content'

let host: HTMLElement
let editor: Editor
let reports: { id: string; status: AIChangeStatus; before?: string; after?: string }[]
let focused: (string | null)[]

const para = (id: string, text: string) => ({
  type: 'paragraph',
  attrs: { id },
  content: [{ type: 'text', text }]
})
const texts = () => {
  const out: string[] = []
  editor.state.doc.descendants((node) => {
    // (The trailing empty line Tiptap keeps after a list at the end left out.)
    if (node.isTextblock && node.textContent) out.push(node.textContent)
    return !node.isTextblock
  })
  return out
}
const change = (
  patch: Partial<AIChangeInput> & Pick<AIChangeInput, 'id' | 'kind'>
): AIChangeInput => ({
  title: '',
  status: 'pending',
  ...patch
})

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  reports = []
  focused = []
  const aiChanges: AIChangesHost = {
    report: (id, status, before, after) => reports.push({ id, status, before, after }),
    focused: (id) => focused.push(id)
  }
  editor = createEditor(
    host,
    {
      type: 'doc',
      content: [
        {
          type: 'heading',
          attrs: { id: 'h', level: 2 },
          content: [{ type: 'text', text: 'Verbs' }]
        },
        para('a', 'He know it.'),
        para('b', 'Second line.'),
        {
          type: 'bulletList',
          content: [
            { type: 'listItem', attrs: { id: 'li1' }, content: [para('i1', 'one')] },
            { type: 'listItem', attrs: { id: 'li2' }, content: [para('i2', 'two')] }
          ]
        }
      ]
    },
    { aiChanges }
  )
})
afterEach(() => {
  editor.destroy()
  host.remove()
  document.querySelectorAll('.hk-ai-change-bar').forEach((el) => el.remove())
})

describe('Ask AI changes to the page', () => {
  it('gives the chat the page as blocks with their ids', () => {
    expect(pageBlocks(editor.state)).toEqual([
      { id: 'h', type: 'heading2', html: 'Verbs' },
      { id: 'a', type: 'paragraph', html: 'He know it.' },
      { id: 'b', type: 'paragraph', html: 'Second line.' },
      { id: 'i1', type: 'bullet', html: 'one' },
      { id: 'i2', type: 'bullet', html: 'two' }
    ])
  })

  it('shows the focused rewrite as tracked changes and approves it as one undo step', () => {
    editor.commands.aiSetChanges([
      change({
        id: 'c1',
        kind: 'rewrite',
        block: 'a',
        html: 'He <strong>knows</strong> it.',
        title: 'knows'
      }),
      change({ id: 'c2', kind: 'delete', block: 'b' })
    ])
    expect(host.querySelectorAll('.hk-ai-change')).toHaveLength(2)
    expect(texts()[1]).toBe('He know it.')

    editor.commands.aiFocusChange('c1')
    expect(focused.at(-1)).toBe('c1')
    expect(host.querySelector('.hk-ai-change.is-focused .hk-ai-ins')?.textContent).toContain(
      'knows'
    )
    expect(document.querySelector('[data-testid="ai-change-bar"]')).not.toBeNull()

    editor.commands.aiResolveChange('c1', 'approve')
    expect(texts()[1]).toBe('He knows it.')
    expect(editor.getJSON().content?.[1].content?.[1].marks?.[0].type).toBe('bold')
    expect(reports[0]).toEqual({
      id: 'c1',
      status: 'approved',
      before: 'He know it.',
      after: 'He knows it.'
    })
    // On to the next one.
    expect(focused.at(-1)).toBe('c2')

    undo(editor.state, editor.view.dispatch)
    expect(texts()[1]).toBe('He know it.')
  })

  it('an answer that has ended brings its first change into view without taking the keyboard', () => {
    const scrolled: Element[] = []
    Element.prototype.scrollIntoView = function () {
      scrolled.push(this)
    }
    const other = document.createElement('input')
    document.body.append(other)
    other.focus()
    editor.commands.aiSetChanges(
      [
        change({ id: 'c1', kind: 'delete', block: 'b' }),
        change({ id: 'c2', kind: 'rewrite', block: 'a', html: 'He knows it.' })
      ],
      { focusFirst: true }
    )
    // The first pending one is shown and scrolled to; the chat's field keeps the keyboard.
    expect(focused.at(-1)).toBe('c1')
    expect(scrolled.at(-1)?.textContent).toBe('Second line.')
    expect(document.activeElement).toBe(other)
    // Offered again (a reload, a verdict reported back), the view stays where it is.
    editor.commands.aiSetChanges([change({ id: 'c3', kind: 'delete', block: 'b' })])
    expect(focused.at(-1)).toBe(null)
    expect(scrolled).toHaveLength(1)
    other.remove()
  })

  it('↵ approves and ⌫ skips the focused change while the caret stays put', () => {
    editor.commands.aiSetChanges([
      change({ id: 'c1', kind: 'delete', block: 'b' }),
      change({ id: 'c2', kind: 'rewrite', block: 'i1', html: 'uno' })
    ])
    editor.commands.aiFocusChange('c1')
    const key = (k: string) =>
      editor.view.someProp('handleKeyDown', (f) =>
        f(editor.view, new KeyboardEvent('keydown', { key: k }))
      )
    expect(key('Backspace')).toBe(true)
    expect(reports[0]).toMatchObject({
      id: 'c1',
      status: 'skipped',
      before: 'Second line.',
      after: ''
    })
    expect(texts()).toContain('Second line.')
    expect(key('Enter')).toBe(true)
    expect(texts()).toContain('uno')
    expect(focused.at(-1)).toBeNull()
    // Nothing focused: the keys are the page's again.
    key('Enter')
    expect(reports).toHaveLength(2)
  })

  it('inserts, moves and deletes blocks — list items as items', () => {
    editor.commands.aiSetChanges([
      change({ id: 'ins', kind: 'insert', after: 'h', type: 'heading3', html: 'Intro' }),
      change({ id: 'item', kind: 'insert', after: 'i1', html: 'one and a half' }),
      change({ id: 'mv', kind: 'move', block: 'b', after: undefined }),
      change({ id: 'del', kind: 'delete', block: 'i2' })
    ])
    expect(editor.commands.aiApproveAllChanges()).toBe(true)
    expect(texts()).toEqual([
      'Second line.',
      'Verbs',
      'Intro',
      'He know it.',
      'one',
      'one and a half'
    ])
    const list = editor.getJSON().content?.find((n) => n.type === 'bulletList')
    expect(list?.content?.map((n) => n.type)).toEqual(['listItem', 'listItem'])
    expect(reports.map((r) => r.status)).toEqual(['approved', 'approved', 'approved', 'approved'])
    // All of it is one undo step.
    undo(editor.state, editor.view.dispatch)
    expect(texts()).toEqual(['Verbs', 'He know it.', 'Second line.', 'one', 'two'])
  })

  it('several inserts after one block keep their reading order, approved in order', () => {
    editor.commands.aiSetChanges([
      change({ id: 'p1', kind: 'insert', after: 'b', type: 'heading3', html: 'Difference' }),
      change({ id: 'p2', kind: 'insert', after: 'b', html: 'First paragraph.' }),
      change({ id: 'p3', kind: 'insert', after: 'b', html: 'Second paragraph.' })
    ])
    editor.commands.aiResolveChange('p1', 'approve')
    editor.commands.aiResolveChange('p2', 'approve')
    editor.commands.aiResolveChange('p3', 'approve')
    expect(texts()).toEqual([
      'Verbs',
      'He know it.',
      'Second line.',
      'Difference',
      'First paragraph.',
      'Second paragraph.',
      'one',
      'two'
    ])
    // Approve all does the same in one step.
    undo(editor.state, editor.view.dispatch)
    undo(editor.state, editor.view.dispatch)
    undo(editor.state, editor.view.dispatch)
    editor.commands.aiSetChanges([
      change({ id: 'q1', kind: 'insert', after: 'b', html: 'A' }),
      change({ id: 'q2', kind: 'insert', after: 'b', html: 'B' }),
      change({ id: 'q3', kind: 'insert', after: 'i2', html: 'three' })
    ])
    editor.commands.aiApproveAllChanges()
    expect(texts()).toEqual([
      'Verbs',
      'He know it.',
      'Second line.',
      'A',
      'B',
      'one',
      'two',
      'three'
    ])
  })

  it('several inserts after one block keep their reading order, approved out of order', () => {
    editor.commands.aiSetChanges([
      change({ id: 'p1', kind: 'insert', after: 'b', html: 'One.' }),
      change({ id: 'p2', kind: 'insert', after: 'b', html: 'Two.' }),
      change({ id: 'p3', kind: 'insert', after: 'b', html: 'Three.' })
    ])
    // The first skipped: the second goes straight after the block.
    editor.commands.aiResolveChange('p1', 'skip')
    editor.commands.aiResolveChange('p3', 'approve')
    expect(texts().slice(2, 4)).toEqual(['Second line.', 'Three.'])
    // Its ghost shows where the second will go: between the block and the third.
    editor.commands.aiFocusChange('p2')
    const ghost = host.querySelector('.hk-ai-ghost')
    expect(ghost?.textContent).toBe('Two.')
    expect(ghost?.previousElementSibling?.textContent).toBe('Second line.')
    expect(ghost?.nextElementSibling?.textContent).toBe('Three.')
    editor.commands.aiResolveChange('p2', 'approve')
    expect(texts()).toEqual([
      'Verbs',
      'He know it.',
      'Second line.',
      'Two.',
      'Three.',
      'one',
      'two'
    ])
    // Each inserted block carries an id of its own.
    const ids = editor
      .getJSON()
      .content?.slice(3, 5)
      .map((n) => n.attrs?.id as string | null)
    expect(ids?.every(Boolean)).toBe(true)
    expect(ids?.[0]).not.toBe(ids?.[1])
  })

  it("an insert's ghost shows its line breaks and marks as Approve will insert them", () => {
    editor.commands.aiSetChanges([
      change({
        id: 'p1',
        kind: 'insert',
        after: 'b',
        html: '<strong>ている</strong>: a state<br>ているところ: <em>right now</em>'
      })
    ])
    editor.commands.aiFocusChange('p1')
    const ghost = host.querySelector('.hk-ai-ghost')
    expect(ghost?.querySelector('br')).not.toBeNull()
    expect(ghost?.querySelector('strong')?.textContent).toBe('ている')
    expect(ghost?.querySelector('em')?.textContent).toBe('right now')
    editor.commands.aiResolveChange('p1', 'approve')
    expect(reports[0]).toMatchObject({
      status: 'approved',
      after: 'ている: a state\nているところ: right now'
    })
    const added = editor.getJSON().content?.[3]
    expect(added?.content?.some((n) => n.type === 'hardBreak')).toBe(true)
  })

  it('a change whose block is edited goes stale, the others stay', () => {
    editor.commands.aiSetChanges([
      change({ id: 'c1', kind: 'rewrite', block: 'a', html: 'He knows it.' }),
      change({ id: 'c2', kind: 'rewrite', block: 'b', html: 'Line two.' })
    ])
    editor.commands.insertContentAt(2 + 'Verbs'.length + 2, 'Oh, ')
    return Promise.resolve().then(() => {
      expect(reports).toEqual([{ id: 'c1', status: 'stale', before: undefined, after: undefined }])
      expect(host.querySelectorAll('.hk-ai-change')).toHaveLength(1)
    })
  })

  it('a change naming a block the page no longer has is stale at once', () => {
    editor.commands.aiSetChanges([change({ id: 'c1', kind: 'rewrite', block: 'gone', html: 'x' })])
    expect(reports).toEqual([{ id: 'c1', status: 'stale', before: undefined, after: undefined }])
  })

  it('Edit approves and leaves the caret in the block', () => {
    editor.commands.aiSetChanges([
      change({ id: 'c1', kind: 'rewrite', block: 'a', html: 'He knows it.' })
    ])
    editor.commands.aiFocusChange('c1')
    editor.commands.aiResolveChange('c1', 'edit')
    expect(reports[0].status).toBe('edited')
    const { $from } = editor.state.selection
    expect($from.parent.attrs.id).toBe('a')
    expect($from.parentOffset).toBe('He knows it.'.length)
  })
})
