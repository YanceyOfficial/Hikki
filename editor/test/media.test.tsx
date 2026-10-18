import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { EditorBridge, extensionOf } from '../src/core/bridge'
import { createEditor } from '../src/core/editor'
import { installErrorForwarding } from '../src/core/errors'
import type { ToNativeMessage } from '../src/core/protocol'
import { insertFiles, mediaKindOf, safeMediaSrc, type MediaHost } from '../src/extensions/media'
import { doc, settle, stripIds } from './helpers'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  editor?.destroy()
  host.remove()
})

const asset = 'hikki-editor://assets/0a1b.png'

describe('media src allowlist', () => {
  it('admits assets everywhere, web images and raster data URLs for images, https media', () => {
    expect(safeMediaSrc(asset, 'image')).toBe(asset)
    expect(safeMediaSrc(asset, 'file')).toBe(asset)
    expect(safeMediaSrc('https://example.com/a.jpg', 'image')).toBeTruthy()
    expect(safeMediaSrc('http://example.com/a.jpg', 'image')).toBeTruthy()
    expect(safeMediaSrc('data:image/png;base64,AAAA', 'image')).toBeTruthy()
    expect(safeMediaSrc('https://example.com/a.mp4', 'video')).toBeTruthy()
  })

  it('refuses scripts, documents, SVG data and anything not ours for attachments', () => {
    for (const [src, kind] of [
      ['javascript:alert(1)', 'image'],
      ['data:text/html,<script>alert(1)</script>', 'image'],
      ['data:image/svg+xml;base64,PHN2Zz4=', 'image'],
      ['http://example.com/a.mp4', 'video'],
      ['https://example.com/a.pdf', 'file'],
      ['hikki-editor://app/index.html', 'image'],
      ['hikki-editor://assets/../hikki.sqlite', 'file']
    ] as const) {
      expect(safeMediaSrc(src, kind), src).toBeNull()
    }
  })

  it('a stored image with an unsafe src renders without one', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [{ type: 'image', attrs: { src: 'javascript:alert(1)' } }]
    })
    expect(editor.getHTML()).not.toContain('javascript')
    expect(host.querySelector('img')?.getAttribute('src') ?? '').toBe('')
  })
})

describe('kinds and extensions', () => {
  it('classifies files', () => {
    expect(mediaKindOf({ type: 'image/png', name: 'a.png' })).toBe('image')
    expect(mediaKindOf({ type: 'image/svg+xml', name: 'a.svg' })).toBe('file')
    expect(mediaKindOf({ type: '', name: 'clip.MOV' })).toBe('video')
    expect(mediaKindOf({ type: 'audio/mpeg', name: 'song' })).toBe('audio')
    expect(mediaKindOf({ type: 'application/pdf', name: 'a.pdf' })).toBe('file')
  })

  it('takes the extension from the name, else the type', () => {
    expect(extensionOf({ name: 'Report.PDF', type: '' })).toBe('pdf')
    expect(extensionOf({ name: 'paste', type: 'image/png' })).toBe('png')
    expect(extensionOf({ name: 'weird.!!', type: '' })).toBe('bin')
  })
})

describe('chunked uploads through the bridge', () => {
  it('sends begin, chunks, finish and resolves to the URL', async () => {
    const sent: ToNativeMessage[] = []
    const bridge = new EditorBridge(host, {
      post: async (m) => {
        sent.push(m)
        if (m.type === 'beginUpload') return 'u1'
        if (m.type === 'finishUpload') return 'hikki-editor://assets/x.mp4'
        return null
      }
    })
    const file = new File([new Uint8Array(2 * 1024 * 1024)], 'clip.mp4', { type: 'video/mp4' })
    const progress = vi.fn()
    expect(await bridge.uploadFile(file, progress)).toBe('hikki-editor://assets/x.mp4')
    expect(sent[0]).toMatchObject({ type: 'beginUpload', fileExtension: 'mp4', size: file.size })
    expect(sent.filter((m) => m.type === 'uploadChunk').length).toBeGreaterThan(1)
    expect(sent.at(-1)).toEqual({ type: 'finishUpload', id: 'u1' })
    expect(progress).toHaveBeenLastCalledWith(1)
  })

  it('cancels on failure, so no partial file is kept', async () => {
    const sent: ToNativeMessage[] = []
    const bridge = new EditorBridge(host, {
      post: async (m) => {
        sent.push(m)
        if (m.type === 'beginUpload') return 'u1'
        if (m.type === 'uploadChunk') throw new Error('disk full')
        return null
      }
    })
    await expect(bridge.uploadFile(new File(['abc'], 'a.pdf'))).rejects.toThrow('disk full')
    await settle()
    expect(sent.at(-1)).toEqual({ type: 'cancelUpload', id: 'u1' })
  })
})

