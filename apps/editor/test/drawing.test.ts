import type { Editor } from '@tiptap/core'
import { undoDepth } from '@tiptap/pm/history'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { blockKindLabel } from '../src/core/block-kinds'
import { BLOCK_TYPES } from '../src/core/blocks'
import { DiagramError, DiagramRequests } from '../src/core/diagram'
import { createEditor } from '../src/core/editor'
import { blockTexts } from '../src/core/extract'
import type { ToNativeMessage } from '../src/core/protocol'
import {
  closeDrawing,
  finishDrawing,
  openDrawing,
  type DrawingEditorHost
} from '../src/extensions/drawing'
import { setDrawingsReadOnly } from '../src/lib/drawing-mode'
import { settle } from './helpers'

// The overlay itself is Excalidraw (a canvas happy-dom can't draw): the test plays its part.
type OverlayProps = {
  data: { elements: unknown[]; files: object }
  onChange: (data: { elements: unknown[]; files: object }) => void
  onDone: (data: { elements: unknown[]; files: object }, preview: Blob | null) => Promise<void>
  onFail: () => void
  readOnly?: boolean
  mermaid?: string
}
type Done = { data: { elements: unknown[]; files: object }; preview: Blob | null }
const overlays: {
  props: OverlayProps
  destroyed: boolean
  live: unknown[] | null
  done: () => Promise<Done | null>
}[] = []
vi.mock('../src/components/drawing-overlay', () => ({
  renderDrawingOverlay: (props: OverlayProps) => {
    const overlay = {
      props,
      destroyed: false,
      live: null as unknown[] | null,
      done: async (): Promise<Done | null> => null
    }
    overlays.push(overlay)
    return {
      elements: () => overlay.live,
      done: () => overlay.done(),
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
  setDrawingsReadOnly(false)
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
          { id: 'e1', type: 'embeddable' },
          { id: 'i1', type: 'image', fileId: 'f3' },
          { id: 'i2', type: 'image', fileId: 'f1' }
        ],
        files: {
          f1: { src: 'https://tracker.example/p.png', mimeType: 'image/png' },
          f3: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' },
          // A local picture no element shows is never read either.
          f4: { src: 'hikki-editor://assets/q.png', mimeType: 'image/png' }
        }
      })
    )
    openDrawing(editor, host, drawingPos())
    expect(overlays[0].props.data.files).toEqual({
      f3: { src: 'hikki-editor://assets/p.png', mimeType: 'image/png' }
    })
    expect(overlays[0].props.data.elements).toEqual([
      rect,
      { ...label, link: null },
      { id: 'i1', type: 'image', fileId: 'f3' },
      { id: 'i2', type: 'image', fileId: 'f1' }
    ])
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

  it('finished for another page, it closes as Done does: its preview drawn and stored', async () => {
    editor.commands.setContent(
      drawingDoc({ elements: [rect], preview: 'hikki-editor://assets/old.png' })
    )
    openDrawing(editor, host, drawingPos())
    overlays[0].done = async () => ({
      data: { elements: [rect, label], files: {} },
      preview: new Blob(['png'])
    })
    await finishDrawing()
    expect(host.upload).toHaveBeenCalledWith(expect.any(Blob), 'png')
    expect(drawingAttrs().preview).toBe('hikki-editor://assets/new.png')
    expect(drawingAttrs().elements).toEqual([rect, label])
    expect(overlays[0].destroyed).toBe(true)
  })

  it('finished while Done is saving, it is stored and written once', async () => {
    openDrawing(editor, host, drawingPos())
    const done = vi.fn(async () => ({ data: { elements: [label], files: {} }, preview: null }))
    overlays[0].done = done
    const writes = vi.fn()
    editor.on('transaction', ({ transaction }) => {
      if (transaction.getMeta('hikkiSave')) writes()
    })
    await Promise.all([
      overlays[0].props.onDone({ elements: [rect], files: {} }, new Blob(['png'])),
      finishDrawing()
    ])
    expect(writes).toHaveBeenCalledTimes(1)
    expect(host.upload).toHaveBeenCalledTimes(1)
    expect(done).not.toHaveBeenCalled()
    expect(drawingAttrs().elements).toEqual([rect])
  })

  it("left open when its pictures can't be stored, for the page's change to close at once", async () => {
    openDrawing(editor, host, drawingPos())
    overlays[0].done = () => Promise.reject(new Error('disk full'))
    await finishDrawing()
    expect(overlays[0].destroyed).toBe(false)
    overlays[0].live = [label]
    closeDrawing()
    expect(drawingAttrs().elements).toEqual([label])
  })

  it('on a phone opens to look at only: closing it, at once or as Done, writes nothing', async () => {
    // A phone-sized screen (the app says so).
    setDrawingsReadOnly(true)
    const before = editor.state.doc
    openDrawing(editor, host, drawingPos())
    expect(overlays[0].props.readOnly).toBe(true)
    overlays[0].live = [label]
    overlays[0].done = async () => ({
      data: { elements: [label], files: {} },
      preview: new Blob(['png'])
    })
    await finishDrawing()
    expect(overlays[0].destroyed).toBe(true)
    openDrawing(editor, host, drawingPos())
    overlays[1].live = [label]
    closeDrawing()
    expect(overlays[1].destroyed).toBe(true)
    expect(host.upload).not.toHaveBeenCalled()
    expect(editor.state.doc.eq(before)).toBe(true)
  })

  it('opens to edit anywhere else', () => {
    openDrawing(editor, host, drawingPos())
    expect(overlays[0].props.readOnly).toBe(false)
  })

  it('finishing with no drawing open does nothing', async () => {
    await expect(finishDrawing()).resolves.toBeUndefined()
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

  it('fails with the message the AI panel shows, and the code it is reported under', async () => {
    const { sent, requests } = setup()
    const answer = requests.request('x', '')
    const { id } = sent[0] as { id: string }
    requests.handle({ id, type: 'error', code: 'missingKey', provider: 'OpenAI' })
    await expect(answer).rejects.toThrow('Add your OpenAI API key in Settings → AI')
    await expect(answer).rejects.toMatchObject({ id: 'aiMissingKey' })
    const empty = requests.request('y', '')
    requests.handle({ id: (sent[1] as { id: string }).id, type: 'done' })
    await expect(empty).rejects.toThrow()
  })
})

function selectBefore() {
  editor.commands.setTextSelection({ from: 1, to: 7 })
}

describe('a diagram of the selection', () => {
  it('goes below the passage as a drawing that says it is coming, then opens with the shapes', async () => {
    let answer: ((mermaid: string) => void) | undefined
    host.diagram = vi.fn(() => new Promise<string>((resolve) => (answer = resolve)))
    selectBefore()
    expect(editor.can().insertDiagram('before')).toBe(true)
    expect(editor.commands.insertDiagram('before')).toBe(true)
    await settle()
    expect(host.diagram).toHaveBeenCalledWith('before')
    const drawings = element.querySelectorAll('.hk-drawing')
    expect(drawings).toHaveLength(2)
    expect(drawings[0].getAttribute('aria-label')).toBe('Making a diagram…')
    expect(editor.state.doc.child(1).type.name).toBe('drawing')
    answer?.('flowchart LR\n  A --> B')
    await settle()
    expect(overlays).toHaveLength(1)
    expect(overlays[0].props.mermaid).toBe('flowchart LR\n  A --> B')
    expect(element.querySelectorAll('.hk-drawing')[0].getAttribute('aria-label')).not.toBe(
      'Making a diagram…'
    )
  })

  it('takes its empty drawing away again when no diagram comes', async () => {
    host.diagram = vi.fn(async () => {
      throw new DiagramError('No key', 'aiMissingKey')
    })
    selectBefore()
    editor.commands.insertDiagram('before')
    await settle()
    expect(overlays).toHaveLength(0)
    expect(element.querySelectorAll('.hk-drawing')).toHaveLength(1)
  })

  it('needs AI, words, and a screen drawings can be added on', () => {
    selectBefore()
    expect(editor.can().insertDiagram('before')).toBe(false)
    host.diagram = vi.fn(async () => 'flowchart LR')
    expect(editor.can().insertDiagram('  ')).toBe(false)
    setDrawingsReadOnly(true)
    expect(editor.can().insertDiagram('before')).toBe(false)
    expect(host.diagram).not.toHaveBeenCalled()
  })
})
