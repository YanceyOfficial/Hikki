import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import katex from 'katex'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { TooltipProvider } from '@/components/ui/tooltip'

import { BLOCK_TYPES } from '../src/blocks'
import { createEditor } from '../src/editor'
import { SelectionMenu } from '../src/ui/SelectionMenu'
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
