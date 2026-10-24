import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state'
import type { NodeView } from '@tiptap/pm/view'

import { FloatingLayer } from '../components/floating'
import { renderRubyPanel } from '../components/ruby-panel'
import { tiptapShortcut } from '../core/shortcuts'
import { followNode, followPosition } from './block-units'

/** A run of the selection: kanji with their reading, or kana/punctuation left bare. */
export type RubySegment = { text: string; reading?: string }

/** Where reading suggestions come from (the native side's tokenizer); optional. */
export type RubyHost = {
  /** The selection split into kanji runs with readings and bare kana, or null when the host has none. */
  suggestReading: (text: string) => Promise<RubySegment[] | null>
}

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    ruby: {
      /** Gives the selected text (within one line) the reading; inside a ruby, changes its reading. */
      setRuby: (reading: string) => ReturnType
      /** Replaces the selected text with its segments: a ruby per kanji run, the kana left bare. */
      setRubySegments: (segments: RubySegment[]) => ReturnType
      /** Replaces the ruby at the selection with its base text. */
      unsetRuby: () => ReturnType
      /** Opens the reading panel for the selection (or the ruby the caret is in). */
      editRuby: () => ReturnType
    }
  }
}

/** The ruby node containing `pos`, with its position. */
export function rubyAt(doc: PMNode, pos: number): { node: PMNode; pos: number } | null {
  const $pos = doc.resolve(pos)
  for (let depth = $pos.depth; depth >= 1; depth--) {
    const node = $pos.node(depth)
    if (node.type.name === 'ruby') return { node, pos: $pos.before(depth) }
  }
  const after = $pos.nodeAfter
  if (after?.type.name === 'ruby') return { node: after, pos: $pos.pos }
  return null
}

/** The whole reading of a segmented suggestion (kana kept, kanji read). */
export const wholeReading = (segments: RubySegment[]): string =>
  segments.map((s) => s.reading ?? s.text).join('')

/**
 * The host's reply as segments — `{ text, reading }` objects, a null reading meaning none (the native side
 * encodes nil as null) — or null when it is anything else.
 */
export function rubySegmentsFrom(reply: unknown): RubySegment[] | null {
  if (!Array.isArray(reply) || reply.length === 0) return null
  const segments: RubySegment[] = []
  for (const item of reply) {
    if (typeof item !== 'object' || item === null) return null
    const { text, reading } = item as { text?: unknown; reading?: unknown }
    if (typeof text !== 'string' || !text) return null
    if (typeof reading === 'string' && reading) segments.push({ text, reading })
    else if (reading === null || reading === undefined) segments.push({ text })
    else return null
  }
  return segments
}

let openPanel: { layer: FloatingLayer; stop: () => void } | null = null
const closePanel = () => {
  openPanel?.stop()
  openPanel?.layer.destroy()
  openPanel = null
}

/** The selected text when it sits within one line and holds text only; null otherwise. */
function selectedText(editor: Editor): string | null {
  const { from, to, $from, $to } = editor.state.selection
  if (from === to || !$from.sameParent($to) || !$from.parent.isTextblock) return null
  let text = ''
  let plain = true
  editor.state.doc.slice(from, to).content.forEach((child) => {
    if (child.isText) text += child.text
    else plain = false
  })
  return plain && text ? text : null
}

/**
 * Furigana: 漢字 with its reading above (`<ruby><rb>漢字</rb><rt>かんじ</rt></ruby>`). An inline node whose
 * content is the base text (editable in place); the reading is an attribute, edited in a small panel
 * (click the reading, or ⇧⌘R on a selection). A phrase is read kanji by kanji: 役に立ちます becomes
 * 役(やく)に立(た)ちます.
 */
