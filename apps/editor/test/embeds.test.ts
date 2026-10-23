import { describe, expect, it } from 'vitest'

import {
  clampEmbedHeight,
  embedFromHTML,
  embedFromURL,
  frameSrc,
  htmlEmbedDocument,
  isWebURL,
  linkCardFrom,
  safeFrameSrc,
  reloadsOnSchemeChange,
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
    expect(src('https://www.figma.com/design/AbC123/My-file?node-id=1-2&t=xyz')).toBe(
      'https://embed.figma.com/design/AbC123?node-id=1-2&embed-host=hikki'
    )
    // An older /file/ link is a design; boards and prototypes keep their kind.
    expect(src('https://www.figma.com/file/AbC123/Old')).toBe(
      'https://embed.figma.com/design/AbC123?embed-host=hikki'
    )
    expect(src('https://www.figma.com/board/Bo4rd/Jam')).toBe(
      'https://embed.figma.com/board/Bo4rd?embed-host=hikki'
    )
    expect(src('https://www.figma.com/design/AbC123/x?node-id=1"><script>')).toBe(
      'https://embed.figma.com/design/AbC123?embed-host=hikki'
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

  it('a draw.io diagram is told the appearance in its query, the file named after # untouched', () => {
    const viewer = src('https://app.diagrams.net/#Uhttps%3A%2F%2Fexample.com%2Fa.drawio')!
    expect(themedEmbedSrc('drawio', viewer, true)).toBe(
      'https://viewer.diagrams.net/?nav=1&dark=1#Uhttps%3A%2F%2Fexample.com%2Fa.drawio'
    )
    expect(themedEmbedSrc('drawio', `${viewer.replace('?nav=1', '?nav=1&dark=1')}`, false)).toBe(
      'https://viewer.diagrams.net/?nav=1&dark=0#Uhttps%3A%2F%2Fexample.com%2Fa.drawio'
    )
    expect(reloadsOnSchemeChange('drawio')).toBe(true)
    expect(reloadsOnSchemeChange('youtube')).toBe(false)
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

  it('draw.io: the viewer as it is; an editor link opens its diagram (the fragment) in the viewer', () => {
    const viewer = 'https://viewer.diagrams.net/?highlight=0000ff&nav=1#G1AbCdEf'
    expect(src(viewer)).toBe(viewer)
    expect(provider(viewer)).toBe('drawio')
    expect(src('https://app.diagrams.net/#G1AbCdEf_-x')).toBe(
      'https://viewer.diagrams.net/?nav=1#G1AbCdEf_-x'
    )
    expect(src('https://app.diagrams.net/?src=about#Uhttps%3A%2F%2Fexample.com%2Fd.drawio')).toBe(
      'https://viewer.diagrams.net/?nav=1#Uhttps%3A%2F%2Fexample.com%2Fd.drawio'
    )
    expect(src('https://www.draw.io/#R7Vxbc')).toBe('https://viewer.diagrams.net/?nav=1#R7Vxbc')
    // No diagram named: the page itself, as any other link (a card, not a frame).
    expect(provider('https://app.diagrams.net/')).toBe('generic')
  })

  it('Loom share links → the Loom player', () => {
    const id = '0123456789abcdef0123456789abcdef'
    expect(src(`https://www.loom.com/share/${id}?sid=x`)).toBe(`https://www.loom.com/embed/${id}`)
    expect(src(`https://loom.com/embed/${id}`)).toBe(`https://www.loom.com/embed/${id}`)
    expect(provider('https://www.loom.com/share/not-an-id')).toBe('generic')
  })

  it('Excalidraw share and room links are framed as they are; anything else is a plain link', () => {
    expect(src('https://excalidraw.com/#json=abc123_-X,keyKEY_-9')).toBe(
      'https://excalidraw.com/#json=abc123_-X,keyKEY_-9'
    )
    expect(src('https://excalidraw.com/#room=abcdef0123,keyKEY')).toBe(
      'https://excalidraw.com/#room=abcdef0123,keyKEY'
    )
    expect(provider('https://excalidraw.com/')).toBe('generic')
    expect(provider('https://excalidraw.com/#json=<script>')).toBe('generic')
  })

  it('Miro boards → the read-only live embed', () => {
    expect(src('https://miro.com/app/board/uXjVOabc123=/?share_link_id=42')).toBe(
      'https://miro.com/app/live-embed/uXjVOabc123=/?embedMode=view_only_without_ui'
    )
    expect(provider('https://miro.com/pricing/')).toBe('generic')
  })

  it('Airtable shared views → their embed page', () => {
    expect(src('https://airtable.com/shrAbC123xyz')).toBe('https://airtable.com/embed/shrAbC123xyz')
    expect(src('https://airtable.com/appAbC123/shrXyZ789?backgroundColor=red')).toBe(
      'https://airtable.com/embed/appAbC123/shrXyZ789'
    )
    expect(src('https://airtable.com/embed/shrAbC123xyz')).toBe(
      'https://airtable.com/embed/shrAbC123xyz'
    )
    expect(provider('https://airtable.com/appAbC123/tblPrivate')).toBe('generic')
  })

  it('Spotify → the embed player, compact for a track or an episode', () => {
    expect(
      embedFromURL('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=x')
    ).toMatchObject({
      provider: 'spotify',
      src: 'https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC',
      height: 152
    })
    expect(
      embedFromURL('https://open.spotify.com/intl-ja/playlist/37i9dQZF1DXcBWIGoYBM5M')
    ).toMatchObject({
      src: 'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
      height: 352
    })
    expect(src('https://open.spotify.com/episode/abc123')).toBe(
      'https://open.spotify.com/embed/episode/abc123'
    )
    expect(provider('https://open.spotify.com/user/someone')).toBe('generic')
  })

  it('Calendly scheduling pages and Typeform share links → the page itself in a frame', () => {
    expect(embedFromURL('https://calendly.com/acme/30min?month=2026-10')).toMatchObject({
      provider: 'calendly',
      src: 'https://calendly.com/acme/30min',
      height: 700
    })
    expect(src('https://calendly.com/acme')).toBe('https://calendly.com/acme')
    expect(provider('https://calendly.com/acme/30min/extra')).toBe('generic')
    expect(embedFromURL('https://form.typeform.com/to/AbC123?utm=x')).toMatchObject({
      provider: 'typeform',
      src: 'https://form.typeform.com/to/AbC123'
    })
    expect(src('https://acme.typeform.com/to/Xyz9')).toBe('https://form.typeform.com/to/Xyz9')
    expect(provider('https://www.typeform.com/pricing')).toBe('generic')
  })

  it('services dropped from the "/" menu still embed when pasted into Embed', () => {
    expect(provider('https://form.typeform.com/to/AbC123')).toBe('typeform')
    expect(provider('https://twitter.com/jack/status/20')).toBe('tweet')
    expect(provider('https://open.spotify.com/album/1abc')).toBe('spotify')
    expect(provider('https://www.google.com/maps/place/Tokyo+Tower')).toBe('googleMaps')
  })

  it('CodeSandbox sandboxes → their embed page', () => {
    expect(src('https://codesandbox.io/s/new-abc12')).toBe('https://codesandbox.io/embed/new-abc12')
    expect(src('https://codesandbox.io/p/sandbox/react-xyz9')).toBe(
      'https://codesandbox.io/embed/react-xyz9'
    )
    expect(src('https://codesandbox.io/embed/abc?view=preview')).toBe(
      'https://codesandbox.io/embed/abc'
    )
    expect(provider('https://codesandbox.io/docs')).toBe('generic')
  })

  it('every provider’s frame is an https page on the provider’s own host, whatever was pasted', () => {
    const links = [
      'https://app.diagrams.net/#G1AbC',
      'https://www.loom.com/share/0123456789abcdef0123',
      'https://excalidraw.com/#json=a,b',
      'https://miro.com/app/board/uXjV=/',
      'https://airtable.com/shrAbc',
      'https://open.spotify.com/album/1abc',
      'https://codesandbox.io/s/abc',
      'https://www.figma.com/design/k3y/x',
      'https://calendly.com/acme/intro',
      'https://acme.typeform.com/to/abc'
    ]
    const hosts = [
      'viewer.diagrams.net',
      'www.loom.com',
      'excalidraw.com',
      'miro.com',
      'airtable.com',
      'open.spotify.com',
      'codesandbox.io',
      'embed.figma.com',
      'calendly.com',
      'form.typeform.com'
    ]
    links.forEach((link, i) => {
      const frame = src(link)!
      expect(safeFrameSrc(frame), link).toBe(frame)
      expect(new URL(frame).hostname, link).toBe(hosts[i])
    })
    // A look-alike host is just a link.
    expect(provider('https://loom.com.evil.example/share/0123456789abcdef0123')).toBe('generic')
    expect(provider('http://open.spotify.com/track/abc')).toBeUndefined()
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

  it('only https pages may load in a frame; only web pages open outside', () => {
    expect(safeFrameSrc('https://player.vimeo.com/video/1')).toBe(
      'https://player.vimeo.com/video/1'
    )
    for (const bad of [
      'javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
      'hikki-editor://app/index.html',
      'http://example.com/',
      'blob:hikki-editor://app/abc',
      'not a url',
      '',
      null
    ])
      expect(safeFrameSrc(bad)).toBeNull()
    expect(isWebURL('http://example.com/x')).toBe(true)
    expect(isWebURL('https://example.com/x')).toBe(true)
    expect(isWebURL('javascript:alert(1)')).toBe(false)
    expect(isWebURL('file:///etc/passwd')).toBe(false)
    expect(isWebURL(null)).toBe(false)
  })

  it('a native link preview reply is checked before it reaches a card', () => {
    expect(linkCardFrom({ title: ' A ', description: '', icon: 'https://x.com/i.png' })).toEqual({
      title: 'A',
      description: null,
      icon: 'https://x.com/i.png'
    })
    expect(linkCardFrom({ title: 3, icon: 'javascript:alert(1)' })).toEqual({
      title: null,
      description: null,
      icon: null
    })
    expect(linkCardFrom(null)).toBeNull()
    expect(linkCardFrom('nope')).toBeNull()
  })

  it('heights stay within the range', () => {
    expect(clampEmbedHeight(50)).toBe(120)
    expect(clampEmbedHeight(400.4)).toBe(400)
    expect(clampEmbedHeight(5000)).toBe(1200)
  })
})
