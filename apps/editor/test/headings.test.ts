import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { activeHeadingIndex, outlineItems } from '../src/core/headings'

describe('activeHeadingIndex (the outline follows the scroll)', () => {
  it('is the last heading whose top has passed the line', () => {
    expect(activeHeadingIndex([200, 600, 1200], 96, false)).toBe(-1)
    expect(activeHeadingIndex([40, 600, 1200], 96, false)).toBe(0)
    expect(activeHeadingIndex([-900, -300, 90], 96, false)).toBe(2)
    expect(activeHeadingIndex([-900, 100, 400], 96, false)).toBe(0)
  })

  it('is the last heading at the end of the page, even one that never reaches the line', () => {
    expect(activeHeadingIndex([-900, 300, 700], 96, true)).toBe(2)
    expect(activeHeadingIndex([], 96, true)).toBe(-1)
  })
})

describe('a formula as a heading', () => {
  const latex = String.raw`\begin{rcases} a \\ b \end{rcases} \text{場合は}`

  it('is in the outline, read as its LaTeX (it has no text of its own)', () => {
    const host = document.createElement('div')
    document.body.append(host)
    const editor = createEditor(host, {
      type: 'doc',
      content: [
        { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'before' }] },
        {
          type: 'heading',
          attrs: { level: 2 },
          content: [{ type: 'inlineMath', attrs: { latex } }]
        }
      ]
    })
    expect(outlineItems(editor).map((h) => h.text)).toEqual(['before', latex])
    editor.destroy()
    host.remove()
  })

  it('is set at the heading’s size, and its hover tint covers all of it', () => {
    // vitest runs from editor/ (happy-dom rewrites import.meta.url, so resolve from the cwd).
    const styles = readFileSync(join(process.cwd(), 'src/style.css'), 'utf8')
    expect(styles).toMatch(/\[data-type='inline-math'\]\s*\{\s*@apply inline-block /u)
    // Wider than a phone's column, it scrolls inside itself; the page never scrolls sideways (ISSUE-192). Only
    // there: as a scroller on the Mac it clipped a tall formula and showed a bar for a hair of overflow (ISSUE-232).
    const inline = /\[data-type='inline-math'\]\s*\{\s*@apply ([^;]+);/u.exec(styles)![1].split(' ')
    expect(inline).toEqual(
      expect.arrayContaining(['max-w-full', 'max-phone:overflow-x-auto', 'align-bottom'])
    )
    expect(inline).not.toContain('overflow-x-auto')
    // Unlayered (after the last layer closes), or KaTeX's own stylesheet wins.
    const rule = styles.lastIndexOf('.tiptap :is(h1, h2, h3, h4) .katex {')
    expect(rule).toBeGreaterThan(styles.lastIndexOf('@layer'))
    expect(styles.slice(rule)).toMatch(/^[^}]*font-size: 1em;/u)
  })
})
