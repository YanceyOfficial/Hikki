import { act, fireEvent, screen } from '@testing-library/react'
import type { Editor, JSONContent } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createEditor } from '../src/core/editor'
import { tickDateChips } from '../src/extensions/date-mention'
import type { PageLinksHost } from '../src/extensions/page-links'
import { setDateSheetOpener, type DateSheetChange } from '../src/lib/date-sheet'
import type { DateMentionAttrs } from '../src/lib/dates'
import { settle } from './helpers'

// The menu settles on timers, the chip and the popover draw through React's own queue.
const flush = async () => {
  await settle()
  await act(async () => {})
}

const key = (editor: Editor, k: string) => {
  const event = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}
const options = () =>
  [...document.querySelectorAll('.hk-mention-menu [role=option]')].map((e) =>
    e.getAttribute('aria-label')
  )
const groups = () =>
  [...document.querySelectorAll('.hk-mention-menu .hk-command-list > div:not([role])')]
    .map((e) => e.textContent)
    .filter(Boolean)
const chips = () => [...document.querySelectorAll<HTMLElement>('[data-testid="date-chip"]')]
const dates = (): Record<string, unknown>[] => {
  const out: Record<string, unknown>[] = []
  const walk = (node: JSONContent) => {
    if (node.type === 'dateMention') out.push(node.attrs ?? {})
    node.content?.forEach(walk)
  }
  walk(editor.getJSON())
  return out
}
const withChip = (attrs: Partial<DateMentionAttrs>) =>
  editor.commands.setContent({
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: 'Book the ryokan ' },
          {
            type: 'dateMention',
            attrs: { id: 'm1', date: '2026-10-22', time: null, remind: null, done: false, ...attrs }
          }
        ]
      }
    ]
  })

const host: PageLinksHost = {
  pages: () => [
    { id: 'p1', title: 'Tomorrow plan', icon: '🗓️' },
    { id: 'p2', title: 'Trip to Kyoto', icon: null }
  ],
  currentPageId: () => 'here',
  untitled: () => 'Untitled',
  open: () => {},
  openExternal: () => {}
}

let element: HTMLElement
let editor: Editor
beforeEach(() => {
  // Wednesday, October 21, 2026, at noon; timers stay real (the suggestion menu settles on them).
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(2026, 9, 21, 12, 0))
  element = document.createElement('div')
  document.body.append(element)
  editor = createEditor(element, null, { pageLinks: host })
  editor.commands.setTextSelection(1)
})
afterEach(() => {
  editor.destroy()
  element.remove()
  setDateSheetOpener(null)
  document.querySelectorAll('.hk-mention-menu, .hk-date-popover').forEach((e) => e.remove())
  vi.useRealTimers()
})

describe('"@" puts a date', () => {
  it('offers the date the words read as above the pages, and Enter puts a chip', async () => {
    editor.commands.insertContent('Call @tom')
    await flush()
    expect(groups()).toEqual(['Date', 'Pages'])
    expect(options()).toEqual(['Tomorrow', 'Remind me Tomorrow', 'Tomorrow plan'])
    key(editor, 'Enter')
    await flush()
    expect(document.querySelector('.hk-mention-menu')).toBeNull()
    expect(dates()).toEqual([
      expect.objectContaining({ date: '2026-10-22', time: null, remind: null, done: false })
    ])
    expect(dates()[0].id).toMatch(/^[0-9a-f-]{36}$/u)
    expect(chips()[0].textContent).toBe('Tomorrow')
    expect(chips()[0].dataset.state).toBe('date')
    expect(editor.getText()).toBe('Call Thu, Oct 22, 2026 ')
  })

  it('keeps spaces while the words read as a date, and the reminder row sets one', async () => {
    editor.commands.insertContent('Draft @next fri 3pm')
    await flush()
    expect(options()).toEqual(['Oct 30 3:00 PM', 'Remind me Oct 30 3:00 PM'])
    key(editor, 'ArrowDown')
    key(editor, 'Enter')
    await flush()
    expect(dates()).toEqual([
      expect.objectContaining({ date: '2026-10-30', time: '15:00', remind: 0 })
    ])
    expect(chips()[0].dataset.state).toBe('remind')
  })

  it('with nothing typed, offers today, tomorrow and a reminder tomorrow first', async () => {
    editor.commands.insertContent('@')
    await flush()
    expect(options().slice(0, 3)).toEqual(['Today', 'Tomorrow', 'Remind me Tomorrow'])
  })

  it('ends at a space that makes no date: a page mention stays as it was', async () => {
    editor.commands.insertContent('@Trip and more')
    await flush()
    expect(document.querySelector('.hk-mention-menu')).toBeNull()
  })
})

