# Page Mentions — Design

**Date:** 2026-08-07
**Status:** Approved (design review with user)
**Source spec:** `docs/superpowers/specs/2026-07-18-hikki-design.md` (base app design; this extends the Editor section)

Notion-style internal document links: typing "@" inside the editor opens a searchable picker over the vault's own documents and inserts a live-updating mention pill, so documents can reference each other without leaving BlockNote.

---

## 1. Decisions made during design review

| Decision                 | Choice                                                               | Rationale                                                                                                                                                                                                                                                                                                               |
| ------------------------ | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scope                    | Internal document-to-document mentions only                          | BlockNote's plain "Create link" toolbar button already handles external URLs correctly end-to-end - confirmed live before scoping this feature; no need to touch that path                                                                                                                                              |
| Implementation mechanism | **Approach A**: custom `createInlineContentSpec('pageMention', ...)` | Considered vs. reusing the link mark with a `hikki://doc/<id>` URL scheme. A custom inline content type keeps the mention's identity (`docId`) as structured data in the schema rather than encoded into a URL string, and gives full control over rendering (icon + pill) without fighting the link mark's own styling |
| Trigger character        | `@`                                                                  | Matches Notion's own convention; kept separate from the existing `/` slash-menu (`SuggestionMenuController` supports multiple trigger characters as independent instances)                                                                                                                                              |
| Picker UI                | Flat, search-as-you-type list                                        | The vault tree can be arbitrarily deep; a flat fuzzy-searchable list is faster to scan and to type through than reproducing the sidebar's hierarchy inside a suggestion menu                                                                                                                                            |
| Inline rendering         | Icon + title, pill-styled                                            | Matches Notion's page-mention chip and this app's existing pill/badge visual language elsewhere in the UI                                                                                                                                                                                                               |
| Title freshness          | Always live (resolved at render time, never stored)                  | Storing only `docId` (not a title snapshot) makes a stale title structurally impossible - there is nothing to keep in sync when the target document is renamed                                                                                                                                                          |
| Deleted/trashed target   | Render as broken, not clickable                                      | A dangling reference is a display state, not a failure - no error toast, just a muted, inert pill                                                                                                                                                                                                                       |
| Click behavior           | Direct click navigates                                               | No modifier key required - mentions are meant to be as easy to follow as the sidebar's own document rows                                                                                                                                                                                                                |
| No search matches        | Offer "+ Create '\<query\>'"                                         | Mirrors Notion's own "create and link" affordance; avoids a dead-end when the target document doesn't exist yet                                                                                                                                                                                                         |

## 2. Architecture

A new inline content spec, `pageMention`, is added to the editor's schema alongside the existing custom `codeBlock` spec:

```ts
BlockNoteSchema.create().extend({
  blockSpecs: { codeBlock: createCodeBlockSpec({ ... }) },
  inlineContentSpecs: { pageMention: createPageMentionSpec() }
})
```

A second `SuggestionMenuController` (`triggerCharacter="@"`) is mounted next to the existing `/`-triggered one inside `<BlockNoteView>` in `editor.tsx`. Both are independent controllers - BlockNote supports multiple trigger characters as separate `SuggestionMenuController` instances, confirmed against `@blocknote/react`'s types.

## 3. Components & data flow

- **Storage shape:** a `pageMention` inline content node stores only `{ type: 'pageMention', props: { docId: string } }` in the block JSON. No title, icon, or other snapshot data is ever written - this is what makes "always live" a structural guarantee rather than a cache-invalidation problem.
- **Rendering:** the spec's `render(inlineContent, updateInlineContent, editor)` reads `props.docId`, looks it up in `docMetasAtom` (the same flat metadata list already powering the sidebar's `DocTree`, kept current via `refreshDocsAtom`) fresh on every render, and paints an icon + title pill from whatever is currently there. No separate fetch or cache is introduced.
- **Search/insert flow:** the `@` menu's `getItems(query)` filters `docMetasAtom`'s current value by title (flat, case-insensitive substring match - consistent with a "fast to scan" list rather than the sidebar's tree). Selecting a result inserts a `pageMention` with that document's `id`. When `query` matches nothing, the item list instead shows a single synthetic "+ Create '\<query\>'" entry; selecting it calls `backend.createDocument(null, query)`, awaits the result, calls `refreshDocsAtom` (matching the existing `createDoc`/`createChildDoc` pattern in `sidebar-left.tsx`), and inserts a `pageMention` pointing at the newly created document.
- **Navigation:** a resolved pill's `onClick` sets `window.location.hash = '#/doc/' + docId` directly - the same plain-DOM-navigation-from-imperative-code precedent already used elsewhere in this app (e.g. `code-block-copy-overlay.tsx`), consistent with `createHashRouter` routing.

## 4. Error handling & testing

- **Broken mentions:** if `docId` isn't present in the current `docMetasAtom` value, or its `deletedAt` is set, `render()` takes a distinct branch: a muted, non-interactive pill (no `onClick` attached, `aria-disabled`-style styling) instead of the normal icon+title pill. This is a display-state branch, not a `reportError` case - a dangling reference isn't an actionable failure the user needs to be told about via a toast.
- **"+ Create" failures:** `backend.createDocument` failing on that path routes through the existing `reportError` funnel (`src/lib/errors.ts`), consistent with every other backend call in this app - no new error code group needed if an existing vault/fs code (`HK-1xxx`) already covers document-creation failure; otherwise one new code is added there.
- **Unit testing:** since jsdom cannot render BlockNote (existing project convention), the title/icon/broken-state resolution logic is pulled out into a small pure function - `resolvePageMentionDisplay(docId: string, metas: DocumentMeta[]): { title: string; icon: string | null; isBroken: boolean }` (`#lib/`) - so it's directly unit-testable with Vitest, independent of the editor. The inline content spec's `render()` becomes a thin wrapper around this function.
- **E2E testing (Playwright):** covers what jsdom can't - typing `@` opens the menu; selecting an existing document inserts a working pill and clicking it navigates to that document; typing `@` with a query matching nothing shows only "+ Create"; selecting "+ Create" creates a new document and inserts a mention pointing at it; deleting a mentioned document (via the sidebar's existing delete action) and reloading shows that mention rendered as broken and non-clickable.

## 5. Out of scope

- Backlinks / "linked mentions" panel (what documents link _to_ this one) - not part of this feature; may be a natural follow-up once mentions exist.
- Renaming a mention's underlying reference (e.g. re-pointing an existing pill at a different document) - not requested; a mention is deleted and re-inserted like any other inline content today.
- Nested/hierarchical picker matching the sidebar's tree - explicitly decided against in favor of a flat searchable list (§1).
