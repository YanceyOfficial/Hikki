import { readdirSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'

import { describe, expect, it } from 'vitest'

import {
  checkPaste,
  drawingText,
  excalidrawLanguage,
  inlineFiles,
  mermaidFromAnswer,
  safeDrawingLink,
  safeMermaid,
  storedElements,
  storedFiles,
  usedFileIds
} from '../src/scene'
import { LOCAL_FALLBACK, withoutCDNFallback, withoutRemoteContent } from '../vite-plugin'

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

describe('a hostile scene', () => {
  it('loses every element that would load or run a page, and the HTML a frame would run', () => {
    const elements = storedElements([
      {
        id: 'a',
        type: 'rectangle',
        customData: { generationData: { status: 'done', html: '<script>' } }
      },
      { id: 'b', type: 'embeddable', link: 'https://evil.example' },
      {
        id: 'c',
        type: 'iframe',
        customData: { generationData: { status: 'done', html: '<script>' } }
      },
      { id: 'd', type: 'magicframe' },
      { id: 'e', type: 'unknown-from-the-future' }
    ])
    expect(elements).toEqual([{ id: 'a', type: 'rectangle' }])
  })

  it('keeps links to the web only', () => {
    const links = storedElements(
      [
        'https://example.com/a',
        'http://example.com',
        'javascript:alert(1)',
        ' JavaScript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
        '?element=abc',
        null
      ].map((link, i) => ({ id: String(i), type: 'text', link }))
    ).map((element) => element.link)
    expect(links).toEqual([
      'https://example.com/a',
      'http://example.com/',
      null,
      null,
      null,
      null,
      null,
      null
    ])
    expect(safeDrawingLink(42)).toBeNull()
  })

  it('takes pictures only as data, never by address', () => {
    const files = inlineFiles({
      ok: { mimeType: 'image/png', dataURL: 'data:image/png;base64,iVBORw0KGgo=' },
      web: { mimeType: 'image/png', dataURL: 'https://tracker.example/p.png' },
      html: { mimeType: 'text/html', dataURL: 'data:text/html;base64,PHNjcmlwdD4=' },
      lying: { mimeType: 'image/png', dataURL: 'data:text/html;base64,PHNjcmlwdD4=' }
    })
    expect(Object.keys(files)).toEqual(['ok'])
  })

  it('checks a paste like a stored drawing before Excalidraw takes it', () => {
    const data = {
      elements: [
        { id: 'a', type: 'text', link: 'javascript:alert(1)' },
        { id: 'b', type: 'embeddable', link: 'https://evil.example' }
      ],
      files: { web: { mimeType: 'image/png', dataURL: 'https://tracker.example/p.png' } },
      text: 'flowchart TD\n  A["<img src=https://tracker.example/p.png>Hi"] --> B\n  click A "https://evil.example"'
    }
    expect(checkPaste(data)).toBe(true)
    expect(data.elements).toEqual([{ id: 'a', type: 'text', link: null }])
    expect(data.files).toEqual({})
    expect(data.text).toBe('flowchart TD\n  A["Hi"] --> B')
  })

  it('draws Mermaid with nothing in it that loads or runs', () => {
    expect(
      safeMermaid(
        '%%{init: {"securityLevel": "loose"}}%%\ngraph LR\n  A[<b>Bold</b><br/>next] <--> B\n  style A fill:url(https://x.example/a.svg)\n  B -->|go| C\n  href B "https://x"'
      )
    ).toBe(
      'graph LR\n  A[Bold<br/>next] <--> B\n  style A fill:https://x.example/a.svg)\n  B -->|go| C'
    )
    // A model's answer goes through the same.
    expect(mermaidFromAnswer('```mermaid\ngraph TD\n  A[<img src=https://x>] --> B\n```')).toBe(
      'graph TD\n  A[] --> B'
    )
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

  it("stops Excalidraw fetching pasted pictures by address and running a frame element's HTML, in both builds", () => {
    const require = createRequire(import.meta.url)
    const prod = dirname(require.resolve('@excalidraw/excalidraw'))
    for (const folder of [prod, join(prod, '../dev')]) {
      const code = readFileSync(join(folder, 'index.js'), 'utf8')
      const { code: out, patched } = withoutRemoteContent(code)
      // Each patch finds its one place: a new Excalidraw that moved it fails here rather than shipping unpatched.
      expect(patched).toEqual([1, 1])
      expect(out).not.toMatch(/"imageUrl"\)\s*&&\s*this\.isToolSupported/u)
      expect(out).not.toMatch(/generationData\s*\?\?\s*this\.magicGenerations/u)
    }
  })
})