describe('a date chip', () => {
  it('turns red once its reminder has rung, and back when marked done', () => {
    withChip({ time: '13:00', remind: 0 })
    expect(chips()[0].dataset.state).toBe('remind')
    vi.setSystemTime(new Date(2026, 9, 22, 13, 1))
    act(() => tickDateChips())
    expect(chips()[0].dataset.state).toBe('overdue')
    expect(chips()[0].textContent).toBe('Today 1:00 PM')
    withChip({ time: '13:00', remind: 0, done: true })
    expect(chips()[0].dataset.state).toBe('done')
  })

  it('opens its popover on a click: a day, a time, a reminder, Mark done and Remove', async () => {
    withChip({})
    fireEvent.click(chips()[0])
    await flush()
    expect(screen.getByTestId('date-popover')).toBeTruthy()

    fireEvent.click(screen.getByTestId('date-include-time'))
    await flush()
    expect(dates()[0]).toMatchObject({ time: '09:00', remind: null })

    fireEvent.click(screen.getByTestId('date-remind'))
    fireEvent.click(screen.getByTestId('date-remind-60'))
    await flush()
    expect(dates()[0]).toMatchObject({ remind: 60, done: false })
    expect(chips()[0].dataset.state).toBe('remind')

    fireEvent.click(screen.getByTestId('date-done'))
    await flush()
    expect(dates()[0]).toMatchObject({ done: true })

    // Typed words move it (and keep the time when the words have none).
    const field = screen.getByLabelText('Date', { selector: 'input' })
    fireEvent.change(field, { target: { value: 'fri' } })
    fireEvent.keyDown(field, { key: 'Enter' })
    await flush()
    expect(dates()[0]).toMatchObject({ date: '2026-10-23', time: '09:00' })

    fireEvent.click(screen.getByTestId('date-remove'))
    await flush()
    expect(dates()).toEqual([])
    expect(editor.getText()).toBe('Book the ryokan ')
  })

  it("doesn't open on a page that can't be edited", async () => {
    withChip({})
    editor.setEditable(false)
    fireEvent.click(chips()[0])
    await flush()
    expect(screen.queryByTestId('date-popover')).toBeNull()
  })

  it('on a phone, opens the native sheet and takes its answer instead', async () => {
    let answer: ((change: DateSheetChange) => void) | null = null
    const opened: DateMentionAttrs[] = []
    setDateSheetOpener((attrs, onChange) => {
      opened.push(attrs)
      answer = onChange
      return true
    })
    withChip({ remind: 0, snoozed: '2026-10-22T10:00' })
    fireEvent.click(chips()[0])
    await flush()
    expect(screen.queryByTestId('date-popover')).toBeNull()
    expect(opened[0]).toMatchObject({ id: 'm1', date: '2026-10-22', remind: 0 })
    act(() => answer!({ date: '2026-10-25', time: '08:00', remind: 5, done: false }))
    expect(dates()[0]).toMatchObject({
      date: '2026-10-25',
      time: '08:00',
      remind: 5,
      snoozed: null
    })
    fireEvent.click(chips()[0])
    act(() => answer!(null))
    expect(dates()).toEqual([])
  })

  it('copies out as a <time> and pastes back as the same chip', () => {
    withChip({ time: '09:30', remind: 60 })
    const html = editor.getHTML()
    expect(html).toMatch(/<time [^>]*data-type="date"[^>]*datetime="2026-10-22T09:30"/u)
    editor.commands.setContent(html)
    expect(dates()[0]).toMatchObject({ id: 'm1', date: '2026-10-22', time: '09:30', remind: 60 })
  })
})
