import { describe, expect, it } from 'vitest'

import {
  embedFrameHeight,
  embedThemeCSS,
  embedThemeMessage,
  gistEmbedDocument,
  isGistSnippet
} from '../src/lib/gist-embed'

const snippet = '<script src="https://gist.github.com/octocat/6cad326836d38bd3a7ae.js"></script>'
const theme = (dark: boolean) => ({
  dark,
  tokens: {
    foreground: dark ? 'white' : 'black',
    'syntax-keyword': 'purple',
    'font-mono': 'Menlo'
  }
})

describe('gists', () => {
  it('a gist is recognised by its snippet alone', () => {
    expect(isGistSnippet(snippet)).toBe(true)
    expect(isGistSnippet(` ${snippet}\n`)).toBe(true)
    expect(isGistSnippet(`${snippet}<script>alert(1)</script>`)).toBe(false)
    expect(isGistSnippet('<script src="https://evil.example/a.js"></script>')).toBe(false)
    expect(isGistSnippet(null)).toBe(false)
  })

  it('its page carries our stylesheet, the page’s tokens and the sizing script, in the page’s scheme', () => {
    const page = gistEmbedDocument(snippet, theme(true))
    expect(page).toContain(snippet)
    expect(page).toContain('content="dark"')
    expect(page).toContain('--hk-foreground:white;')
    expect(page).toContain('--hk-syntax-keyword:purple;')
    // GitHub's classes take the syntax tokens; the "hosted by" link is hidden.
    expect(page).toContain('.gist .pl-k')
    expect(page).toContain('var(--hk-syntax-keyword)')
    expect(page).toContain('a[href="https://github.com"]{display:none')
    expect(page).toContain("hikkiEmbed:'size'")
    expect(page).toContain('<base target="_blank">')
    expect(gistEmbedDocument(snippet, theme(false))).toContain('content="light"')
  })

  it('a token can’t break out of the frame’s style element', () => {
    const css = embedThemeCSS({
      dark: false,
      tokens: { foreground: 'red;}</style><script>alert(1)</script>', 'Bad Name': 'x' }
    })
    expect(css).not.toContain('<')
    expect(css).not.toContain('Bad Name')
    expect(css.startsWith(':root{color-scheme:light;')).toBe(true)
    expect(css.match(/[{}]/gu)).toEqual(['{', '}'])
  })

  it('a theme change is one message; a frame’s size report is checked', () => {
    expect(embedThemeMessage(theme(true))).toMatchObject({ hikkiEmbed: 'theme', dark: true })
    expect(embedThemeMessage(theme(true)).css).toContain('color-scheme:dark')
    expect(embedFrameHeight({ hikkiEmbed: 'size', height: 211.2 })).toBe(212)
    for (const bad of [
      null,
      'x',
      { hikkiEmbed: 'size', height: 'big' },
      { hikkiEmbed: 'size', height: -1 },
      { hikkiEmbed: 'other', height: 5 },
      { hikkiEmbed: 'size', height: Infinity }
    ])
      expect(embedFrameHeight(bad)).toBeNull()
  })
})
