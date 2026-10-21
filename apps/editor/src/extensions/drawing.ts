import {
  drawingText,
  storedElements,
  storedFiles,
  usedFileIds,
  type DrawingData,
  type StoredElement
} from '@hikki/excalidraw'
import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { NodeView } from '@tiptap/pm/view'

import { renderDrawingOverlay, type DrawingOverlay } from '../components/drawing-overlay'
import { reportError } from '../core/errors'
import { t } from '../core/i18n'
import { followNode, type Followed, type BlockUnit } from './block-units'
import { SAVE_META } from './comments'
import { localAssetSrc } from './media'

/** What a drawing needs from the editor's host: storing files and Text to diagram (AI). */
export type DrawingEditorHost = {
  /** Stores a file (a picture placed in the drawing, its preview); resolves to its asset URL. */
  upload: (blob: Blob, extension: string) => Promise<string>
  /** Reads a stored file back (one of the editor's own assets). */
  read: (src: string) => Promise<Blob>
  /** Opens a drawing's link (http or https) in the browser. */
  openLink: (url: string) => void
  /** The user's words as a Mermaid diagram; null without AI. Rejects with a message to show. */
  diagram: ((prompt: string) => Promise<string>) | null
  /** The drawing's editor took the whole page, or gave it back: the native bars over the page step aside meanwhile. */
  fullScreen?: (open: boolean) => void
}

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    drawing: {
      /** Adds an empty drawing at the selection and opens it. */
      insertDrawing: () => ReturnType
    }
  }
}

/** A drawing's pictures and preview are files of this workspace only: a scene never loads anything off the device. */
const isSafeFileSrc = (src: string) => localAssetSrc(src) !== null

/** A drawing's stored data, checked (stored content can carry anything). */
export function drawingData(node: PMNode): DrawingData {
  const elements = storedElements(node.attrs.elements)
  // Only the pictures a kept image element shows: entries for dropped elements (or none) are never read.
  const used = new Set(usedFileIds(elements))
  const files = Object.fromEntries(
    Object.entries(storedFiles(node.attrs.files, isSafeFileSrc)).filter(([id]) => used.has(id))
  )
  return { elements, files }
}

const jsonAttribute = (name: string, fallback: () => unknown) => ({
  default: fallback(),
  parseHTML: (el: HTMLElement) => {
    try {
      return JSON.parse(el.getAttribute(`data-${name}`) ?? '') as unknown
    } catch {
      return fallback()
    }
  },
  renderHTML: (attrs: Record<string, unknown>) => ({
    [`data-${name}`]: JSON.stringify(attrs[name])
  })
})

/** The drawing open in the full-screen editor, if any (one at a time). */
let open: { overlay: DrawingOverlay; close: () => void } | null = null

/**
 * Closes the open drawing with what it holds now, at once: its page is about to be replaced (`loadDocument`), so
 * the last strokes go into the page before it is saved. Pictures not stored yet are left out.
 */
export function closeDrawing(): void {
  open?.close()
}

/**
 * Opens the drawing at `pos` in the full-screen editor. Changes go into the block as they are made (out of the page's
 * undo — the drawing has its own — but saved), the preview when it closes.
 */
export function openDrawing(editor: Editor, host: DrawingEditorHost, pos: number): void {
  if (!editor.isEditable) return
  const node = editor.state.doc.nodeAt(pos)
  if (node?.type.name !== 'drawing') return
  closeDrawing()
  let followed: Followed<BlockUnit> | null = null
  const write = (
    attrs: Partial<{ elements: StoredElement[]; files: object; preview: string | null }>
  ) => {
    const unit = followed?.current
    if (!unit || editor.isDestroyed) return
    editor.view.dispatch(
      editor.state.tr
        .setNodeMarkup(unit.pos, undefined, { ...unit.node.attrs, ...attrs })
        .setMeta('addToHistory', false)
        .setMeta(SAVE_META, true)
    )
  }
  const finish = () => {
    followed?.stop()
    overlay.destroy()
    if (open?.overlay === overlay) open = null
    host.fullScreen?.(false)
  }
  const overlay = renderDrawingOverlay({
    data: drawingData(node),
    host,
    title: t('drawing.title'),
    onChange: (data) => write({ elements: data.elements, files: data.files }),
    onFail: () => finish(),
    onDone: async (data, preview) => {
      let src: string | null = (followed?.current?.node.attrs.preview as string | null) ?? null
      try {
        src = preview ? await host.upload(preview, 'png') : null
      } catch (error) {
        reportError('drawingPreviewFailed', error)
      }
      write({ elements: data.elements, files: data.files, preview: src })
      finish()
      if (!editor.isDestroyed) editor.commands.focus()
    }
  })
  followed = followNode(editor, pos, () => {
    // The block went away under it (a remote reload without it, the page closing): nothing left to write to.
    if (open?.overlay === overlay) open = null
    overlay.destroy()
    host.fullScreen?.(false)
  })
  host.fullScreen?.(true)
  open = {
    overlay,
    close: () => {
      const elements = overlay.elements()
      if (elements) write({ elements })
      finish()
    }
  }
}

