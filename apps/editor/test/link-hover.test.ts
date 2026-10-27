import { fireEvent } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { LINK_HOVER_DELAY, LINK_LEAVE_DELAY } from '../src/extensions/link-hover'

let host: HTMLElement
let editor: Editor

const page = {
  type: 'doc',
  content: [
    {
      type: 'paragraph',
      content: [
        { type: 'text', text: 'See ' },
        {
          type: 'text',
          text: 'the site',
          marks: [{ type: 'link', attrs: { href: 'https://example.com/docs' } }]
        },
        { type: 'text', text: ' and ' },
        {
          type: 'text',
          text: 'a block',
          marks: [{ type: 'link', attrs: { href: 'hikki://page/notes#b1' } }]
        }
      ]
    }
  ]
}

const card = () => document.querySelector<HTMLElement>('[data-testid="link-card"]')
const anchors = () => [...editor.view.dom.querySelectorAll<HTMLAnchorElement>('a[href]')]
const hover = (el: Element) => el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }))
const leave = (el: Element, to: Element | null = null) =>
  el.dispatchEvent(new MouseEvent('mouseout', { bubbles: true, relatedTarget: to }))

beforeEach(() => {
  vi.useFakeTimers()
  // A mouse (the card is for fine pointers).
  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: query === '(pointer: fine)',
    addEventListener: () => {},
    removeEventListener: () => {}
  }))
  host = document.createElement('div')
  document.body.append(host)
  editor = createEditor(host, page, {
    pageLinks: {
      pages: () => [{ id: 'notes', title: 'Meeting notes', icon: '📓' }],
      currentPageId: () => 'here',
      untitled: () => 'Untitled',
      open: () => {},
      openExternal: () => {}
    }
  })
})
afterEach(() => {
  editor.destroy()
  host.remove()
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('the link card (ISSUE-241)', () => {
  it('shows after the pointer rests on a link, names where it goes, and goes once the pointer has left', () => {
    const [site] = anchors()
    hover(site)
    expect(card()).toBeNull()
    vi.advanceTimersByTime(LINK_HOVER_DELAY + 10)
    expect(card()?.textContent).toContain('https://example.com/docs')
    // Onto the card itself: it stays; off both: it goes after a moment.
    leave(site, card())
    vi.advanceTimersByTime(LINK_LEAVE_DELAY + 10)
    expect(card()).not.toBeNull()
    leave(site)
    vi.advanceTimersByTime(LINK_LEAVE_DELAY + 10)
    expect(card()).toBeNull()
  })

  it('names a page link by the page, and Edit changes or removes the link', () => {
    const [, block] = anchors()
    hover(block)
    vi.advanceTimersByTime(LINK_HOVER_DELAY + 10)
    expect(card()?.textContent).toContain('Meeting notes')
    const edit = [...card()!.querySelectorAll('button')].find((b) => b.textContent === 'Edit')!
    edit.click()
    const field = card()!.querySelector('input')!
    expect(field.value).toBe('hikki://page/notes#b1')
    // While editing the card stays through the pointer leaving.
    leave(block)
    vi.advanceTimersByTime(LINK_LEAVE_DELAY + 10)
    expect(card()).not.toBeNull()
    fireEvent.change(field, { target: { value: 'https://example.org/' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    expect(editor.getHTML()).toContain('href="https://example.org/"')
    expect(editor.getHTML()).not.toContain('hikki://page/notes#b1')
    expect(card()).toBeNull()
  })

  it('Remove link takes the mark off, and a page change closes the card', () => {
    const [site] = anchors()
    hover(site)
    vi.advanceTimersByTime(LINK_HOVER_DELAY + 10)
    ;[...card()!.querySelectorAll('button')].find((b) => b.textContent === 'Edit')!.click()
    ;[...card()!.querySelectorAll('button')].find((b) => b.textContent === 'Remove link')!.click()
    expect(editor.getHTML()).not.toContain('example.com')
    expect(editor.getText()).toContain('See the site and')
    expect(card()).toBeNull()
    const [block] = anchors()
    hover(block)
    vi.advanceTimersByTime(LINK_HOVER_DELAY + 10)
    expect(card()).not.toBeNull()
    editor.commands.insertContentAt(1, 'x')
    expect(card()).toBeNull()
  })

  it('shows no card for a mention chip', () => {
    editor.commands.setContent({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [{ type: 'mention', attrs: { id: 'notes', label: 'Meeting notes' } }]
        }
      ]
    })
    const chip = editor.view.dom.querySelector('a.hk-mention')!
    hover(chip)
    vi.advanceTimersByTime(LINK_HOVER_DELAY + 10)
    expect(card()).toBeNull()
  })
})
