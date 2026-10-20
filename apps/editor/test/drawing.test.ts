import type { Editor } from '@tiptap/core'
import { undoDepth } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { blockKindLabel } from '../src/core/block-kinds'
import { BLOCK_TYPES } from '../src/core/blocks'
import { DiagramRequests } from '../src/core/diagram'
import { createEditor } from '../src/core/editor'
import { blockTexts } from '../src/core/extract'
import type { ToNativeMessage } from '../src/core/protocol'
import { closeDrawing, openDrawing, type DrawingEditorHost } from '../src/extensions/drawing'
import { settle } from './helpers'

// The overlay itself is Excalidraw (a canvas happy-dom can't draw): the test plays its part.
type OverlayProps = {
  data: { elements: unknown[]; files: object }
  onChange: (data: { elements: unknown[]; files: object }) => void
  onDone: (data: { elements: unknown[]; files: object }, preview: Blob | null) => Promise<void>
  onFail: () => void
}
const overlays: { props: OverlayProps; destroyed: boolean; live: unknown[] | null }[] = []
vi.mock('../src/components/drawing-overlay', () => ({
  renderDrawingOverlay: (props: OverlayProps) => {
    const overlay = { props, destroyed: false, live: null as unknown[] | null }
    overlays.push(overlay)
    return {
      elements: () => overlay.live,
      destroy: () => {
        overlay.destroyed = true
      }
    }
  }
}))

const rect = { id: 'r1', type: 'rectangle', x: 0, y: 0, width: 10, height: 10 }
const label = { id: 't1', type: 'text', text: 'Login', originalText: 'Login' }

const drawingDoc = (attrs: Record<string, unknown>) => ({
  type: 'doc',
  content: [
    { type: 'paragraph', content: [{ type: 'text', text: 'before' }] },
    { type: 'drawing', attrs: { id: 'dr1', ...attrs } },
    { type: 'paragraph', content: [{ type: 'text', text: 'after' }] }
  ]
})

let element: HTMLElement
let editor: Editor
let host: DrawingEditorHost & { upload: ReturnType<typeof vi.fn> }

const drawingPos = () => {
  let found = -1
  editor.state.doc.descendants((node, pos) => {
    if (node.type.name === 'drawing') found = pos
    return found < 0
  })
  return found
}
const drawingAttrs = () => editor.state.doc.nodeAt(drawingPos())?.attrs ?? {}

beforeEach(() => {
  overlays.length = 0
  element = document.createElement('div')
  document.body.append(element)
  host = {
    upload: vi.fn(
      async (_blob: Blob, extension: string) => `hikki-editor://assets/new.${extension}`
    ),
    read: async () => new Blob(),
    diagram: null,
    openLink: vi.fn()
  }
  editor = createEditor(element, drawingDoc({ elements: [rect, label] }), { drawing: host })
})
afterEach(() => {
  closeDrawing()
  editor.destroy()
  element.remove()
})