/** The block in the page: the drawing's preview (a PNG), or a prompt to draw when it is empty; a click opens it. */
class DrawingView implements NodeView {
  dom: HTMLElement
  private node: PMNode

  constructor(
    node: PMNode,
    private readonly editor: Editor,
    private readonly getPos: () => number | undefined,
    private readonly host: DrawingEditorHost | null
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.className = 'hk-drawing'
    this.dom.contentEditable = 'false'
    this.dom.setAttribute('role', 'button')
    this.dom.tabIndex = 0
    this.dom.addEventListener('click', this.open)
    this.dom.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault()
        this.open()
      }
    })
    this.render()
  }

  private open = () => {
    const pos = this.getPos()
    if (pos !== undefined && this.host) openDrawing(this.editor, this.host, pos)
  }

  private render() {
    const preview = localAssetSrc(this.node.attrs.preview)
    const empty = storedElements(this.node.attrs.elements).length === 0
    this.dom.replaceChildren()
    this.dom.dataset.empty = String(empty || !preview)
    const text = drawingText(this.node.attrs.elements as unknown[])
    // Read out as what shows: the picture ("Drawing", its words), or the placeholder's own line.
    const shows = preview && !empty
    const name = shows ? t('drawing.title') : empty ? t('drawing.empty') : t('drawing.noPreview')
    this.dom.setAttribute('aria-label', text ? `${name}: ${text}` : name)
    if (shows) {
      const img = document.createElement('img')
      img.className = 'hk-drawing-preview'
      img.alt = text || t('drawing.title')
      img.draggable = false
      // Drawn at its own size (the PNG is twice that), never wider than the column.
      img.addEventListener('load', () => {
        img.style.width = `${img.naturalWidth / 2}px`
      })
      img.src = preview
      this.dom.append(img)
      return
    }
    const label = document.createElement('span')
    label.className = 'hk-drawing-empty'
    label.textContent = name
    this.dom.append(label)
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    const changed =
      node.attrs.preview !== this.node.attrs.preview ||
      node.attrs.elements !== this.node.attrs.elements
    this.node = node
    if (changed) this.render()
    return true
  }

  stopEvent(event: Event) {
    // A click opens the drawing; dragging the block still goes to ProseMirror.
    return event.type === 'click' || event.type === 'keydown'
  }

  ignoreMutation() {
    return true
  }
}

/**
 * An Excalidraw drawing (`@hikki/excalidraw`): its elements and pictures stored in the block, shown in the page as a
 * PNG preview kept as an asset; Excalidraw itself loads only when a drawing is opened.
 */
export const Drawing = Node.create<{ host: DrawingEditorHost | null }>({
  name: 'drawing',
  group: 'block',
  atom: true,
  draggable: true,
  selectable: true,
  addOptions() {
    return { host: null }
  },
  addAttributes() {
    return {
      elements: jsonAttribute('elements', () => []),
      files: jsonAttribute('files', () => ({})),
      preview: {
        default: null,
        parseHTML: (el) => localAssetSrc(el.querySelector('img')?.getAttribute('src')),
        renderHTML: () => ({})
      }
    }
  },
  parseHTML() {
    return [{ tag: 'div[data-type="drawing"]' }]
  },
  renderHTML({ node, HTMLAttributes }) {
    const preview = localAssetSrc(node.attrs.preview)
    const alt = drawingText(node.attrs.elements as unknown[])
    const attrs = mergeAttributes(HTMLAttributes, { 'data-type': 'drawing' })
    return preview ? ['div', attrs, ['img', { src: preview, alt }]] : ['div', attrs]
  },
  addCommands() {
    return {
      insertDrawing:
        () =>
        ({ editor, tr, dispatch, commands }) => {
          const at = tr.selection.from
          if (!commands.insertContent({ type: this.name })) return false
          if (dispatch) {
            const host = this.options.host
            // Opened once the block is in the page (the transaction applied).
            if (host)
              queueMicrotask(() => {
                const pos = findInserted(editor, at)
                if (pos !== null) openDrawing(editor, host, pos)
              })
          }
          return true
        }
    }
  },
  addNodeView() {
    return ({ node, editor, getPos }) => new DrawingView(node, editor, getPos, this.options.host)
  }
})

/** The empty drawing just inserted around `near` (the first at or after it). */
function findInserted(editor: Editor, near: number): number | null {
  let found: number | null = null
  editor.state.doc.descendants((node, pos) => {
    if (found !== null) return false
    if (node.type.name === 'drawing' && pos + node.nodeSize > near - 1) found = pos
    return found === null
  })
  return found
}
