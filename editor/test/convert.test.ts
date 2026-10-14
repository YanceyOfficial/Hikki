import { describe, expect, it } from 'vitest'

import { exportPage, importDocument } from '../src/core/convert'
import { stripIds } from './helpers'

const text = (value: string, marks?: { type: string; attrs?: object }[]) => ({
  type: 'text',
  text: value,
  ...(marks ? { marks } : {})
})
const p = (...content: object[]) => ({ type: 'paragraph', content })

const rich = {
  type: 'doc',
  content: [
    { type: 'heading', attrs: { level: 2 }, content: [text('Section')] },
    p(
      text('Some '),
      text('bold', [{ type: 'bold' }]),
      text(' and '),
      text('a link', [{ type: 'link', attrs: { href: 'https://example.com' } }])
    ),
    {
      type: 'bulletList',
      content: [
        { type: 'listItem', content: [p(text('one'))] },
        { type: 'listItem', content: [p(text('two'))] }
      ]
    },
    { type: 'codeBlock', attrs: { language: 'js' }, content: [text('let x = 1')] },
    { type: 'image', attrs: { src: 'hikki-editor://assets/cat.png', alt: 'cat' } },
    { type: 'callout', content: [p(text('inside a callout'))] }
  ]
}

describe('export', () => {
  it('writes Markdown with the title as the first heading', () => {
    const md = exportPage({ title: 'My page', content: rich }, 'markdown')
    expect(md.startsWith('# My page\n\n## Section\n')).toBe(true)
    expect(md).toContain('Some **bold** and [a link](https://example.com)')
    expect(md).toMatch(/- one\n- two/u)
    expect(md).toContain('```js\nlet x = 1\n```')
    expect(md).toContain('hikki-editor://assets/cat.png')
    // A block without a Markdown form of its own keeps its words.
    expect(md).toContain('inside a callout')
  })

  it('writes a whole HTML document', () => {
    const html = exportPage({ title: 'A <page>', content: rich }, 'html')
    expect(html).toMatch(/^<!doctype html>/u)
    expect(html).toContain('<title>A &lt;page&gt;</title>')
    expect(html).toContain('<h1>A &lt;page&gt;</h1>')
    expect(html).toContain('<strong>bold</strong>')
    expect(html).toContain('src="hikki-editor://assets/cat.png"')
    expect(html).toContain('inside a callout')
  })

  it('writes blocks Markdown has no form for as the HTML the page renders', () => {
    const md = exportPage(
      {
        title: 'Files',
        content: {
          type: 'doc',
          content: [
            {
              type: 'fileAttachment',
              attrs: { src: 'hikki-editor://assets/a.pdf', name: 'report.pdf' }
            }
          ]
        }
      },
      'markdown'
    )
    expect(md).toMatch(/<[a-z]+ [^>]*data-type="file"[^>]*>report\.pdf</u)
    expect(md).toContain('hikki-editor://assets/a.pdf')
  })

  it('leaves the title out when there is none', () => {
    const md = exportPage(
      { title: '', content: { type: 'doc', content: [p(text('just text'))] } },
      'markdown'
    )
    expect(md).toBe('just text\n')
  })
})

describe('import', () => {
  it('reads Markdown into the schema, the first H1 as the title', () => {
    const page = importDocument(
      '# Trip\n\nPack **light**.\n\n- [ ] passport\n- [x] tickets\n',
      'markdown',
      'trip'
    )
    expect(page.title).toBe('Trip')
    const blocks = stripIds(page.content).content
    expect(blocks[0]).toEqual({
      type: 'paragraph',
      content: [
        { type: 'text', text: 'Pack ' },
        { type: 'text', text: 'light', marks: [{ type: 'bold' }] },
        { type: 'text', text: '.' }
      ]
    })
    expect(blocks[1].type).toBe('taskList')
    expect(
      blocks[1].content.map((item: { attrs: { checked: boolean } }) => item.attrs.checked)
    ).toEqual([false, true])
  })

  it('falls back to the file name without a leading H1', () => {
    const page = importDocument('## Not a title\n\ntext', 'markdown', 'notes')
    expect(page.title).toBe('notes')
    expect(page.content.content?.[0]?.type).toBe('heading')
  })

  it('reads HTML through the schema: scripts and unknown elements go, the <title> names the page', () => {
    const page = importDocument(
      '<html><head><title>Saved</title></head><body><h2>Hi</h2><script>alert(1)</script><p>a <em>b</em></p><marquee>c</marquee></body></html>',
      'html',
      'file'
    )
    expect(page.title).toBe('Saved')
    const json = JSON.stringify(page.content)
    expect(json).not.toContain('alert')
    expect(stripIds(page.content).content[0]).toEqual({
      type: 'heading',
      attrs: { level: 2 },
      content: [{ type: 'text', text: 'Hi' }]
    })
    expect(json).toContain('"italic"')
  })

  it('keeps an HTML page whose <h1> repeats its title once', () => {
    const page = importDocument('<title>Doc</title><h1>Doc</h1><p>x</p>', 'html', 'f')
    expect(page.title).toBe('Doc')
    expect(stripIds(page.content).content).toEqual([
      { type: 'paragraph', content: [{ type: 'text', text: 'x' }] }
    ])
  })

  it('reads plain text as paragraphs, keeping line breaks inside one', () => {
    const page = importDocument('first\nline two\n\n\nsecond\r\n', 'text', 'plain')
    expect(page.title).toBe('plain')
    expect(page.text).toBe('first\nline two\nsecond')
    expect(page.wordCount).toBe(5) // the title counts too
    expect(page.content).toEqual({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            { type: 'text', text: 'first' },
            { type: 'hardBreak' },
            { type: 'text', text: 'line two' }
          ]
        },
        { type: 'paragraph', content: [{ type: 'text', text: 'second' }] }
      ]
    })
  })

  it('an empty file is an empty page', () => {
    expect(importDocument('', 'markdown', 'empty')).toMatchObject({
      title: 'empty',
      content: { type: 'doc', content: [{ type: 'paragraph' }] }
    })
  })

  it('round-trips its own Markdown export', () => {
    const md = exportPage({ title: 'Round', content: rich }, 'markdown')
    const page = importDocument(md, 'markdown', 'x')
    expect(page.title).toBe('Round')
    const types = stripIds(page.content).content.map((b: { type: string }) => b.type)
    expect(types.slice(0, 4)).toEqual(['heading', 'paragraph', 'bulletList', 'codeBlock'])
  })
})
