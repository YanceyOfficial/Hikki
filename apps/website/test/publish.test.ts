import katex from 'katex'
// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest'

import fixture from '../../../design/fixtures/publish.json'
import {
  blobType,
  coverView,
  hasLinks,
  outline,
  decrypt,
  hasMath,
  isListed,
  keyFromFragment,
  listRequest,
  listURL,
  lookupRequest,
  lookupURL,
  parseList,
  PUBLISH_TAGS,
  queryTerms,
  recordFiles,
  renderMath,
  sanitize,
  saveToHikkiURL,
  searchTerms,
  sharedTitle
} from '../src/publish'

const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCodePoint(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/u, '')

describe('the link', () => {
  it('carries a 32-byte key in its fragment, base64url', () => {
    const key = new Uint8Array(32).map((_, i) => i)
    expect(keyFromFragment(`#${base64url(key)}`)).toEqual(key)
    expect(keyFromFragment('')).toBeNull()
    expect(keyFromFragment('#short')).toBeNull()
    expect(keyFromFragment('#!!!!')).toBeNull()
  })

  it('reads the record from the public database, development or production', () => {
    expect(lookupURL('production', 'abc')).toBe(
      'https://api.apple-cloudkit.com/database/1/iCloud.app.yancey.hikki/production/public/records/lookup?ckAPIToken=abc'
    )
    expect(lookupURL('development', 'a/b')).toContain(
      '/development/public/records/lookup?ckAPIToken=a%2Fb'
    )
  })

  it('asks for the record as a simple request, with no header that needs a CORS preflight', () => {
    const request = lookupRequest('abc-123')
    expect(request.method).toBe('POST')
    // CloudKit's preflight allows no request headers: a content-type header got the lookup blocked in the browser.
    expect(request.headers).toBeUndefined()
    expect(JSON.parse(String(request.body))).toEqual({ records: [{ recordName: 'abc-123' }] })
  })

  it('opens what the app sealed (AES-GCM, nonce first)', async () => {
    const key = crypto.getRandomValues(new Uint8Array(32))
    const nonce = crypto.getRandomValues(new Uint8Array(12))
    const cryptoKey = await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt'])
    const sealed = new Uint8Array(
      await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: nonce },
        cryptoKey,
        new TextEncoder().encode('{"title":"T"}')
      )
    )
    const combined = new Uint8Array(12 + sealed.length)
    combined.set(nonce)
    combined.set(sealed, 12)
    expect(new TextDecoder().decode(await decrypt(combined.buffer, key))).toBe('{"title":"T"}')
    await expect(
      decrypt(combined.buffer, crypto.getRandomValues(new Uint8Array(32)))
    ).rejects.toBeDefined()
  })
})

describe('the record', () => {
  it('names the payload and the files, with the file name filled in', () => {
    const files = recordFiles({
      fields: {
        payloadFile: { value: { downloadURL: 'https://cv.example/x/${f}?o=1' } },
        files: { value: [{ downloadURL: 'https://cv.example/y/${f}?o=2' }] }
      }
    })
    expect(files).toEqual({
      payloadURL: 'https://cv.example/x/payload?o=1',
      fileURLs: ['https://cv.example/y/file-0?o=2']
    })
    expect(recordFiles({ serverErrorCode: 'NOT_FOUND' })).toBe('notFound')
    expect(recordFiles({ serverErrorCode: 'ACCESS_DENIED' })).toBeNull()
    expect(recordFiles({ fields: {} })).toBeNull()
    expect(recordFiles(null)).toBeNull()
  })
})

const assets = (name: string) => (name === 'a.png' ? 'blob:x' : null)

