import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import katex from 'katex'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { TooltipProvider } from '@/components/ui/tooltip'

import { SelectionMenu } from '../src/components/selection-menu'
import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import {
  setIconSheetOpener,
  type IconSheetHandlers,
  type IconSheetRequest
} from '../src/lib/icon-sheet'
import { doc, settle, stripIds } from './helpers'

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
  document
    .querySelectorAll('.hk-math-editor, [data-slot=popover-content]')
    .forEach((e) => e.remove())
})

// vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
const styles = readFileSync(join(process.cwd(), 'src/style.css'), 'utf8')

/** A real keydown through ProseMirror's handlers (as the keyboard sends it). */
const press = (key: string) => {
  const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}

const block = (id: string) => BLOCK_TYPES.find((b) => b.id === id)!
/** Types like a user: through the input-rule handler, so Markdown shortcuts fire. */
const type = (text: string) => {
  for (const char of text) {
    const { view } = editor
    const { from, to } = view.state.selection
    const handled = view.someProp('handleTextInput', (f) =>
      f(view, from, to, char, () => view.state.tr.insertText(char, from, to))
    )
    if (!handled) view.dispatch(view.state.tr.insertText(char, from, to))
  }
}

describe('toggle list', () => {
  it('"> " makes a toggle that opens for typing; opening/closing is not an edit', async () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    type('> ')
    await settle()
    expect(editor.getJSON().content?.[0].type).toBe('details')
    const toggle = host.querySelector('.hk-toggle') as HTMLElement
    const button = toggle.querySelector(':scope > button') as HTMLButtonElement
    expect(toggle.classList.contains('is-open')).toBe(true)
    expect(button.getAttribute('aria-label')).toBe('Collapse')
    const onUpdate = vi.fn()
    editor.on('update', onUpdate)
    button.click()
    expect(toggle.classList.contains('is-open')).toBe(false)
    expect(button.getAttribute('aria-label')).toBe('Expand')
    expect(onUpdate).not.toHaveBeenCalled()
  })

  it('stored toggles load without a content error', () => {
    const stored = {
      type: 'doc',
      content: [
        {
          type: 'details',
          content: [
            { type: 'detailsSummary', content: [{ type: 'text', text: 'More' }] },
            {
              type: 'detailsContent',
              content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Hidden' }] }]
            }
          ]
        }
      ]
    }
    const onError = vi.fn()
    editor = createEditor(host, stored, { onContentError: onError })
    expect(onError).not.toHaveBeenCalled()
    expect(stripIds(editor.getJSON())).toEqual(stored)
  })

  it('draws Phosphor’s caret and hides WebKit’s own summary marker', async () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    type('> ')
    await settle()
    const svg = host.querySelector('.hk-toggle > button svg')!
    // Phosphor's 256-unit grid (the old hand-drawn triangle was 16), filled like Notion's.
    expect(svg.getAttribute('viewBox')).toBe('0 0 256 256')
    expect(svg.getAttribute('aria-hidden')).toBe('true')
    // A <summary> outside <details> still gets WebKit's disclosure marker — the stray diamond over the caret.
    expect(styles).toMatch(/\.hk-toggle summary::-webkit-details-marker\s*\{\s*@apply hidden;/u)
    expect(styles).toMatch(/\.hk-toggle summary\s*\{\s*@apply block list-none/u)
  })

  it('"# " to "### " at the start of a summary make it a toggle heading; Backspace makes it plain again', async () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    type('> ')
    await settle()
    type('## ')
    type('Title')
    expect(summary().attrs.level).toBe(2)
    expect(summary().textContent).toBe('Title')
    expect(host.querySelector('.hk-toggle summary')?.getAttribute('data-level')).toBe('2')
    editor.commands.setTextSelection(editor.state.selection.from - 'Title'.length)
    press('Backspace')
    expect(summary().attrs.level).toBeNull()
    expect(editor.getJSON().content?.[0].type).toBe('details')
    // Only at the start of the summary, and only up to three levels.
    type('#### ')
    expect(summary().attrs.level).toBeNull()
  })

  it('a stored toggle heading round-trips through HTML; one without a level stays plain', () => {
    const heading = {
      type: 'doc',
      content: [
        {
          type: 'details',
          content: [
            {
              type: 'detailsSummary',
              attrs: { level: 1 },
              content: [{ type: 'text', text: 'Big' }]
            },
            { type: 'detailsContent', content: [{ type: 'paragraph' }] }
          ]
        }
      ]
    }
    editor = createEditor(host, heading)
    expect(stripIds(editor.getJSON())).toEqual(heading)
    const html = editor.getHTML()
    expect(html).toContain('<summary data-level="1">Big</summary>')
    editor.commands.setContent(html)
    expect(summary().attrs.level).toBe(1)
    editor.commands.setContent(html.replace('data-level="1"', 'data-level="9"'))
    expect(summary().attrs.level).toBeNull()
  })
})

