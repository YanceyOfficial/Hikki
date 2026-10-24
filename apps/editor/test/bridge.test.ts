import { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { openBlockMenu } from '../src/components/block-menu'
import { openFloatingLayers } from '../src/components/floating'
import { EditorBridge, type Transport } from '../src/core/bridge'
import { installErrorForwarding } from '../src/core/errors'
import type { ToNativeMessage } from '../src/core/protocol'
import { unitAtPos } from '../src/extensions/block-units'
import { openEmbedPanel } from '../src/extensions/embed'
import { insertFiles } from '../src/extensions/media'
import { moveBlockHost } from '../src/extensions/move-block'
import { drawingsReadOnly } from '../src/lib/drawing-mode'
import { doc, page, stripIds } from './helpers'

const heading = (level: number, text: string) => ({
  type: 'heading',
  attrs: { level },
  content: [{ type: 'text', text }]
})
const pageInfo = (sent: ToNativeMessage[]) =>
  sent.filter((m) => m.type === 'pageInfo') as Extract<ToNativeMessage, { type: 'pageInfo' }>[]

const ofType = (sent: ToNativeMessage[], type: ToNativeMessage['type']) =>
  sent.filter((m) => m.type === type)

/** A transport whose `changed` posts fail while `failing` is set. */
function flakyTransport(sent: ToNativeMessage[]) {
  const state = { failing: true, posts: 0 }
  const transport: Transport = {
    post: (m) => {
      sent.push(m)
      if (m.type !== 'changed') return Promise.resolve(null)
      state.posts += 1
      return state.failing ? Promise.reject(new Error('handler gone')) : Promise.resolve(null)
    }
  }
  return { state, transport }
}

describe('EditorBridge', () => {
  let sent: ToNativeMessage[]
  let bridge: EditorBridge
  let host: HTMLElement

  beforeEach(() => {
    vi.useFakeTimers()
    sent = []
    const transport: Transport = {
      post: async (m) => {
        sent.push(m)
        return m.type === 'saveAsset' ? 'hikki-editor://assets/x.png' : null
      }
    }
    host = document.createElement('div')
    document.body.append(host)
    bridge = new EditorBridge(host, transport, { debounceMs: 400 })
  })
  afterEach(() => {
    vi.useRealTimers()
    host.remove()
  })

  const changed = () => sent.filter((m) => m.type === 'changed')
  const editing = () => ofType(sent, 'editing')
  const reported = () => ofType(sent, 'reportError')
  /** The bridge over a transport whose saves fail until told otherwise. */
  const flaky = () => {
    const { state, transport } = flakyTransport(sent)
    bridge = new EditorBridge(host, transport, { debounceMs: 400 })
    return state
  }
  const selections = () => sent.filter((m) => m.type === 'selection')
  const editor = () => (bridge as any).editor

  it('reports the selected text once it settles, once per change, and its clearing', () => {
    bridge.loadDocument(page('a', { content: doc('hello world') }))
    editor().commands.setTextSelection({ from: 1, to: 6 })
    editor().commands.setTextSelection({ from: 1, to: 4 })
    vi.advanceTimersByTime(250)
    expect(selections()).toEqual([{ type: 'selection', docId: 'a', text: 'hel', caret: null }])
    editor().commands.setTextSelection({ from: 1, to: 4 })
    vi.advanceTimersByTime(250)
    expect(selections()).toHaveLength(1)
    editor().commands.setTextSelection(3)
    vi.advanceTimersByTime(250)
    expect(selections().at(-1)).toEqual({ type: 'selection', docId: 'a', text: '', caret: 3 })
    // A caret put elsewhere (a tap) is a change of its own: the keyboard bar closes its panel on it.
    editor().commands.setTextSelection(5)
    vi.advanceTimersByTime(250)
    expect(selections().at(-1)).toEqual({ type: 'selection', docId: 'a', text: '', caret: 5 })
    expect(selections()).toHaveLength(3)
  })

  it('loading a page does not emit a change and exposes header state', () => {
    bridge.loadDocument(
      page('a', { title: 'Plan', icon: '🌊', cover: 'gradient:ocean', content: doc('hi') })
    )
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
    expect(bridge.page.get()).toMatchObject({
      docId: 'a',
      title: 'Plan',
      icon: '🌊',
      cover: 'gradient:ocean'
    })
    expect(bridge.snapshot()).toMatchObject({ docId: 'a', title: 'Plan', text: 'hi', wordCount: 2 })
  })

  it('debounces body edits into one changed message', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent(' there')
    editor().commands.insertContent(' again')
    vi.advanceTimersByTime(399)
    expect(changed()).toHaveLength(0)
    vi.advanceTimersByTime(1)
    expect(changed()).toHaveLength(1)
  })

  it('says "editing" once per save, never for a page only viewed', () => {
    bridge.loadDocument(page('a'))
    vi.advanceTimersByTime(1000)
    expect(editing()).toEqual([])
    editor().commands.insertContent(' there')
    editor().commands.insertContent(' again')
    expect(editing()).toEqual([{ type: 'editing', docId: 'a' }])
    vi.advanceTimersByTime(400)
    expect(changed()).toHaveLength(1)
    editor().commands.insertContent('!')
    expect(editing()).toHaveLength(2)
    // Handed over by a flush: the next edit says so again.
    expect(bridge.flush()).not.toBeNull()
    bridge.setTitle('Plan')
    expect(editing()).toHaveLength(3)
  })

  it('a comment saves the page (its passage mark is part of the page) without entering undo', () => {
    bridge.loadDocument(page('a', { content: doc('the quick fox') }))
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
    editor().commands.setTextSelection({ from: 5, to: 10 })
    editor().commands.commentStart()
    vi.advanceTimersByTime(1000)
    // A draft is only a highlight: nothing to save yet.
    expect(changed()).toHaveLength(0)
    editor().commands.commentSend('样态')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(1)
    expect(JSON.stringify(changed()[0])).toContain('"comment"')
    // Undo doesn't take the mark away from a thread that exists.
    editor().commands.undo()
    expect(JSON.stringify(editor().getJSON())).toContain('"comment"')
    // Deleting the thread saves the page without its mark.
    const id = editor()
      .getJSON()
      .content[0].content.find((n: any) => n.marks)?.marks[0].attrs.id
    editor().commands.commentDelete(id)
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(2)
    expect(JSON.stringify(changed()[1])).not.toContain('"comment"')
  })

  it("a phone that draws threads natively hears which one is open, and its actions run as the page's", () => {
    bridge.loadDocument(page('a', { content: doc('hello world') }))
    editor().commands.setTextSelection({ from: 1, to: 6 })
    editor().commands.commentStart()
    editor().commands.commentSend('Nice')
    const threads = () => sent.filter((m) => m.type === 'commentThread')
    // Not asked to: the page keeps its own sheet and says nothing.
    expect(threads()).toEqual([])
    const id = (sent.find((m) => m.type === 'commentCreate') as { threadId: string }).threadId
    bridge.setNativeComments(true)
    bridge.openComment(null)
    bridge.openComment(id)
    expect(threads()).toEqual([{ type: 'commentThread', docId: 'a', threadId: id }])
    expect(bridge.commentAction({ type: 'reply', threadId: id, body: '  Thanks ' })).toBe(true)
    expect(sent.at(-1)).toEqual({ type: 'commentReply', docId: 'a', threadId: id, body: 'Thanks' })
    expect(bridge.commentAction({ type: 'reply', threadId: id, body: ' ' })).toBe(false)
    // Deleting the thread takes its mark away and closes it.
    bridge.commentAction({ type: 'delete', threadId: id })
    expect(sent).toContainEqual({ type: 'commentDelete', docId: 'a', threadId: id })
    expect(JSON.stringify(editor().getJSON())).not.toContain('"comment"')
    expect(threads().at(-1)).toEqual({ type: 'commentThread', docId: 'a', threadId: null })
  })

  it('title edits are saved through the same debounced snapshot, newlines stripped', () => {
    bridge.loadDocument(page('a'))
    bridge.setTitle('Weekly\nsync')
    vi.advanceTimersByTime(400)
    const msg = changed()[0]
    expect(msg.type === 'changed' && msg.snapshot.title).toBe('Weekly sync')
  })

  it('locking saves the words typed just before it at once, and nothing after', () => {
    bridge.loadDocument(page('a', { content: doc('hello') }))
    editor().commands.insertContentAt(6, ' world')
    vi.advanceTimersByTime(100)
    bridge.setLocked(true)
    // Saved at the lock, not by the debounce once the page is locked.
    expect(changed()).toHaveLength(1)
    expect(JSON.stringify(changed()[0])).toContain('hello world')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(1)
    bridge.setTitle('Renamed')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(1)
  })

  it('icon and cover changes are sent immediately, not debounced', () => {
    bridge.loadDocument(page('a'))
    bridge.setIcon('👋')
    bridge.setCover('gradient:dusk')
    expect(sent.filter((m) => m.type === 'setIcon' || m.type === 'setCover')).toEqual([
      { type: 'setIcon', docId: 'a', icon: '👋' },
      { type: 'setCover', docId: 'a', cover: 'gradient:dusk' }
    ])
    expect(changed()).toHaveLength(0)
  })

  it('an icon or cover the native side refuses to store goes back to what it was', async () => {
    vi.useRealTimers()
    const refusing: Transport = {
      post: async (m) => {
        if (m.type === 'setIcon' || m.type === 'setCover') throw new Error('locked')
        return null
      }
    }
    const refused = new EditorBridge(host, refusing, { debounceMs: 400 })
    refused.loadDocument(page('a', { icon: '🌊', cover: 'gradient:ocean' }))
    refused.setIcon('👋')
    refused.setCover('gradient:dusk')
    expect(refused.page.get().icon).toBe('👋')
    await Promise.resolve()
    await Promise.resolve()
    expect(refused.page.get().icon).toBe('🌊')
    expect(refused.page.get().cover).toBe('gradient:ocean')
  })

  it('saveAsset base64-encodes the file and resolves to the URL the native side returns', async () => {
    vi.useRealTimers()
    bridge.loadDocument(page('a'))
    const url = await bridge.saveAsset(
      new Blob([new Uint8Array([1, 2, 3])], { type: 'image/png' }),
      'png'
    )
    expect(url).toBe('hikki-editor://assets/x.png')
    expect(sent.find((m) => m.type === 'saveAsset')).toEqual({
      type: 'saveAsset',
      fileExtension: 'png',
      dataBase64: 'AQID'
    })
  })

  it('flushes a pending edit of the previous page before loading the next', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    bridge.loadDocument(page('b'))
    expect(changed()).toHaveLength(1)
    const msg = changed()[0]
    expect(msg.type === 'changed' && msg.snapshot.docId).toBe('a')
  })

  it('flush() returns null when the page was only viewed (viewing must not bump "edited")', () => {
    bridge.loadDocument(page('a'))
    expect(bridge.flush()).toBeNull()
    editor().commands.insertContent('!')
    vi.advanceTimersByTime(400) // the debounced save already reported it
    expect(bridge.flush()).toBeNull()
  })

  it('flush() returns the snapshot and cancels the pending debounce', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    expect(bridge.flush()?.docId).toBe('a')
    vi.advanceTimersByTime(1000)
    expect(changed()).toHaveLength(0)
  })

  it('does not share undo history across pages', () => {
    bridge.loadDocument(page('a'))
    editor().commands.insertContent('!')
    bridge.loadDocument(page('b', { content: doc('other') }))
    bridge.exec('undo')
    expect(bridge.snapshot()?.text).toBe('other')
  })

  it('collects headings for the outline and keeps them current', () => {
    bridge.loadDocument(
      page('a', {
        content: {
          type: 'doc',
          content: [
            { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Goals' }] },
            { type: 'paragraph' }
          ]
        }
      })
    )
    expect(bridge.page.get().headings.map((h) => h.text)).toEqual(['Goals'])
    editor().commands.insertContentAt(editor().state.doc.content.size, {
      type: 'heading',
      attrs: { level: 3 },
      content: [{ type: 'text', text: 'Risks' }]
    })
    expect(bridge.page.get().headings.map((h) => [h.level, h.text])).toEqual([
      [2, 'Goals'],
      [3, 'Risks']
    ])
  })

  it('re-marking a lost comment passage on open is no edit; the mark goes out with the next real one', async () => {
    bridge.loadDocument(page('a', { content: doc('the quick fox') }))
    const thread = {
      id: 't1',
      quote: 'quick',
      resolved: false,
      comments: [{ id: 'c1', body: 'hi', author: null, device: null, createdAt: 0 }]
    }
    bridge.setComments('a', [thread], null)
    await vi.advanceTimersByTimeAsync(3000)
    expect(changed()).toHaveLength(0)
    editor().commands.insertContentAt(1, 'x')
    await vi.advanceTimersByTimeAsync(3000)
    expect(changed()).toHaveLength(1)
    expect(JSON.stringify(bridge.snapshot()?.content)).toContain('"comment"')
  })

  it('a remote change waits while a file is uploading into the page', () => {
    bridge.loadDocument(page('a', { content: doc('mine') }))
    insertFiles(
      editor(),
      { upload: () => new Promise(() => {}), openAsset: () => {} },
      [new File(['x'], 'a.pdf')],
      1
    )
    expect(bridge.reload(page('a', { content: doc('theirs') }))).toBe(false)
  })

  it("a page's last scroll goes out before another page replaces it", async () => {
    bridge.loadDocument(page('a', { content: doc('one') }))
    const scroller = document.scrollingElement ?? document.documentElement
    scroller.scrollTop = 420
    window.dispatchEvent(new Event('scroll'))
    await vi.advanceTimersByTimeAsync(20) // the frame the scroll waits for, not the 250 ms report
    bridge.loadDocument(page('b', { content: doc('two') }))
    await vi.advanceTimersByTimeAsync(300)
    const scrolls = sent.filter((m) => m.type === 'scroll')
    expect(scrolls[0]).toMatchObject({ docId: 'a', top: 420 })
    expect(scrolls.some((m) => m.type === 'scroll' && m.docId === 'b' && m.top === 420)).toBe(false)
  })

  it('typing outside headings leaves the outline (and its readers) alone', () => {
    bridge.loadDocument(
      page('a', {
        content: {
          type: 'doc',
          content: [
            { type: 'paragraph', content: [{ type: 'text', text: 'intro' }] },
            { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Goals' }] }
          ]
        }
      })
    )
    let notified = 0
    bridge.page.subscribe(() => notified++)
    editor().commands.insertContentAt(2, 'more ')
    expect(notified).toBe(0)
    const goals = editor().state.doc.child(1)
    editor().commands.insertContentAt(
      editor().state.doc.child(0).nodeSize + goals.nodeSize - 1,
      '!'
    )
    expect(notified).toBe(1)
    expect(bridge.page.get().headings.map((h) => h.text)).toEqual(['Goals!'])
  })

  it('reports the page info — outline with block ids, words, characters — on load, then throttled', () => {
    bridge.loadDocument(
      page('a', {
        title: 'Plan',
        content: {
          type: 'doc',
          content: [
            heading(1, 'One'),
            { type: 'paragraph', content: [{ type: 'text', text: 'hello world' }] }
          ]
        }
      })
    )
    expect(pageInfo(sent)).toHaveLength(1)
    expect(pageInfo(sent)[0]).toMatchObject({ docId: 'a', words: 4 })
    expect(pageInfo(sent)[0].characters).toBe(
      editor().storage.characterCount.characters() + 'Plan'.length
    )
    expect(pageInfo(sent)[0].headings).toMatchObject([{ level: 1, text: 'One' }])
    // Block ids are stamped before the editor sees the page: the first report carries them, no follow-up.
    expect(typeof pageInfo(sent)[0].headings[0].id).toBe('string')
    vi.advanceTimersByTime(300)
    expect(pageInfo(sent)).toHaveLength(1)
    editor().commands.insertContentAt(editor().state.doc.content.size, heading(2, 'Two'))
    bridge.setTitle('Plan B')
    expect(pageInfo(sent)).toHaveLength(1)
    vi.advanceTimersByTime(300)
    expect(pageInfo(sent)).toHaveLength(2)
    expect(pageInfo(sent)[1].headings.map((h) => h.text)).toEqual(['One', 'Two'])
    expect(pageInfo(sent)[1].words).toBe(6)
    // Hiding the rail is state the outline reads; it never reaches the native side.
    bridge.setOutlineRail(false)
    expect(bridge.page.get().railHidden).toBe(true)
  })

  it('Backspace at the start of the body asks the header to focus the title', () => {
    bridge.loadDocument(page('a'))
    editor().commands.setTextSelection(1)
    const before = bridge.page.get().focusTitleRequest
    const event = new KeyboardEvent('keydown', {
      key: 'Backspace',
      bubbles: true,
      cancelable: true
    })
    editor().view.someProp('handleKeyDown', (f: any) => f(editor().view, event))
    expect(bridge.page.get().focusTitleRequest).toBe(before + 1)
  })

  it('a press below the last block opens an empty line there, reusing an empty last paragraph', () => {
    bridge.loadDocument(page('a', { content: doc('ddd') }))
    expect(bridge.focusEnd()).toBe(true)
    const json = () =>
      editor()
        .getJSON()
        .content.map((n: any) => n.type + ':' + (n.content?.[0]?.text ?? ''))
    expect(json()).toEqual(['paragraph:ddd', 'paragraph:'])
    expect(editor().state.selection.$from.parent.content.size).toBe(0)
    expect(editor().state.selection.from).toBe(editor().state.doc.content.size - 1)
    // Already an empty line at the end: no second one.
    expect(bridge.focusEnd()).toBe(true)
    expect(json()).toEqual(['paragraph:ddd', 'paragraph:'])
    // A heading (or any other block) last gets a paragraph after it.
    bridge.loadDocument(
      page('b', {
        content: {
          type: 'doc',
          content: [
            { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'H' }] }
          ]
        }
      })
    )
    bridge.focusEnd()
    expect(
      editor()
        .getJSON()
        .content.map((n: any) => n.type)
    ).toEqual(['heading', 'paragraph'])
    // Locked pages stay as they are.
    bridge.loadDocument(page('c', { content: doc('x'), locked: true }))
    expect(bridge.focusEnd()).toBe(false)
    expect(editor().getJSON().content).toHaveLength(1)
  })

  it('blur() drops editor focus and is safe before any page is loaded', () => {
    expect(() => bridge.blur()).not.toThrow()
    bridge.loadDocument(page('a'))
    bridge.focus()
    vi.advanceTimersByTime(50) // Tiptap applies focus on the next frame
    expect(editor().isFocused).toBe(true)
    bridge.blur()
    vi.advanceTimersByTime(50)
    expect(editor().isFocused).toBe(false)
  })

  it('blur() leaves no selection behind: WebKit would keep painting it, with its edit menu over it', () => {
    bridge.loadDocument(page('a', { content: doc('hello world') }))
    editor().commands.setTextSelection({ from: 1, to: 6 })
    window.getSelection()?.selectAllChildren(host)
    bridge.blur()
    expect(editor().state.selection.empty).toBe(true)
    expect(editor().state.selection.from).toBe(6)
    expect(window.getSelection()?.rangeCount ?? 0).toBe(0)
  })

  it('enterFromTitle focuses the body synchronously and starts a fresh first line', () => {
    bridge.loadDocument(page('a', { content: doc('existing') }))
    bridge.enterFromTitle()
    // Focus must already be in the editor — no frame delay for keystrokes to slip into the title.
    expect(editor().view.hasFocus()).toBe(true)
    expect(editor().state.selection.from).toBe(1)
    expect(stripIds(editor().getJSON().content)).toEqual([
      { type: 'paragraph' },
      { type: 'paragraph', content: [{ type: 'text', text: 'existing' }] }
    ])
  })

  it('enterFromTitle reuses an empty first line instead of stacking blanks', () => {
    bridge.loadDocument(page('a', { content: doc('') }))
    bridge.enterFromTitle()
    expect(stripIds(editor().getJSON().content)).toEqual([{ type: 'paragraph' }])
  })

  it('loading another page takes down the menus and panels of the one before', () => {
    bridge.loadDocument(page('a', { content: doc('one', 'two') }))
    const ed = editor()
    act(() => openBlockMenu(ed, unitAtPos(ed.state, 1)!, new DOMRect(0, 0, 10, 10)))
    act(() => openEmbedPanel(ed, 'generic'))
    expect(document.querySelector('.hk-block-menu')).not.toBeNull()
    expect(document.querySelector('.hk-embed-panel')).not.toBeNull()
    act(() => bridge.loadDocument(page('b', { content: doc('three') })))
    expect(document.querySelector('.hk-block-menu')).toBeNull()
    expect(document.querySelector('.hk-embed-panel')).toBeNull()
    expect(openFloatingLayers()).toHaveLength(0)
  })

  it('demoAI selects the words and asks AI to edit them, as the selection menu would', () => {
    bridge.loadDocument(page('a', { content: doc('Notes stay on your own devices.') }))
    expect(bridge.ai.demoAI(['stay on your own'], 'improve')).toBe(true)
    const request = sent.find((m) => m.type === 'aiRequest')
    expect(request).toMatchObject({ type: 'aiRequest', action: 'improve', answer: false })
    expect(JSON.stringify(request)).toContain('stay on your own')
    expect(bridge.ai.demoAI(['not in the page'], 'improve')).toBe(false)
  })

  it("iOS's text size reaches the page as a clamped factor", () => {
    const root = document.documentElement.style
    bridge.setTextScale(1.35)
    expect(root.getPropertyValue('--hk-text-scale')).toBe('1.35')
    bridge.setTextScale(3.1)
    expect(root.getPropertyValue('--hk-text-scale')).toBe('2')
    bridge.setTextScale(0.5)
    expect(root.getPropertyValue('--hk-text-scale')).toBe('0.85')
    bridge.setTextScale(Number.NaN)
    expect(root.getPropertyValue('--hk-text-scale')).toBe('1')
  })

  it("the phone's AI field takes the caret's block, its link field the word", () => {
    bridge.loadDocument(page('a', { content: doc('Kyoto trip in spring') }))
    editor().commands.setTextSelection(3)
    expect(bridge.touch.touchPrepare('block')?.quote).toBe('Kyoto trip in spring')
    editor().commands.setTextSelection(3)
    expect(bridge.touch.touchPrepare()?.quote).toBe('Kyoto')
  })

  it("the phone's AI field offers the panel's presets only: no Translate, no Make", () => {
    bridge.loadDocument(page('a', { content: doc('Kyoto trip') }))
    editor().commands.setTextSelection({ from: 1, to: 6 })
    const presets = bridge.touch.touchPrepare()?.presets.map((p) => p.id) ?? []
    expect(presets).toContain('improve')
    expect(presets.filter((id) => id.startsWith('translate:') || id.startsWith('make:'))).toEqual(
      []
    )
  })

  it('rejects unknown commands', () => {
    bridge.loadDocument(page('a'))
    expect(bridge.exec('rm -rf')).toBe(false)
  })

  describe('block ids', () => {
    it('stamps ids on load without counting it as an edit (viewing never saves)', () => {
      bridge.loadDocument(page('a', { content: doc('one', 'two') }))
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(bridge.flush()).toBeNull()
      const ids = editor()
        .getJSON()
        .content.map((n: any) => n.attrs?.id)
      expect(ids.every((id: unknown) => typeof id === 'string' && id.length > 0)).toBe(true)
    })

    it('saves the ids with the first real edit and keeps stored ones', () => {
      const stored = {
        type: 'doc',
        content: [
          { type: 'paragraph', attrs: { id: 'keep-me' }, content: [{ type: 'text', text: 'x' }] }
        ]
      }
      bridge.loadDocument(page('a', { content: stored }))
      editor().commands.insertContentAt(editor().state.doc.content.size, { type: 'paragraph' })
      const snapshot = bridge.flush()
      expect(snapshot?.content.content?.[0].attrs?.id).toBe('keep-me')
      expect(snapshot?.content.content?.[1].attrs?.id).toEqual(expect.any(String))
    })
  })

  describe('a save that does not reach the app', () => {
    beforeEach(() => {
      // reportError posts through the forwarding sink: this test's list.
      const quiet = Object.assign(new EventTarget(), {
        console: { ...console, warn: () => {}, error: () => {} }
      }) as any
      installErrorForwarding({ post: (m) => Promise.resolve(void sent.push(m)) }, quiet)
      vi.spyOn(console, 'error').mockImplementation(() => {})
    })
    afterEach(() => vi.restoreAllMocks())

    it('keeps the edit pending, retries, and reports once the retries are spent', async () => {
      const state = flaky()
      bridge.loadDocument(page('a'))
      editor().commands.insertContent('!')
      await vi.advanceTimersByTimeAsync(400)
      expect(state.posts).toBe(1)
      await vi.advanceTimersByTimeAsync(500)
      expect(state.posts).toBe(2)
      await vi.advanceTimersByTimeAsync(1000)
      expect(state.posts).toBe(3)
      expect(reported()).toEqual([expect.objectContaining({ code: 3008 })])
      await vi.advanceTimersByTimeAsync(10_000)
      expect(state.posts).toBe(3)
      // Never taken: still pending, so a flush (a page switch, backgrounding) hands it over — nothing is lost.
      expect(bridge.flush()?.text).toBe('!hi')
    })

    it('a retry that gets through settles it: nothing more is sent or reported', async () => {
      const state = flaky()
      bridge.loadDocument(page('a'))
      editor().commands.insertContent('!')
      await vi.advanceTimersByTimeAsync(400)
      state.failing = false
      await vi.advanceTimersByTimeAsync(500)
      expect(state.posts).toBe(2)
      await vi.advanceTimersByTimeAsync(10_000)
      expect(state.posts).toBe(2)
      expect(reported()).toEqual([])
      expect(bridge.flush()).toBeNull()
    })

    it("a page left keeps its words: retried, and shown again if it's opened before they got through", async () => {
      const state = flaky()
      bridge.loadDocument(page('a'))
      editor().commands.insertContent('!')
      bridge.loadDocument(page('b'))
      await vi.advanceTimersByTimeAsync(5000)
      expect(changed().map((m) => (m.type === 'changed' ? m.snapshot.docId : ''))).toEqual([
        'a',
        'a',
        'a'
      ])
      expect(reported()).toHaveLength(1)
      // The app still has the old words; the page opens with the ones that never reached it, as an edit.
      bridge.loadDocument(page('a'))
      expect(editor().getText()).toBe('!hi')
      state.failing = false
      await vi.advanceTimersByTimeAsync(400)
      const last = changed().at(-1)
      expect(last?.type === 'changed' && last.snapshot.text).toBe('!hi')
    })
  })

  describe('saving while typing', () => {
    it('continuous typing still saves at least every maxWaitMs', () => {
      bridge = new EditorBridge(
        host,
        { post: async (m) => void sent.push(m) },
        { debounceMs: 400, maxWaitMs: 2000 }
      )
      bridge.loadDocument(page('a'))
      // A keystroke every 100 ms never leaves a 400 ms pause.
      for (let i = 0; i < 25; i++) {
        editor().commands.insertContent('x')
        vi.advanceTimersByTime(100)
      }
      expect(changed().length).toBeGreaterThanOrEqual(1)
    })
  })

  describe('content that does not fit the schema', () => {
    const future = {
      type: 'doc',
      content: [
        { type: 'paragraph', content: [{ type: 'text', text: 'before' }] },
        { type: 'columns', content: [{ type: 'column', content: [{ type: 'paragraph' }] }] }
      ]
    }

    it('opens read-only and never saves, so the stored content stays intact', () => {
      bridge.loadDocument(page('a', { title: 'Future', content: future }))
      expect(bridge.page.get().readOnly).toBe(true)
      expect(editor().isEditable).toBe(false)
      editor().commands.insertContent('typed')
      bridge.setTitle('Renamed')
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(bridge.flush()).toBeNull()
      expect(bridge.page.get().title).toBe('Future')
    })

    it('shows what it can — an unknown block as its text, a misnested one as its blocks — never a blank page', () => {
      const newer = {
        type: 'doc',
        content: [
          { type: 'paragraph', content: [{ type: 'text', text: 'before' }] },
          {
            type: 'futureBlock',
            attrs: { flavour: 'x' },
            content: [{ type: 'text', text: 'kept words', marks: [{ type: 'futureMark' }] }]
          },
          {
            type: 'columns',
            content: [
              {
                type: 'column',
                content: [{ type: 'paragraph', content: [{ type: 'text', text: 'in a column' }] }]
              }
            ]
          },
          {
            type: 'paragraph',
            content: [
              { type: 'text', text: 'after', marks: [{ type: 'bold' }, { type: 'futureMark' }] }
            ]
          }
        ]
      }
      bridge.loadDocument(page('a', { content: newer }))
      expect(bridge.page.get().readOnly).toBe(true)
      expect(stripIds(editor().getJSON()).content).toEqual([
        { type: 'paragraph', content: [{ type: 'text', text: 'before' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'kept words' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'in a column' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'after', marks: [{ type: 'bold' }] }] }
      ])
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(bridge.flush()).toBeNull()
    })

    it('a valid page loaded afterwards is editable again', () => {
      bridge.loadDocument(page('a', { content: future }))
      bridge.loadDocument(page('b'))
      expect(bridge.page.get().readOnly).toBe(false)
      expect(editor().isEditable).toBe(true)
    })

    it('a locked page refuses edits, commands and header changes until it is unlocked', () => {
      bridge.loadDocument(page('a', { title: 'Plan', locked: true }))
      expect(bridge.page.get()).toMatchObject({ locked: true, readOnly: false })
      expect(editor().isEditable).toBe(false)
      expect(bridge.exec('bold')).toBe(false)
      bridge.setTitle('Renamed')
      bridge.setIcon('🔒')
      bridge.setCover('gradient:dusk')
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(sent.filter((m) => m.type === 'setIcon' || m.type === 'setCover')).toHaveLength(0)
      expect(bridge.page.get().title).toBe('Plan')
      // Unlocked while open (Page → Unlock): editable again, and edits save. (act: the menus' React roots
      // re-render on editability; flushed here rather than after the test's DOM is gone.)
      act(() => bridge.setLocked(false))
      expect(editor().isEditable).toBe(true)
      bridge.setTitle('Renamed')
      vi.advanceTimersByTime(1000)
      expect(changed()).toHaveLength(1)
      act(() => bridge.setLocked(true))
      expect(editor().isEditable).toBe(false)
    })
  })

  describe('reload (page changed on another device)', () => {
    it('applies the new content in place without saving or adding an undo step', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      expect(
        bridge.reload(page('a', { title: 'New title', icon: '🌱', content: doc('new') }))
      ).toBe(true)
      expect(bridge.snapshot()?.text).toBe('new')
      expect(bridge.page.get()).toMatchObject({ title: 'New title', icon: '🌱' })
      vi.advanceTimersByTime(5000)
      expect(changed()).toHaveLength(0)
      expect(editor().can().undo()).toBe(false)
    })

    it('keeps unsaved edits instead (they win and are saved over it)', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      editor().commands.insertContent('mine ')
      expect(bridge.reload(page('a', { content: doc('theirs') }))).toBe(false)
      expect(bridge.snapshot()?.text).toContain('mine')
    })

    it('ignores another page and invalid content', () => {
      bridge.loadDocument(page('a', { content: doc('old') }))
      expect(bridge.reload(page('b', { content: doc('other') }))).toBe(false)
      expect(
        bridge.reload(page('a', { content: { type: 'doc', content: [{ type: 'columns' }] } }))
      ).toBe(false)
      expect(bridge.snapshot()?.text).toBe('old')
    })

    it('keeps the caret where it was (clamped to the new length)', () => {
      bridge.loadDocument(page('a', { content: doc('hello world') }))
      editor().commands.setTextSelection(4)
      bridge.reload(page('a', { content: doc('hello brave world') }))
      expect(editor().state.selection.from).toBe(4)
      bridge.reload(page('a', { content: doc('hi') }))
      expect(editor().state.selection.from).toBeLessThanOrEqual(editor().state.doc.content.size)
    })
  })

  describe('moving a block to another page', () => {
    it('sends it with the page it leaves, and takes WebKit’s 1 as yes', async () => {
      const replies: unknown[] = [1, false, null]
      bridge = new EditorBridge(host, {
        post: async (m) => {
          sent.push(m)
          return m.type === 'moveBlocks' ? replies.shift() : null
        }
      })
      bridge.loadDocument(page('a', { content: doc('go', 'stay', 'also') }))
      const mover = moveBlockHost()!
      await expect(mover.move('b', [{ type: 'paragraph' }], 'go', 1)).resolves.toBe(true)
      expect(sent.filter((m) => m.type === 'moveBlocks')).toEqual([
        {
          type: 'moveBlocks',
          docId: 'a',
          target: 'b',
          blocks: [{ type: 'paragraph' }],
          text: 'go',
          words: 1
        }
      ])
      await expect(mover.move('b', [], '', 0)).resolves.toBe(false)
      await expect(mover.move('b', [], '', 0)).resolves.toBe(false)
    })
  })

  describe("a drawing's Library", () => {
    it('is offered only once the app says it keeps one; read-only rides along', () => {
      expect(bridge.drawingHost.library?.()).toBeNull()
      bridge.setDrawings({ library: true, readOnly: false })
      expect(bridge.drawingHost.library?.()).not.toBeNull()
      bridge.setDrawings({ library: false, readOnly: true })
      expect(drawingsReadOnly()).toBe(true)
      bridge.setDrawings({ library: false, readOnly: false })
    })

    it("reads the stored items, and fails when the app can't read them", async () => {
      const replies: unknown[] = [{ items: [{ id: 'a' }] }, null]
      bridge = new EditorBridge(host, {
        post: async (m) => {
          sent.push(m)
          return m.type === 'drawingLibrary' ? replies.shift() : null
        }
      })
      bridge.setDrawings({ library: true, readOnly: false })
      const library = bridge.drawingHost.library?.()
      await expect(library?.load()).resolves.toEqual([{ id: 'a' }])
      await expect(library?.load()).rejects.toThrow()
      library?.save([])
      expect(sent.filter((m) => m.type === 'saveDrawingLibrary')).toEqual([
        { type: 'saveDrawingLibrary', items: [] }
      ])
    })
  })
})