describe('the HTML', () => {
  it('keeps the page and drops what could run or reach out', () => {
    const html =
      '<h1>T</h1><p onclick="x()">Hi <a href="javascript:alert(1)">bad</a> <a href="https://a.b/c">ok</a></p>' +
      '<script>alert(1)</script><style>p{}</style><img src="assets/a.png" alt="a"><img src="https://evil/x.png">' +
      '<iframe src="https://www.youtube.com/embed/1"></iframe><iframe src="javascript:x"></iframe>'
    const out = sanitize(html, assets)
    expect(out).toContain('<h1>T</h1>')
    expect(out).not.toContain('onclick')
    expect(out).not.toContain('javascript:')
    expect(out).not.toContain('<script')
    expect(out).not.toContain('<style')
    expect(out).toContain(
      '<a href="https://a.b/c" rel="noopener noreferrer" target="_blank">ok</a>'
    )
    expect(out).toContain('<img src="blob:x" alt="a">')
    expect(out).not.toContain('evil')
    expect(out).toContain(
      '<a href="https://www.youtube.com/embed/1" rel="noopener noreferrer" target="_blank">https://www.youtube.com/embed/1</a>'
    )
    expect(out).not.toContain('<iframe')
  })

  it("keeps an unknown block as its text and the editor's classes and data attributes", () => {
    const out = sanitize(
      '<custom-block class="c"><p>inside</p></custom-block><div data-type="callout" class="x" style="color:red">c</div>',
      assets
    )
    expect(out).toContain('inside')
    expect(out).not.toContain('custom-block')
    expect(out).toContain('<div data-type="callout" class="x">c</div>')
  })

  it('keeps checkboxes read-only and drops other inputs', () => {
    const out = sanitize(
      '<ul><li><input type="checkbox" checked>done</li></ul><input type="text" value="x">',
      assets
    )
    expect(out).toContain('<input type="checkbox" checked="" disabled="">')
    expect(out).not.toContain('type="text"')
  })
})

describe('Hikki Shared', () => {
  it("files pages under the app's preset tags", () => {
    expect(PUBLISH_TAGS.map((tag) => tag.id)).toEqual(fixture.tags)
  })

  it('finds a page by the terms the app gave it', () => {
    for (const item of fixture.terms) expect(searchTerms(item.text), item.text).toEqual(item.terms)
    for (const item of fixture.queries)
      expect(queryTerms(item.query), item.query).toEqual(item.terms)
  })

  it('asks for listed pages, newest first, under a tag and holding every term', () => {
    expect(listURL('production', 't')).toContain('/production/public/records/query?ckAPIToken=t')
    const request = listRequest({ query: 'N5 文法', tag: 'study', marker: 'next' })
    expect(request.headers).toBeUndefined()
    const body = JSON.parse(String(request.body))
    expect(body.query.recordType).toBe('PublishedPage')
    expect(body.query.sortBy).toEqual([{ fieldName: 'publishedAt', ascending: false }])
    expect(
      body.query.filterBy.map((f: { fieldName: string; fieldValue: { value: unknown } }) => [
        f.fieldName,
        f.fieldValue.value
      ])
    ).toEqual([
      ['listed', 1],
      ['tags', 'study'],
      ['terms', 'n5'],
      ['terms', '文法']
    ])
    expect(body.continuationMarker).toBe('next')
    expect(JSON.parse(String(listRequest({}).body)).query.filterBy).toHaveLength(1)
  })

  it('reads the list, leaving out a record without its title', () => {
    const list = parseList({
      records: [
        {
          recordName: 'a',
          fields: {
            title: { value: 'Grammar' },
            icon: { value: '🚀' },
            excerpt: { value: 'Words' },
            tags: { value: ['study', 7] },
            author: { value: ' Yancey ' },
            publishedAt: { value: 1793158373564 }
          }
        },
        { recordName: 'b', fields: {} }
      ],
      continuationMarker: 'm'
    })
    expect(list).toEqual({
      pages: [
        {
          id: 'a',
          title: 'Grammar',
          icon: '🚀',
          excerpt: 'Words',
          tags: ['study'],
          author: 'Yancey',
          publishedAt: 1793158373564
        }
      ],
      marker: 'm'
    })
    expect(parseList({ serverErrorCode: 'BAD_REQUEST' })).toBeNull()
    expect(isListed({ fields: { listed: { value: 1 } } })).toBe(true)
    expect(isListed({ fields: { listed: { value: 0 } } })).toBe(false)
  })

  it('hands the app its own link to save a copy', () => {
    expect(saveToHikkiURL('abc')).toBe('hikki://shared/abc')
    expect(saveToHikkiURL('abc', 'k_1')).toBe('hikki://shared/abc#k_1')
  })

  it("reads the export's body only, without its head or the title heading", () => {
    const html =
      '<!doctype html><html><head><title>N5</title><style>body{max-width:46rem}</style></head><body><h1>N5</h1><h2>Nouns</h2><p>Text</p></body></html>'
    const out = sanitize(html, () => null, 'N5')
    expect(out).toBe('<h2>Nouns</h2><p>Text</p>')
    // Another first heading stays.
    expect(sanitize('<h1>Other</h1>', () => null, 'N5')).toBe('<h1>Other</h1>')
  })
})

