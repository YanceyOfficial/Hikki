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
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
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
 * `ThreadsSidebar`. Task 20 replaced that with one marker **per thread**,
 * each independently positioned near its real document location. Live user
 * feedback after Task 20 shipped asked for two more things (this task, 21):
 *
 * 1. **Proximity clustering** (narrow/default mode): threads whose computed
 *    `top` values land within `CLUSTER_DISTANCE_THRESHOLD` of each other
 *    render as one combined marker instead of several overlapping ones.
 *    `clusterEntries` below does this via simple chain-linkage - sort by
 *    `top`, walk through, and start a new cluster whenever the gap to the
 *    *previous* (not the cluster's first) entry exceeds the threshold. This
 *    also happens to give orphaned threads (stacked `ORPHANED_MARKER_GAP`,
 *    44px, apart - see below) a single combined badge for free whenever
 *    there's more than one, since 44px is comfortably under the clustering
 *    threshold - verified live that this reads better than a column of
 *    individually-stacked orphaned markers, so no special-casing was added
 *    to keep them separate.
 *
 * 2. **Width-responsive expansion**: on a sufficiently wide window, every
 *    thread renders its own `Thread` card directly and persistently - no
 *    click needed - closer to Notion's own floating-card rail. Two design
 *    questions the task brief left open, resolved as follows:
 *
 *    - **Does clustering still apply in wide mode?** No - `ExpandedCards`
 *      renders one card *per thread*, never merged, because wide mode by
 *      definition has the screen space clustering exists to save; merging
 *      would throw away per-thread granularity exactly when there's room to
 *      show it. Overlaps between naturally-close threads are instead solved
 *      with collision avoidance (below), matching Notion's own wide-rail
 *      behavior more closely than a cluster badge would.
 *    - **Collision avoidance**: `layoutExpandedCards` sorts entries by
 *      natural `top`, walks through in order, and pushes each card down to
 *      `max(naturalTop, previousCard's measured bottom + gap)` whenever its
 *      natural position would overlap the card above it, tracking a running
 *      `prevBottom`. Card heights are variable (a thread with 10 replies is
 *      much taller than one with a single comment), so they're measured live
 *      via a `ResizeObserver` per card (`useExpandedCardHeights` - same
 *      established pattern as `useMarkerTops` below and this codebase's other
 *      DOM-measuring overlays), falling back to `DEFAULT_EXPANDED_CARD_HEIGHT`
 *      for the one frame before a card's first real measurement lands. This
 *      is deterministic and jitter-free in steady state: the same
 *      entries+heights always produce the same layout, and heights only
 *      change when a thread's actual rendered content does (a reply added,
 *      not spurious re-renders).
 *    - **Popover vs. plain `fixed` div**: expanded cards use a plain `fixed`
 *      `<div>` wrapping `Thread` directly, *not* a permanently-`open`
 *      `Popover`. `Thread`'s own `Card` (BlockNote's `@blocknote/shadcn`
 *      `Card.tsx`, confirmed via its source) already supplies the full card
 *      chrome - border, shadow, `w-[300px]` - so no extra frame is needed
 *      around it. A permanently-open `Popover` was considered simpler
 *      (reusing the exact narrow-mode markup) but rejected: it needs a real
 *      anchor element for floating-ui to position against, which fights our
 *      own collision-avoided `top`/`left` values, and while this app's
 *      `Popover` (`@base-ui/react`) defaults `modal={false}` (no backdrop,
 *      no focus trap, no scroll lock - confirmed via
 *      `@base-ui/react/popover/root/PopoverRoot.d.ts`), there's no reason to
 *      route through floating-ui's positioning logic at all for a case
 *      where every pixel is already computed by hand.
 *
 * **Wide-mode width threshold arithmetic** (`WIDE_MODE_MIN_WIDTH`): the
 * reading column is `max-w-3xl` (768px) inside `document-page.tsx`'s
 * `px-12` (48px each side, 96px total) padded area, itself to the right of
 * the 256px (`16rem`, `ui/sidebar.tsx`'s `SIDEBAR_WIDTH`) left sidebar - so
 * the column reaches its full 768px width (no squeeze, matching Task 9/11's
 * existing constraint) once the window is at least 256+96+768 = 1120px, and
 * is centered (`mx-auto`) within whatever space remains beyond that. That
 * centering is the subtlety a flat "sum the widths" estimate misses: every
 * pixel the window grows past 1120 is split *in half* between the column's
 * left slack and its right slack, so only half of any extra window width
 * actually becomes usable space to the column's right - the wide-mode card
 * (BlockNote's own 300px-wide `Card`, plus a 24px gutter clear of the
 * column, plus this app's existing 24px (`right-6`) margin from the window's
 * own right edge, matching every other floating badge in this file) needs
 * `2*24 (gutter) + 2*24 (right margin) + 2*300 (card) + 1024 = 1720`px of
 * window width before it's guaranteed to clear the column with no overlap
 * (full derivation, in case this needs revisiting: column's right edge sits
 * at `1072 + (W-1120)/2`; the card's left edge sits at `W-24-300`; setting
 * their difference to the 24px gutter and solving for `W` gives 1720).
 * Verified live via Playwright resize that 1720px leaves a clean gap and
 * that the column never shrinks below `max-w-3xl` at or above it.
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
 * orphaned thread still reads as content-with-a-lost-position rather than
 * looking like an ordinary comment. That header text itself comes from this
 * app's own overridden `deleted_reference_text` dictionary string
 * (`editor.tsx`) - not BlockNote's stock "Original content deleted", which is
 * misleading here since orphaning happens on *every* reload, not genuine
 * content deletion, and the comment body itself always survives (see
 * `editor.tsx`'s dictionary override for the full reasoning).
 *
 * Each marker/card renders `<Thread thread={...} referenceText={...}
 * orphaned={...} />` directly (also a genuine public `@blocknote/react`
 * export - `node_modules/@blocknote/react/src/index.ts` re-exports it from
 * `./components/Comments/Thread.js`) rather than the full `<ThreadsSidebar
 * filter="all" sort="position" />` list, since a single marker's popover (or
 * expanded card) must show only its own thread(s), not every thread in the
 * document.
 *
 * Still mounted as a child of `<BlockNoteView>` in editor.tsx (not
 * document-page.tsx) for the same reason as before: `useThreads`/
 * `useExtensionState`/`Thread` read the editor and the shadcn comment-card
 * components off `BlockNoteContext`/`ComponentsContext` - both are only
 * provided within `BlockNoteView`'s own subtree. Each marker/card still
 * paints via `ReactDOM.createPortal` into `portalTarget` - document-page.tsx's
 * `comments-anchor` div - so its DOM output can live outside
 * `BlockNoteView`'s own tree (each positions itself independently via its
 * own inline `fixed` `top`, so the anchor div's own position doesn't matter;
 * it's just a plain portal mount point, see document-page.tsx). React context
 * still flows through the component tree the portal was created from, not
 * through the DOM, so this keeps working even though the portaled output
 * ends up physically outside `BlockNoteView`'s own DOM subtree.
 *
 * Renders nothing at all when there are no threads (`threads.size === 0`),
 * so no marker ever occupies screen space it has nothing to show for.
 */
interface CommentThreadsSidebarProps {
  portalTarget: HTMLElement | null
}

// Absolute floor: never let a marker/card render above the titlebar (~56px -
// see table-of-contents.tsx's `SCROLL_OFFSET`), no matter what. Task 20/21
// hardcoded this as the *entire* top-clamp value (`MARKER_TOP_MIN = 64`) -
// Task 23 found (live user report, reproduced directly) that this collides
// with a cover image (page-header.tsx, up to ~280px tall via `max-h-70`):
// an orphaned thread's marker/card, and any marker whose natural position
// happened to clamp against this same floor, rendered pinned to a fixed
// y=64 even when a full-bleed cover image occupied that exact region
// (confirmed live: cover at y=36..306, orphaned card at y=64, height=243,
// bottom=307 - overlapping almost exactly).
//
// `useMarkerTops` below now computes a dynamic `markerTopMin` from
// `editor.domElement?.getBoundingClientRect().top` - the real, live top
// edge of the ProseMirror content area - clamped with
// `Math.max(TITLEBAR_CLEARANCE, thatValue)` so it never goes *below* this
// floor once the cover/header scrolls out of view (verified live: scrolled
// past the cover, `editor.domElement`'s top goes negative and the `Math.max`
// correctly falls back to plain titlebar clearance). This self-corrects
// whether a cover is present or not and whether the user has scrolled past
// it, without hardcoding any cover-specific height.
//
// One nuance verified live, worth recording: `editor.domElement`'s top
// also includes this app's fixed per-document header chrome (icon/cover
// button row + title + "Edited…" timestamp, page-header.tsx) - measured at
// ~208px above the editor even with NO cover present (vs. this constant's
// bare 64px). That header content is confined to the `max-w-3xl` reading
// column, though, never the right margin where markers/cards actually
// render (`fixed right-6`) - so raising the floor by that amount changes
// the *number* for a no-cover document but not anything visible: that
// region of the right margin is empty screen space either way. Live-checked
// both with and without a cover, scrolled and unscrolled, to confirm no
// visual regression before accepting this rather than adding a
// cover-specific DOM query (which `page-header.tsx`'s cover `<img>` has no
// stable non-testid selector for - and testids are stripped from
// production builds, per vite.config.ts's `react-remove-properties`, so
// they can't be relied on for real app behavior anyway).
//
// `clampTop`'s floor, `layoutExpandedCards`' `Math.max`, and the
// orphaned-thread stacking formula in `useThreadEntries` all take this
// dynamic `markerTopMin` as a parameter now instead of reading a
// module-level constant, so all three stay consistent by construction.
const TITLEBAR_CLEARANCE = 64
// Keeps every marker clear of the table-of-contents floating toggle
// (`right-6 bottom-24`, `icon-lg` = 36px tall - table-of-contents.tsx) below,
// regardless of scroll position. A max-clamped marker's bottom edge sits at
// `innerHeight - MARKER_BOTTOM_MARGIN + <marker height, ~28px for
// size="sm">`; the TOC toggle's own top edge sits at
// `innerHeight - bottom-24(96px) - 36px = innerHeight - 132px` - so this
// needs to clear `132 - 28 = 104px` with room to spare, not just barely
// touch it (160 leaves an exact zero-pixel gap, found live during review).
const MARKER_BOTTOM_MARGIN = 176
// Vertical spacing between stacked orphaned markers (no real document
// position to place them at - see the doc comment above). Deliberately under
// CLUSTER_DISTANCE_THRESHOLD so multiple orphaned threads chain-cluster into
// one badge in narrow mode instead of stacking as separate ones (verified
// live - reads cleaner).
const ORPHANED_MARKER_GAP = 44
// Narrow/default mode: threads whose natural `top` values land within this
// many pixels of their neighbor chain-cluster into one combined marker.
// Task 20's markers are `size="sm"` buttons, ~28px tall; the task brief
// suggested starting around 1.5-2x that (42-56px). Verified live: two
// comments placed on adjacent lines of body text land ~34-40px apart
// (line-height plus the small block-to-block gap) and need to cluster; two
// comments separated by a full filler paragraph land 100px+ apart and must
// stay separate. 48px sits inside the adjacent-lines gap and well under the
// full-paragraph gap.
const CLUSTER_DISTANCE_THRESHOLD = 48
// See the doc comment above for the full derivation.
const WIDE_MODE_MIN_WIDTH = 1720
// Gap kept between two collision-avoided expanded cards (see
// `layoutExpandedCards`).
const EXPANDED_CARD_GAP = 16
// Assumed card height for one render frame, before a card's first real
// `ResizeObserver` measurement lands (see `useExpandedCardHeights`).
const DEFAULT_EXPANDED_CARD_HEIGHT = 160

interface ThreadEntry {
  thread: ThreadData
  threadPosition: { from: number; to: number } | undefined
  naturalTop: number
}

export function CommentThreadsSidebar({
  portalTarget
}: CommentThreadsSidebarProps) {
  const editor = useBlockNoteEditor<any, any, any>()
  const threads = useThreads()
  const { threadPositions } = useExtensionState(CommentsExtension)
  const { entries, markerTopMin } = useThreadEntries(
    editor,
    threads,
    threadPositions
  )
  const isWide = useIsWideMode()

  if (threads.size === 0) {
    return null
  }

  const content = isWide ? (
    <ExpandedCards
      editor={editor}
      entries={entries}
      markerTopMin={markerTopMin}
    />
  ) : (
    <ClusteredMarkers
      editor={editor}
      entries={entries}
      markerTopMin={markerTopMin}
    />
  )

  return portalTarget ? createPortal(content, portalTarget) : content
}

/**
 * Computes every thread's natural (unclamped, unclustered) viewport-relative
 * `top` - shared by both the narrow-mode clustering path and the wide-mode
 * collision-avoidance path below, so positioning logic for a single thread
 * lives in exactly one place. Also returns `markerTopMin` (see
 * `useMarkerTops`) so callers can pass the *same* dynamic floor value into
 * `clampTop`/`layoutExpandedCards` below, keeping every one of this file's
 * three former `MARKER_TOP_MIN` call sites consistent by construction
 * instead of each reading its own copy.
 */
function useThreadEntries(
  editor: BlockNoteEditor<any, any, any>,
  threads: Map<string, ThreadData>,
  threadPositions: Map<string, { from: number; to: number }>
): { entries: ThreadEntry[]; markerTopMin: number } {
  const { tops: markerTops, markerTopMin } = useMarkerTops(
    editor,
    threadPositions
  )

  const entries = useMemo(() => {
    let orphanedIndex = 0
    return Array.from(threads.values()).map((thread) => {
      const threadPosition = threadPositions.get(thread.id)
      const rawTop = markerTops.get(thread.id)
      const naturalTop =
        rawTop === undefined
          ? markerTopMin + orphanedIndex++ * ORPHANED_MARKER_GAP
          : rawTop
      return { thread, threadPosition, naturalTop }
    })
  }, [threads, threadPositions, markerTops, markerTopMin])

  return { entries, markerTopMin }
}

function clampTop(top: number, markerTopMin: number): number {
  const max = Math.max(markerTopMin, window.innerHeight - MARKER_BOTTOM_MARGIN)
  return Math.min(Math.max(top, markerTopMin), max)
}

/**
 * Groups thread entries whose natural `top` values chain within
 * `CLUSTER_DISTANCE_THRESHOLD` of their immediate neighbor into one cluster
 * (sorted ascending, so this is a single linear pass - not full pairwise
 * comparison). A cluster's own `top` is its topmost entry's natural `top`.
 */
function clusterEntries(entries: ThreadEntry[]): {
  key: string
  top: number
  entries: ThreadEntry[]
}[] {
  const sorted = [...entries].sort((a, b) => a.naturalTop - b.naturalTop)
  const clusters: { key: string; top: number; entries: ThreadEntry[] }[] = []

  for (const entry of sorted) {
    const current = clusters[clusters.length - 1]
    const previous = current?.entries[current.entries.length - 1]
    if (
      current &&
      previous &&
      entry.naturalTop - previous.naturalTop <= CLUSTER_DISTANCE_THRESHOLD
    ) {
      current.entries.push(entry)
    } else {
      clusters.push({
        key: entry.thread.id,
        top: entry.naturalTop,
        entries: [entry]
      })
    }
  }

  return clusters
}

function ClusteredMarkers({
  editor,
  entries,
  markerTopMin
}: {
  editor: BlockNoteEditor<any, any, any>
  entries: ThreadEntry[]
  markerTopMin: number
}) {
  const clusters = clusterEntries(entries)

  return (
    <>
      {clusters.map((cluster) => (
        <ClusterMarker
          key={cluster.key}
          editor={editor}
          entries={cluster.entries}
          top={clampTop(cluster.top, markerTopMin)}
        />
      ))}
    </>
  )
}

/**
 * Computes each positioned thread's current viewport-relative `top` (see the
 * component doc comment above for the full `coordsAtPos` rationale), keyed by
 * thread id, plus `markerTopMin` - the dynamic top-clearance floor described
 * at `TITLEBAR_CLEARANCE`'s doc comment above, computed here (rather than in
 * a second, separately-timed effect) specifically so it shares this same
 * `tick` recompute cycle. Orphaned threads (no entry in `threadPositions`)
 * simply have no entry in the returned map - the caller falls back to a
 * stacked position (anchored at `markerTopMin`) for those.
 *
 * `tick` exists purely to force a recompute on scroll/resize/layout-shift:
 * `coordsAtPos` and `getBoundingClientRect` both read live DOM layout, not
 * React state, so there's nothing to put directly in a dependency array for
 * "the window scrolled" - bumping a counter on each such event and depending
 * on it is the same trick `code-block-copy-overlay.tsx` uses for the same
 * reason. Note the `ResizeObserver` below only fires on `editor.domElement`'s
 * own size changing, not merely its position - a cover being added/removed
 * above it (page-header.tsx) doesn't resize the editor itself, only shifts
 * it, so that case relies on the `scroll`/`resize` listeners (or a later
 * scroll/resize after the cover changes) to pick up the new `markerTopMin`,
 * matching this hook's pre-existing scope (documented above, not a new gap
 * introduced by this task).
 */
function useMarkerTops(
  editor: BlockNoteEditor<any, any, any>,
  threadPositions: Map<string, { from: number; to: number }>
): { tops: Map<string, number>; markerTopMin: number } {
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

  const tops = useMemo(() => {
    const tops = new Map<string, number>()
    for (const [threadId, position] of threadPositions) {
      const coords = editor.prosemirrorView?.coordsAtPos(position.from)
      if (coords) {
        tops.set(threadId, coords.top)
      }
    }
    return tops
  }, [editor, threadPositions, tick])

  const markerTopMin = useMemo(() => {
    const contentTop = editor.domElement?.getBoundingClientRect().top
    return Math.max(TITLEBAR_CLEARANCE, contentTop ?? TITLEBAR_CLEARANCE)
  }, [editor, tick])

  return { tops, markerTopMin }
}

/**
 * Tracks whether the window is wide enough to switch from narrow mode
 * (clustered, click-to-open markers) to wide mode (every thread expanded
 * into a persistent card) - see the component doc comment above for the full
 * `WIDE_MODE_MIN_WIDTH` arithmetic. Mirrors `use-mobile.ts`'s
 * `matchMedia`-plus-`change`-listener pattern, the established way this
 * codebase tracks a width breakpoint reactively.
 */
function useIsWideMode(): boolean {
  const [isWide, setIsWide] = useState(
    () => window.innerWidth >= WIDE_MODE_MIN_WIDTH
  )

  useEffect(() => {
    const mql = window.matchMedia(`(min-width: ${WIDE_MODE_MIN_WIDTH}px)`)
    const onChange = () => setIsWide(window.innerWidth >= WIDE_MODE_MIN_WIDTH)
    mql.addEventListener('change', onChange)
    onChange()
    return () => mql.removeEventListener('change', onChange)
  }, [])

  return isWide
}

function ClusterMarker({
  editor,
  entries,
  top
}: {
  editor: BlockNoteEditor<any, any, any>
  entries: ThreadEntry[]
  top: number
}) {
  const isCluster = entries.length > 1
  const orphaned = entries.every((entry) => !entry.threadPosition)
  const badgeCount = isCluster
    ? entries.length
    : entries[0].thread.comments.length
  const idSuffix = isCluster
    ? `cluster-${entries.map((entry) => entry.thread.id).join('-')}`
    : entries[0].thread.id

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
            data-testid={`comment-marker-${idSuffix}`}
            data-thread-count={entries.length}
            data-orphaned={orphaned || undefined}
          />
        }
      >
        <MessageSquare className="size-3.5" />
        {badgeCount}
      </PopoverTrigger>
      <PopoverContent
        side="left"
        align="start"
        sideOffset={12}
        data-testid={`comment-marker-popover-${idSuffix}`}
        className="flex max-h-[70vh] w-80 flex-col overflow-y-auto"
      >
        {isCluster ? (
          <div className="divide-border/60 flex flex-col divide-y">
            {entries.map((entry) => (
              <div key={entry.thread.id} className="py-3 first:pt-0 last:pb-0">
                <Thread
                  thread={entry.thread}
                  referenceText={getReferenceText(editor, entry.threadPosition)}
                  orphaned={!entry.threadPosition}
                />
              </div>
            ))}
          </div>
        ) : (
          <Thread
            thread={entries[0].thread}
            referenceText={getReferenceText(editor, entries[0].threadPosition)}
            orphaned={orphaned}
          />
        )}
      </PopoverContent>
    </Popover>
  )
}

