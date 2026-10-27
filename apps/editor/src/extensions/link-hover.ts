import { Extension, getMarkRange } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import type { EditorView } from '@tiptap/pm/view'

import { FloatingLayer } from '../components/floating'
import { renderLinkCard } from '../components/link-card'
import { FINE_POINTER, matches } from '../lib/device'
import { parsePageLink, type PageLinksHost } from './page-links'

export const LinkHoverKey = new PluginKey('linkHover')

/** How long the pointer rests on a link before its card shows, and how long it may be off both before the card goes. */
export const LINK_HOVER_DELAY = 350
export const LINK_LEAVE_DELAY = 200

type Open = {
  layer: FloatingLayer
  anchor: HTMLAnchorElement
  range: { from: number; to: number }
  href: string
  editing: boolean
}

/**
 * Notion's link card (ISSUE-241): the pointer resting on a link shows where it goes, with Copy and Edit; Edit turns
 * the card into the link field, with Remove link. Fine pointers only (a touch has no hover); page mentions are
 * chips of their own and show no card. The card goes when the pointer has left both the link and the card, when
 * the page changes under it, or — while editing — on Escape or a press outside.
 */
/** The link under the pointer: a link mark's <a> in the page, never a mention chip. */
function linkAt(view: EditorView, target: EventTarget | null): HTMLAnchorElement | null {
  const anchor = (target as Element | null)?.closest?.('a[href]')
  if (!(anchor instanceof HTMLAnchorElement) || !view.dom.contains(anchor)) return null
  return anchor.closest('.hk-mention') ? null : anchor
}

export function LinkHover(host: PageLinksHost) {
  /** The page's title for a page link (a block's, its page's), else the address. */
  const display = (href: string) => {
    const target = parsePageLink(href)
    if (!target) return href
    const page = host.pages().find((p) => p.id === target.pageId)
    return page?.title.trim() || host.untitled()
  }
  return Extension.create({
    name: 'linkHover',

    addProseMirrorPlugins() {
      const editor = this.editor
      let open: Open | null = null
      let showTimer = 0
      let hideTimer = 0

      const close = () => {
        clearTimeout(showTimer)
        clearTimeout(hideTimer)
        showTimer = 0
        hideTimer = 0
        open?.layer.destroy()
        open = null
      }
      const cancelHide = () => {
        clearTimeout(hideTimer)
        hideTimer = 0
      }
      const scheduleHide = () => {
        if (!open || open.editing || hideTimer) return
        hideTimer = window.setTimeout(() => {
          hideTimer = 0
          close()
        }, LINK_LEAVE_DELAY)
      }
      const draw = () => {
        if (!open) return
        const { layer, anchor, range, href } = open
        renderLinkCard(
          layer,
          {
            href,
            display: display(href),
            editing: open.editing,
            onEdit: () => {
              if (!open) return
              open.editing = true
              cancelHide()
              draw()
            },
            onApply: (next) => {
              editor
                .chain()
                .focus()
                .setTextSelection(range)
                .extendMarkRange('link')
                .setLink({ href: next })
                .run()
              close()
            },
            onRemove: () => {
              editor
                .chain()
                .focus()
                .setTextSelection(range)
                .extendMarkRange('link')
                .unsetLink()
                .run()
              close()
            },
            onCancel: close,
            onEnter: cancelHide,
            onLeave: scheduleHide
          },
          () => anchor.getBoundingClientRect()
        )
      }
      const show = (view: EditorView, anchor: HTMLAnchorElement) => {
        close()
        const pos = view.posAtDOM(anchor, 0)
        const $pos = view.state.doc.resolve(Math.min(pos + 1, view.state.doc.content.size))
        const linkType = view.state.schema.marks.link
        const range = linkType && getMarkRange($pos, linkType)
        if (!range) return
        const href = $pos.marks().find((m) => m.type === linkType)?.attrs.href as string | undefined
        if (!href) return
        const layer = new FloatingLayer('hk-link-card p-(--layout-popover-padding)', {
          onDismiss: () => close()
        })
        open = { layer, anchor, range: { from: range.from, to: range.to }, href, editing: false }
        draw()
      }
      return [
        new Plugin({
          key: LinkHoverKey,
          view: () => ({ destroy: close }),
          props: {
            handleDOMEvents: {
              mouseover: (view, event) => {
                if (!matches(FINE_POINTER) || !view.editable) return false
                const anchor = linkAt(view, event.target)
                if (!anchor) {
                  clearTimeout(showTimer)
                  showTimer = 0
                  return false
                }
                if (open?.anchor === anchor) {
                  cancelHide()
                  return false
                }
                clearTimeout(showTimer)
                showTimer = window.setTimeout(() => {
                  showTimer = 0
                  show(view, anchor)
                }, LINK_HOVER_DELAY)
                return false
              },
              mouseout: (view, event) => {
                const anchor = linkAt(view, event.target)
                if (anchor && (!open || open.anchor !== anchor)) {
                  clearTimeout(showTimer)
                  showTimer = 0
                }
                if (open && anchor === open.anchor) {
                  const to = event.relatedTarget as Node | null
                  if (!to || !open.layer.element.contains(to)) scheduleHide()
                }
                return false
              }
            }
          },
          // The page changing under the card (typing, a reload): the card goes.
          appendTransaction: (transactions) => {
            if (open && transactions.some((tr) => tr.docChanged)) close()
            return null
          }
        })
      ]
    }
  })
}