describe('formulas', () => {
  it('draws the formulas the export keeps as their source, inline and as blocks', () => {
    const html = sanitize(
      '<p>Area <span data-type="inline-math" data-latex="\\pi r^2"></span></p><div data-type="block-math" data-latex="e^{i\\pi}+1=0"></div>',
      () => null
    )
    expect(hasMath(html)).toBe(true)
    const out = renderMath(html, katex)
    expect(out).toContain('class="katex"')
    expect(out).toContain('katex-display')
    expect(hasMath('<p>none</p>')).toBe(false)
  })

  it('shows a formula KaTeX cannot read as an error, and never makes a link of one', () => {
    for (const latex of ['\\frac{', '\\href{javascript:alert(1)}{x}']) {
      const out = renderMath(`<span data-type="inline-math" data-latex="${latex}"></span>`, katex)
      expect(out).not.toMatch(/<a\b|href=/u)
    }
    expect(
      renderMath('<span data-type="inline-math" data-latex="\\frac{"></span>', katex)
    ).toContain('katex-error')
  })
})

describe('sharedTitle', () => {
  it('names the tab after the page, untitled when blank', () => {
    expect(sharedTitle('N5 文法')).toBe('N5 文法 · Hikki Community')
    expect(sharedTitle('  ')).toBe('Untitled · Hikki Community')
  })
})

const asset = (name: string) => (name === 'c.png' ? 'blob:c' : null)

describe('coverView', () => {
  it('draws a built-in gradient from the tokens', () => {
    expect(coverView({ gradient: 'ocean' }, asset)).toEqual({
      gradient: 'linear-gradient(135deg, #c2e9fb 0%, #a1c4fd 100%)'
    })
    expect(coverView({ gradient: 'nope' }, asset)).toBeNull()
  })
  it('takes https pictures and the page’s own, with their position', () => {
    expect(coverView({ image: 'https://images.unsplash.com/p?w=1', position: 30 }, asset)).toEqual({
      image: 'https://images.unsplash.com/p?w=1',
      position: 30
    })
    expect(coverView({ image: 'assets/c.png', position: 140 }, asset)).toEqual({
      image: 'blob:c',
      position: 100
    })
    expect(coverView({ image: 'assets/missing.png' }, asset)).toBeNull()
    expect(coverView({ image: 'http://example.com/a.png' }, asset)).toBeNull()
    expect(coverView({ image: 'javascript:alert(1)' }, asset)).toBeNull()
    // Any other host would learn who reads the page.
    expect(coverView({ image: 'https://tracker.example/pixel.png' }, asset)).toBeNull()
    expect(coverView({ image: 'https://images.unsplash.com.evil.example/a.png' }, asset)).toBeNull()
    expect(coverView(null, asset)).toBeNull()
  })
})

describe('outline', () => {
  it('lists the headings and gives each an id of its own', () => {
    const { html, items } = outline(
      '<h1 id="x">One</h1><p>a</p><h2>Two  <b>bold</b></h2><h3> </h3><h4>Four</h4>'
    )
    expect(items).toEqual([
      { id: 'toc-1', level: 1, text: 'One' },
      { id: 'toc-2', level: 2, text: 'Two bold' }
    ])
    expect(html).toContain('<h1 id="toc-1">One</h1>')
    expect(html).toContain('<h2 id="toc-2">')
  })
  it('leaves a page without headings as it was', () => {
    expect(outline('<p>a</p>')).toEqual({ html: '<p>a</p>', items: [] })
  })
})

describe('links that may not open', () => {
  it('marks a link into the author’s Hikki and says the page has links', () => {
    const html = sanitize(
      '<p><a href="hikki://page/abc#b">Other</a> <a href="https://example.com">Web</a></p>',
      () => null
    )
    expect(html).toContain('<a data-link="private" title=')
    expect(html).not.toContain('hikki://')
    expect(hasLinks(html)).toBe(true)
    expect(hasLinks('<p><span data-type="mention" data-id="a">@A</span></p>')).toBe(true)
    expect(hasLinks('<p>No links</p>')).toBe(false)
  })
})

describe('blobType', () => {
  it('keeps media types and turns anything the browser would run into a download', () => {
    expect(blobType('image/png')).toBe('image/png')
    expect(blobType('Video/MP4; codecs=avc1')).toBe('video/mp4')
    expect(blobType('image/svg+xml')).toBe('application/octet-stream')
    expect(blobType('text/html')).toBe('application/octet-stream')
    expect(blobType('application/javascript')).toBe('application/octet-stream')
    expect(blobType(undefined)).toBe('application/octet-stream')
  })
})