/**
 * Wide-mode collision avoidance: sorts by natural `top`, then walks through
 * pushing each card down to clear the previous (already-placed) card's
 * measured bottom edge whenever its natural position would overlap it.
 * Deterministic given the same `entries`/`heights` inputs, so this only
 * changes when a thread's real position or a card's real measured height
 * changes - not on every render - which is what keeps it jitter-free.
 */
function layoutExpandedCards(
  entries: ThreadEntry[],
  heights: Map<string, number>,
  markerTopMin: number
): Map<string, number> {
  const sorted = [...entries].sort((a, b) => a.naturalTop - b.naturalTop)
  const positions = new Map<string, number>()
  let prevBottom = -Infinity

  for (const entry of sorted) {
    const top = Math.max(entry.naturalTop, markerTopMin, prevBottom)
    positions.set(entry.thread.id, top)
    const height = heights.get(entry.thread.id) ?? DEFAULT_EXPANDED_CARD_HEIGHT
    prevBottom = top + height + EXPANDED_CARD_GAP
  }

  return positions
}

/**
 * Measures each expanded card's real rendered height via one shared
 * `ResizeObserver` (same established pattern as `useMarkerTops` above),
 * keyed by thread id through a `data-card-id` attribute set on the observed
 * node rather than through the `ResizeObserverEntry`'s target identity
 * directly, since cards can unmount/remount as threads are added/removed.
 */
