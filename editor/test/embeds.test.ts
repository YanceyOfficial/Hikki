import { describe, expect, it } from 'vitest'

import {
  clampEmbedHeight,
  embedFromHTML,
  embedFromURL,
  frameSrc,
  htmlEmbedDocument,
  themedEmbedSrc
} from '../src/lib/embeds'

const src = (input: string) => {
  const source = embedFromURL(input)
  return source?.kind === 'iframe' ? source.src : null
}
const provider = (input: string) => embedFromURL(input)?.provider

describe('embedFromURL', () => {
  it('YouTube in its forms → the no-cookie player', () => {
    expect(src('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s')).toBe(
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=42'
    )
    expect(src('https://youtu.be/dQw4w9WgXcQ')).toBe(
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'
    )
    expect(src('https://youtube.com/shorts/dQw4w9WgXcQ')).toBe(
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'
    )
    expect(provider('https://youtu.be/dQw4w9WgXcQ')).toBe('youtube')
  })

  it('Vimeo, Figma, CodePen → their players and embed pages', () => {
    expect(src('https://vimeo.com/123456789')).toBe('https://player.vimeo.com/video/123456789')
    expect(src('https://www.figma.com/design/AbC123/My-file?node-id=1-2')).toBe(
      'https://www.figma.com/embed?embed_host=hikki&url=' +
        encodeURIComponent('https://www.figma.com/design/AbC123/My-file?node-id=1-2')
    )
    expect(src('https://codepen.io/someone/pen/abcXYZ')).toBe(
      'https://codepen.io/someone/embed/abcXYZ?default-tab=result'
    )
  })

  it('Google Maps → the embed view of the place; an embed link stays as it is', () => {
    expect(src('https://www.google.com/maps/place/Tokyo+Tower/@35.65,139.74,17z')).toBe(
      'https://maps.google.com/maps?q=Tokyo%20Tower&output=embed'
    )
    expect(src('https://www.google.com/maps/@35.65,139.74,15z')).toBe(
      'https://maps.google.com/maps?q=35.65%2C139.74&output=embed'
    )
    const embed = 'https://www.google.com/maps/embed?pb=!1m18'
    expect(src(embed)).toBe(embed)
  })

  it('Google Drive and Docs → previews', () => {
    expect(src('https://drive.google.com/file/d/1aB_c-D/view?usp=sharing')).toBe(
      'https://drive.google.com/file/d/1aB_c-D/preview'
    )
    expect(src('https://docs.google.com/spreadsheets/d/1xyz/edit#gid=0')).toBe(
      'https://docs.google.com/spreadsheets/d/1xyz/preview'
    )
    expect(src('https://docs.google.com/forms/d/e/1FAIpQL/viewform')).toBe(
      'https://docs.google.com/forms/d/e/1FAIpQL/viewform?embedded=true'
    )
    expect(provider('https://drive.google.com/file/d/1aB_c-D/view')).toBe('googleDrive')
  })

  it('a gist becomes a snippet that loads its script; a tweet goes through the platform frame', () => {
    const gist = embedFromURL('https://gist.github.com/octocat/6cad326836d38bd3a7ae')
    expect(gist).toMatchObject({
      kind: 'html',
      html: '<script src="https://gist.github.com/octocat/6cad326836d38bd3a7ae.js"></script>'
    })
    expect(src('https://x.com/jack/status/20')).toBe(
      'https://platform.twitter.com/embed/Tweet.html?id=20&dnt=true'
    )
    expect(
      themedEmbedSrc('tweet', 'https://platform.twitter.com/embed/Tweet.html?id=20', true)
    ).toBe('https://platform.twitter.com/embed/Tweet.html?id=20&theme=dark')
    expect(themedEmbedSrc('generic', 'https://example.com/', true)).toBe('https://example.com/')
  })

  it('any other https link is framed as it is; bare domains become https; the rest is refused', () => {
    expect(embedFromURL('https://example.com/page')).toMatchObject({
      kind: 'iframe',
      provider: 'generic',
      src: 'https://example.com/page',
      original: 'https://example.com/page',
      height: 400
    })
    expect(src('example.com/page')).toBe('https://example.com/page')
    expect(embedFromURL('http://example.com/')).toBeNull()
    expect(embedFromURL('javascript:alert(1)')).toBeNull()
    expect(embedFromURL('   ')).toBeNull()
    expect(embedFromURL('not a link at all')).toBeNull()
  })
})

describe('embedFromHTML and friends', () => {
  it('keeps a trimmed snippet, refuses an empty one, and wraps it in a page of the right scheme', () => {
    expect(embedFromHTML('  <b>hi</b> ')).toMatchObject({ kind: 'html', html: '<b>hi</b>' })
    expect(embedFromHTML('   ')).toBeNull()
    const page = htmlEmbedDocument('<b>hi</b>', true)
    expect(page).toContain('<b>hi</b>')
    expect(page).toContain('color-scheme" content="dark"')
    expect(htmlEmbedDocument('x', false)).toContain('content="light"')
  })

  it('YouTube frames go through the BFF shim when there is a BFF; nothing else does', () => {
    const player = 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'
    expect(frameSrc('youtube', `${player}?start=7`, 'https://bff.example')).toBe(
      'https://bff.example/embed/youtube/dQw4w9WgXcQ?start=7'
    )
    expect(frameSrc('youtube', player, 'https://bff.example')).toBe(
      'https://bff.example/embed/youtube/dQw4w9WgXcQ'
    )
    expect(frameSrc('youtube', player, null)).toBe(player)
    expect(frameSrc('vimeo', 'https://player.vimeo.com/video/1', 'https://bff.example')).toBe(
      'https://player.vimeo.com/video/1'
    )
  })

  it('heights stay within the range', () => {
    expect(clampEmbedHeight(50)).toBe(120)
    expect(clampEmbedHeight(400.4)).toBe(400)
    expect(clampEmbedHeight(5000)).toBe(1200)
  })
})
