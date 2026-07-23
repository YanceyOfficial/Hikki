import type { BlockNoteEditor } from '@blocknote/core'
import { CommentsExtension } from '@blocknote/core/comments'
import type { ThreadData } from '@blocknote/core/comments'
import {
  Thread,
  getReferenceText,
  useBlockNoteEditor,
  useExtensionState,
  useThreads
} from '@blocknote/react'
import { MessageSquare } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import { cn } from '#lib/utils'

/**
 * Mitigates a structural BlockNote limitation (confirmed via BlockNote's own
 * GitHub issue #1701): the comment mark/highlight is a TipTap mark, not part
 * of the `Block[]` JSON model `editor.document` serializes, so it's never
 * persisted. `VaultThreadStore` still round-trips `doc.threads` correctly
 * (see vault-thread-store.ts) - the *thread data* survives a reload - but
 * without the mark there's nothing left in the document body to click: after
 * a reload, existing comment threads have no highlight, no marker, nothing,
 * even though `doc.threads` still holds them. `useExtensionState`'s
 * `threadPositions` (a `Map<threadId, {from, to}>` - see
 * `@blocknote/core`'s `comments/extension.ts`) has no entry for such a
 * thread, which is how orphaning is detected below.
 *
 * Task 19 first shipped this as a single aggregate badge (chat icon + total
 * count) opening a popover listing every thread via BlockNote's own
 * `ThreadsSidebar`. Live user testing against a real Notion screenshot
 * pushed back: Notion doesn't aggregate every comment into one button - each
 * thread gets its own small marker, positioned near where it actually is in
 * the document. Task 20 (this version) replaces the aggregate badge with one
 * marker **per thread**, each independently positioned and independently
 * clickable. Note what's deliberately still NOT here (both explicitly
 * deferred to Task 21): proximity clustering of nearby threads into a single
 * badge, and always-expanded (no-click) rendering on wide windows - this is
 * scoped purely to fixing *positioning*.
 *
 * Positioning: for a thread WITH a position, `threadPositions.get(id).from`
 * is a ProseMirror document position - `editor.prosemirrorView
 * ?.coordsAtPos(pos)` (a real method on `prosemirror-view`'s `EditorView`,
 * reachable through `BlockNoteEditor`'s own public `prosemirrorView` getter
 * with no new import needed - confirmed via `@blocknote/core`'s
 * `BlockNoteEditor.ts` and `prosemirror-view`'s own `.d.ts`; this project
 * can't import `@tiptap/core` or `prosemirror-view` directly since neither is
 * a hoisted top-level dependency under this repo's strict pnpm layout, which
 * is also why this doesn't reuse `@blocknote/react`'s own
 * `PositionPopover`/`posToDOMRect` internals) returns `{top, bottom, left,
 * right}` in viewport-relative pixels - exactly what a `fixed`-positioned
 * marker needs. Recomputed on scroll/resize, following the same pattern as
 * this codebase's other DOM-position-tracking overlays
 * (`code-block-copy-overlay.tsx`, `heading-anchor-overlay.tsx`): this app's
 * content scrolls via its own nested `overflow-y-auto` element (`#lib`
 * `page-content`), not `window`, so the `scroll` listener is attached to
 * `window` with the capture-phase flag (scroll events don't bubble, but a
 * capture-phase listener still observes them on any descendant scroll
 * container). A `ResizeObserver` on `editor.domElement` additionally catches
 * layout shifts that aren't accompanied by a scroll/resize event or a
 * `threadPositions` change (e.g. an async image finishing layout above an
 * anchor).
 *
 * For an orphaned thread (no entry in `threadPositions` - the #1701 case
 * above), there's no meaningful document position left to recover. Rather
 * than drop it from the UI, it still gets its own marker - just stacked at a
 * fixed fallback spot (top of the right margin) instead of tracking real
 * content. `getReferenceText`/`orphaned` (from `@blocknote/react`, the exact
 * helper and flag BlockNote's own `ThreadsSidebar` uses internally - see
 * `node_modules/@blocknote/react/src/components/Comments/ThreadsSidebar.tsx`)
 * drive `Thread`'s header text and `bn-thread-orphaned` styling so an
 * orphaned thread still reads as "content deleted" rather than looking like
 * an ordinary comment.
 *
 * Each marker renders `<Thread thread={...} referenceText={...}
 * orphaned={...} />` directly (also a genuine public `@blocknote/react`
 * export - `node_modules/@blocknote/react/src/index.ts` re-exports it from
 * `./components/Comments/Thread.js`) rather than the full `<ThreadsSidebar
 * filter="all" sort="position" />` list, since a single marker's popover
 * must show only that marker's own thread, not every thread in the document.
 *
 * Still mounted as a child of `<BlockNoteView>` in editor.tsx (not
 * document-page.tsx) for the same reason as before: `useThreads`/
 * `useExtensionState`/`Thread` read the editor and the shadcn comment-card
 * components off `BlockNoteContext`/`ComponentsContext` - both are only
 * provided within `BlockNoteView`'s own subtree. Each marker still paints via
 * `ReactDOM.createPortal` into `portalTarget` - document-page.tsx's
 * `comments-anchor` div - so its DOM output can live outside
 * `BlockNoteView`'s own tree (each marker positions itself independently via
 * its own inline `fixed` `top`, so - unlike Task 19's single anchored badge -
 * the anchor div's own position no longer matters; it's now just a plain
 * portal mount point, see document-page.tsx). React context still flows
 * through the component tree the portal was created from, not through the
 * DOM, so this keeps working even though the portaled output ends up
 * physically outside `BlockNoteView`'s own DOM subtree.
 *
 * Renders nothing at all when there are no threads (`threads.size === 0`),
 * so no marker ever occupies screen space it has nothing to show for.
 */