/** The first toggle's summary node. */
const summary = () => editor.state.doc.firstChild!.firstChild!

const toggle = () => host.querySelector('.hk-toggle') as HTMLElement
const toggleContent = () => toggle().querySelector('[data-type=detailsContent]') as HTMLElement

describe('arriving inside a closed toggle', () => {
  const stored = {
    type: 'doc',
    content: [
      {
        type: 'details',
        content: [
          { type: 'detailsSummary', content: [{ type: 'text', text: 'More' }] },
          {
            type: 'detailsContent',
            content: [
              {
                type: 'paragraph',
                attrs: { id: 'p1' },
                content: [{ type: 'text', text: 'needle' }]
              }
            ]
          }
        ]
      }
    ]
  }

  it('a search result opens the toggle around its words', () => {
    editor = createEditor(host, stored)
    window.scrollTo = vi.fn()
    expect(toggle().classList.contains('is-open')).toBe(false)
    expect(editor.commands.revealText(['needle'], 'p1')).toBe(true)
    expect(toggle().classList.contains('is-open')).toBe(true)
    expect(toggleContent().hasAttribute('hidden')).toBe(false)
  })

  it('a link to a block inside it opens the toggle too', () => {
    editor = createEditor(host, stored)
    HTMLElement.prototype.scrollIntoView = vi.fn()
    expect(editor.commands.scrollToBlock('p1')).toBe(true)
    expect(toggle().classList.contains('is-open')).toBe(true)
  })
})

describe('quote', () => {
  it('moves to the `" ` shortcut, straight or curly', () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    type('" ')
    expect(editor.getJSON().content?.[0].type).toBe('blockquote')
    editor.commands.setContent(doc(''))
    editor.commands.setTextSelection(1)
    type('“ ')
    expect(editor.getJSON().content?.[0].type).toBe('blockquote')
  })
})

describe('callout', () => {
  it('wraps the block, with a default icon and gray background', async () => {
    editor = createEditor(host, doc('Remember this'))
    editor.commands.setTextSelection(3)
    block('callout').turnInto!(editor.chain().focus()).run()
    const json = editor.getJSON().content?.[0]
    expect(json).toMatchObject({ type: 'callout', attrs: { icon: '💡', color: null } })
    expect(editor.getText()).toContain('Remember this')
    await waitFor(() =>
      expect(host.querySelector('.hk-callout [aria-label="Change icon"]')?.textContent).toBe('💡')
    )
  })

  it('on a phone its icon opens the native sheet, whose picks set the icon and the colour', async () => {
    vi.stubGlobal('matchMedia', (query: string) => ({
      matches: query === '(pointer: coarse)',
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {}
    }))
    const opened: IconSheetRequest[] = []
    let handlers: IconSheetHandlers | null = null
    setIconSheetOpener((request, next) => {
      opened.push(request)
      handlers = next
      return true
    })
    try {
      editor = createEditor(host, null)
      editor.commands.setContent('<div data-type="callout" data-icon="🔥"><p>Hot</p></div>')
      const button = await waitFor(() => {
        const found = host.querySelector<HTMLElement>('.hk-callout [aria-label="Change icon"]')
        expect(found).toBeTruthy()
        return found!
      })
      fireEvent.click(button)
      expect(opened).toEqual([{ kind: 'callout', icon: '🔥', color: null }])
      act(() => {
        handlers!.onIcon('🌊')
        handlers!.onColor!('blue')
      })
      expect(editor.getJSON().content?.[0]).toMatchObject({ attrs: { icon: '🌊', color: 'blue' } })
      // Remove leaves the callout its default icon (a callout always has one).
      act(() => handlers!.onIcon(null))
      expect(editor.getJSON().content?.[0]).toMatchObject({ attrs: { icon: '💡' } })
    } finally {
      setIconSheetOpener(null)
      vi.unstubAllGlobals()
    }
  })

  it('round-trips through HTML (icon and palette color)', () => {
    editor = createEditor(host, null)
    editor.commands.setContent(
      '<div data-type="callout" data-icon="🔥" data-bg-color="red"><p>Hot</p></div>'
    )
    expect(editor.getJSON().content?.[0]).toMatchObject({
      type: 'callout',
      attrs: { icon: '🔥', color: 'red' }
    })
    expect(editor.getHTML()).toContain('data-bg-color="red"')
  })

  it('Backspace at the start of its first line unwraps it', () => {
    editor = createEditor(host, doc('Inside'))
    editor.commands.setTextSelection(1)
    editor.commands.setCallout()
    editor.commands.setTextSelection(2)
    editor.commands.keyboardShortcut('Backspace')
    expect(editor.getJSON().content?.[0].type).toBe('paragraph')
  })
})

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

