import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { TooltipProvider } from '@/components/ui/tooltip'

import { createEditor } from '../src/editor'
import { normalizeHref, SelectionMenu } from '../src/ui/SelectionMenu'
import { doc } from './helpers'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  editor = createEditor(host, doc('hello world'))
})
afterEach(() => {
  cleanup()
  editor.destroy()
  host.remove()
})

/** Selects "hello" (positions 1–6 in the first paragraph). */
const selectHello = () => act(() => void editor.commands.setTextSelection({ from: 1, to: 6 }))
const firstText = () => editor.getJSON().content?.[0].content?.[0]

describe('color marks', () => {
  it('store palette names, rendered as data attributes', () => {
    editor.commands.setTextSelection({ from: 1, to: 6 })
    editor.commands.setTextColor('red')
    editor.commands.setBackgroundColor('yellow')
    expect(firstText()?.marks).toEqual([
      { type: 'textStyle', attrs: { textColor: 'red', bgColor: 'yellow' } }
    ])
    expect(editor.getHTML()).toContain('data-text-color="red"')
    expect(editor.getHTML()).toContain('data-bg-color="yellow"')
  })

  it('null takes a color off, and the empty mark goes with it', () => {
    editor.commands.setTextSelection({ from: 1, to: 6 })
    editor.commands.setTextColor('blue')
    editor.commands.setTextColor(null)
    expect(firstText()?.marks).toBeUndefined()
  })

  it('pasted HTML keeps palette names and drops anything else', () => {
    editor.commands.setContent({ type: 'doc', content: [{ type: 'paragraph' }] })
    editor.commands.setTextSelection(1)
    editor.view.pasteHTML(
      '<p><span data-text-color="green">ok</span><span data-text-color="javascript:x">no</span></p>'
    )
    const [ok, no] = editor.getJSON().content?.[0].content ?? []
    expect(ok.marks?.[0].attrs?.textColor).toBe('green')
    expect(no.marks).toBeUndefined()
  })
})

const show = () =>
  render(
    <TooltipProvider>
      <SelectionMenu editor={editor} />
    </TooltipProvider>
  )

describe('SelectionMenu', () => {
  it('toggles marks and reflects them as pressed', () => {
    show()
    selectHello()
    fireEvent.click(screen.getByRole('button', { name: 'Bold' }))
    expect(firstText()?.marks).toEqual([{ type: 'bold' }])
    expect(screen.getByRole('button', { name: 'Bold' }).getAttribute('aria-pressed')).toBe('true')
    fireEvent.click(screen.getByRole('button', { name: 'Underline' }))
    fireEvent.click(screen.getByRole('button', { name: 'Clear formatting' }))
    expect(firstText()?.marks).toBeUndefined()
  })

  it('"Turn into" shows the current block and converts it, keeping the text', () => {
    show()
    selectHello()
    const turnInto = screen.getByRole('button', { name: /Text/u })
    fireEvent.click(turnInto)
    const menu = screen.getByRole('menu', { name: 'Turn into' })
    expect(menu.querySelector('[aria-checked=true]')?.textContent).toContain('Text')
    fireEvent.click(screen.getByRole('menuitemradio', { name: /Heading 2/u }))
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
    expect(editor.getText().trim()).toBe('hello world')
  })

  it('turns a list item back into plain text (lifted out of the list)', () => {
    editor.commands.toggleBulletList()
    show()
    selectHello()
    fireEvent.click(screen.getByRole('button', { name: /Bulleted list/u }))
    fireEvent.click(screen.getByRole('menuitemradio', { name: /^Text/u }))
    expect(editor.getJSON().content?.[0].type).toBe('paragraph')
  })

  it('colors the selection from the color panel', () => {
    show()
    selectHello()
    fireEvent.click(screen.getByRole('button', { name: 'Color' }))
    const panel = screen.getByRole('menu', { name: 'Color' })
    const red = [...panel.querySelectorAll('[role=menuitemradio]')].find((b) =>
      b.textContent?.includes('Red')
    ) as HTMLElement
    fireEvent.click(red)
    expect(firstText()?.marks?.[0].attrs?.textColor).toBe('red')
  })

  it('adds, then removes, a link', () => {
    show()
    selectHello()
    fireEvent.click(screen.getByRole('button', { name: 'Link' }))
    const input = screen.getByPlaceholderText('Paste or type a link')
    fireEvent.change(input, { target: { value: 'example.com' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(firstText()?.marks?.[0]).toMatchObject({
      type: 'link',
      attrs: { href: 'https://example.com' }
    })

    selectHello()
    fireEvent.click(screen.getByRole('button', { name: 'Link' }))
    fireEvent.click(screen.getByRole('button', { name: 'Remove link' }))
    expect(firstText()?.marks).toBeUndefined()
  })

  it('a new selection closes an open panel', () => {
    show()
    selectHello()
    fireEvent.click(screen.getByRole('button', { name: 'Color' }))
    expect(screen.queryByRole('menu', { name: 'Color' })).not.toBeNull()
    act(() => void editor.commands.setTextSelection({ from: 7, to: 12 }))
    expect(screen.queryByRole('menu', { name: 'Color' })).toBeNull()
  })
})

describe('normalizeHref', () => {
  it('adds https to bare domains and keeps explicit schemes and anchors', () => {
    expect(normalizeHref(' example.com ')).toBe('https://example.com')
    expect(normalizeHref('mailto:a@b.c')).toBe('mailto:a@b.c')
    expect(normalizeHref('hikki://page/x')).toBe('hikki://page/x')
    expect(normalizeHref('#top')).toBe('#top')
    expect(normalizeHref('   ')).toBeNull()
  })
})
