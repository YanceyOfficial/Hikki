import { act, cleanup, fireEvent, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { EditorBridge } from '../src/bridge'
import { createEditor } from '../src/editor'
import { findShortcut, runFind } from '../src/extensions/find'
import { doc, page, settle } from './helpers'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  cleanup()
  editor?.destroy()
  host.remove()
})

const key = (init: KeyboardEventInit) => new KeyboardEvent('keydown', init)

describe('find shortcuts', () => {
  it('map ⌘F, ⌥⌘F, ⌘G and ⇧⌘G by key code (⌥ changes the key on macOS)', () => {
    expect(findShortcut(key({ metaKey: true, code: 'KeyF', key: 'f' }))).toBe('find')
    expect(findShortcut(key({ metaKey: true, altKey: true, code: 'KeyF', key: 'ƒ' }))).toBe(
      'replace'
    )
    expect(findShortcut(key({ metaKey: true, code: 'KeyG', key: 'g' }))).toBe('next')
    expect(findShortcut(key({ metaKey: true, shiftKey: true, code: 'KeyG', key: 'G' }))).toBe(
      'previous'
    )
    expect(findShortcut(key({ code: 'KeyF', key: 'f' }))).toBeNull()
  })
})

describe('find and replace', () => {
  it('finds, counts, steps and replaces; searching alone is not an edit', async () => {
    editor = createEditor(host, doc('apple pie', 'Apple tart', 'banana'))
    // Block ids are stamped on create (a housekeeping update); listen after that.
    await settle()
    const onUpdate = vi.fn()
    editor.on('update', onUpdate)
    act(() => runFind(editor, 'find'))
    const input = await screen.findByPlaceholderText('Find')
    act(() => void fireEvent.change(input, { target: { value: 'apple' } }))
    await waitFor(() => expect(screen.getByText('1 of 2')).toBeTruthy())
    expect(host.querySelectorAll('.find-and-replace-result')).toHaveLength(2)
    act(() => void fireEvent.keyDown(input, { key: 'Enter' }))
    expect(screen.getByText('2 of 2')).toBeTruthy()
    expect(onUpdate).not.toHaveBeenCalled()

    act(() => screen.getByRole('button', { name: 'Match case' }).click())
    await waitFor(() => expect(screen.getByText('1 of 1')).toBeTruthy())

    act(() => runFind(editor, 'replace'))
    const replace = screen.getByPlaceholderText('Replace with')
    act(() => void fireEvent.change(replace, { target: { value: 'pear' } }))
    act(() => screen.getByRole('button', { name: 'Replace all' }).click())
    expect(editor.getText()).toContain('pear pie')
    expect(editor.getText()).toContain('Apple tart')
    expect(onUpdate).toHaveBeenCalled()
  })

  it('starts from the selected text and closes with Escape, clearing the highlights', async () => {
    editor = createEditor(host, doc('find me twice: me'))
    editor.commands.setTextSelection({ from: 6, to: 8 })
    act(() => runFind(editor, 'find'))
    const input = (await screen.findByPlaceholderText('Find')) as HTMLInputElement
    await waitFor(() => expect(input.value).toBe('me'))
    await waitFor(() => expect(host.querySelectorAll('.find-and-replace-result').length).toBe(2))
    act(() => void fireEvent.keyDown(input, { key: 'Escape' }))
    expect(screen.queryByTestId('find-panel')).toBeNull()
    expect(host.querySelectorAll('.find-and-replace-result')).toHaveLength(0)
  })

  it('regular expressions use RE2 (no catastrophic backtracking)', async () => {
    editor = createEditor(host, doc(`${'a'.repeat(40)}!`))
    act(() => runFind(editor, 'find'))
    ;(await screen.findByRole('button', { name: 'Regular expression' })).click()
    const input = await screen.findByPlaceholderText('Find')
    const started = performance.now()
    act(() => void fireEvent.change(input, { target: { value: '(a+)+$' } }))
    await waitFor(() => expect(screen.getByText('No results')).toBeTruthy())
    expect(performance.now() - started).toBeLessThan(1000)
  })
})

describe('spellcheck setting', () => {
  it('applies to the open page and to pages loaded later', () => {
    const bridge = new EditorBridge(host, { post: async () => null })
    bridge.loadDocument(page('a'))
    expect(host.querySelector('.tiptap')?.getAttribute('spellcheck')).toBe('true')
    bridge.setSpellcheck(false)
    expect(host.querySelector('.tiptap')?.getAttribute('spellcheck')).toBe('false')
    bridge.loadDocument(page('b'))
    expect(host.querySelector('.tiptap')?.getAttribute('spellcheck')).toBe('false')
  })
})

describe('table of contents block', () => {
  it('lists the headings and follows edits', async () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        { type: 'tableOfContents' },
        { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: 'Intro' }] },
        { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Details' }] }
      ]
    })
    const items = () => [...host.querySelectorAll('.hk-toc-item')].map((e) => e.textContent)
    expect(items()).toEqual(['Intro', 'Details'])
    editor.commands.insertContentAt(editor.state.doc.content.size, {
      type: 'heading',
      attrs: { level: 2 },
      content: [{ type: 'text', text: 'More' }]
    })
    expect(items()).toEqual(['Intro', 'Details', 'More'])
    ;(host.querySelectorAll('.hk-toc-item')[1] as HTMLElement).click()
    expect(editor.state.selection.$from.parent.textContent).toBe('Details')
  })
})

describe('outline rail', () => {
  it('samples long heading lists evenly, keeping the first and last', async () => {
    const { sampleEvenly } = await import('../src/page/Outline')
    const items = Array.from({ length: 60 }, (_, i) => i)
    const bars = sampleEvenly(items, 20)
    expect(bars).toHaveLength(20)
    expect(bars[0]).toBe(0)
    expect(bars.at(-1)).toBe(59)
    expect(new Set(bars).size).toBe(20)
    expect(sampleEvenly([1, 2, 3], 20)).toEqual([1, 2, 3])
  })
})
