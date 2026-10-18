import { act, fireEvent, screen, waitFor } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { BLOCK_TYPES } from '../src/core/blocks'
import { createEditor } from '../src/core/editor'
import { detectLanguage } from '../src/extensions/code-block'
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

  it('"Auto-detect" highlights by guessing and names the guess in the header', async () => {
    editor = createEditor(
      host,
      codeDoc(
        'auto',
        'function add(a, b) {\n  return a + b\n}\nexport const total = [1, 2, 3].reduce(add, 0)'
      )
    )
    await settle()
    expect(host.querySelector('.hljs-keyword')).not.toBeNull()
    await waitFor(
      () =>
        expect(host.querySelector('.hk-code-header')?.textContent).toContain(
          'Auto-detect · JavaScript'
        ),
      { timeout: 2000 }
    )
  })

  it('detectLanguage tells the catalog languages apart by their signatures, and stays quiet otherwise', () => {
    expect(detectLanguage('x = 1')).toBeNull()
    expect(
      detectLanguage('hello there, this is a sentence of prose with no code in it at all')
    ).toBeNull()
    const samples: Record<string, string> = {
      javascript:
        'function add(a, b) {\n  return a + b\n}\nconsole.log(add(1, 2))\nexport default add',
      typescript:
        'interface Page {\n  id: string\n  title: string\n}\nexport const empty: Page = { id: "", title: "" }',
      python:
        'def add(a, b):\n    return a + b\n\nprint(add(1, 2))\nfor i in range(3):\n    print(i)',
      swift:
        'import Foundation\n\nstruct Page: Codable {\n    let id: String\n    var title: String\n}\nfunc open(_ page: Page) {}',
      rust: 'fn main() {\n    let mut total = 0;\n    for n in 1..4 { total += n; }\n    println!("{}", total);\n}',
      go: 'package main\n\nimport "fmt"\n\nfunc main() {\n\tx := 1\n\tfmt.Println(x)\n}',
      css: '.hk-pop {\n  transform-origin: top left;\n  animation: hk-pop-in 150ms ease-out;\n}\n.row:hover { color: red; }',
      json: '{\n  "id": "a",\n  "title": "Plan",\n  "tags": ["x", "y"],\n  "locked": false\n}',
      sql: 'SELECT id, title FROM document WHERE deletedAt IS NULL ORDER BY sortKey',
      bash: '#!/bin/bash\nfor f in *.json; do\n  echo "$f"\ndone',
      yaml: 'name: hikki\nversion: 1\nscripts:\n  - build\n  - test',
      xml: '<!DOCTYPE html>\n<html>\n  <body><p class="x">Hi</p></body>\n</html>',
      java: 'import java.util.List;\n\npublic class Main {\n  public static void main(String[] args) {\n    System.out.println("hi");\n  }\n}',
      diff: '--- a/x.ts\n+++ b/x.ts\n@@ -1,2 +1,2 @@\n-const a = 1\n+const a = 2',
      markdown: '# Title\n\nSome **bold** text and a [link](https://example.com).\n\n- one\n- two'
    }
    for (const [language, code] of Object.entries(samples)) {
      expect(detectLanguage(code), language).toBe(language)
    }
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
    // The header is a React root rendered after the node view mounts: wait for it rather than one tick.
    const copy = await screen.findByRole('button', { name: 'Copy' })
    act(() => copy.click())
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