export function Ruby(host: RubyHost | null = null) {
  return Node.create({
    name: 'ruby',
    group: 'inline',
    inline: true,
    content: 'text*',
    // The base text takes the page's marks (bold, colour…); the reading never does — a mark the ruby itself gets (a
    // whole line made bold) moves onto its base text (`RubyMarksInside`).
    marks: '_',
    defining: true,

    addAttributes() {
      return {
        reading: {
          default: '',
          parseHTML: (el) => el.querySelector('rt')?.textContent?.trim() ?? '',
          renderHTML: (attrs) => ({ 'data-reading': attrs.reading })
        }
      }
    },

    parseHTML() {
      return [
        {
          tag: 'ruby',
          contentElement: (el) => {
            // The base text: <rb> when there is one, else the ruby without its <rt>/<rp>.
            const rb = el.querySelector('rb')
            if (rb) return rb
            const clone = el.cloneNode(true) as HTMLElement
            clone.querySelectorAll('rt, rp').forEach((n) => n.remove())
            return clone
          }
        }
      ]
    },

    renderHTML({ node, HTMLAttributes }) {
      return [
        'ruby',
        mergeAttributes(HTMLAttributes, { class: 'hk-ruby' }),
        ['rb', 0],
        ['rt', {}, node.attrs.reading as string]
      ]
    },

    renderText({ node }) {
      return node.textContent
    },

    addCommands() {
      return {
        setRuby:
          (reading) =>
          ({ state, tr, dispatch, editor }) => {
            const clean = reading.trim()
            const existing = rubyAt(state.doc, state.selection.from)
            if (existing) {
              if (dispatch)
                tr.setNodeMarkup(existing.pos, undefined, {
                  ...existing.node.attrs,
                  reading: clean
                })
              return true
            }
            const text = selectedText(editor)
            if (!text) return false
            if (dispatch) {
              const { from, to } = state.selection
              const node = this.type.create({ reading: clean }, state.schema.text(text))
              tr.replaceRangeWith(from, to, node)
              tr.setSelection(TextSelection.create(tr.doc, from + node.nodeSize))
            }
            return true
          },
        setRubySegments:
          (segments) =>
          ({ state, tr, dispatch, editor }) => {
            const text = selectedText(editor)
            // The segments must spell the selection; otherwise nothing is guessed.
            if (!text || segments.map((s) => s.text).join('') !== text) return false
            if (!segments.some((s) => s.reading?.trim())) return false
            if (dispatch) {
              const { from, to } = state.selection
              const nodes = segments.map((segment) =>
                segment.reading?.trim()
                  ? this.type.create(
                      { reading: segment.reading.trim() },
                      state.schema.text(segment.text)
                    )
                  : state.schema.text(segment.text)
              )
              tr.replaceWith(from, to, nodes)
              const end = from + nodes.reduce((size, node) => size + node.nodeSize, 0)
              tr.setSelection(TextSelection.create(tr.doc, end))
            }
            return true
          },
        unsetRuby:
          () =>
          ({ state, tr, dispatch }) => {
            const existing = rubyAt(state.doc, state.selection.from)
            if (!existing) return false
            if (dispatch) {
              tr.replaceWith(
                existing.pos,
                existing.pos + existing.node.nodeSize,
                existing.node.content
              )
            }
            return true
          },
        editRuby:
          () =>
          ({ editor }) => {
            openRubyPanel(editor, host)
            return true
          }
      }
    },

    addKeyboardShortcuts() {
      return { [tiptapShortcut('ruby')]: () => this.editor.commands.editRuby() }
    },

    addProseMirrorPlugins() {
      return [rubyMarksInside()]
    },

    addNodeView() {
      return ({ node, editor }) => new RubyView(node, editor, host)
    },

    onDestroy() {
      closePanel()
    }
  })
}

/**
 * Marks belong to the base text, not the ruby: ProseMirror marks an inline node as a whole when a range covers it, and
 * the mark's element would then wrap the reading too (a bold, underlined or coloured reading). Housekeeping, so it
 * rides with the edit that marked it (no undo step of its own).
 */
function rubyMarksInside(): Plugin {
  return new Plugin({
    key: new PluginKey('rubyMarksInside'),
    appendTransaction: (transactions, _old, state) => {
      if (!transactions.some((tr) => tr.docChanged)) return null
      const tr = state.tr
      state.doc.descendants((node, pos) => {
        if (node.type.name !== 'ruby') return true
        for (const mark of node.marks) {
          tr.removeNodeMark(tr.mapping.map(pos), mark)
          if (node.content.size > 0) tr.addMark(pos + 1, pos + node.nodeSize - 1, mark)
        }
        return false
      })
      return tr.docChanged ? tr : null
    }
  })
}

