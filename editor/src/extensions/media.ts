import { Extension, mergeAttributes, Node, type Editor } from '@tiptap/core'
import FileHandler from '@tiptap/extension-file-handler'
import Image from '@tiptap/extension-image'
import type { Node as PMNode } from '@tiptap/pm/model'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet, type NodeView } from '@tiptap/pm/view'

import { reportError } from '../core/errors'
import { t } from '../core/i18n'
import { mediaToolbarExtension } from './media-toolbar'

export type MediaKind = 'image' | 'video' | 'audio' | 'file'

/** What the editor needs from its host (the bridge) for media. */
export type MediaHost = {
  /** Stores a file; resolves to its URL (`hikki-editor://assets/<name>`). */
  upload: (file: File, onProgress: (fraction: number) => void) => Promise<string>
  /** Opens an attachment with the system (Quick Look). */
  /** `name`: the file's own name, for the viewer's tab. */
  openAsset: (url: string, name?: string | null) => void
}

const ASSET = /^hikki-editor:\/\/assets\/[^/\\?#]+$/u

/**
 * A src the editor will render. Stored content (synced, imported, pasted) can carry anything, so it's an
 * allowlist: our assets everywhere; web images (http/https) and raster data URLs for images; https for
 * video/audio; blob: URLs (the browser dev build). Anything else renders as nothing.
 */
export function safeMediaSrc(src: unknown, kind: MediaKind): string | null {
  if (typeof src !== 'string') return null
  const value = src.trim()
  if (ASSET.test(value) || value.startsWith('blob:')) return value
  if (kind === 'file') return null
  if (/^https:\/\//iu.test(value)) return value
  if (kind === 'image') {
    if (/^http:\/\//iu.test(value)) return value
    if (/^data:image\/(png|jpe?g|gif|webp);base64,[a-z0-9+/=]+$/iu.test(value)) return value
  }
  return null
}

/** The kind a file becomes when dropped/pasted/picked. */
export function mediaKindOf(file: { type: string; name: string }): MediaKind {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? ''
  if (file.type.startsWith('image/') && file.type !== 'image/svg+xml') return 'image'
  if (file.type.startsWith('video/') || ['mp4', 'm4v', 'mov', 'webm'].includes(ext)) return 'video'
  if (file.type.startsWith('audio/') || ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'].includes(ext)) {
    return 'audio'
  }
  return 'file'
}

/** Human file size ("2.4 MB"). */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return ''
  const units = ['B', 'KB', 'MB', 'GB']
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`
}

const srcAttribute = (kind: MediaKind) => ({
  default: null,
  parseHTML: (el: HTMLElement) =>
    safeMediaSrc(el.getAttribute('src') ?? el.getAttribute('data-src'), kind),
  renderHTML: (attrs: Record<string, unknown>) => {
    const src = safeMediaSrc(attrs.src, kind)
    return src ? { [kind === 'file' ? 'data-src' : 'src']: src } : {}
  }
})

/** Images: Tiptap's (resizable from the sides, aspect kept) with an allowlisted src and an alignment. */
export const MediaImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      src: srcAttribute('image'),
      align: {
        default: 'center',
        parseHTML: (el) =>
          ['left', 'center', 'right'].includes(el.dataset.align ?? '')
            ? el.dataset.align
            : 'center',
        renderHTML: (attrs) => ({ 'data-align': attrs.align })
      }
    }
  }
}).configure({
  inline: false,
  allowBase64: false,
  HTMLAttributes: { class: 'hk-image' },
  resize: {
    enabled: true,
    directions: ['left', 'right'],
    minWidth: 80,
    alwaysPreserveAspectRatio: true
  }
})

/** A node whose DOM is a media element the user interacts with (controls), not ProseMirror. */
class MediaView implements NodeView {
  dom: HTMLElement
  constructor(element: HTMLElement) {
    this.dom = document.createElement('div')
    this.dom.className = 'hk-media'
    this.dom.contentEditable = 'false'
    this.dom.append(element)
  }
  stopEvent(event: Event) {
    // Play/seek/volume belong to the element; dragging the block still goes to ProseMirror.
    return event.type !== 'dragstart' && event.type !== 'drop'
  }
  ignoreMutation() {
    return true
  }
}

function mediaNode(name: 'video' | 'audio') {
  return Node.create({
    name,
    group: 'block',
    atom: true,
    draggable: true,
    selectable: true,
    addAttributes() {
      return { src: srcAttribute(name), name: { default: null } }
    },
    parseHTML() {
      return [{ tag: `${name}[src]` }]
    },
    renderHTML({ HTMLAttributes }) {
      return [name, mergeAttributes(HTMLAttributes, { controls: 'true', preload: 'metadata' })]
    },
    addNodeView() {
      return ({ node }) => {
        const element = document.createElement(name)
        element.controls = true
        element.preload = 'metadata'
        if (name === 'video') (element as HTMLVideoElement).playsInline = true
        const src = safeMediaSrc(node.attrs.src, name)
        if (src) element.src = src
        element.className = `hk-${name}`
        return new MediaView(element)
      }
    }
  })
}

export const Video = mediaNode('video')
export const Audio = mediaNode('audio')

/** An attachment: icon, name and size; opens with the system (Quick Look), never in the web view. */
export const FileAttachment = Node.create<{ host: MediaHost | null }>({
  name: 'fileAttachment',
  group: 'block',
  atom: true,
  draggable: true,
  selectable: true,
  addOptions() {
    return { host: null }
  },
  addAttributes() {
    return {
      src: srcAttribute('file'),
      name: { default: null, parseHTML: (el) => el.getAttribute('data-name') },
      size: {
        default: null,
        parseHTML: (el) => Number(el.getAttribute('data-size')) || null,
        renderHTML: (attrs) => (attrs.size ? { 'data-size': String(attrs.size) } : {})
      }
    }
  },
  parseHTML() {
    return [{ tag: 'div[data-type="file"]' }]
  },
  renderHTML({ node, HTMLAttributes }) {
    return [
      'div',
      mergeAttributes(HTMLAttributes, { 'data-type': 'file', 'data-name': node.attrs.name ?? '' }),
      node.attrs.name ?? ''
    ]
  },
  addNodeView() {
    return ({ node }) => {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = 'hk-file'
      const icon = document.createElement('span')
      icon.className = 'hk-file-icon'
      icon.textContent =
        (node.attrs.name as string | null)?.split('.').pop()?.slice(0, 4).toUpperCase() ?? ''
      const name = document.createElement('span')
      name.className = 'hk-file-name'
      name.textContent = (node.attrs.name as string | null) ?? t('media.file')
      const size = document.createElement('span')
      size.className = 'hk-file-size'
      size.textContent = formatBytes(node.attrs.size as number)
      button.append(icon, name, size)
      const src = safeMediaSrc(node.attrs.src, 'file')
      button.addEventListener('click', () => {
        if (src) this.options.host?.openAsset(src, node.attrs.name as string | null)
      })
      return new MediaView(button)
    }
  }
})

// MARK: - Uploads

type Pending = {
  id: string
  pos: number
  name: string
  kind: MediaKind
  progress: number
  failed: boolean
}
export const UploadsKey = new PluginKey<{ pending: Pending[]; decorations: DecorationSet }>(
  'uploads'
)

function placeholder(item: Pending): HTMLElement {
  const el = document.createElement('div')
  el.className = 'hk-upload'
  el.dataset.failed = String(item.failed)
  el.setAttribute('role', 'status')
  const label = document.createElement('span')
  label.className = 'hk-upload-name'
  label.textContent = item.failed ? t('media.uploadFailed', { name: item.name }) : item.name
  const bar = document.createElement('span')
  bar.className = 'hk-upload-bar'
  const fill = document.createElement('span')
  fill.style.transform = `scaleX(${item.progress})`
  bar.append(fill)
  el.append(label, bar)
  return el
}

function decorate(doc: PMNode, pending: Pending[]) {
  return DecorationSet.create(
    doc,
    pending.map((item) =>
      Decoration.widget(item.pos, () => placeholder(item), {
        key: `${item.id}:${item.progress}:${item.failed}`,
        side: -1
      })
    )
  )
}

/**
 * In-flight uploads show as placeholders (decorations — not in the document, so a crash or a quit mid-upload
 * leaves nothing broken behind). When the file is stored, the real node goes where the placeholder is now.
 */
const uploadsPlugin = new Plugin({
  key: UploadsKey,
  state: {
    init: () => ({ pending: [] as Pending[], decorations: DecorationSet.empty }),
    apply(tr, value) {
      const meta = tr.getMeta(UploadsKey) as
        | { add?: Pending; update?: Partial<Pending> & { id: string }; remove?: string }
        | undefined
      let pending = value.pending.map((p) => ({ ...p, pos: tr.mapping.map(p.pos) }))
      if (meta?.add) pending = [...pending, meta.add]
      if (meta?.update)
        pending = pending.map((p) => (p.id === meta.update!.id ? { ...p, ...meta.update } : p))
      if (meta?.remove) pending = pending.filter((p) => p.id !== meta.remove)
      if (!meta && !tr.docChanged) return value
      return { pending, decorations: decorate(tr.doc, pending) }
    }
  },
  props: {
    decorations: (state) => UploadsKey.getState(state)?.decorations
  }
})

let uploadSeq = 0

/** Uploads `files` and inserts them as blocks at `pos` (in order). */
export function insertFiles(editor: Editor, host: MediaHost, files: File[], pos: number): void {
  for (const file of files) {
    const id = `upload-${++uploadSeq}`
    const kind = mediaKindOf(file)
    const at = Math.min(pos, editor.state.doc.content.size)
    editor.view.dispatch(
      editor.state.tr.setMeta(UploadsKey, {
        add: { id, pos: at, name: file.name, kind, progress: 0, failed: false }
      })
    )
    const update = (patch: Partial<Pending>) => {
      if (editor.isDestroyed) return
      editor.view.dispatch(editor.state.tr.setMeta(UploadsKey, { update: { id, ...patch } }))
    }
    host
      .upload(file, (progress) => update({ progress }))
      .then((src) => {
        if (editor.isDestroyed) return
        const item = UploadsKey.getState(editor.state)?.pending.find((p) => p.id === id)
        if (!item) return
        const node = nodeFor(kind, src, file)
        const tr = editor.state.tr
          .setMeta(UploadsKey, { remove: id })
          .insert(item.pos, node(editor))
        editor.view.dispatch(tr)
      })
      .catch((error: unknown) => {
        reportError('uploadFailed', error, { kind })
        update({ failed: true })
        setTimeout(() => {
          if (!editor.isDestroyed)
            editor.view.dispatch(editor.state.tr.setMeta(UploadsKey, { remove: id }))
        }, 4000)
      })
  }
}

function nodeFor(kind: MediaKind, src: string, file: File) {
  return (editor: Editor) => {
    const { schema } = editor.state
    switch (kind) {
      case 'image':
        return schema.nodes.image.create({ src, alt: file.name })
      case 'video':
        return schema.nodes.video.create({ src, name: file.name })
      case 'audio':
        return schema.nodes.audio.create({ src, name: file.name })
      case 'file':
        return schema.nodes.fileAttachment.create({ src, name: file.name, size: file.size })
    }
  }
}

const ACCEPT: Record<MediaKind, string> = {
  image: 'image/png,image/jpeg,image/gif,image/webp,image/heic,image/avif',
  video: 'video/*',
  audio: 'audio/*',
  file: ''
}

/** "/" Image, Video, Audio, File: the system file picker, then upload at the caret. */
export function pickFiles(editor: Editor, host: MediaHost, kind: MediaKind): void {
  const input = document.createElement('input')
  input.type = 'file'
  input.multiple = kind !== 'file'
  if (ACCEPT[kind]) input.accept = ACCEPT[kind]
  const pos = editor.state.selection.from
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? [])
    if (files.length) insertFiles(editor, host, files, pos)
  })
  input.click()
}

/** Media blocks plus dropping/pasting files from the system. */
export function mediaExtensions(host: MediaHost | null) {
  const uploads = Extension.create({
    name: 'uploads',
    addProseMirrorPlugins: () => [uploadsPlugin]
  })
  const handler = host
    ? [
        FileHandler.configure({
          onDrop: (editor, files, pos) => insertFiles(editor, host, files, pos),
          onPaste: (editor, files) => insertFiles(editor, host, files, editor.state.selection.from)
        })
      ]
    : []
  return [
    MediaImage,
    Video,
    Audio,
    FileAttachment.configure({ host }),
    uploads,
    mediaToolbarExtension(host),
    ...handler
  ]
}
