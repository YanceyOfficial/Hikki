import { act, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { EditorBridge, type Transport } from '../src/core/bridge'
import type { ToNativeMessage } from '../src/core/protocol'
import { doc, page } from './helpers'

type FindState = Extract<ToNativeMessage, { type: 'findState' }>
type MathSheet = Extract<ToNativeMessage, { type: 'mathSheet' }>

const inline = (latex: string) => ({
  type: 'doc',
  content: [
    {
      type: 'paragraph',
      content: [
        { type: 'text', text: 'see ' },
        { type: 'inlineMath', attrs: { latex } }
      ]
    }
  ]
})

let sent: ToNativeMessage[]
let bridge: EditorBridge
let host: HTMLElement

beforeEach(() => {
  sent = []
  const transport: Transport = {
    post: async (m) => {
      sent.push(m)
      return null
    }
  }
  host = document.createElement('div')
  document.body.append(host)
  bridge = new EditorBridge(host, transport, { debounceMs: 400 })
})
afterEach(() => {
  bridge.setNativeFind(false)
  bridge.setNativeMath(false)
  host.remove()
})

const editor = () => (bridge as any).editor as import('@tiptap/core').Editor | null
const findStates = () => sent.filter((m): m is FindState => m.type === 'findState')
const lastFind = () => findStates().at(-1)!
const mathSheets = () => sent.filter((m): m is MathSheet => m.type === 'mathSheet')
const formula = () => host.querySelector('[data-type="inline-math"]')?.getAttribute('data-latex')

describe('find with a native bar (ISSUE-225)', () => {
  it('reports the search instead of showing the panel, and the bar drives it', async () => {
    bridge.setNativeFind(true)
    bridge.loadDocument(page('a', { content: doc('apple pie', 'Apple tart', 'banana') }))
    const scrolled = vi.fn()
    Element.prototype.scrollIntoView = scrolled

    expect(bridge.find('find')).toBe(true)
    expect(lastFind()).toMatchObject({ docId: 'a', open: true, replace: false, term: '', count: 0 })
    // The page's own panel stays shut.
    expect(screen.queryByPlaceholderText('Find')).toBeNull()

    expect(bridge.findSet({ term: 'apple' })).toBe(true)
    await waitFor(() => expect(lastFind()).toMatchObject({ term: 'apple', count: 2, current: 0 }))
    expect(host.querySelectorAll('.find-and-replace-result')).toHaveLength(2)
    // A new term's first match is brought into view; stepping brings the next.
    expect(scrolled).toHaveBeenCalledTimes(1)
    expect(bridge.findStep(1)).toBe(true)
    expect(lastFind()).toMatchObject({ count: 2, current: 1 })
    expect(scrolled).toHaveBeenCalledTimes(2)
    expect(bridge.findStep(-1)).toBe(true)
    expect(lastFind()).toMatchObject({ current: 0 })

    // Options: match case leaves the capitalised one out.
    bridge.findSet({ caseSensitive: true })
    expect(lastFind()).toMatchObject({ caseSensitive: true, count: 1, current: 0 })

    // Replace is an ordinary edit.
    bridge.findSet({ replace: true, replaceTerm: 'pear' })
    expect(lastFind()).toMatchObject({ replace: true, replaceTerm: 'pear' })
    expect(bridge.findReplace(false)).toBe(true)
    expect(editor()?.getText()).toContain('pear pie')
    expect(lastFind()).toMatchObject({ count: 0, current: null })

    // Nothing is sent twice: the same state again is no message.
    const before = findStates().length
    bridge.findSet({ caseSensitive: true })
    expect(findStates().length).toBe(before)

    bridge.find('close')
    expect(lastFind()).toMatchObject({ open: false, term: '', count: 0, current: null })
    expect(host.querySelectorAll('.find-and-replace-result')).toHaveLength(0)
  })

  it('refuses a replace on a locked page, and a page switch closes the bar', async () => {
    bridge.setNativeFind(true)
    bridge.loadDocument(page('a', { content: doc('apple pie'), locked: true }))
    bridge.find('find')
    bridge.findSet({ term: 'apple', replaceTerm: 'pear' })
    await waitFor(() => expect(lastFind()).toMatchObject({ count: 1 }))
    expect(bridge.findReplace(false)).toBe(false)
    expect(editor()?.getText()).toContain('apple pie')

    bridge.loadDocument(page('b', { content: doc('other') }))
    expect(lastFind()).toMatchObject({ open: false })
  })

  it('shows the panel again once the native bar is off', async () => {
    bridge.setNativeFind(true)
    bridge.loadDocument(page('a', { content: doc('apple pie') }))
    bridge.setNativeFind(false)
    bridge.find('find')
    expect(await screen.findByPlaceholderText('Find')).toBeTruthy()
    expect(findStates()).toHaveLength(0)
  })
})

describe('formulas in a native sheet (ISSUE-225)', () => {
  it('asks for the sheet, previews its typing outside undo, and takes Done as the edit', async () => {
    bridge.setNativeMath(true)
    bridge.loadDocument(page('a', { content: inline('x^2') }))
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    expect(document.querySelector('.hk-math-editor')).toBeNull()
    const request = mathSheets().at(-1)!
    expect(request).toMatchObject({ docId: 'a', latex: 'x^2', kind: 'inline' })

    expect(bridge.previewMath(request.id, 'y_1')).toBe(true)
    expect(formula()).toBe('y_1')
    // A preview is neither an undo step nor a save.
    expect(editor()?.can().undo()).toBe(false)
    expect(sent.filter((m) => m.type === 'changed')).toHaveLength(0)

    // Done with the text already previewed is still the edit: undoable and saved (it was a no-op before, and the
    // page file kept the formula as it was).
    expect(bridge.applyMath(request.id, 'y_1')).toBe(true)
    expect(formula()).toBe('y_1')
    expect(editor()?.can().undo()).toBe(true)
    await waitFor(() => expect(sent.filter((m) => m.type === 'changed')).toHaveLength(1))
    // The opening is over: a late answer is refused.
    expect(bridge.applyMath(request.id, 'w')).toBe(false)
    expect(bridge.previewMath(request.id, 'w')).toBe(false)
    expect(formula()).toBe('y_1')
  })

  it('Cancel puts the formula back; an emptied one is removed', () => {
    bridge.setNativeMath(true)
    bridge.loadDocument(page('a', { content: inline('x^2') }))
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    const first = mathSheets().at(-1)!
    bridge.previewMath(first.id, 'y')
    expect(formula()).toBe('y')
    expect(bridge.applyMath(first.id, null)).toBe(true)
    expect(formula()).toBe('x^2')
    expect(editor()?.can().undo()).toBe(false)

    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    const second = mathSheets().at(-1)!
    expect(second.id).not.toBe(first.id)
    expect(bridge.applyMath(second.id, '')).toBe(true)
    expect(host.querySelector('[data-type="inline-math"]')).toBeNull()
  })

  it('a formula just inserted goes away again when its sheet is cancelled', () => {
    bridge.setNativeMath(true)
    bridge.loadDocument(page('a', { content: inline('') }))
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    const request = mathSheets().at(-1)!
    expect(bridge.applyMath(request.id, null)).toBe(true)
    expect(host.querySelector('[data-type="inline-math"]')).toBeNull()
  })

  it('opens the page panel instead once the native sheet is off', async () => {
    bridge.setNativeMath(true)
    bridge.loadDocument(page('a', { content: inline('x^2') }))
    bridge.setNativeMath(false)
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    expect(await screen.findByLabelText('Formula (LaTeX)')).toBeTruthy()
    expect(mathSheets()).toHaveLength(0)
  })
})