class RubyView implements NodeView {
  dom: HTMLElement
  contentDOM: HTMLElement
  private rt: HTMLElement
  constructor(
    private node: PMNode,
    editor: Editor,
    host: RubyHost | null
  ) {
    this.dom = document.createElement('ruby')
    this.dom.className = 'hk-ruby'
    this.contentDOM = document.createElement('rb')
    this.rt = document.createElement('rt')
    this.rt.contentEditable = 'false'
    this.rt.textContent = node.attrs.reading as string
    this.dom.append(this.contentDOM, this.rt)
    // Clicking the reading edits it.
    this.rt.addEventListener('mousedown', (event) => {
      event.preventDefault()
      const pos = editor.view.posAtDOM(this.contentDOM, 0)
      editor.commands.setTextSelection(pos)
      openRubyPanel(editor, host)
    })
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    this.node = node
    if (this.rt.textContent !== node.attrs.reading)
      this.rt.textContent = node.attrs.reading as string
    return true
  }

  stopEvent(event: Event) {
    return this.rt.contains(event.target as globalThis.Node)
  }

  ignoreMutation(mutation: MutationRecord | { type: 'selection'; target: globalThis.Node }) {
    return this.rt.contains(mutation.target)
  }
}

/**
 * The reading panel under the selection (or the ruby at the caret). For a new ruby the host's suggestion
 * arrives a moment later and fills the fields: one per kanji run, or one for the whole phrase.
 */
export function openRubyPanel(editor: Editor, host: RubyHost | null): void {
  closePanel()
  const { state } = editor
  const existing = rubyAt(state.doc, state.selection.from)
  const base = existing ? existing.node.textContent : (selectedText(editor) ?? '')
  if (!base.trim()) return
  const finish = () => {
    closePanel()
    if (!editor.isDestroyed) editor.commands.focus()
  }
  // Escape or a press outside cancels (the layers' bus).
  const layer = new FloatingLayer(
    'hk-ruby-panel w-(--layout-panel-ruby) max-w-(--layout-viewport-max) p-2',
    {
      onDismiss: finish
    }
  )
  // What the panel acts on — the ruby, or the selected text — followed through edits meanwhile (a remote
  // reload): the commands run on it where it is then, and the panel closes when it is gone.
  const gone = () => closePanel()
  const ruby = existing ? followNode(editor, existing.pos, gone) : null
  const start = existing ? null : followPosition(editor, state.selection.from, gone)
  const end = existing ? null : followPosition(editor, state.selection.to, gone)
  openPanel = {
    layer,
    stop: () => [ruby, start, end].forEach((f) => f?.stop())
  }
  const anchorPos = () => (ruby ? ruby.current?.pos : start?.current) ?? 0
  const anchor = () => {
    const dom = editor.view.nodeDOM(anchorPos())
    if (dom instanceof HTMLElement) return dom.getBoundingClientRect()
    const coords = editor.view.coordsAtPos(anchorPos())
    return new DOMRect(coords.left, coords.top, 1, coords.bottom - coords.top)
  }
  /** Puts the selection back on what the panel was opened for; false when it is gone. */
  const reselect = (): boolean => {
    const range = ruby
      ? ruby.current && { from: ruby.current.pos + 1, to: ruby.current.pos + 1 }
      : typeof start?.current === 'number' &&
        typeof end?.current === 'number' && { from: start.current, to: end.current }
    if (!range) return false
    openPanel?.stop()
    editor.commands.setTextSelection(range)
    return true
  }
  const done = (reading: string) => {
    if (reselect()) {
      if (reading.trim()) editor.commands.setRuby(reading)
      else if (existing) editor.commands.unsetRuby()
    }
    finish()
  }
  const doneSegments = (segments: RubySegment[]) => {
    if (reselect() && !editor.commands.setRubySegments(segments))
      editor.commands.setRuby(wholeReading(segments))
    finish()
  }
  const render = (segments: RubySegment[] | null, suggesting: boolean) =>
    renderRubyPanel(
      layer,
      {
        base,
        initial: (existing?.node.attrs.reading as string) ?? '',
        segments,
        suggesting,
        canRemove: existing !== null,
        onDone: done,
        onDoneSegments: doneSegments,
        onRemove: () => done('')
      },
      anchor
    )
  const wantsSuggestion = host !== null && !existing
  render(null, wantsSuggestion)
  if (wantsSuggestion) {
    // The fields fill in once the reading arrives, unless the panel closed (or was replaced) meanwhile.
    host
      .suggestReading(base)
      .then((segments) => {
        if (openPanel?.layer === layer) render(segments, false)
      })
      .catch(() => {
        if (openPanel?.layer === layer) render(null, false)
      })
  }
}