describe('a drawing block', () => {
  it('keeps its elements, pictures and preview in the page, and through HTML', () => {
    editor.commands.setContent(
      drawingDoc({
        elements: [rect, label],
        files: { f1: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' } },
        preview: 'hikki-editor://assets/preview.png'
      })
    )
    const html = editor.getHTML()
    expect(html).toContain('data-type="drawing"')
    expect(html).toContain('src="hikki-editor://assets/preview.png"')
    expect(html).toContain('alt="Login"')
    editor.commands.setContent(html)
    expect(drawingAttrs().elements).toEqual([rect, label])
    expect(drawingAttrs().files).toEqual({
      f1: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' }
    })
    expect(drawingAttrs().preview).toBe('hikki-editor://assets/preview.png')
  })

  it('shows its preview, or a prompt to draw when it has none', () => {
    expect(element.querySelector('.hk-drawing')?.textContent).toBe('Drawing — click to open')
    editor.commands.setContent(drawingDoc({ elements: [], preview: null }))
    expect(element.querySelector('.hk-drawing')?.textContent).toBe('Empty drawing — click to draw')
    expect(element.querySelector('.hk-drawing')?.getAttribute('aria-label')).toBe(
      'Empty drawing — click to draw'
    )
    editor.commands.setContent(
      drawingDoc({ elements: [rect], preview: 'hikki-editor://assets/preview.png' })
    )
    expect(element.querySelector<HTMLImageElement>('.hk-drawing-preview')?.src).toBe(
      'hikki-editor://assets/preview.png'
    )
    // Read out by what it shows: only the picture is "Drawing".
    expect(element.querySelector('.hk-drawing')?.getAttribute('aria-label')).toMatch(
      /^Drawing(:|$)/u
    )
    // A stored preview that isn't ours or a web picture never renders.
    editor.commands.setContent(drawingDoc({ elements: [rect], preview: 'javascript:alert(1)' }))
    expect(element.querySelector('.hk-drawing-preview')).toBeNull()
  })

  it('loads nothing off the device: pictures and a preview named by address are left out', () => {
    editor.commands.setContent(
      drawingDoc({
        elements: [
          rect,
          { ...label, link: 'javascript:alert(1)' },
          { id: 'e1', type: 'embeddable' }
        ],
        files: {
          f1: { src: 'https://tracker.example/p.png', mimeType: 'image/png' },
          f2: { src: 'http://tracker.example/p.png', mimeType: 'image/png' },
          f3: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' }
        },
        preview: 'https://tracker.example/preview.png'
      })
    )
    expect(element.querySelector('.hk-drawing-preview')).toBeNull()
    expect(editor.getHTML()).not.toContain('tracker.example/preview.png')
    // Pasted HTML naming a web picture as the preview doesn't bring it in either.
    editor.commands.setContent(
      '<div data-type="drawing" data-elements="[]"><img src="https://tracker.example/preview.png"></div>'
    )
    expect(drawingAttrs().preview).toBeNull()

    editor.commands.setContent(
      drawingDoc({
        elements: [
          rect,
          { ...label, link: 'javascript:alert(1)' },
          { id: 'e1', type: 'embeddable' }
        ],
        files: {
          f1: { src: 'https://tracker.example/p.png', mimeType: 'image/png' },
          f3: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' }
        }
      })
    )
    openDrawing(editor, host, drawingPos())
    expect(overlays[0].props.data.files).toEqual({
      f3: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' }
    })
    expect(overlays[0].props.data.elements).toEqual([rect, { ...label, link: null }])
  })

  it('is in the "/" menu and named in the block menu', () => {
    const type = BLOCK_TYPES.find((b) => b.id === 'drawing')
    expect(type?.group).toBe('media')
    expect(type?.aliases).toContain('huitu')
    expect(blockKindLabel(editor.state.doc.nodeAt(drawingPos())!)).toBe('Drawing')
  })

  it('counts its words as one block of the page', () => {
    expect(blockTexts(editor.getJSON())).toEqual(['before', 'Login', 'after'])
  })
})

describe('editing a drawing', () => {
  it('opens on a click with the stored drawing', () => {
    element.querySelector<HTMLElement>('.hk-drawing')!.click()
    expect(overlays).toHaveLength(1)
    expect(overlays[0].props.data.elements).toEqual([rect, label])
  })

  it('writes changes into the block out of the page undo, saved; Done stores the preview and closes', async () => {
    openDrawing(editor, host, drawingPos())
    const depth = undoDepth(editor.state)
    const saved = vi.fn()
    editor.on('transaction', ({ transaction }) => {
      if (transaction.getMeta('hikkiSave')) saved()
    })
    const moved = { ...rect, x: 50 }
    overlays[0].props.onChange({ elements: [moved], files: {} })
    expect(drawingAttrs().elements).toEqual([moved])
    expect(saved).toHaveBeenCalled()
    await overlays[0].props.onDone({ elements: [moved, label], files: {} }, new Blob(['png']))
    expect(host.upload).toHaveBeenCalledWith(expect.any(Blob), 'png')
    expect(drawingAttrs().preview).toBe('hikki-editor://assets/new.png')
    expect(drawingAttrs().elements).toEqual([moved, label])
    expect(undoDepth(editor.state)).toBe(depth)
    expect(overlays[0].destroyed).toBe(true)
  })

  it('an empty drawing closed with Done has no preview', async () => {
    editor.commands.setContent(
      drawingDoc({ elements: [rect], preview: 'hikki-editor://assets/old.png' })
    )
    openDrawing(editor, host, drawingPos())
    await overlays[0].props.onDone({ elements: [], files: {} }, null)
    expect(host.upload).not.toHaveBeenCalled()
    expect(drawingAttrs().preview).toBeNull()
    expect(drawingAttrs().elements).toEqual([])
  })

  it('a preview that fails to store keeps the old one', async () => {
    editor.commands.setContent(
      drawingDoc({ elements: [rect], preview: 'hikki-editor://assets/old.png' })
    )
    host.upload.mockRejectedValueOnce(new Error('disk full'))
    openDrawing(editor, host, drawingPos())
    await overlays[0].props.onDone({ elements: [rect, label], files: {} }, new Blob(['png']))
    expect(drawingAttrs().preview).toBe('hikki-editor://assets/old.png')
    expect(drawingAttrs().elements).toEqual([rect, label])
  })

  it('takes the whole page while open: the native bars step aside, and come back', async () => {
    const fullScreen = vi.fn()
    host.fullScreen = fullScreen
    openDrawing(editor, host, drawingPos())
    expect(fullScreen).toHaveBeenLastCalledWith(true)
    await overlays[0].props.onDone({ elements: [rect], files: {} }, null)
    expect(fullScreen).toHaveBeenLastCalledWith(false)
  })

  it('closing for another page puts its last strokes into the block first', () => {
    openDrawing(editor, host, drawingPos())
    overlays[0].live = [label]
    closeDrawing()
    expect(drawingAttrs().elements).toEqual([label])
    expect(overlays[0].destroyed).toBe(true)
  })

  it('follows its block when the page above it changes', () => {
    openDrawing(editor, host, drawingPos())
    editor.commands.insertContentAt(0, {
      type: 'paragraph',
      content: [{ type: 'text', text: 'new' }]
    })
    overlays[0].props.onChange({ elements: [label], files: {} })
    expect(drawingAttrs().elements).toEqual([label])
  })

  it("doesn't open on a locked page", () => {
    editor.setEditable(false)
    openDrawing(editor, host, drawingPos())
    expect(overlays).toHaveLength(0)
  })

  it('"/" Drawing adds an empty drawing and opens it', async () => {
    editor.commands.setContent({ type: 'doc', content: [{ type: 'paragraph' }] })
    editor.commands.focus('start')
    BLOCK_TYPES.find((b) => b.id === 'drawing')!
      .apply(editor.chain().focus())
      .run()
    await settle()
    expect(editor.state.doc.firstChild?.type.name).toBe('drawing')
    expect(overlays).toHaveLength(1)
    expect(overlays[0].props.data.elements).toEqual([])
  })
})

const setup = () => {
  const sent: ToNativeMessage[] = []
  return { sent, requests: new DiagramRequests((message) => sent.push(message)) }
}

describe('text to diagram', () => {
  it('asks the native AI with the diagram action and resolves with the Mermaid', async () => {
    const { sent, requests } = setup()
    const answer = requests.request('Sign-in flow', 'Plans')
    const message = sent[0] as Extract<ToNativeMessage, { type: 'aiRequest' }>
    expect(message).toMatchObject({
      type: 'aiRequest',
      action: 'diagram',
      instruction: 'Sign-in flow',
      answer: true,
      units: [],
      context: { title: 'Plans' }
    })
    expect(
      requests.handle({ id: message.id, type: 'text', delta: '```mermaid\nflowchart LR\n' })
    ).toBe(true)
    requests.handle({ id: message.id, type: 'text', delta: '  A --> B\n```' })
    requests.handle({ id: message.id, type: 'done' })
    await expect(answer).resolves.toBe('flowchart LR\n  A --> B')
  })

  it("leaves other requests' events to the page's AI", () => {
    const { requests } = setup()
    expect(requests.handle({ id: 'ai-1', type: 'done' })).toBe(false)
  })

  it('fails with the message the AI panel shows', async () => {
    const { sent, requests } = setup()
    const answer = requests.request('x', '')
    const { id } = sent[0] as { id: string }
    requests.handle({ id, type: 'error', code: 'missingKey', provider: 'OpenAI' })
    await expect(answer).rejects.toThrow('Add your OpenAI API key in Settings → AI')
    const empty = requests.request('y', '')
    requests.handle({ id: (sent[1] as { id: string }).id, type: 'done' })
    await expect(empty).rejects.toThrow()
  })
})
