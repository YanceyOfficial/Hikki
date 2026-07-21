import { ThreadsSidebar, useThreads } from '@blocknote/react'

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
 * `BlockNoteView.tsx`).
 *
 * Kept deliberately simple for v1: no collapse/toggle affordance (there's no
 * existing pattern for one in this app, and BlockNote's own default UI has
 * no comments-count badge to hang a toggle off), just an always-visible
 * section that renders nothing when there are no threads at all.
 */
export function CommentThreadsSidebar() {
  const threads = useThreads()

  if (threads.size === 0) {
    return null
  }

  return (
    <div
      data-testid="comment-threads-sidebar"
      className="border-border/60 mt-10 border-t pt-6"
    >
      <h2 className="text-muted-foreground mb-3 text-xs font-semibold tracking-wide uppercase">
        Comments
      </h2>
      <ThreadsSidebar filter="all" sort="position" />
    </div>
  )
}