function useExpandedCardHeights() {
  const [heights, setHeights] = useState<Map<string, number>>(new Map())
  const observerRef = useRef<ResizeObserver | null>(null)
  const nodesRef = useRef<Map<string, Element>>(new Map())

  useEffect(() => {
    const observer = new ResizeObserver((observedEntries) => {
      setHeights((prev) => {
        let changed = false
        const next = new Map(prev)
        for (const observedEntry of observedEntries) {
          const id = (observedEntry.target as HTMLElement).dataset.cardId
          const height = observedEntry.contentRect.height
          if (id && next.get(id) !== height) {
            next.set(id, height)
            changed = true
          }
        }
        return changed ? next : prev
      })
    })
    observerRef.current = observer
    return () => observer.disconnect()
  }, [])

  const registerCard = useCallback((id: string, node: HTMLElement | null) => {
    const observer = observerRef.current
    const prevNode = nodesRef.current.get(id)
    if (prevNode && observer) {
      observer.unobserve(prevNode)
    }
    if (node) {
      nodesRef.current.set(id, node)
      observer?.observe(node)
    } else {
      nodesRef.current.delete(id)
    }
  }, [])

  return { heights, registerCard }
}

function ExpandedCards({
  editor,
  entries,
  markerTopMin
}: {
  editor: BlockNoteEditor<any, any, any>
  entries: ThreadEntry[]
  markerTopMin: number
}) {
  const { heights, registerCard } = useExpandedCardHeights()
  const positions = useMemo(
    () => layoutExpandedCards(entries, heights, markerTopMin),
    [entries, heights, markerTopMin]
  )

  return (
    <>
      {entries.map((entry) => {
        const orphaned = !entry.threadPosition
        return (
          <div
            key={entry.thread.id}
            ref={(node) => registerCard(entry.thread.id, node)}
            data-card-id={entry.thread.id}
            className={cn(
              'fixed right-6 z-40 max-h-[70vh] overflow-y-auto',
              orphaned && 'opacity-70'
            )}
            style={{ top: positions.get(entry.thread.id) ?? entry.naturalTop }}
            data-testid={`comment-card-${entry.thread.id}`}
            data-orphaned={orphaned || undefined}
          >
            <Thread
              thread={entry.thread}
              referenceText={getReferenceText(editor, entry.threadPosition)}
              orphaned={orphaned}
            />
          </div>
        )
      })}
    </>
  )
}
