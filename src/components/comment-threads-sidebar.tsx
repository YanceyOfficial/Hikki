import { ThreadsSidebar, useThreads } from '@blocknote/react'
import { createPortal } from 'react-dom'

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
 * `BlockNoteView.tsx`). That's still true even now that the cards need to
 * *visually* land in document-page.tsx's right-margin rail rather than
 * inline: this component keeps mounting inside `<BlockNoteView>` to read
 * those contexts, and instead uses `ReactDOM.createPortal` to paint its
 * output into `portalTarget` - a plain DOM node document-page.tsx owns
 * (`pageRailNode`) and passes down through `Editor`'s `commentsPortalTarget`
 * prop. React context still flows through the component tree the portal was
 * created from, not through the DOM, so this works even though the portaled
 * output ends up physically outside `<BlockNoteView>`'s own DOM subtree.
 *
 * v1 scope, styled after Notion's floating comment cards but simplified:
 * every thread renders as a stacked vertical list of cards in this
 * persistent rail (literally what `ThreadsSidebar` is designed for - its own
 * source doc comment calls it "similar to Google Docs' Show All Comments
 * sidebar"), not per-thread floating beside its own highlighted text at a
 * matching scroll position. `ThreadsSidebar` only exposes `threadPositions`
 * as ProseMirror document offsets (`from`/`to`), not pixel coordinates -
 * turning that into scroll-synced Y positions (`editor.view.coordsAtPos`,
 * scroll/resize listeners, collision handling between nearby threads) is a
 * substantially larger feature, out of scope here.
 *
 * Kept deliberately simple for v1: no collapse/toggle affordance (there's no
 * existing pattern for one in this app, and BlockNote's own default UI has
 * no comments-count badge to hang a toggle off), just an always-rendered
 * portal that paints nothing when there are no threads at all.
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
    <div data-testid="comment-threads-sidebar" className="flex flex-col gap-3">
      <ThreadsSidebar filter="all" sort="position" />
    </div>
  )

  return portalTarget ? createPortal(content, portalTarget) : content
}