const fakeHost = (upload: MediaHost['upload']): MediaHost => ({ upload, openAsset: vi.fn() })

describe('inserting files', () => {
  it('shows a placeholder outside the document, then inserts the block where it stood', async () => {
    let resolve!: (url: string) => void
    const media = fakeHost(() => new Promise((r) => (resolve = r)))
    editor = createEditor(host, doc('before', 'after'), { media })
    const end = editor.state.doc.firstChild!.nodeSize
    insertFiles(editor, media, [new File(['x'], 'photo.png', { type: 'image/png' })], end)
    expect(host.querySelector('.hk-upload')?.textContent).toContain('photo.png')
    expect(JSON.stringify(editor.getJSON())).not.toContain('image')
    resolve(asset)
    await settle()
    expect(host.querySelector('.hk-upload')).toBeNull()
    const types = editor.getJSON().content?.map((n) => n.type)
    expect(types).toEqual(['paragraph', 'image', 'paragraph'])
    expect(editor.getJSON().content?.[1].attrs?.src).toBe(asset)
  })

  it('a failed upload shows briefly and leaves the document unchanged', async () => {
    vi.useFakeTimers()
    const media = fakeHost(() => Promise.reject(new Error('nope')))
    editor = createEditor(host, doc('text'), { media })
    const before = JSON.stringify(stripIds(editor.getJSON()))
    insertFiles(editor, media, [new File(['x'], 'a.pdf')], 1)
    await vi.advanceTimersByTimeAsync(0)
    expect(host.querySelector('.hk-upload')?.getAttribute('data-failed')).toBe('true')
    await vi.advanceTimersByTimeAsync(5000)
    expect(host.querySelector('.hk-upload')).toBeNull()
    expect(JSON.stringify(stripIds(editor.getJSON()))).toBe(before)
    vi.useRealTimers()
  })

  it('an upload that finishes after its page closed is reported, not dropped silently', async () => {
    const posted: unknown[] = []
    installErrorForwarding({ post: async (m) => void posted.push(m) })
    let resolve!: (url: string) => void
    const media = fakeHost(() => new Promise((r) => (resolve = r)))
    editor = createEditor(host, doc('text'), { media })
    insertFiles(editor, media, [new File(['x'], 'photo.png', { type: 'image/png' })], 1)
    editor.destroy()
    resolve(asset)
    await settle()
    expect(posted).toContainEqual(
      expect.objectContaining({
        type: 'reportError',
        context: { kind: 'image', reason: 'pageClosed' }
      })
    )
  })

  it('attachments open through the host, only for our assets', () => {
    const media = fakeHost(async () => '')
    editor = createEditor(
      host,
      {
        type: 'doc',
        content: [
          {
            type: 'fileAttachment',
            attrs: { src: 'hikki-editor://assets/r.pdf', name: 'r.pdf', size: 2048 }
          },
          { type: 'fileAttachment', attrs: { src: 'https://evil.example/x.html', name: 'x.html' } }
        ]
      },
      { media }
    )
    const [ours, theirs] = host.querySelectorAll<HTMLButtonElement>('.hk-file')
    expect(ours.textContent).toContain('2.0 KB')
    ours.click()
    theirs.click()
    expect(media.openAsset).toHaveBeenCalledTimes(1)
    expect(media.openAsset).toHaveBeenCalledWith('hikki-editor://assets/r.pdf', 'r.pdf')
  })
})

describe('image toolbar', () => {
  it('aligns the selected image', async () => {
    editor = createEditor(
      host,
      { type: 'doc', content: [{ type: 'image', attrs: { src: asset } }, { type: 'paragraph' }] },
      {
        media: fakeHost(async () => '')
      }
    )
    editor.commands.setNodeSelection(0)
    editor.chain().focus().updateAttributes('image', { align: 'right' }).run()
    expect(editor.getJSON().content?.[0].attrs?.align).toBe('right')
    expect(editor.getHTML()).toContain('data-align="right"')
  })
})

describe('video first frame', () => {
  it('seeks a hair past 0 once the metadata is in, so WebKit paints the first frame', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [{ type: 'video', attrs: { src: 'hikki-editor://assets/clip.mp4' } }]
    })
    const video = host.querySelector('video')!
    expect(video.getAttribute('src')).toBe('hikki-editor://assets/clip.mp4')
    expect(video.currentTime).toBe(0)
    video.dispatchEvent(new Event('loadedmetadata'))
    expect(video.currentTime).toBe(0.001)
    // The stored src carries no `#t=` fragment.
    expect(JSON.stringify(editor.getJSON())).not.toContain('#t=')
  })
})
