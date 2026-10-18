import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { draggedPage, inSplitZone } from '../src/extensions/split-drop'
import { doc } from './helpers'

/** A DataTransfer stand-in (jsdom has none): the types and data a drag carries. */
const transfer = (data: Record<string, string>) =>
  ({
    types: Object.keys(data),
    getData: (type: string) => data[type] ?? '',
    dropEffect: 'none'
  }) as unknown as DataTransfer

/** A drag event (jsdom has no DragEvent) at `clientX`, carrying `data`. */
const drag = (type: string, clientX: number, data: Record<string, string>) => {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX })
  Object.defineProperty(event, 'dataTransfer', { value: transfer(data) })
  return event
}

const hint = () => document.querySelector('.hk-split-drop') as HTMLElement

describe('split drop helpers', () => {
  it('the zone is the right quarter, at least 96 and at most 240 points wide', () => {
    expect(inSplitZone(799, 800)).toBe(true)
    expect(inSplitZone(600, 800)).toBe(true)
    expect(inSplitZone(599, 800)).toBe(false)
    expect(inSplitZone(1760, 2000)).toBe(true)
    expect(inSplitZone(1759, 2000)).toBe(false)
    expect(inSplitZone(205, 300)).toBe(true)
    expect(inSplitZone(203, 300)).toBe(false)
  })

  it('reads the page from the URL list or the text', () => {
    expect(draggedPage(transfer({ 'text/uri-list': '# comment\nhikki://page/p1' }))).toBe('p1')
    expect(draggedPage(transfer({ 'text/plain': 'hikki://page/p2#block' }))).toBe('p2')
    expect(draggedPage(transfer({ 'text/uri-list': 'https://example.com' }))).toBeNull()
    expect(draggedPage(null)).toBeNull()
  })
})

describe('dropping a page on the right edge', () => {
  let element: HTMLElement
  let editor: Editor
  let mode: 'off' | 'open' | 'replace' | 'here'
  let opened: string[]
  let hovers: boolean[]

  beforeEach(() => {
    mode = 'open'
    opened = []
    hovers = []
    Object.defineProperty(window, 'innerWidth', { value: 800, configurable: true })
    element = document.createElement('div')
    document.body.append(element)
    editor = createEditor(element, doc('a page'), {
      splitDrop: {
        mode: () => mode,
        open: (id) => void opened.push(id),
        hover: (active) => void hovers.push(active)
      }
    })
  })
  afterEach(() => {
    editor.destroy()
    element.remove()
  })

  const link = { 'text/uri-list': 'hikki://page/notes' }

  it('shows where it opens over the edge, and opens it there instead of inserting a link', () => {
    editor.view.dom.dispatchEvent(drag('dragover', 700, link))
    expect(hint().dataset.open).toBe('true')
    expect(hint().textContent).toBe('Open on the right')
    const drop = drag('drop', 700, link)
    editor.view.dom.dispatchEvent(drop)
    expect(opened).toEqual(['notes'])
    expect(drop.defaultPrevented).toBe(true)
    expect(hint().dataset.open).toBe('false')
    expect(editor.getText()).toBe('a page')
  })

  it('split already: the right side is outlined by the app, not a half-width zone here', () => {
    mode = 'replace'
    editor.view.dom.dispatchEvent(drag('dragover', 700, link))
    editor.view.dom.dispatchEvent(drag('dragover', 710, link))
    expect(hint().dataset.open).toBe('false')
    expect(hovers).toEqual([true])
    editor.view.dom.dispatchEvent(drag('dragover', 300, link))
    expect(hovers).toEqual([true, false])
    editor.view.dom.dispatchEvent(drag('dragover', 700, link))
    editor.view.dom.dispatchEvent(drag('drop', 700, link))
    expect(opened).toEqual(['notes'])
    expect(hovers).toEqual([true, false, true, false])
  })

  it('says what the drop does: show here on the right one', () => {
    mode = 'here'
    editor.view.dom.dispatchEvent(drag('dragover', 700, link))
    expect(hint().textContent).toBe('Show here')
    editor.view.dom.dispatchEvent(drag('drop', 700, link))
    expect(opened).toEqual(['notes'])
  })

  it('leaves drops elsewhere, text drags and phones alone', () => {
    editor.view.dom.dispatchEvent(drag('dragover', 300, link))
    expect(hint().dataset.open).toBe('false')
    editor.view.dom.dispatchEvent(drag('dragover', 700, { 'text/plain': 'some text' }))
    expect(hint().dataset.open).toBe('false')
    mode = 'off'
    editor.view.dom.dispatchEvent(drag('dragover', 700, link))
    expect(hint().dataset.open).toBe('false')
    editor.view.dom.dispatchEvent(drag('drop', 700, link))
    expect(opened).toEqual([])
  })
})
