# Page Mention Picker Refinements — Design

## Context

Follow-up UX polish on the just-shipped Page Mentions (`docs/superpowers/specs/2026-08-07-page-mention-design.md`) and Heading-Targeted Page Mentions (`docs/superpowers/specs/2026-08-12-heading-mentions-design.md`) features, after live user testing surfaced three issues:

1. Hikki documents can be nested (`parentId`) with no title-uniqueness constraint — two documents anywhere in the tree can share the exact same title. The "@" picker's document-search results render a flat list of bare titles, so same-titled documents are indistinguishable.
2. The "@" picker's rendered menu (`PageMentionMenu` in `src/components/editor.tsx`) is a hand-rolled `<div>`/`<button>` list, violating this project's "shadcn/ui first — never hand-roll" convention (CLAUDE.md). This app's `src/components/ui/combobox.tsx` (Base UI's `Combobox`, unused elsewhere in the codebase so far) is the natural visual reference.
3. The heading-targeted mention pill (`PageMentionRender` in `src/components/page-mention.tsx`) renders `"{title} → {headingText}"` unconditionally. The user wants `#` instead of `→`, and wants the heading portion hidden until the pill is hovered (or focused), revealed with an animation.

All three are additive UI refinements — no schema change, no new inline content type, no change to persisted `Doc.blocks` data.

## Decisions (locked via user Q&A and a live browser preview)

- **Combobox scope:** keep today's interaction model — typing after "@" directly in the BlockNote editor is still what drives the query (`SuggestionMenuController`'s own tracking, untouched). Only the _rendered menu's visual styling_ changes to match the shadcn Combobox's look. A full `Combobox.Root`-driven popup (its own separate search input, Cmd+K-palette style) was explicitly rejected — it would mean two competing places to type.
- **Path disambiguation format:** every document-search result always shows `"Parent / Title"` (immediate parent only, not the full ancestor chain); a top-level document (no `parentId`, or a parent that no longer resolves) shows plain `"Title"`. Chosen over "only show on an actual collision" (rejected — format would jump around as the query changes) and "full breadcrumb" (rejected — unnecessarily long for deep nesting). This applies only to the picker's document-search list, not the heading drill-down list (headings are already scoped to one chosen document, no cross-document collision is possible there) and not the rendered mention pill (the pill only ever needs the _mentioned_ document's own title).
- **Hover-reveal animation:** confirmed via a live browser preview (built with the pill's real CSS custom properties from `src/assets/globals.css`) against three candidates (fade, width-expand, slide+fade), then refined the winning width-expand candidate after initial feedback that a plain `max-width` transition felt abrupt. Final approach: wrap the `#` + heading text in an `inline-grid` container animating `grid-template-columns` from `0fr` to `1fr` (260ms, `cubic-bezier(0.16, 1, 0.3, 1)`) — this interpolates against the text's _actual_ intrinsic width, unlike a `max-width` transition toward an oversized cap, so there's no overshoot or snap. The text's own `opacity` fades in separately (180ms ease, 60ms delay) so it's never visible mid-squeeze. Both the `#` and the heading text are inside the same collapsing wrapper — at rest, a heading-targeted pill is visually identical to a plain whole-document pill (this is intentional, confirmed by the user, not a regression to "fix" later). Revealed on `:hover` and `:focus-visible` (keyboard accessible, not mouse-only). Respects `prefers-reduced-motion` (transitions removed entirely).

## Architecture

Three independent changes, each scoped to files already touched by the base features:

**A. Path disambiguation** (`src/lib/page-mention.ts`) — a new pure function resolves a document's display path from the same flat `DocumentMeta[]` list already passed to `searchPageMentionCandidates`. No new data source, no new backend call.

**B. Combobox-styled menu** (`src/components/editor.tsx`) — `PageMentionMenu`'s markup keeps its exact current structure (same `data-testid`s, same `kind`-based click routing built in the heading-mentions plan) but its Tailwind classes are replaced with ones matching `src/components/ui/combobox.tsx`'s `ComboboxList`/`ComboboxItem` visual language (rounded item highlight on `data-highlighted`, muted empty/group-label typography). Those Base UI-backed components can't be reused directly standalone — `ComboboxItem` calls `useComboboxRootContext()` and throws outside a `Combobox.Root` (confirmed by reading the installed `@base-ui/react` source), and introducing a real `Combobox.Root` here would mean the rejected two-inputs design — so this is a _visual_ match (borrowing the same class strings), not a literal component swap. One natural consequence: the drill-down "whole document" escape-hatch item's label (`` `← ${drill.docTitle} (whole document)` ``) captures `docTitle` from the clicked item's already-path-prefixed `title` (per the heading-mentions plan's existing `setDrill({ docTitle: item.title, ... })`), so it will read `"← Parent / Title (whole document)"` once path disambiguation ships — accepted as-is, not a separate decision to make.

