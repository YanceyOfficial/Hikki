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
  type LinkCard,
  type EmbedProvider,
  type EmbedSource
} from '../lib/embeds'
import { followPosition, type Followed } from './block-units'

/** What embeds need from the host: where the original page opens, and the BFF that shims YouTube (or null). */
export type EmbedHost = {
  openExternal: (href: string) => void
  bff: string | null
  /** A page's title, description and icon for a link card (null when it can't be read). */
  linkPreview: (url: string) => Promise<LinkCard | null>
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
      // A link card's details, read once when the embed is added (and stored, so the card shows offline).
      title: { default: null, parseHTML: (el) => el.getAttribute('data-title') },
      description: { default: null, parseHTML: (el) => el.getAttribute('data-description') },
      icon: { default: null, parseHTML: (el) => el.getAttribute('data-icon') },
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
    const { src, html, provider, original, title, description, icon } = node.attrs
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-type': 'embed',
        'data-src': src,
        'data-html': html,
        'data-provider': provider,
        'data-original': original,
        'data-title': title,
        'data-description': description,
        'data-icon': icon
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
      // Any page without an embed of its own is a link card: most sites refuse to be framed by another page.
      node.attrs.provider === 'generic' && node.attrs.html === null
        ? new LinkCardView(node, editor, getPos as () => number | undefined, this.options.host)
        : new EmbedView(node, editor, getPos as () => number | undefined, this.options.host)
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

/** Links whose cards were just added from the panel: their details are saved into the block once read. */
const freshCards = new Set<string>()

/**
 * A link card (Notion's bookmark): the page's icon, title, description and address, opening the page outside when
 * clicked. A card added just now saves what it reads into the block; an older one without details reads them for
 * display only, so viewing a page never counts as editing it.
 */
class LinkCardView implements NodeView {
  dom: HTMLElement
  private node: PMNode
  private shown: LinkCard | null = null

  constructor(
    node: PMNode,
    private readonly editor: Editor,
    private readonly getPos: () => number | undefined,
    private readonly host: EmbedHost | null
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.className = 'hk-embed-card'
    this.dom.contentEditable = 'false'
    this.dom.setAttribute('role', 'link')
    this.dom.tabIndex = 0
    this.dom.addEventListener('click', this.open)
    this.dom.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') this.open()
    })
    this.render()
    this.readDetails()
  }

  private get url(): string | null {
    const original = this.node.attrs.original as string | null
    return isWebURL(original) ? original : null
  }

  private open = () => {
    if (this.url && this.host) this.host.openExternal(this.url)
  }

  private readDetails() {
    const url = this.url
    if (!url || !this.host || this.node.attrs.title) {
      if (url) freshCards.delete(url)
      return
    }
    const fresh = freshCards.delete(url)
    void this.host.linkPreview(url).then((card) => {
      if (!card || this.editor.isDestroyed) return
      this.shown = card
      this.render()
      const pos = this.getPos()
      if (!fresh || pos === undefined || !this.editor.isEditable) return
      this.editor.view.dispatch(
        this.editor.state.tr.setNodeMarkup(pos, undefined, {
          ...this.node.attrs,
          title: card.title,
          description: card.description,
          icon: card.icon
        })
      )
    })
  }

  private render() {
    const attrs = this.node.attrs
    const title = (attrs.title as string | null) ?? this.shown?.title ?? null
    const description = (attrs.description as string | null) ?? this.shown?.description ?? null
    const icon = (attrs.icon as string | null) ?? this.shown?.icon ?? null
    const url = this.url ?? (attrs.original as string | null) ?? ''
    this.dom.replaceChildren()
    if (isWebURL(icon)) {
      const img = document.createElement('img')
      img.className = 'hk-embed-card-icon'
      img.alt = ''
      img.referrerPolicy = 'no-referrer'
      img.src = icon
      img.addEventListener('error', () => img.remove(), { once: true })
      this.dom.append(img)
    }
    const heading = document.createElement('div')
    heading.className = 'hk-embed-card-title'
    heading.textContent = title ?? hostOf(url)
    this.dom.append(heading)
    if (description) {
      const line = document.createElement('div')
      line.className = 'hk-embed-card-description'
      line.textContent = description
      this.dom.append(line)
    }
    const address = document.createElement('div')
    address.className = 'hk-embed-card-url'
    address.textContent = url
    this.dom.append(address)
    this.dom.setAttribute('aria-label', title ?? url)
  }

  update(node: PMNode) {
    if (
      node.type !== this.node.type ||
      node.attrs.provider !== 'generic' ||
      node.attrs.html !== null
    )
      return false
    const changed = node.attrs.original !== this.node.attrs.original
    this.node = node
    if (changed) this.shown = null
    this.render()
    if (changed) this.readDetails()
    return true
  }

  stopEvent(event: Event) {
    return event.type !== 'dragstart' && event.type !== 'drop'
  }

  ignoreMutation() {
    return true
  }
}

function hostOf(url: string): string {
  try {
    return new URL(url).host
  } catch {
    return url
  }
}

let open: { layer: FloatingLayer; at: Followed<number> } | null = null

function close() {
  open?.at.stop()
  open?.layer.destroy()
  open = null
}

/**
 * The panel that asks for the link (or the HTML) at the caret and inserts the embed; Escape or a press
 * outside cancels (the layers' bus).
 */
export function openEmbedPanel(editor: Editor, provider: EmbedProvider | 'html'): void {
  close()
  // Where the embed goes, followed through edits meanwhile (a remote reload replacing it closes the panel).
  const at = followPosition(editor, editor.state.selection.from, () => close())
  const anchor = () => {
    try {
      const coords = editor.view.coordsAtPos(at.current ?? 0)
      return new DOMRect(coords.left, coords.top, 1, coords.bottom - coords.top)
    } catch {
      return null
    }
  }
  const cancel = () => {
    close()
    if (!editor.isDestroyed) editor.commands.focus()
  }
  const layer = new FloatingLayer('hk-embed-panel w-[400px] max-w-[calc(100vw-16px)] p-2', {
    onDismiss: cancel
  })
  open = { layer, at }
  renderEmbedPanel(
    layer,
    {
      provider,
      onDone: (source) => {
        const pos = at.current
        close()
        if (pos === null) return
        // A link card just added stores what it reads about its page (an edit the user made).
        if (source.kind === 'iframe' && source.provider === 'generic')
          freshCards.add(source.original)
        editor.chain().focus().setTextSelection(pos).insertEmbed(source).run()
      }
    },
    anchor
  )
}