interface CommentThreadsSidebarProps {
  portalTarget: HTMLElement | null
}

// Keeps every marker clear of the titlebar (~56px - see
// table-of-contents.tsx's `SCROLL_OFFSET`) above, and the table-of-contents
// floating toggle (`right-6 bottom-24`, `icon-lg` = 36px tall -
// table-of-contents.tsx) below, regardless of scroll position. A
// max-clamped marker's bottom edge sits at
// `innerHeight - MARKER_BOTTOM_MARGIN + <marker height, ~28px for
// size="sm">`; the TOC toggle's own top edge sits at
// `innerHeight - bottom-24(96px) - 36px = innerHeight - 132px` - so this
// needs to clear `132 - 28 = 104px` with room to spare, not just barely
// touch it (160 leaves an exact zero-pixel gap, found live during review).
const MARKER_TOP_MIN = 64
const MARKER_BOTTOM_MARGIN = 176
// Vertical spacing between stacked orphaned markers (no real document
// position to place them at - see the doc comment above).
const ORPHANED_MARKER_GAP = 44

export function CommentThreadsSidebar({
  portalTarget
}: CommentThreadsSidebarProps) {
  const editor = useBlockNoteEditor<any, any, any>()
  const threads = useThreads()
  const { threadPositions } = useExtensionState(CommentsExtension)
  const markerTops = useMarkerTops(editor, threadPositions)

  if (threads.size === 0) {
    return null
  }

  let orphanedIndex = 0
  const markers = Array.from(threads.values()).map((thread) => {
    const threadPosition = threadPositions.get(thread.id)
    const rawTop = markerTops.get(thread.id)
    const top =
      rawTop === undefined
        ? MARKER_TOP_MIN + orphanedIndex++ * ORPHANED_MARKER_GAP
        : clampTop(rawTop)

    return (
      <CommentMarker
        key={thread.id}
        editor={editor}
        thread={thread}
        threadPosition={threadPosition}
        top={top}
      />
    )
  })

  return portalTarget ? createPortal(markers, portalTarget) : markers
}

function clampTop(top: number): number {
  const max = Math.max(
    MARKER_TOP_MIN,
    window.innerHeight - MARKER_BOTTOM_MARGIN
  )
  return Math.min(Math.max(top, MARKER_TOP_MIN), max)
}

/**
 * Computes each positioned thread's current viewport-relative `top` (see the
 * component doc comment above for the full `coordsAtPos` rationale), keyed by
 * thread id. Orphaned threads (no entry in `threadPositions`) simply have no
 * entry in the returned map - the caller falls back to a stacked position for
 * those.
 *
 * `tick` exists purely to force a recompute on scroll/resize/layout-shift:
 * `coordsAtPos` reads live DOM layout, not React state, so there's nothing to
 * put directly in a dependency array for "the window scrolled" - bumping a
 * counter on each such event and depending on it is the same trick
 * `code-block-copy-overlay.tsx` uses for the same reason.
 */
function useMarkerTops(
  editor: BlockNoteEditor<any, any, any>,
  threadPositions: Map<string, { from: number; to: number }>
) {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const recompute = () => setTick((t) => t + 1)
    // `editor.prosemirrorView` may not be attached yet on this component's
    // very first render (it mounts as a child of `BlockNoteView`, whose
    // ProseMirror view is created during the same commit) - re-running once
    // after mount picks up the final layout instead of leaving positions
    // stuck at whatever briefly existed at first paint.
    recompute()

    const resizeObserver = new ResizeObserver(recompute)
    if (editor.domElement) {
      resizeObserver.observe(editor.domElement)
    }

    window.addEventListener('resize', recompute)
    window.addEventListener('scroll', recompute, true)

    return () => {
      resizeObserver.disconnect()
      window.removeEventListener('resize', recompute)
      window.removeEventListener('scroll', recompute, true)
    }
  }, [editor])

  return useMemo(() => {
    const tops = new Map<string, number>()
    for (const [threadId, position] of threadPositions) {
      const coords = editor.prosemirrorView?.coordsAtPos(position.from)
      if (coords) {
        tops.set(threadId, coords.top)
      }
    }
    return tops
  }, [editor, threadPositions, tick])
}

function CommentMarker({
  editor,
  thread,
  threadPosition,
  top
}: {
  editor: BlockNoteEditor<any, any, any>
  thread: ThreadData
  threadPosition: { from: number; to: number } | undefined
  top: number
}) {
  const orphaned = !threadPosition

  return (
    <Popover>
      <PopoverTrigger
        render={
          <Button
            variant="secondary"
            size="sm"
            className={cn(
              'fixed right-6 z-40 gap-1 rounded-full shadow-md',
              orphaned && 'opacity-70'
            )}
            style={{ top }}
            data-testid={`comment-marker-${thread.id}`}
            data-thread-id={thread.id}
            data-orphaned={orphaned || undefined}
          />
        }
      >
        <MessageSquare className="size-3.5" />
        {thread.comments.length}
      </PopoverTrigger>
      <PopoverContent
        side="left"
        align="start"
        sideOffset={12}
        data-testid={`comment-marker-popover-${thread.id}`}
        className="flex max-h-[70vh] w-80 flex-col overflow-y-auto"
      >
        <Thread
          thread={thread}
          referenceText={getReferenceText(editor, threadPosition)}
          orphaned={orphaned}
        />
      </PopoverContent>
    </Popover>
  )
}