**C. Pill hover-reveal** (`src/components/page-mention.tsx`) — `PageMentionRender`'s `displayTitle` string-concatenation approach is replaced with real markup: the title renders as before, followed by a new wrapper `<span>` (only rendered when `resolvedHeadingText` is non-null) containing the `#` separator and heading text, styled with the grid-track hover-reveal described above.

## Data flow / interfaces

```ts
// src/lib/page-mention.ts — new
export function resolveDocPath(
  meta: DocumentMeta,
  allMetas: DocumentMeta[]
): string
```

- No `parentId`, or parent not found in `allMetas` (deleted/orphaned): returns `meta.title || 'Untitled'`.
- Parent found: returns `` `${parentTitle || 'Untitled'} / ${meta.title || 'Untitled'}` ``.

`PageMentionMenu`'s existing `PageMentionItem`/`getPageMentionItems` types and click-routing (`kind: 'document' | 'drillable-document' | 'heading' | 'whole-document' | 'create'`, `docId`, `docUpdatedAt`) are unchanged — only each document-kind item's rendered `title` string now comes from `resolveDocPath` instead of the bare `meta.title`. Heading-kind items keep their existing plain heading text (no path — not a document, no collision concern).

`PageMentionRender`'s existing `resolveHeadingMentionText`/`headingCacheAtom`/`loadHeadings` logic (the existence check and cache invalidation from the heading-mentions feature) is entirely unchanged — this refinement only changes _how_ the already-resolved `resolvedHeadingText` renders, never whether it resolves.

## Error handling

No new failure modes. A document whose parent has been deleted (orphaned `parentId`) falls back to showing its plain title in the picker — same graceful-degradation posture as every other broken-reference case in this feature (missing docs, deleted headings).

## Testing

- `resolveDocPath`: unit tests — top-level document (no parent), nested document (parent found), orphaned `parentId` (parent not in the list) falls back to plain title.
- `PageMentionMenu` styling: no new unit tests (jsdom can't render BlockNote, same constraint as the rest of this feature) — the existing e2e assertions that read menu item text (`page-mention-item-*` testids) continue to pass unchanged, since only CSS classes move, not structure or testids.
- Pill separator/hover-reveal: extend `page-mention.test.tsx` to assert the rendered heading text now includes `#` instead of `→`. Testing the hidden-by-default/hover-revealed _visual_ state needs a `getComputedStyle`-based check, not `toBeVisible()`/`toHaveText()` — Playwright's `toHaveText()` reads `textContent` regardless of CSS visibility/collapsed grid tracks (the same class of gap as `toBeVisible()` not checking `opacity`, previously hit and documented for this project), so an e2e assertion needs to explicitly check the wrapper's computed `opacity`/`grid-template-columns` at rest vs. after `hover()`. A new `data-testid` on the heading-suffix wrapper (e.g. `page-mention-heading-suffix`) is added specifically so this check has a stable target.
- Existing e2e assertions in `e2e-tests/app.spec.ts` that check pill text with the old `"Doc → Heading"` format update to `"Doc #Heading"` (text-content checks pass regardless of the hover state, per the note above — no behavior change needed to those tests beyond the separator character itself).

## Out of scope (YAGNI)

- Grouping/section labels (`ComboboxGroup`/`ComboboxLabel`) in the picker — the user asked for visual polish to the existing flat list, not a new taxonomy.
- Full ancestor breadcrumb (more than one parent level) — explicitly rejected during design.
- Any change to the mention pill's own click/navigation behavior, the heading-existence cache, or the drill-down interaction mechanics from the heading-mentions feature — all untouched by this refinement.