describe('formulas', () => {
  it('render with KaTeX and edit in the panel', async () => {
    editor = createEditor(host, inline('x^2'))
    // KaTeX itself refuses happy-dom's quirks-mode document; rendering is checked in the browser.
    expect(host.querySelector('[data-type="inline-math"]')?.getAttribute('data-latex')).toBe('x^2')
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    const input = await screen.findByLabelText('Formula (LaTeX)')
    fireEvent.change(input, { target: { value: 'y_1' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    const math = editor.getJSON().content?.[0].content?.[1]
    expect(math).toMatchObject({ type: 'inlineMath', attrs: { latex: 'y_1' } })
    expect(document.querySelector('.hk-math-editor')).toBeNull()
  })

  it('a new equation from "/" opens the editor; cancelling an empty one removes it', async () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    const math = block('blockMath')
    math.apply(editor.chain().focus()).run()
    math.after!(editor)
    const input = await screen.findByLabelText('Formula (LaTeX)')
    expect(JSON.stringify(editor.getJSON())).toContain('blockMath')
    fireEvent.keyDown(input, { key: 'Escape' })
    expect(JSON.stringify(editor.getJSON())).not.toContain('blockMath')
  })

  it('the panel edits its formula where it is now, after the page changed under it', async () => {
    editor = createEditor(host, inline('x^2'))
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    const input = await screen.findByLabelText('Formula (LaTeX)')
    // A remote reload put a line before it (outside the undo history).
    act(() => {
      const tr = editor.state.tr.insert(
        0,
        editor.schema.nodes.paragraph.create(null, editor.schema.text('new'))
      )
      editor.view.dispatch(tr.setMeta('addToHistory', false))
    })
    fireEvent.change(input, { target: { value: 'y_1' } })
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(editor.getJSON().content?.[1].content?.[1]).toMatchObject({
      type: 'inlineMath',
      attrs: { latex: 'y_1' }
    })
    expect(editor.getText()).toContain('new')
  })

  it('the panel closes when its formula is gone', async () => {
    editor = createEditor(host, inline('x^2'))
    act(() => (host.querySelector('[data-type="inline-math"]') as HTMLElement).click())
    await screen.findByLabelText('Formula (LaTeX)')
    act(() => void editor.commands.setContent(doc('replaced')))
    expect(document.querySelector('.hk-math-editor')).toBeNull()
  })

  it('the selection menu turns selected text into an inline formula', () => {
    editor = createEditor(host, doc('a^2 + b^2'))
    render(
      <TooltipProvider>
        <SelectionMenu editor={editor} />
      </TooltipProvider>
    )
    act(() => void editor.commands.setTextSelection({ from: 1, to: 10 }))
    fireEvent.click(screen.getByRole('button', { name: 'Equation' }))
    expect(editor.getJSON().content?.[0].content?.[0]).toMatchObject({
      type: 'inlineMath',
      attrs: { latex: 'a^2 + b^2' }
    })
  })

  it('KaTeX output never carries markup from the formula', () => {
    const html = katex.renderToString('<script>alert(1)</script>\\href{javascript:alert(1)}{x}', {
      throwOnError: false,
      strict: 'ignore'
    })
    const probe = document.createElement('div')
    probe.innerHTML = html
    expect(probe.querySelector('script')).toBeNull()
    expect(probe.querySelector('a[href^="javascript"]')).toBeNull()
  })
})
