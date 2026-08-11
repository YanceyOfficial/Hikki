# Heading-Targeted Page Mentions — Design

**Date:** 2026-08-12
**Status:** Approved (design review with user)
**Source spec:** `docs/superpowers/specs/2026-08-07-page-mention-design.md` (the whole-document Page Mentions feature this extends)

Extends the shipped Page Mentions feature so an `@` mention can optionally target a specific heading/section within a document, not just the document as a whole — motivated by a concrete pain point: linking from one set of study notes to a specific section of a separate article, not the whole thing.

---

## 1. Decisions made during design review

| Decision                            | Choice                                                                                                       | Rationale                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Selection flow                      | Continue typing in the same "@" menu to narrow into a document's headings                                    | Matches how the user already expects this to work (à la Notion's page-then-section drill-down); picking a document doesn't have to be a dead end                                                                                                                                                                               |
| Heading-deleted-but-document-intact | The pill silently degrades to a plain whole-document mention (still clickable, drops the "→ heading" suffix) | Consistent with the existing whole-document broken-mention philosophy: a dangling reference is a display state, not a failure worth interrupting the user over                                                                                                                                                                 |
| Heading label in the pill           | Shown, but as an insert-time snapshot, not live                                                              | A document's headings aren't part of the lightweight `docMetasAtom` the way its title is - keeping the heading label live would mean fetching another document's full content just to render one inline pill. A snapshot is deliberately accepted to go stale on rename, mirroring the doc-title/heading-existence split below |

## 2. Architecture

`pageMention`'s existing propSchema (`{ docId }`) gains two new optional props, both defaulting to `''` so every already-shipped whole-document mention continues to parse and render unchanged:

```ts
propSchema: {
  docId: { default: '' },
  headingId: { default: '' },
  headingText: { default: '' }
}
```

The `@` `SuggestionMenuController` in `editor.tsx` gets a custom `suggestionMenuComponent` (a documented `SuggestionMenuController` prop, `FC<SuggestionMenuProps<T>>`) in place of BlockNote's default menu-rendering component. This is necessary, not cosmetic: BlockNote's default menu component always calls `closeMenu()`/`clearQuery()` immediately before invoking any item's `onItemClick`, which would end the "@" session the instant a document is picked. A custom component keeps the same `@`-triggered query-tracking and floating-ui positioning BlockNote already provides, but takes over what happens when an item is clicked - letting "pick a document" swap the rendered item list to that document's headings instead of closing the menu.

A new small module, `src/lib/heading-mention-cache.ts`, lazily fetches a document's headings on demand (`backend.loadDocument(docId)`, once per document id, cached in a Jotai atom family) and extracts them with `table-of-contents.tsx`'s already-exported, pure `extractTocItems(blocks)`. Both the picker's drill-down and the render component's existence check go through this same cache - it is never used to derive a _displayed_ heading string, only to answer "does this document have headings" / "does this specific heading id still exist."

## 3. Components & data flow

- **Storage:** `{ type: 'pageMention', props: { docId, headingId, headingText } }`. `headingId` is BlockNote's own stable block id (the same identity already used by `heading-anchor-overlay.tsx` and the table of contents) - not a derived or positional index, so it survives reordering and edits to surrounding content. `headingText` is captured once, at insertion time, from the picker's already-fetched heading list; it is never re-read or re-synced afterward.
- **Picker:** typing `@` and narrowing to a document behaves exactly as the shipped feature does today when that document has no headings - selecting it immediately inserts a whole-document mention. When it does have headings, the custom suggestion-menu component swaps the visible item list to that document's headings (via the heading-mention cache), with a "← Whole document" item pinned at the top as an explicit escape hatch back to the plain whole-document mention. Continued typing filters within whichever list (documents, or the current document's headings) is currently showing. Nothing here excludes mentioning a heading within the same document you're currently editing - the base feature never excluded self-mentions either, and this extension doesn't change that.
- **Rendering:** `PageMentionRender` resolves the document's title live from `docMetasAtom`, exactly as today - this part is unaffected by any of the new props. When `headingId` is non-empty, it additionally asks the heading-mention cache whether that id is still present among the target document's current headings. If yes, the pill renders `"{live document title} → {headingText snapshot}"`. If no - or if the whole document itself is gone, the existing broken-mention case from the base feature - it renders as an ordinary whole-document mention (or the existing broken-pill state), with no visible trace of the stale heading reference.
- **Navigation:** a heading-targeted pill's click sets `window.location.hash` to `` `#/doc/${docId}?heading=${headingId}` `` instead of the plain `` `#/doc/${docId}` `` the base feature uses. `document-page.tsx` reads `heading` via `react-router`'s `useSearchParams()` (which parses whatever follows `#` as a normal path+query under `createHashRouter`, exactly as it would under a browser router - no new routing convention needed). Once the target document has loaded and its own `heading-anchor-overlay.tsx`-rendered anchors exist in the DOM, it scrolls to the matching id the same way a table-of-contents click already does (`document.getElementById(id)?.scrollIntoView(...)`). Reloading or revisiting the same link re-triggers the same scroll every time, matching how a plain HTML `#anchor` link behaves - this is treated as expected, not something to "consume" and clear.

## 4. Error handling & testing

- A failed or missing fetch in the heading-mention cache (deleted document, corrupted file, IO error) is treated the same as "this document has no headings" at both call sites - the picker just doesn't offer a drill-down, and the render-time existence check treats it as "not found," falling into the same graceful degradation as a genuinely-deleted heading. Neither path raises a `reportError` toast; this mirrors the base feature's existing broken-mention handling, which is a silent display state, not an actionable failure.
- If the target document hasn't finished loading (or its anchors haven't painted yet) at the moment `document-page.tsx` tries to scroll, the scroll is simply skipped rather than retried indefinitely - functionally equivalent to landing on a plain whole-document mention, and not distinguishable by the user from the heading having been deleted.
- **Unit tests:** the heading-mention cache's extraction/lookup logic (pure, given a fetched `Doc`); `PageMentionRender`'s new degraded-vs-with-heading rendering branches, using the same `getDefaultStore()` + `docMetasAtom` pattern the base feature's existing tests already use, with the heading cache's atom seeded directly rather than mocking a network call.
- **E2E:** the full flow - typing `@`, drilling into a document with headings, picking one, confirming the inserted pill shows the document-title-then-heading-snapshot label, clicking it and confirming the browser scrolls to that heading in the newly-loaded target document; deleting just the target heading (document left intact) and confirming the pill visually degrades to a plain whole-document mention; deleting the whole target document and confirming it still falls into the base feature's existing broken-pill case, unchanged.

## 5. Out of scope

- Keeping the heading _label_ live/synced after insertion (§1) - explicitly a snapshot, not a live value, unlike the document title.
- Multi-level heading breadcrumbs (e.g. showing an intermediate heading's own parent heading) - the picker flattens a document's headings into one list (matching the existing table of contents' own flattened-with-indentation presentation), and the pill shows only the single chosen heading's text.
- Re-pointing an existing heading-targeted mention at a different heading after insertion, or converting a whole-document mention into a heading-targeted one after the fact - not requested; a mention is deleted and re-inserted like any other inline content, same as the base feature's own stated scope boundary.
