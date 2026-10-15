import { Extension, type Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'
import { Plugin, PluginKey, Selection, TextSelection } from '@tiptap/pm/state'
import type { EditorView } from '@tiptap/pm/view'

import { isSafeHref } from '../core/links'
import { setBlockHighlight } from './block-highlight'
import { openTogglesAround } from './toggle'

/** A page as the sidebar knows it, for naming links (`window.hikki.setPages`). */
export type PageIndexEntry = { id: string; title: string; icon: string | null }
export type PageLinkTarget = { pageId: string; blockId: string | null }

/** What page links need from the host (the bridge). */
export type PageLinksHost = {
  pages: () => PageIndexEntry[]
  currentPageId: () => string | null
  untitled: () => string
  /** A page link was clicked: open that page (and scroll to the block). */
  open: (target: PageLinkTarget) => void
  /** Any other link: the system opens it. */
  openExternal: (href: string) => void
}

const PAGE_LINK = /^hikki:\/\/page\/([A-Za-z0-9_-]+)(?:#([A-Za-z0-9_-]+))?\/?$/u

export function parsePageLink(href: string): PageLinkTarget | null {
  const match = PAGE_LINK.exec(href.trim())
  return match ? { pageId: match[1], blockId: match[2] ?? null } : null
}

export function pageLinkHref(pageId: string, blockId?: string | null): string {
  return `hikki://page/${pageId}${blockId ? `#${blockId}` : ''}`
}

/** How much of a block's text a link shows. */
const MAX_LABEL = 80

/** A block's text as a link label (headings whole, long paragraphs cut), or null for blocks without text. */
export function blockLabel(node: PMNode): string | null {
  const text = node.textContent.replace(/\s+/gu, ' ').trim()
  if (!text) return null
  return text.length > MAX_LABEL ? `${text.slice(0, MAX_LABEL - 1)}…` : text
}

/** The node with this block id and where it starts, or null when the page has none. */
export function findBlockById(doc: PMNode, id: string): { node: PMNode; pos: number } | null {
  let found: { node: PMNode; pos: number } | null = null
  doc.descendants((node, pos) => {
    if (found) return false
    if (node.attrs.id === id) found = { node, pos }
    return !found
  })
  return found
}

/**
 * Text for a link to `target`: the block's own text when the block is in this document, otherwise the page's
 * title (from the index), otherwise "Untitled". A block in another page reads as that page: its text isn't
 * known here, and the link still lands on the block.
 */
export function linkLabel(editor: Editor, target: PageLinkTarget, host: PageLinksHost): string {
  if (target.blockId && target.pageId === host.currentPageId()) {
    const block = findBlockById(editor.state.doc, target.blockId)?.node ?? null
    const label = block && blockLabel(block)
    if (label) return label
  }
  const page = host.pages().find((p) => p.id === target.pageId)
  const title = page?.title.trim()
  return title ? `${page?.icon ? `${page.icon} ` : ''}${title}` : host.untitled()
}

/** Puts a link on the clipboard as a ready hyperlink (HTML) and as its URL (plain text). */
export async function copyLink(href: string, label: string): Promise<void> {
  const html = `<a href="${escapeAttribute(href)}">${escapeText(label)}</a>`
  const clipboard = navigator.clipboard
  if (clipboard && typeof ClipboardItem !== 'undefined' && clipboard.write) {
    try {
      await clipboard.write([
        new ClipboardItem({
          'text/plain': new Blob([href], { type: 'text/plain' }),
          'text/html': new Blob([html], { type: 'text/html' })
        })
      ])
      return
    } catch {
      // Fall through to plain text.
    }
  }
  await clipboard?.writeText(href)
}

const escapeText = (s: string) =>
  s.replace(/&/gu, '&amp;').replace(/</gu, '&lt;').replace(/>/gu, '&gt;')
const escapeAttribute = (s: string) => escapeText(s).replace(/"/gu, '&quot;')

export const PageLinksKey = new PluginKey('pageLinks')

declare module '@tiptap/core' {
  interface Commands<ReturnType> {
    pageLinks: {
      /** Inserts a link to `target` at the caret, labelled like a pasted one. */
      insertPageLink: (target: PageLinkTarget) => ReturnType
      /** Scrolls to the block with this id and tints it for a moment (arriving by link). */
      scrollToBlock: (blockId: string) => ReturnType
      /** Scrolls to a search's words — in its block, else their first place — tints the block, selects them. */
      revealText: (terms: string[], blockId?: string | null) => ReturnType
    }
  }
}

/** How long an arrived-at block stays tinted. */
const ARRIVAL_TINT_MS = 1400

/** The block arrived at (by a link, a search result) is tinted for a moment. */
function tintArrival(editor: Editor, range: { from: number; to: number }): void {
  setBlockHighlight(editor.view, { menu: range })
  setTimeout(() => {
    if (!editor.isDestroyed) setBlockHighlight(editor.view, { menu: null })
  }, ARRIVAL_TINT_MS)
}

/**
 * Search folds case and accents away as Foundation's `.caseInsensitive, .diacriticInsensitive` does
 * (`SearchQuery.fold`): "cafe" finds Café and "strasse" Straße, but kana keep their voicing marks (ので is not のて)
 * and Hangul stays composed.
 */
function fold(text: string): string {
  return text
    .toUpperCase()
    .toLowerCase()
    .normalize('NFD')
    .replace(/(?![\u3099\u309A])\p{M}/gu, '')
    .normalize('NFC')
}

/** Where a search's (already folded) terms first occur in one textblock (at `pos`), as a document range. */
function matchInBlock(
  node: PMNode,
  pos: number,
  terms: string[]
): { from: number; to: number } | null {
  // The block's text folded, with the document position each folded unit came from.
  let text = ''
  const at: number[] = []
  node.forEach((child, offset) => {
    if (!child.isText) return
    let index = 0
    for (const char of child.text!) {
      const folded = fold(char)
      text += folded
      for (let i = 0; i < folded.length; i++) at.push(pos + 1 + offset + index)
      index += char.length
    }
  })
  let best: { start: number; end: number } | null = null
  for (const term of terms) {
    const start = term ? text.indexOf(term) : -1
    if (start >= 0 && (!best || start < best.start)) best = { start, end: start + term.length }
  }
  return best && { from: at[best.start], to: at[best.end - 1] + 1 }
}

/**
 * Where a search's (already folded) terms occur, as a document range, or null: in the block the search named
 * (`SearchHit.blockId`) when it is in the page — null when its words aren't in it any more — otherwise the first
 * place in the body (an index older than the page). Text across marks counts as one run.
 */
export function findTextMatch(
  doc: PMNode,
  terms: string[],
  blockId: string | null = null
): { from: number; to: number } | null {
  const block = blockId ? findBlockById(doc, blockId) : null
  if (block) return block.node.isTextblock ? matchInBlock(block.node, block.pos, terms) : null
  let found: { from: number; to: number } | null = null
  doc.descendants((node, pos) => {
    if (found) return false
    if (!node.isTextblock) return true
    found = matchInBlock(node, pos, terms)
    return false
  })
  return found
}

/** The page link in a drag's payload (a sidebar row carries its URL as a URI list and as text), or null. */
export function droppedPageLink(data: DataTransfer | null): PageLinkTarget | null {
  if (!data) return null
  // A URI list may hold several lines and `#` comments; the first URL is the one.
  const uri = data
    .getData('text/uri-list')
    .split('\n')
    .find((line) => line && !line.startsWith('#'))
  return parsePageLink(uri ?? data.getData('text/plain'))
}

/**
 * Page links (`hikki://page/<id>#<block>`): pasting one as plain text inserts a labelled hyperlink
 * (Notion's "Copy link to block" → paste), and so does dropping one (a sidebar page dragged into the page);
 * clicking a link opens the page, or hands other links to the system. Tiptap's own `linkOnPaste` still
 * links a non-empty selection with the pasted URL.
 */
export function PageLinks(host: PageLinksHost) {
  return Extension.create({
    name: 'pageLinks',

    addCommands() {
      return {
        insertPageLink:
          (target) =>
          ({ editor, chain }) => {
            const href = pageLinkHref(target.pageId, target.blockId)
            const label = linkLabel(editor, target, host)
            return chain()
              .insertContent({
                type: 'text',
                text: label,
                marks: [{ type: 'link', attrs: { href } }]
              })
              .unsetMark('link')
              .run()
          },
        // Both arrivals open toggles and tint the block (each a dispatch of its own), so they dispatch from the
        // view's current state and keep Tiptap from dispatching the command's transaction, stale by then.
        scrollToBlock:
          (blockId) =>
          ({ editor, view, tr }) => {
            const block = findBlockById(editor.state.doc, blockId)
            if (!block) return false
            tr.setMeta('preventDispatch', true)
            const { node, pos } = block
            openTogglesAround(editor, pos)
            const dom = view.nodeDOM(pos)
            if (dom instanceof HTMLElement)
              dom.scrollIntoView({ behavior: 'smooth', block: 'center' })
            tintArrival(editor, { from: pos, to: pos + node.nodeSize })
            if (node.isTextblock) {
              view.dispatch(
                view.state.tr.setSelection(TextSelection.create(view.state.doc, pos + 1))
              )
            }
            return true
          },
        revealText:
          (terms, blockId = null) =>
          ({ editor, view, tr }) => {
            const match = findTextMatch(editor.state.doc, terms, blockId)
            if (!match) return false
            tr.setMeta('preventDispatch', true)
            openTogglesAround(editor, match.from)
            const $from = editor.state.doc.resolve(match.from)
            const coords = view.coordsAtPos(match.from)
            window.scrollTo({
              top: Math.max(0, window.scrollY + coords.top - window.innerHeight / 3),
              behavior: 'smooth'
            })
            tintArrival(editor, { from: $from.before(), to: $from.after() })
            view.dispatch(
              view.state.tr.setSelection(TextSelection.create(view.state.doc, match.from, match.to))
            )
            return true
          }
      }
    },

    addProseMirrorPlugins() {
      const editor = this.editor
      return [
        new Plugin({
          key: PageLinksKey,
          props: {
            handlePaste(view, event) {
              const text = event.clipboardData?.getData('text/plain') ?? ''
              const html = event.clipboardData?.getData('text/html') ?? ''
              const target = parsePageLink(text)
              // Our own copies carry a ready <a>: the HTML paste path handles those.
              if (!target || /<a\s/iu.test(html) || !view.state.selection.empty) return false
              return editor.commands.insertPageLink(target)
            },
            handleDrop(view, event, _slice, moved) {
              // Blocks moved within the page are the block controls' business, not a link.
              if (moved || !view.editable) return false
              const target = droppedPageLink(event.dataTransfer)
              if (!target) return false
              const hit = view.posAtCoords({ left: event.clientX, top: event.clientY })
              if (!hit) return false
              // The nearest place text can go (a drop on a block's edge or on an image lands beside it).
              const $pos = view.state.doc.resolve(hit.pos)
              const selection =
                Selection.findFrom($pos, 1, true) ?? Selection.findFrom($pos, -1, true)
              if (!selection) return false
              event.preventDefault()
              view.dispatch(view.state.tr.setSelection(selection))
              return editor.chain().focus().insertPageLink(target).run()
            },
            handleClick(view: EditorView, _pos, event) {
              if (event.button !== 0 || event.shiftKey || event.altKey || event.ctrlKey)
                return false
              const anchor = (event.target as HTMLElement).closest?.('a[href]')
              if (!(anchor instanceof HTMLAnchorElement) || !view.dom.contains(anchor)) return false
              const href = anchor.getAttribute('href') ?? ''
              const target = parsePageLink(href)
              if (target) host.open(target)
              else if (isSafeHref(href)) host.openExternal(href)
              else return false
              event.preventDefault()
              return true
            }
          }
        })
      ]
    }
  })
}
