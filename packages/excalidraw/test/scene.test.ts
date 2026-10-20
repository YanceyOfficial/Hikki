import { readdirSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'

import { describe, expect, it } from 'vitest'

import {
  drawingText,
  excalidrawLanguage,
  mermaidFromAnswer,
  storedElements,
  storedFiles,
  usedFileIds
} from '../src/scene'
import { LOCAL_FALLBACK, withoutCDNFallback } from '../vite-plugin'

const safe = (src: string) => src.startsWith('hikki-editor://assets/')

describe('a stored drawing', () => {
  it('keeps only live elements that have an id and a type', () => {
    const elements = storedElements([
      { id: 'a', type: 'rectangle' },
      { id: 'b', type: 'text', isDeleted: true },
      { type: 'ellipse' },
      'junk',
      null,
      [1, 2]
    ])
    expect(elements.map((e) => e.id)).toEqual(['a'])
    expect(storedElements({ not: 'an array' })).toEqual([])
  })

  it('keeps picture references with a safe src and a picture type', () => {
    expect(
      storedFiles(
        {
          ok: { src: 'hikki-editor://assets/a.png', mimeType: 'image/png' },
          web: { src: 'javascript:alert(1)', mimeType: 'image/png' },
          html: { src: 'hikki-editor://assets/b.html', mimeType: 'text/html' },
          broken: { src: 1 }
        },
        safe
      )
    ).toEqual({ ok: { src: 'hikki-editor://assets/a.png', mimeType: 'image/png' } })
    expect(storedFiles([], safe)).toEqual({})
  })

  it('reads its words one text element a line, as typed (ContentText reads the same)', () => {
    expect(
      drawingText([
        { id: 'r', type: 'rectangle' },
        { id: 't1', type: 'text', text: 'Login', originalText: 'Login' },
        { id: 't2', type: 'text', text: 'gone', isDeleted: true },
        { id: 't3', type: 'text', text: 'Wrapped\nline', originalText: 'Wrapped line' },
        { id: 't4', type: 'text', text: '  ' }
      ])
    ).toBe('Login\nWrapped line')
    expect(drawingText([])).toBe('')
  })

  it('names the pictures its image elements show, once each', () => {
    expect(
      usedFileIds([
        { id: 'a', type: 'image', fileId: 'f1' },
        { id: 'b', type: 'image', fileId: 'f1' },
        { id: 'c', type: 'image', fileId: 'f2', isDeleted: true },
        { id: 'd', type: 'rectangle', fileId: 'f3' }
      ])
    ).toEqual(['f1'])
  })
})

describe('text to diagram', () => {
  it('takes the Mermaid out of a fenced answer, or the whole answer', () => {
    expect(mermaidFromAnswer('Here:\n```mermaid\nflowchart LR\n  A --> B\n```\nDone')).toBe(
      'flowchart LR\n  A --> B'
    )
    expect(mermaidFromAnswer('```\nsequenceDiagram\n  A->>B: hi\n```')).toBe(
      'sequenceDiagram\n  A->>B: hi'
    )
    expect(mermaidFromAnswer('  flowchart TD\n  A --> B\n')).toBe('flowchart TD\n  A --> B')
    expect(mermaidFromAnswer('   ')).toBe('')
  })
})

describe("Excalidraw's language", () => {
  it('follows the app', () => {
    expect(excalidrawLanguage('zh-Hans')).toBe('zh-CN')
    expect(excalidrawLanguage('zh-Hant-TW')).toBe('zh-TW')
    expect(excalidrawLanguage('en')).toBe('en')
    expect(excalidrawLanguage('fr')).toBe('en')
  })
})

describe('no CDN', () => {
  it("takes esm.sh out of every Excalidraw chunk that names it (the editor's build runs the same)", () => {
    const require = createRequire(import.meta.url)
    const prod = dirname(require.resolve('@excalidraw/excalidraw'))
    let patched = 0
    for (const folder of [prod, join(prod, '../dev')]) {
      for (const name of readdirSync(folder).filter((file) => file.endsWith('.js'))) {
        const code = readFileSync(join(folder, name), 'utf8')
        if (!code.includes('esm.sh')) continue
        const out = withoutCDNFallback(code)
        expect(out).not.toContain('esm.sh')
        expect(out).toContain(LOCAL_FALLBACK)
        patched += 1
      }
    }
    expect(patched).toBe(2)
  })
})
