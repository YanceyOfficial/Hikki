import { ListTree } from 'lucide-react'
import { useRef } from 'react'
import { FluidToc, type TocItem } from 'react-fluid-toc'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'

/**
 * BlockNote's `heading` blocks are plain `div`s under the hood (confirmed via
 * its compiled CSS - `[data-content-type=heading]{--level:3em;...}`, no real
 * `<h1>`-`<h6>` element), so `react-fluid-toc`'s DOM-scanning
 * `extractHeadings` helper (which looks for real `<h2>`/`<h3>` tags) finds
 * nothing here. This instead derives the outline directly from a BlockNote
 * `blocks` array (walking `children` too, since headings can live inside
 * container blocks like toggle list items) - the matching real DOM elements
 * `FluidToc`'s `IntersectionObserver` active-heading detection needs (found
 * via `document.getElementById`) are rendered separately, in
 * heading-anchor-overlay.tsx (see its doc comment for why that's an overlay
 * of real elements rather than an `id` set directly on BlockNote's own
 * heading DOM node).
 *
 * `onItemClick` below overrides `FluidToc`'s default click behaviour for a
 * second, unrelated reason: this app's main content region scrolls via its
 * own nested `overflow-y-auto` element (see `AppShell`), not `window` - so
 * the default handler's `window.scrollTo(...)` is a silent no-op here
 * (confirmed live: clicking a TOC entry left the page exactly where it was).
 * `Element.scrollIntoView()` walks up the real scroll-container chain
 * regardless of how many nested scrollable ancestors sit in between, so it
 * works unmodified in both this app's nested-scroll layout and a plain
 * `window`-scrolls-everything page.
 *
 * Rendered as its own small always-available floating badge (Notion-style,
 * per a live design review against a real Notion screenshot), not a
 * permanent in-flow or wide-rail-only column: unlike `CommentThreadsSidebar`,
 * this component only ever needed `blocks` - a plain prop already available
 * in document-page.tsx, no BlockNote context - so it never needed a portal;
 * it owns its own `fixed`-positioned wrapper directly. Stacked in the same
 * bottom-right corner as the comments badge but higher up, so both are
 * simultaneously visible and clickable without overlapping (verified live at
 * the app's 1320px default width).
 */

interface InlineContentNode {
  type?: unknown
  text?: unknown
  content?: unknown
}

interface BlockNode {
  id?: unknown
  type?: unknown
  props?: unknown
  content?: unknown
  children?: unknown
}

function extractText(content: unknown): string {
  if (!Array.isArray(content)) return ''
  return content
    .map((node) => {
      if (!node || typeof node !== 'object') return ''
      const { text, content: nested } = node as InlineContentNode
      if (typeof text === 'string') return text
      // Link inline content nests its own StyledText[] under `content`.
      if (Array.isArray(nested)) return extractText(nested)
      return ''
    })
    .join('')
}

/** Pure so it's independently unit-testable from the `FluidToc` rendering. */
export function extractTocItems(blocks: unknown[]): TocItem[] {
  const items: TocItem[] = []

  const walk = (list: unknown[]) => {
    for (const block of list) {
      if (!block || typeof block !== 'object') continue
      const { id, type, props, content, children } = block as BlockNode

      if (type === 'heading' && typeof id === 'string') {
        const level = (props as { level?: unknown } | undefined)?.level
        const text = extractText(content).trim()
        if (text.length > 0) {
          items.push({
            id,
            text,
            depth: typeof level === 'number' ? level : 1
          })
        }
      }

      if (Array.isArray(children) && children.length > 0) {
        walk(children)
      }
    }
  }

  walk(blocks)
  return items
}

function tocItemsEqual(a: TocItem[], b: TocItem[]): boolean {
  return (
    a.length === b.length &&
    a.every(
      (item, i) =>
        item.id === b[i].id &&
        item.text === b[i].text &&
        item.depth === b[i].depth
    )
  )
}

/**
 * `blocks` is a fresh array/object graph from `editor.document` on every
 * keystroke, anywhere in the document (see document-page.tsx) - not just
 * ones that touch a heading. Recomputing `extractTocItems` on every render is
 * cheap, but returning a brand-new `TocItem[]` reference every time is not
 * free downstream: `FluidToc` keys several of its own effects (scroll-spying,
 * SVG rail geometry) off `items` by reference, and reference churn on every
 * unrelated paragraph edit was empirically confirmed live to cascade into a
 * "Maximum update depth exceeded" loop (its `ResizeObserver`/
 * `IntersectionObserver` effects tearing down and rebuilding, firing their
 * own initial callback, on every single keystroke). This keeps the same
 * array reference across renders whenever the derived heading list is
 * value-equal to last time, so `FluidToc` only sees a new `items` reference
 * when the outline actually changed (a heading added/removed/edited/
 * reordered).
 */
function useStableTocItems(blocks: unknown[]): TocItem[] {
  const items = extractTocItems(blocks)
  const stableRef = useRef(items)
  if (!tocItemsEqual(stableRef.current, items)) {
    stableRef.current = items
  }
  return stableRef.current
}

interface TableOfContentsProps {
  blocks: unknown[]
}

// ~= the titlebar height (see AppShell/useTrafficLightInset) - kept clear of
// both scroll-to-heading and active-heading detection so the target heading
// doesn't land underneath it. Exported so heading-anchor-overlay.tsx's
// invisible anchors can set the matching `scroll-margin-top`, which is what
// actually makes `scrollIntoView` below honor this offset.
export const SCROLL_OFFSET = 56

export function TableOfContents({ blocks }: TableOfContentsProps) {
  const items = useStableTocItems(blocks)

  if (items.length === 0) return null

  return (
    <div className="fixed right-6 bottom-24 z-40">
      <Popover>
        <PopoverTrigger
          render={
            <Button
              variant="secondary"
              size="icon-lg"
              className="rounded-full shadow-md"
              data-testid="toc-toggle"
            />
          }
        >
          <ListTree className="size-4" />
        </PopoverTrigger>
        <PopoverContent
          align="end"
          side="top"
          sideOffset={12}
          data-testid="table-of-contents"
          className="flex max-h-[70vh] w-72 flex-col gap-2 overflow-y-auto"
        >
          <p className="text-muted-foreground text-xs font-medium">
            On this page
          </p>
          <FluidToc
            items={items}
            scrollOffset={SCROLL_OFFSET}
            className="fluid-toc"
            onItemClick={(id, event) => {
              event.preventDefault()
              document
                .getElementById(id)
                ?.scrollIntoView({ behavior: 'smooth', block: 'start' })
            }}
          />
        </PopoverContent>
      </Popover>
    </div>
  )
}
