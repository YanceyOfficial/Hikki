import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { EditorBridge } from '../src/core/bridge'
import type { ToNativeMessage } from '../src/core/protocol'
import { Outline } from '../src/page/outline'
import { PageHeader } from '../src/page/page-header'
import { page, settle } from './helpers'

describe('PageHeader', () => {
  let sent: ToNativeMessage[]
  let bridge: EditorBridge
  let host: HTMLElement

  beforeEach(() => {
    sent = []
    host = document.createElement('div')
    document.body.append(host)
    bridge = new EditorBridge(
      host,
      {
        post: async (m) => {
          sent.push(m)
          return null
        }
      },
      { debounceMs: 0 }
    )
  })
  afterEach(() => {
    cleanup()
    host.remove()
  })

  const load = (patch = {}) => act(() => bridge.loadDocument(page('a', patch)))

  it('focusTitle (native Rename) focuses the title with all of it selected', () => {
    render(<PageHeader bridge={bridge} />)
    load({ title: 'Trip to Iceland' })
    const title = screen.getByLabelText('Page title') as HTMLTextAreaElement
    act(() => bridge.focusTitle())
    expect(document.activeElement).toBe(title)
    expect([title.selectionStart, title.selectionEnd]).toEqual([0, 'Trip to Iceland'.length])
  })

  it('renders the title as an independent field and writes edits back', async () => {
    render(<PageHeader bridge={bridge} />)
    load({ title: 'Plan' })
    const title = screen.getByLabelText('Page title') as HTMLTextAreaElement
    expect(title.value).toBe('Plan')
    fireEvent.change(title, { target: { value: 'Plan v2' } })
    expect(bridge.page.get().title).toBe('Plan v2')
    await settle()
    expect(sent.some((m) => m.type === 'changed' && m.snapshot.title === 'Plan v2')).toBe(true)
  })

  it('Enter in the title moves into the body; Enter while composing (IME) does not', () => {
    render(<PageHeader bridge={bridge} />)
    load()
    const title = screen.getByLabelText('Page title')
    let moved = 0
    bridge.enterFromTitle = () => {
      moved++
    }
    fireEvent.compositionStart(title)
    fireEvent.keyDown(title, { key: 'Enter' })
    expect(moved).toBe(0)
    fireEvent.compositionEnd(title)
    fireEvent.keyDown(title, { key: 'Enter' })
    expect(moved).toBe(1)
  })

  it('"Add icon" and "Add cover" set values immediately and then disappear', () => {
    render(<PageHeader bridge={bridge} />)
    load()
    fireEvent.click(screen.getByText('Add icon'))
    fireEvent.click(screen.getByText('Add cover'))
    expect(sent.find((m) => m.type === 'setIcon')).toMatchObject({
      docId: 'a',
      icon: expect.any(String)
    })
    expect(sent.find((m) => m.type === 'setCover')).toMatchObject({
      docId: 'a',
      cover: expect.stringMatching(/^gradient:/)
    })
    expect(screen.queryByText('Add icon')).toBeNull()
    expect(screen.queryByText('Add cover')).toBeNull()
    expect(screen.getByTestId('cover')).toBeTruthy()
  })

  it('a locked page shows no icon/cover controls and a read-only title until unlocked', () => {
    render(<PageHeader bridge={bridge} />)
    load({ icon: '🌊', cover: 'gradient:ocean', locked: true })
    expect(screen.queryByText('Change cover')).toBeNull()
    expect((screen.getByLabelText('Page title') as HTMLTextAreaElement).readOnly).toBe(true)
    expect((screen.getByLabelText('Change icon') as HTMLButtonElement).disabled).toBe(true)
    act(() => bridge.setLocked(false))
    expect((screen.getByLabelText('Page title') as HTMLTextAreaElement).readOnly).toBe(false)
    expect((screen.getByLabelText('Change icon') as HTMLButtonElement).disabled).toBe(false)
    expect(screen.getByText('Change cover')).toBeTruthy()
  })

  it('Reposition drags an image cover up and down, Save keeps it, Cancel drops it', () => {
    render(<PageHeader bridge={bridge} />)
    load({ cover: 'gradient:dusk' })
    // Gradients have nothing to reposition.
    expect(screen.queryByText('Reposition')).toBeNull()
    load({ cover: 'hikki-editor://assets/a.png' })
    fireEvent.click(screen.getByText('Reposition'))
    const cover = screen.getByTestId('cover')
    expect(screen.getByText('Drag image to reposition')).toBeTruthy()
    expect(screen.queryByText('Change cover')).toBeNull()
    // Nothing is measured in this DOM, so 200 px of drag span the whole range: 50 px down = a quarter.
    fireEvent.pointerDown(cover, { pointerId: 1, button: 0, clientY: 100 })
    fireEvent.pointerMove(cover, { pointerId: 1, clientY: 150 })
    fireEvent.pointerUp(cover, { pointerId: 1 })
    expect(cover.style.background).toContain('50% 25%')
    // The page itself is untouched until Save.
    expect(bridge.page.get().cover).toBe('hikki-editor://assets/a.png')
    // A press on the controls is not a drag.
    fireEvent.pointerDown(screen.getByText('Save position'), {
      pointerId: 3,
      button: 0,
      clientY: 10
    })
    fireEvent.pointerMove(cover, { pointerId: 3, clientY: 110 })
    expect(cover.style.background).toContain('50% 25%')
    fireEvent.click(screen.getByText('Save position'))
    expect(bridge.page.get().cover).toBe('hikki-editor://assets/a.png#y=25')
    expect(sent.at(-1)).toMatchObject({
      type: 'setCover',
      cover: 'hikki-editor://assets/a.png#y=25'
    })
    expect(screen.queryByText('Drag image to reposition')).toBeNull()
    // Cancel: the drag shows, then goes.
    fireEvent.click(screen.getByText('Reposition'))
    fireEvent.pointerDown(cover, { pointerId: 2, button: 0, clientY: 100 })
    fireEvent.pointerMove(cover, { pointerId: 2, clientY: 0 })
    expect(screen.getByTestId('cover').style.background).toContain('50% 75%')
    fireEvent.click(screen.getByText('Cancel'))
    expect(screen.getByTestId('cover').style.background).toContain('50% 25%')
    expect(bridge.page.get().cover).toBe('hikki-editor://assets/a.png#y=25')
  })

  it('cover picker swaps the gradient and Remove clears it', () => {
    render(<PageHeader bridge={bridge} />)
    load({ cover: 'gradient:dusk' })
    fireEvent.click(screen.getByText('Change cover'))
    fireEvent.click(screen.getByRole('button', { name: 'Ocean' }))
    expect(bridge.page.get().cover).toBe('gradient:ocean')
    fireEvent.click(screen.getAllByText('Remove')[0])
    expect(bridge.page.get().cover).toBeNull()
    expect(screen.queryByTestId('cover')).toBeNull()
  })

  it('clicking the icon opens the picker; Remove clears the icon', () => {
    render(<PageHeader bridge={bridge} />)
    load({ icon: '🌊' })
    fireEvent.click(screen.getByLabelText('Change icon'))
    expect(screen.getByRole('dialog', { name: 'Choose icon' })).toBeTruthy()
    fireEvent.click(screen.getByText(/Remove|移除/))
    expect(bridge.page.get().icon).toBeNull()
  })

  it('a focus request from the body puts the caret at the end of the title', () => {
    render(<PageHeader bridge={bridge} />)
    load({ title: 'Plan' })
    act(() => bridge.page.set({ focusTitleRequest: 1 }))
    const title = screen.getByLabelText('Page title') as HTMLTextAreaElement
    expect(document.activeElement).toBe(title)
    expect(title.selectionStart).toBe(4)
  })
})

describe('Outline', () => {
  afterEach(cleanup)

  it('appears with two or more headings and scrolls on click', () => {
    const host = document.createElement('div')
    document.body.append(host)
    const bridge = new EditorBridge(host, { post: async () => null })
    render(<Outline bridge={bridge} />)
    act(() =>
      bridge.loadDocument(
        page('a', {
          content: {
            type: 'doc',
            content: [
              { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Goals' }] }
            ]
          }
        })
      )
    )
    expect(screen.queryByRole('navigation', { name: 'Outline' })).toBeNull()
    act(() =>
      bridge.page.set({
        headings: [
          { id: null, pos: 0, level: 2, text: 'Goals' },
          { id: null, pos: 7, level: 3, text: 'Risks' }
        ]
      })
    )
    let scrolled = -1
    bridge.scrollToHeading = (pos) => {
      scrolled = pos
    }
    fireEvent.click(screen.getByRole('button', { name: 'Risks' }))
    expect(scrolled).toBe(7)
    host.remove()
  })
})
