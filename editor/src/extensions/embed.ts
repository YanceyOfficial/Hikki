import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { NodeView } from '@tiptap/pm/view'

import { renderEmbedPanel } from '../components/embed-panel'
import { FloatingLayer } from '../components/floating'
import { t } from '../core/i18n'
import {
  clampEmbedHeight,
  frameSrc,
  htmlEmbedDocument,
  isWebURL,
  safeFrameSrc,
  themedEmbedSrc,
  type EmbedProvider,
  type EmbedSource
} from '../lib/embeds'

/** What embeds need from the host: where the original page opens, and the BFF that shims YouTube (or null). */
export type EmbedHost = {
  openExternal: (href: string) => void
  bff: string | null
}

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    embed: {
      /** Inserts an embed block (replacing the empty block the caret is in). */
      insertEmbed: (source: EmbedSource) => ReturnType
    }
  }
}

const dark = () =>
  typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: dark)').matches

/** Sandbox for a third-party page: it runs, keeps its own origin, may open popups (the host sends them out). */
const PAGE_SANDBOX = 'allow-scripts allow-same-origin allow-popups allow-forms allow-presentation'
/** Sandbox for a snippet: it runs, but as no origin at all. */
const HTML_SANDBOX = 'allow-scripts allow-popups'
const ALLOW = 'autoplay; fullscreen; picture-in-picture; clipboard-write; encrypted-media'

/**
 * Embed block (Notion's Embed / HTML / Google Drive / Tweet / Gist / Maps / Figma): a frame on a third-party
 * page or a sandboxed snippet of HTML, as wide as the column and as tall as its `height`, which a handle
 * under the frame changes. The original link opens outside from the hover bar.
 */
export const Embed = Node.create<{ host: EmbedHost | null }>({
  name: 'embed',
  group: 'block',
  atom: true,
  draggable: true,
  selectable: true,

  addOptions() {
    return { host: null }
  },

  addAttributes() {
    return {
      src: { default: null, parseHTML: (el) => el.getAttribute('data-src') },
      html: { default: null, parseHTML: (el) => el.getAttribute('data-html') },
      provider: {
        default: 'generic',
        parseHTML: (el) => el.getAttribute('data-provider') ?? 'generic'
      },
      original: { default: null, parseHTML: (el) => el.getAttribute('data-original') },
      height: {
        default: 400,
        parseHTML: (el) => Number(el.getAttribute('data-height')) || 400,
        renderHTML: (attrs) => ({ 'data-height': String(attrs.height) })
      }
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="embed"]' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    const { src, html, provider, original } = node.attrs
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-type': 'embed',
        'data-src': src,
        'data-html': html,
        'data-provider': provider,
        'data-original': original
      })
    ]
  },

  addCommands() {
    return {
      insertEmbed:
        (source) =>
        ({ chain }) =>
          chain()
            .insertContent({
              type: this.name,
              attrs:
                source.kind === 'iframe'
                  ? {
                      src: source.src,
                      provider: source.provider,
                      original: source.original,
                      height: source.height
                    }
                  : { html: source.html, provider: 'generic', height: source.height }
            })
            .run()
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) =>
      new EmbedView(node, editor, getPos as () => number | undefined, this.options.host)
  }
})

class EmbedView implements NodeView {
  dom: HTMLElement
  private frame: HTMLIFrameElement
  private node: PMNode

  constructor(
    node: PMNode,
    private readonly editor: Editor,
    private readonly getPos: () => number | undefined,
    private readonly host: EmbedHost | null
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.className = 'hk-embed group/embed'
    this.dom.contentEditable = 'false'
    this.dom.dataset.provider = node.attrs.provider as string

    this.frame = document.createElement('iframe')
    this.frame.className = 'hk-embed-frame'
    this.frame.title = t('embed.frameTitle')
    this.frame.loading = 'lazy'
    this.frame.referrerPolicy = 'strict-origin-when-cross-origin'
    this.frame.setAttribute('allow', ALLOW)
    this.frame.setAttribute('allowfullscreen', 'true')
    this.load()
    this.dom.append(this.frame)

    // The hover bar: the original page, opened outside.
    const original = node.attrs.original as string | null
    if (isWebURL(original) && this.host) {
      const { openExternal } = this.host
      const bar = document.createElement('div')
      bar.className = 'hk-embed-bar'
      const open = document.createElement('button')
      open.type = 'button'
      open.className = 'hk-embed-open'
      open.textContent = t('embed.open')
      open.addEventListener('click', () => openExternal(original))
      bar.append(open)
      this.dom.append(bar)
    }

    // The handle under the frame: drag to set the height.
    const handle = document.createElement('div')
    handle.className = 'hk-embed-resize'
    handle.setAttribute('role', 'separator')
    handle.setAttribute('aria-label', t('embed.resize'))
    handle.addEventListener('pointerdown', this.onResizeStart)
    this.dom.append(handle)
    this.applyHeight(node.attrs.height as number)
  }

