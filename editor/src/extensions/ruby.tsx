import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import { TextSelection } from '@tiptap/pm/state'
import type { NodeView } from '@tiptap/pm/view'

import { tiptapShortcut } from '../shortcuts'
import { FloatingLayer } from '../ui/floating'
import { IconProvider } from '../ui/icons'
import { RubyPanel } from '../ui/RubyPanel'

/** Where reading suggestions come from (the native side's tokenizer); optional. */
export type RubyHost = {
  /** A reading (hiragana) for `text`, or null when the host has none. */
  suggestReading: (text: string) => Promise<string | null>
}

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    ruby: {
      /** Gives the selected text (within one line) the reading; inside a ruby, changes its reading. */
      setRuby: (reading: string) => ReturnType
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

let openPanel: FloatingLayer | null = null
const closePanel = () => {
  openPanel?.destroy()
  openPanel = null
}

/**
 * Furigana: 漢字 with its reading above (`<ruby><rb>漢字</rb><rt>かんじ</rt></ruby>`). An inline node whose
 * content is the base text (editable in place); the reading is an attribute, edited in a small panel
 * (click the reading, or ⇧⌘R on a selection).
 */
export function Ruby(host: RubyHost | null = null) {
  return Node.create({
    name: 'ruby',
    group: 'inline',
    inline: true,
    content: 'text*',
    marks: '',
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
          ({ state, tr, dispatch }) => {
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
            const { from, to, $from, $to } = state.selection
            if (from === to || !$from.sameParent($to) || !$from.parent.isTextblock) return false
            const slice = state.doc.slice(from, to)
            let text = ''
            let plain = true
            slice.content.forEach((child) => {
              if (child.isText) text += child.text
              else plain = false
            })
            if (!plain || !text) return false
            if (dispatch) {
              const node = this.type.create({ reading: clean }, state.schema.text(text))
              tr.replaceRangeWith(from, to, node)
              tr.setSelection(TextSelection.create(tr.doc, from + node.nodeSize))
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

    addNodeView() {
      return ({ node, editor }) => new RubyView(node, editor, host)
    },

    onDestroy() {
      closePanel()
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

/** The reading panel under the selection (or the ruby at the caret), prefilled with the host's suggestion. */
export function openRubyPanel(editor: Editor, host: RubyHost | null): void {
  closePanel()
  const { state } = editor
  const existing = rubyAt(state.doc, state.selection.from)
  const base = existing
    ? existing.node.textContent
    : state.doc.textBetween(state.selection.from, state.selection.to, ' ')
  if (!base.trim()) return
  const layer = new FloatingLayer('hk-ruby-panel w-[300px] max-w-[calc(100vw-16px)] p-2')
  openPanel = layer
  const anchorPos = existing ? existing.pos : state.selection.from
  const anchor = () => {
    const dom = editor.view.nodeDOM(anchorPos)
    if (dom instanceof HTMLElement) return dom.getBoundingClientRect()
    const coords = editor.view.coordsAtPos(anchorPos)
    return new DOMRect(coords.left, coords.top, 1, coords.bottom - coords.top)
  }
  const done = (reading: string) => {
    if (reading.trim()) editor.commands.setRuby(reading)
    else if (existing) editor.commands.unsetRuby()
    closePanel()
    editor.commands.focus()
  }
  const cancel = () => {
    closePanel()
    editor.commands.focus()
  }
  const render = (suggestion: string | null, suggesting: boolean) =>
    layer.render(
      <IconProvider>
        <RubyPanel
          base={base}
          initial={(existing?.node.attrs.reading as string) ?? ''}
          suggestion={suggestion}
          suggesting={suggesting}
          canRemove={existing !== null}
          onDone={done}
          onRemove={() => done('')}
          onCancel={cancel}
        />
      </IconProvider>,
      anchor
    )
  const wantsSuggestion = host !== null && !existing
  render(null, wantsSuggestion)
  if (wantsSuggestion) {
    // The field fills in once the reading arrives, unless the panel closed (or was replaced) meanwhile.
    host
      .suggestReading(base)
      .then((suggestion) => {
        if (openPanel === layer) render(suggestion, false)
      })
      .catch(() => {
        if (openPanel === layer) render(null, false)
      })
  }
}
