import { mergeAttributes, Node, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import type { NodeView } from '@tiptap/pm/view'
import { createRoot, type Root } from 'react-dom/client'

import { CalloutIcon } from '../ui/CalloutIcon'
import { IconProvider } from '../ui/icons'
import { PALETTE, type PaletteColor } from './colors'

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    callout: {
      /** Wraps the current block(s) in a callout. */
      setCallout: (attrs?: { icon?: string; color?: PaletteColor | null }) => ReturnType
      /** Lifts the content out of the callout. */
      unsetCallout: () => ReturnType
    }
  }
}

export const DEFAULT_CALLOUT_ICON = '💡'

const isPaletteColor = (value: unknown): value is PaletteColor =>
  typeof value === 'string' && (PALETTE as readonly string[]).includes(value)

/**
 * Callout: an emoji beside a block of content on a soft background (Notion). The color is a palette name
 * (wash-* tokens; null is the default gray).
 */
export const Callout = Node.create({
  name: 'callout',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      icon: {
        default: DEFAULT_CALLOUT_ICON,
        parseHTML: (el) => el.getAttribute('data-icon') || DEFAULT_CALLOUT_ICON,
        renderHTML: (attrs) => ({ 'data-icon': attrs.icon })
      },
      color: {
        default: null,
        parseHTML: (el) => {
          const value = el.getAttribute('data-bg-color')
          return isPaletteColor(value) ? value : null
        },
        renderHTML: (attrs) => (isPaletteColor(attrs.color) ? { 'data-bg-color': attrs.color } : {})
      }
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="callout"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'callout' }), 0]
  },

  addCommands() {
    return {
      setCallout:
        (attrs) =>
        ({ commands }) =>
          commands.wrapIn(this.name, attrs),
      unsetCallout:
        () =>
        ({ commands }) =>
          commands.lift(this.name)
    }
  },

  addKeyboardShortcuts() {
    return {
      // Backspace at the very start of an empty callout's first block unwraps it.
      Backspace: ({ editor }) => {
        const { $from, empty } = editor.state.selection
        if (!empty || $from.parentOffset !== 0) return false
        const callout = $from.node(-1)
        if (callout?.type.name !== this.name || $from.index(-1) !== 0) return false
        return editor.commands.lift(this.name)
      }
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) =>
      new CalloutView(node, editor, getPos as () => number | undefined)
  }
})

class CalloutView implements NodeView {
  dom: HTMLElement
  contentDOM: HTMLElement
  private icon: HTMLElement
  private root: Root
  private node: PMNode

  constructor(
    node: PMNode,
    private readonly editor: Editor,
    private readonly getPos: () => number | undefined
  ) {
    this.node = node
    this.dom = document.createElement('div')
    this.dom.dataset.type = 'callout'
    this.dom.className = 'hk-callout'
    this.icon = document.createElement('div')
    this.icon.contentEditable = 'false'
    this.icon.className = 'hk-callout-icon'
    this.contentDOM = document.createElement('div')
    this.contentDOM.className = 'hk-callout-content'
    this.dom.append(this.icon, this.contentDOM)
    this.root = createRoot(this.icon)
    this.render()
  }

  private render() {
    const color = this.node.attrs.color as PaletteColor | null
    if (color) this.dom.dataset.bgColor = color
    else delete this.dom.dataset.bgColor
    this.root.render(
      <IconProvider>
        <CalloutIcon
          icon={this.node.attrs.icon as string}
          color={color}
          editable={this.editor.isEditable}
          onIcon={(icon) => this.setAttrs({ icon })}
          onColor={(next) => this.setAttrs({ color: next })}
        />
      </IconProvider>
    )
  }

  private setAttrs(attrs: Record<string, unknown>) {
    const pos = this.getPos()
    if (pos === undefined) return
    this.editor
      .chain()
      .command(({ tr }) => {
        tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, ...attrs })
        return true
      })
      .run()
  }

  update(node: PMNode) {
    if (node.type !== this.node.type) return false
    const changed =
      node.attrs.icon !== this.node.attrs.icon || node.attrs.color !== this.node.attrs.color
    this.node = node
    if (changed) this.render()
    return true
  }

  stopEvent(event: Event) {
    return this.icon.contains(event.target as globalThis.Node)
  }

  ignoreMutation(mutation: MutationRecord | { type: 'selection'; target: globalThis.Node }) {
    return this.icon.contains(mutation.target)
  }

  destroy() {
    const root = this.root
    queueMicrotask(() => root.unmount())
  }
}
