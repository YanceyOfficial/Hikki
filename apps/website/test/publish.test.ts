// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest'

import {
  decrypt,
  keyFromFragment,
  lookupRequest,
  lookupURL,
  recordFiles,
  sanitize
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
