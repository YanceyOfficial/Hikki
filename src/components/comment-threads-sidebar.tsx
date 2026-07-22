import { ThreadsSidebar, useThreads } from '@blocknote/react'
import { MessageSquare } from 'lucide-react'
import { createPortal } from 'react-dom'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'

/**
 * Mitigates a structural BlockNote limitation (confirmed via BlockNote's own
 * GitHub issue #1701): the comment mark/highlight is a TipTap mark, not part
 * of the `Block[]` JSON model `editor.document` serializes, so it's never
 * persisted. `VaultThreadStore` still round-trips `doc.threads` correctly
 * (see vault-thread-store.ts) - the *thread data* survives a reload - but
 * without the mark there's nothing left in the document body to click:
 * after a reload, existing comment threads have no highlight, no badge,
 * nothing, even though `doc.threads` still holds them.
 *
 * `ThreadsSidebar` (from `@blocknote/react`) lists every thread the
 * currently-registered `CommentsExtension` knows about, independent of
 * whether its inline anchor survived - it derives an `orphaned` flag per
 * thread from `threadPositions` (see its source), and BlockNote's own
 * `getReferenceText` falls back to `dict.comments.deleted_reference_text`
 * ("Original content deleted") as that thread's header when the anchor is
 * gone. That's enough to make every thread discoverable again after reload,
 * even though the highlight itself is unrecoverable (BlockNote's own
 * maintainers have confirmed this on #1701 as a structural, not-fixable-
 * within-reasonable-scope limitation - not something to chase further here).
 *
 * Note: despite `ThreadsSidebar`'s `filter` prop being documented as
 * `@default "all"`, the component never actually applies that default at
 * runtime (no destructured default in its source) - omitting it renders an
 * empty list, since neither its "open" nor "resolved" branch matches
 * `undefined`. `filter="all"` must be passed explicitly.
 *
 * Rendered as a child of `<BlockNoteView>` in editor.tsx (not from
 * document-page.tsx) because `ThreadsSidebar`/`useThreads` read the editor
 * off `BlockNoteContext` (`useBlockNoteEditor`) and the shadcn comment-card
 * components off `ComponentsContext`/`ShadCNComponentsContext` - both are
 * only provided within `BlockNoteView`'s subtree (see
 * `@blocknote/react`'s `BlockNoteView.tsx` and `@blocknote/shadcn`'s
 * `BlockNoteView.tsx`). That's still true under this component's current
 * floating-badge shape: this component keeps mounting inside `<BlockNoteView>`
 * to read those contexts, and instead uses `ReactDOM.createPortal` to paint
 * its output into `portalTarget` - a small `fixed`-positioned anchor `<div>`
 * document-page.tsx owns and passes down through `Editor`'s
 * `commentsPortalTarget` prop. React context still flows through the
 * component tree the portal was created from, not through the DOM, so this
 * works even though the portaled output ends up physically outside
 * `<BlockNoteView>`'s own DOM subtree.
 *
 * Styled after Notion's own floating comments affordance (confirmed against
 * a live Notion screenshot during design review): a small always-available
 * badge - a chat-bubble icon plus `threads.size` - anchored to a fixed
 * corner of the viewport rather than a permanent in-flow or wide-rail-only
 * column. Clicking it opens a `Popover` containing the same `ThreadsSidebar`
 * list used before; collapsed by default so it costs no reading-column width
 * at any window size, and works identically whether the window is narrow or
 * wide. Renders nothing at all when there are no threads (`threads.size ===
 * 0`), so the badge never occupies screen space it has nothing to show for.
 */
interface CommentThreadsSidebarProps {
  portalTarget: HTMLElement | null
}

export function CommentThreadsSidebar({
  portalTarget
}: CommentThreadsSidebarProps) {
  const threads = useThreads()

  if (threads.size === 0) {
    return null
  }

  const content = (
    <Popover>
      <PopoverTrigger
        render={
          <Button
            variant="secondary"
            size="lg"
            className="gap-1.5 rounded-full shadow-md"
            data-testid="comments-toggle"
          />
        }
      >
        <MessageSquare className="size-4" />
        {threads.size}
      </PopoverTrigger>
      <PopoverContent
        align="end"
        side="top"
        sideOffset={12}
        data-testid="comment-threads-sidebar"
        className="flex max-h-[70vh] w-80 flex-col gap-3 overflow-y-auto"
      >
        <ThreadsSidebar filter="all" sort="position" />
      </PopoverContent>
    </Popover>
  )

  return portalTarget ? createPortal(content, portalTarget) : content
}
