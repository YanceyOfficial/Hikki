import type { Block, BlockNoteEditor } from '@blocknote/core'
import { type RefObject, useCallback, useEffect, useState } from 'react'

import { SCROLL_OFFSET } from '#components/table-of-contents'

/**
 * `table-of-contents.tsx` (`react-fluid-toc`) needs real DOM elements with a
 * matching `id` - both its default click-to-scroll handler and its
 * `IntersectionObserver`-based active-heading spy look things up via
 * `document.getElementById`. BlockNote's `heading` blocks render as plain
 * `div`s with no real `id` (confirmed via its compiled CSS: no actual
 * `<h1>`-`<h6>` element, and its DOM only carries the block id as `data-id`
 * on `.bn-block-outer`/`.bn-block`, not as an `id` on the heading `div`
 * itself).
 *
 * An earlier version of this tried setting `.id` directly on that rendered
 * heading `div`, inside the editor's own contentEditable subtree. That does
 * not work at all, and isn't just a style nit: ProseMirror's `DOMObserver`
 * watches `attributes: true` across its whole contentEditable subtree, and
 * its `ignoreMutation` default only skips mutations on elements *without* a
 * `contentDOM` (`prosemirror-view`'s `flush`/`registerMutation`) - a
 * heading's content wrapper doesn't qualify, so PM treats our own `.id =`
 * write as unexpected foreign input and immediately redraws that block's
 * DOM to "heal" it (empirically confirmed live: a `MutationObserver` logged
 * a `childList` mutation - the content `div` being replaced - within one
 * animation frame of setting `.id`, and `document.getElementById` for that
 * id was already `null` again 50ms later). Every `onChange` pass would then
 * find the id missing, re-set it, get immediately healed away again - a
 * silent no-op forever, not just a cosmetic bug: since `getElementById`
 * always failed, `FluidToc`'s own click handler's `if (!el) return` branch
 * never reached its `event.preventDefault()`, so clicking a TOC entry fell
 * through to the anchor's native behavior and set `location.hash` directly -
 * which this app's `createHashRouter` also reads as its route, so every TOC
 * click actually *navigated away from the document* into a router 404.
 *
 * This sidesteps ProseMirror entirely, reusing the same proven pattern
 * `CodeBlockCopyOverlay` already established for a structurally identical
 * problem (see that component's own doc comment): render real DOM elements
 * as absolutely-positioned overlay children that are DOM *siblings* of
 * `BlockNoteView`, not descendants of its contentEditable tree - so
 * ProseMirror's `DOMObserver` never sees them, never "heals" them, and they
 * can safely carry the exact `id`s `react-fluid-toc` needs. Each anchor is
 * positioned (via `getBoundingClientRect`, relative to the shared
 * `containerRef` overlay layer editor.tsx already anchors
 * `CodeBlockCopyOverlay` to) to track its real heading's vertical position,
 * recomputed on every editor change plus container/window resize. Unlike
 * `CodeBlockCopyOverlay`, this never needs a `scroll` listener: both the
 * anchor and the heading it tracks live in the same normal document flow
 * and scroll together as one unit with zero extra JS (a `top: Npx` container-
 * relative offset stays correct at any scroll position purely from normal
 * CSS layout), and this only ever needs a `top` offset accurate enough for
 * `IntersectionObserver`/`getBoundingClientRect` checks, not pixel-perfect
 * click-target alignment.
 */
export function useHeadingAnchors(
  containerRef: RefObject<HTMLElement | null>,
  editor: BlockNoteEditor<any, any, any>
): [HeadingAnchorPosition[], () => void] {
  const [anchors, setAnchors] = useState<HeadingAnchorPosition[]>([])

  const recompute = useCallback(() => {
    const container = containerRef.current
    if (!container) return

    const ids: string[] = []
    collectHeadingIds(editor.document as Block[], ids)

    const containerRect = container.getBoundingClientRect()
    const next: HeadingAnchorPosition[] = []
    for (const id of ids) {
      const heading = container.querySelector<HTMLElement>(
        `[data-id="${id}"] [data-content-type="heading"]`
      )
      if (!heading) continue
      const rect = heading.getBoundingClientRect()
      next.push({ id, top: rect.top - containerRect.top })
    }

    setAnchors((prev) => {
      const unchanged =
        prev.length === next.length &&
        prev.every(
          (anchor, i) => anchor.id === next[i].id && anchor.top === next[i].top
        )
      return unchanged ? prev : next
    })
  }, [containerRef, editor])

  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    recompute()

    // A heading moves vertically whenever anything above it changes height
    // (text wrapping, a block added/removed/resized) - all of which change
    // the container's own content-box size, so observing just the container
    // (rather than every individual heading) is enough to catch every case.
    const resizeObserver = new ResizeObserver(recompute)
    resizeObserver.observe(container)
    window.addEventListener('resize', recompute)

    return () => {
      resizeObserver.disconnect()
      window.removeEventListener('resize', recompute)
    }
  }, [containerRef, recompute])

  return [anchors, recompute]
}

export function HeadingAnchors({
  anchors
}: {
  anchors: HeadingAnchorPosition[]
}) {
  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0">
      {anchors.map(({ id, top }) => (
        <span
          key={id}
          id={id}
          // `scrollMarginTop` is what makes table-of-contents.tsx's
          // `scrollIntoView({ block: 'start' })` stop `SCROLL_OFFSET`px short
          // of the true top (clearing the titlebar) - entirely handled by
          // the browser, no manual scroll-position math needed, and it keeps
          // working regardless of which ancestor ends up being the actual
          // scrolling container.
          style={{
            position: 'absolute',
            top,
            left: 0,
            width: 1,
            height: 1,
            scrollMarginTop: SCROLL_OFFSET
          }}
        />
      ))}
    </div>
  )
}

interface HeadingAnchorPosition {
  id: string
  top: number
}

function collectHeadingIds(blocks: Block[], ids: string[]): void {
  for (const block of blocks) {
    if (block.type === 'heading') {
      ids.push(block.id)
    }
    if (Array.isArray(block.children) && block.children.length > 0) {
      collectHeadingIds(block.children as Block[], ids)
    }
  }
}
