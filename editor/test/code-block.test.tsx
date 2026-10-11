import { act, fireEvent, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { BLOCK_TYPES } from '../src/blocks'
import { createEditor } from '../src/editor'
import { filterLanguages, findLanguage, lastCodeLanguage } from '../src/extensions/code-languages'
import { settle } from './helpers'

let host: HTMLElement
let editor: Editor

const codeDoc = (language: string | null, text: string) => ({
  type: 'doc',
  content: [{ type: 'codeBlock', attrs: { language }, content: [{ type: 'text', text }] }]
})

beforeEach(() => {
  localStorage.clear()
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  editor?.destroy()
  host.remove()
  document.body.querySelectorAll('[data-slot=popover-content]').forEach((e) => e.remove())
})

describe('code block', () => {
  it('highlights with lowlight (classes the Xcode theme colors)', async () => {
    editor = createEditor(host, codeDoc('javascript', 'const answer = 42 // why'))
    await settle()
    expect(host.querySelector('.hljs-keyword')?.textContent).toBe('const')
    expect(host.querySelector('.hljs-number')?.textContent).toBe('42')
    expect(host.querySelector('.hljs-comment')?.textContent).toBe('// why')
  })

  it('plain text is not auto-detected', async () => {
    editor = createEditor(host, codeDoc('plaintext', 'const answer = 42'))
    await settle()
    expect(host.querySelector('[class^=hljs-]')).toBeNull()
  })

  it('shows the language and switches it from the picker, remembering the choice', async () => {
    editor = createEditor(host, codeDoc('plaintext', 'let x = 1'))
    await settle()
    const trigger = await screen.findByRole('button', { name: 'Language' })
    expect(trigger.textContent).toContain('Plain text')
    act(() => trigger.click())
    const search = await screen.findByPlaceholderText('Search languages')
    fireEvent.change(search, { target: { value: 'swi' } })
    fireEvent.keyDown(search, { key: 'Enter' })
    await settle()
    expect(editor.getJSON().content?.[0].attrs?.language).toBe('swift')
    expect(lastCodeLanguage()).toBe('swift')
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Language' }).textContent).toContain('Swift')
    )
  })

  it('new code blocks from the "/" menu start in the last language', async () => {
    localStorage.setItem('hikki.codeLanguage', 'python')
    editor = createEditor(host, null)
    const code = BLOCK_TYPES.find((b) => b.id === 'codeBlock')!
    code.apply(editor.chain().focus()).run()
    expect(editor.getJSON().content?.[0]).toMatchObject({
      type: 'codeBlock',
      attrs: { language: 'python' }
    })
  })

  it('copies the code', async () => {
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    editor = createEditor(host, codeDoc('json', '{"a": 1}'))
    await settle()
    act(() => screen.getByRole('button', { name: 'Copy' }).click())
    expect(writeText).toHaveBeenCalledWith('{"a": 1}')
    expect(await screen.findByRole('button', { name: 'Copied' })).toBeTruthy()
  })
})

describe('code languages', () => {
  it('finds languages by name, id and alias', () => {
    expect(findLanguage('ts')?.id).toBe('typescript')
    expect(findLanguage('HTML')?.id).toBe('xml')
    expect(findLanguage('nope')).toBeNull()
    expect(filterLanguages('py').map((l) => l.id)).toContain('python')
  })
})