  private load() {
    const provider = this.node.attrs.provider as EmbedProvider
    const html = this.node.attrs.html as string | null
    const src = this.node.attrs.src as string | null
    if (html !== null) {
      this.frame.setAttribute('sandbox', HTML_SANDBOX)
      this.frame.srcdoc = htmlEmbedDocument(html, dark())
      return
    }
    const safe = safeFrameSrc(src)
    if (safe) {
      this.frame.setAttribute('sandbox', PAGE_SANDBOX)
      this.frame.src = themedEmbedSrc(
        provider,
        frameSrc(provider, safe, this.host?.bff ?? null),
        dark()
      )
    } else {
      // Nothing loads for a src that isn't an https page (a corrupt or hostile document).
      this.frame.removeAttribute('src')
    }
  }

  private applyHeight(height: number) {
    this.frame.style.height = `${clampEmbedHeight(height)}px`
  }

  private onResizeStart = (event: PointerEvent) => {
    if (event.button !== 0 || !this.editor.isEditable) return
    event.preventDefault()
    const handle = event.currentTarget as HTMLElement
    const startY = event.clientY
    const startHeight = clampEmbedHeight(this.node.attrs.height as number)
    let height = startHeight
    // The frame would swallow the pointer once it is over it: it goes inert for the drag.
    this.dom.dataset.resizing = 'true'
    handle.setPointerCapture?.(event.pointerId)
    const move = (e: PointerEvent) => {
      if (e.pointerId !== event.pointerId) return
      height = clampEmbedHeight(startHeight + (e.clientY - startY))
      this.applyHeight(height)
    }
    const end = (e: PointerEvent) => {
      if (e.pointerId !== event.pointerId) return
      handle.removeEventListener('pointermove', move)
      handle.removeEventListener('pointerup', end)
      handle.removeEventListener('pointercancel', end)
      delete this.dom.dataset.resizing
      const pos = this.getPos()
      if (height !== startHeight && pos !== undefined) {
        this.editor.view.dispatch(
          this.editor.state.tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, height })
        )
      }
    }
    handle.addEventListener('pointermove', move)
    handle.addEventListener('pointerup', end)
    handle.addEventListener('pointercancel', end)
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    const reload =
      node.attrs.src !== this.node.attrs.src ||
      node.attrs.html !== this.node.attrs.html ||
      node.attrs.provider !== this.node.attrs.provider
    this.node = node
    if (reload) this.load()
    this.applyHeight(node.attrs.height as number)
    return true
  }

  /** The frame's content, the hover bar and the handle are ours; dragging the block still goes to ProseMirror. */
  stopEvent(event: Event) {
    return event.type !== 'dragstart' && event.type !== 'drop'
  }

  ignoreMutation() {
    return true
  }
}

let open: FloatingLayer | null = null

function close() {
  open?.destroy()
  open = null
}

/**
 * The panel that asks for the link (or the HTML) at the caret and inserts the embed; Escape or a press
 * outside cancels (the layers' bus).
 */
export function openEmbedPanel(editor: Editor, provider: EmbedProvider | 'html'): void {
  close()
  const { from } = editor.state.selection
  const anchor = () => {
    try {
      const coords = editor.view.coordsAtPos(from)
      return new DOMRect(coords.left, coords.top, 1, coords.bottom - coords.top)
    } catch {
      return null
    }
  }
  const cancel = () => {
    close()
    editor.commands.focus()
  }
  const layer = new FloatingLayer('hk-embed-panel w-[400px] max-w-[calc(100vw-16px)] p-2', {
    onDismiss: cancel
  })
  open = layer
  renderEmbedPanel(
    layer,
    {
      provider,
      onDone: (source) => {
        close()
        editor.chain().focus().insertEmbed(source).run()
      },
      onCancel: cancel
    },
    anchor
  )
}
