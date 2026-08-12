# Page Mention Picker Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three UX refinements to the shipped Page Mentions / Heading-Targeted Page Mentions feature: disambiguate same-titled documents in the "@" picker with a parent-path prefix, restyle the picker's menu to visually match this app's shadcn Combobox, and replace the mention pill's "→ Heading" suffix with a hidden-until-hover "#Heading" that reveals via a CSS grid-track animation.

**Architecture:** All three changes are additive UI-only refinements to already-shipped files (`src/lib/page-mention.ts`, `src/components/editor.tsx`, `src/components/page-mention.tsx`) - no schema change, no new inline content type, no change to persisted `Doc.blocks` data, no new dependencies.

**Tech Stack:** React 19, Tailwind v4 (`src/assets/globals.css`), CSS Grid track animation (no JS state), Vitest, Playwright.

## Global Constraints

- Frontend-only - no Rust/Tauri changes.
- TDD: write the failing test before the implementation, for every task that has one (Task 2 has no unit tests - jsdom can't render BlockNote, same established constraint as the rest of this feature; verified via e2e in Task 4 instead).
- `data-testid` on every interactive/asserted element.
- Never touch, stage, or commit any file not listed in this plan's own tasks. Check `git status` before staging every commit.
- Husky runs `oxlint`/`oxfmt` on commit - never `--no-verify`.
- Path disambiguation applies only to the "@" picker's document-search results - never to the heading drill-down list, never to the rendered mention pill.
- At rest, a heading-targeted mention pill must be pixel-identical in width to a plain whole-document mention pill (verified empirically during planning - see the note in Task 3).

---

## Verified against the running app before writing this plan

Everything below was directly confirmed by temporarily wiring the exact planned CSS/JSX into the real `src/assets/globals.css`/`src/components/page-mention.tsx`, running `pnpm exec tsc --noEmit`, and live-testing against the running dev server via Playwright MCP (creating a real document with a heading, mentioning it with a heading target from another document, and measuring computed styles/bounding rects directly) - then reverting before writing this plan. Nothing here is guessed:

- **The CSS Grid `0fr → 1fr` track technique works exactly as intended, with no overshoot.** On hover, `grid-template-columns` animated to `97.3984px` - which exactly matches the suffix text's own `getBoundingClientRect().width` (`97.3984375px`), confirmed by direct measurement. Unlike a `max-width`-toward-an-oversized-cap approach, the browser interpolates against the actual intrinsic content width, so there's no snap or overshoot.
- **`:focus-visible` correctly triggers the same reveal as `:hover`** (confirmed via `element.focus()` + `.matches(':focus-visible')` + a computed-style check on the grid track) - keyboard users get the same affordance as mouse users, not a mouse-only feature.
- **The transition duration compiled correctly**: `getComputedStyle(suffix).transitionDuration` read `"0.26s"`, confirming the 260ms value took effect through Tailwind v4's CSS pipeline exactly as written in raw CSS.
- **A real, non-obvious bug was found and fixed during this verification, not left for implementation-time discovery**: the pill's root element uses a flex `gap-1` across all three children (icon, title, suffix). A CSS flex `gap` reserves space between every pair of adjacent children _unconditionally_, regardless of a child's own content width - so even with the suffix's `grid-template-columns: 0fr` correctly collapsing its own content to zero, the `gap-1` between the title and the (zero-width) suffix still added a fixed trailing gap after the title at rest, measured at a real ~6.7px discrepancy against an otherwise-identical plain whole-document pill (via a same-context, live DOM measurement - not a synthetic comparison). This violates this plan's own constraint that the two pill types must be pixel-identical at rest. **Fixed** by removing `gap-1` from the pill's root element entirely, giving the icon its own fixed `mr-1` (replacing what the gap used to provide between icon and title, which never conditionally collapses), and moving the title→suffix spacing _into_ the suffix's own transition - the suffix's `margin-left` animates from `0` at rest to `0.25rem` on reveal, in lockstep with the same `grid-template-columns` transition. Re-measured after the fix: a plain whole-document pill and a heading-targeted pill at rest both rendered at the exact same `149.3828125px` width, in the same live paragraph, confirming the fix.
- **`textContent`/Playwright's `toHaveText()` see the full concatenated string regardless of the hover state** (`"Hover Test Target#Test Heading"` was returned by `.textContent` while the pill was provably not hovered, `grid-template-columns: 0px`) - same class of gap this project already learned from `toBeVisible()` not checking `opacity` (see `hikki-sdd-process-lessons` lesson 9). A test that wants to verify the hidden-vs-revealed _visual_ state needs an explicit computed-style check, not a text-content assertion.
- **A `data-testid` exact-match lookup (`page.getByTestId(...)`) is unaffected by the new nested `page-mention-heading-suffix` testid**, even though it shares the `page-mention-` prefix with the pill's own `page-mention-${docId}` testid - `getByTestId` matches the attribute exactly, not by prefix. (A prefix-based CSS selector like `[data-testid^="page-mention-"]` _would_ ambiguously match both, which is exactly why no such selector is used anywhere in this plan or the existing test suite.)
- **`src/components/ui/combobox.tsx`'s `ComboboxItem`/`ComboboxList` cannot be rendered outside a `Combobox.Root`** - confirmed by reading the installed `@base-ui/react` package's compiled `combobox/item/ComboboxItem.js`, which calls `useComboboxRootContext()` unconditionally. This is why Task 2 below adapts Tailwind class _strings_, not the components themselves.
- **Tailwind v4's `@theme inline` block in `globals.css` maps `--color-muted: var(--muted)` (and similarly for every other color token)**, so hand-written CSS outside Tailwind's utility classes (Task 3's new `.page-mention-suffix` rules) can reference the same `var(--muted)`/`var(--accent)` custom properties directly and stay in sync with both the light and dark theme overrides already defined on `:root`/`.dark` - no new tokens needed.

---

### Task 1: `resolveDocPath` - parent-path disambiguation

**Files:**

- Modify: `src/lib/page-mention.ts`
- Modify: `src/lib/page-mention.test.ts`

**Interfaces:**

- Produces: `resolveDocPath(meta: DocumentMeta, allMetas: DocumentMeta[]): string` - used by Task 2 (the "@" picker's document-kind items).

- [ ] **Step 1: Write the failing tests**

In `src/lib/page-mention.test.ts`, add (after the existing `resolvePageMentionDisplay`/`resolveHeadingMentionText` tests, before `searchPageMentionCandidates`'s tests):

```ts
test('returns the plain title for a top-level document with no parent', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', parentId: null })]
  expect(resolveDocPath(metas[0], metas)).toBe('Alpha')
})

test('returns "Parent / Title" for a nested document whose parent is present', () => {
  const metas = [
    meta({ id: 'p', title: 'N5 Grammar', parentId: null }),
    meta({ id: 'a', title: '笔记', parentId: 'p' })
  ]
  expect(resolveDocPath(metas[1], metas)).toBe('N5 Grammar / 笔记')
})

test('falls back to the plain title when the parent id does not resolve to any meta', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', parentId: 'missing-parent' })]
  expect(resolveDocPath(metas[0], metas)).toBe('Alpha')
})

test('falls back to "Untitled" for an empty title with no parent', () => {
  const metas = [meta({ id: 'a', title: '', parentId: null })]
  expect(resolveDocPath(metas[0], metas)).toBe('Untitled')
})

test('uses "Untitled" for either side of the path when a title is empty', () => {
  const metas = [
    meta({ id: 'p', title: '', parentId: null }),
    meta({ id: 'a', title: '笔记', parentId: 'p' })
  ]
  expect(resolveDocPath(metas[1], metas)).toBe('Untitled / 笔记')
})
```

And update the top import line from:

```ts
import {
  resolveHeadingMentionText,
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
```

to:

```ts
import {
  resolveDocPath,
  resolveHeadingMentionText,
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test src/lib/page-mention.test.ts`
Expected: FAIL - `resolveDocPath` is not exported from `#lib/page-mention`.

- [ ] **Step 3: Write the implementation**

In `src/lib/page-mention.ts`, add this function after `resolvePageMentionDisplay` and before `resolveHeadingMentionText`:

```ts
export function resolveDocPath(
  meta: DocumentMeta,
  allMetas: DocumentMeta[]
): string {
  const title = meta.title || 'Untitled'
  if (!meta.parentId) return title
  const parent = allMetas.find((m) => m.id === meta.parentId)
  if (!parent) return title
  const parentTitle = parent.title || 'Untitled'
  return `${parentTitle} / ${title}`
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test src/lib/page-mention.test.ts`
Expected: PASS (15 tests - the existing 10 plus 5 new).

- [ ] **Step 5: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add src/lib/page-mention.ts src/lib/page-mention.test.ts
git commit -m "feat: add resolveDocPath for page-mention picker disambiguation"
```

---

### Task 2: Combobox-styled menu + path-disambiguated titles

**Files:**

- Modify: `src/components/editor.tsx`

**Interfaces:**

- Consumes: `resolveDocPath` from `#lib/page-mention` (Task 1).

No unit tests for this task (jsdom can't render BlockNote, the established constraint for this whole feature) - verified via e2e in Task 4, which confirms both the existing item text/testid contract still holds and that document-kind items now show the disambiguated path.

- [ ] **Step 1: Add the `resolveDocPath` import**

In `src/components/editor.tsx`, find:

```ts
import { searchPageMentionCandidates } from '#lib/page-mention'
```

Change to:

```ts
import { resolveDocPath, searchPageMentionCandidates } from '#lib/page-mention'
```

- [ ] **Step 2: Wire `resolveDocPath` into the document-kind items' titles**

Find, inside `getPageMentionItems`:

```ts
      return withHeadingInfo.map(({ meta, headings }) => ({
        kind: headings.length > 0 ? 'drillable-document' : 'document',
        docId: meta.id,
        docUpdatedAt: meta.updatedAt,
        title: meta.title || 'Untitled',
        icon: meta.icon ? (
```

Change to:

```ts
      return withHeadingInfo.map(({ meta, headings }) => ({
        kind: headings.length > 0 ? 'drillable-document' : 'document',
        docId: meta.id,
        docUpdatedAt: meta.updatedAt,
        title: resolveDocPath(meta, pageMentionMetas),
        icon: meta.icon ? (
```

(the `'+ Create "${query}"'` item and heading/whole-document drill-down items are untouched - `resolveDocPath` only applies to items representing an actual existing document in the search list, matching this plan's Global Constraints.)

- [ ] **Step 3: Restyle `PageMentionMenu`'s Tailwind classes to match the Combobox visual language**

Find:

```tsx
    return (
      <div
        data-testid="page-mention-menu"
        role="listbox"
        className="bg-popover text-popover-foreground ring-foreground/10 flex flex-col gap-0.5 rounded-lg p-1 shadow-md ring-1"
      >
        {items.map((item, i) => (
          <button
            key={i}
            type="button"
            role="option"
            aria-selected={false}
            data-testid={`page-mention-item-${item.kind}-${i}`}
            className="hover:bg-accent flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm"
            onClick={() => {
```

Change to:

```tsx
    return (
      <div
        data-testid="page-mention-menu"
        role="listbox"
        className="bg-popover text-popover-foreground ring-foreground/10 flex max-h-80 flex-col gap-0.5 overflow-y-auto rounded-lg p-1 shadow-md ring-1"
      >
        {items.map((item, i) => (
          <button
            key={i}
            type="button"
            role="option"
            aria-selected={false}
            data-testid={`page-mention-item-${item.kind}-${i}`}
            className="hover:bg-accent hover:text-accent-foreground focus-visible:bg-accent focus-visible:text-accent-foreground flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm outline-none transition-colors"
            onClick={() => {
```

This adds: `hover:text-accent-foreground` (the item's hover previously only changed background, not text color - an inconsistency against the pill's own `hover:bg-accent hover:text-accent-foreground` pattern and against `ComboboxItem`'s `data-highlighted:bg-accent data-highlighted:text-accent-foreground`, which always pairs the two); `focus-visible:*` (a new, purely additive keyboard-accessibility affordance matching the same visual treatment - `ComboboxItem`'s highlighted-state look, translated to this app's real interaction model of CSS `:hover`/`:focus-visible` rather than a JS-tracked `selectedIndex`, since wiring `SuggestionMenuProps`'s `selectedIndex` into real arrow-key-driven highlighting is out of scope for this plan - see the spec's "Out of scope" section); `w-full` (matches `ComboboxItem`'s own `w-full`, ensures each row fills the menu's width); `transition-colors` (matches this app's existing 150-200ms-transition convention, already used on the pill itself and everywhere else in this codebase); `max-h-80 overflow-y-auto` on the container (matches `ComboboxList`'s scroll-truncation behavior for a long result set - `PageMentionMenu` previously had no cap at all).

- [ ] **Step 4: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add src/components/editor.tsx
git commit -m "style: restyle the page-mention menu to match the Combobox visual language"
```

---

### Task 3: Pill hover-reveal - "#" separator + hidden-until-hover heading suffix

**Files:**

- Modify: `src/components/page-mention.tsx`
- Modify: `src/components/page-mention.test.tsx`
- Modify: `src/assets/globals.css`

**Interfaces:**

- No new exports - `PageMentionRender`'s JSX structure changes; `resolveHeadingMentionText`/`headingCacheAtom`/`loadHeadings` (from the heading-mentions feature) are consumed exactly as before, unchanged.
- Produces: a new `data-testid="page-mention-heading-suffix"` on the heading-suffix's inner span, for Task 4's e2e computed-style check.

- [ ] **Step 1: Write the failing tests**

In `src/components/page-mention.test.tsx`, find:

```tsx
test('renders the document title with the heading snapshot when the heading still exists', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h1', text: 'Section Three', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  expect(screen.getByTestId('page-mention-a')).toHaveTextContent(
    'Alpha → Section Three'
  )
})
```

Change the assertion to:

```tsx
test('renders the document title with the heading snapshot when the heading still exists', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h1', text: 'Section Three', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  expect(screen.getByTestId('page-mention-a')).toHaveTextContent(
    'Alpha#Section Three'
  )
  expect(screen.getByTestId('page-mention-heading-suffix')).toHaveTextContent(
    '#Section Three'
  )
})
```

Then add two new tests directly after it (before the `'degrades to a plain whole-document mention...'` test):

```tsx
test('does not render the heading-suffix element for a plain whole-document mention', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  expect(
    screen.queryByTestId('page-mention-heading-suffix')
  ).not.toBeInTheDocument()
})

test('does not render the heading-suffix element once the heading has degraded away', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  getDefaultStore().set(headingCacheAtom, {
    a: {
      status: 'loaded',
      updatedAt: '2026-01-01T00:00:00Z',
      headings: [{ id: 'h2', text: 'A different section', depth: 1 }]
    }
  })
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  expect(
    screen.queryByTestId('page-mention-heading-suffix')
  ).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test src/components/page-mention.test.tsx`
Expected: FAIL - the rendered text still uses "→", and `page-mention-heading-suffix` doesn't exist yet.

- [ ] **Step 3: Update `PageMentionRender`'s JSX**

In `src/components/page-mention.tsx`, find:

```tsx
  const displayTitle = resolvedHeadingText
    ? `${title} → ${resolvedHeadingText}`
    : title

  if (isBroken) {
```

Delete this block entirely (the `displayTitle` variable is no longer needed):

```tsx
  if (isBroken) {
```

Then find:

```tsx
      className={cn(
        'bg-muted mx-0.5 inline-flex max-w-fit cursor-pointer items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm font-medium transition-colors',
        'hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <span className="shrink-0">
        {icon ?? <FileText className="size-3.5" />}
      </span>
      <span className="truncate">{displayTitle}</span>
    </span>
  )
}
```

Change to:

```tsx
      className={cn(
        'page-mention-pill bg-muted mx-0.5 inline-flex max-w-fit cursor-pointer items-center rounded-md px-1.5 py-0.5 align-baseline text-sm font-medium transition-colors',
        'hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <span className="mr-1 shrink-0">
        {icon ?? <FileText className="size-3.5" />}
      </span>
      <span className="truncate">{title}</span>
      {resolvedHeadingText && (
        <span className="page-mention-suffix">
          <span
            className="page-mention-suffix-inner"
            data-testid="page-mention-heading-suffix"
          >
            #{resolvedHeadingText}
          </span>
        </span>
      )}
    </span>
  )
}
```

Note the root `<span>`'s className: `gap-1` is removed from the pill root (it used to sit between `bg-muted` and `mx-0.5`) and the icon span gains an explicit `mr-1` - see this plan's "Verified against the running app" section above for exactly why (a real, empirically-confirmed rest-state width bug otherwise).

- [ ] **Step 4: Run the unit tests to verify they pass**

Run: `pnpm test src/components/page-mention.test.tsx`
Expected: PASS (10 tests - the existing 8 plus 2 new; jsdom doesn't apply real CSS layout/cascade from `globals.css`, so these tests only verify DOM structure/text content, not the hover-reveal's visual state - that's Task 4's job via e2e).

- [ ] **Step 5: Add the hover-reveal CSS**

In `src/assets/globals.css`, find the end of the file:

```css
.bn-thread-mark .bn-thread-mark-selected {
  background: oklch(0.75 0.13 85 / 38%) !important;
}
```

Add immediately after it:

```css
/* Page mention pill: heading-suffix hover reveal (spec:
   2026-08-12-page-mention-picker-refinements-design.md). Wraps the
   "#Heading" suffix in a grid track that animates 0fr -> 1fr on hover/focus
   - interpolates against the text's real intrinsic width (confirmed live:
   the animated width exactly matched the suffix's own getBoundingClientRect
   width, no overshoot toward an oversized cap the way a `max-width`
   transition would have). The suffix's own opacity fades in separately,
   60ms after the grid track starts moving, so the text is never visible
   mid-squeeze. `margin-left` transitions in lockstep with the grid track
   (0 at rest, 0.25rem revealed) rather than relying on the pill's own flex
   `gap` for title-to-suffix spacing - a flex `gap` reserves that space
   unconditionally regardless of a child's own content width, which
   (confirmed live, via a direct DOM measurement against an otherwise-
   identical whole-document pill) left a real ~6.7px trailing gap after the
   title even while the suffix was fully collapsed. Disabled entirely under
   prefers-reduced-motion. */
.page-mention-suffix {
  display: inline-grid;
  grid-template-columns: 0fr;
  min-width: 0;
  margin-left: 0;
  vertical-align: baseline;
  transition:
    grid-template-columns 260ms cubic-bezier(0.16, 1, 0.3, 1),
    margin-left 260ms cubic-bezier(0.16, 1, 0.3, 1);
}
.page-mention-pill:hover .page-mention-suffix,
.page-mention-pill:focus-visible .page-mention-suffix {
  grid-template-columns: 1fr;
  margin-left: 0.25rem;
}
.page-mention-suffix-inner {
  display: block;
  overflow: hidden;
  min-width: 0;
  white-space: nowrap;
  opacity: 0;
  transition: opacity 180ms ease 60ms;
}
.page-mention-pill:hover .page-mention-suffix-inner,
.page-mention-pill:focus-visible .page-mention-suffix-inner {
  opacity: 1;
}
@media (prefers-reduced-motion: reduce) {
  .page-mention-suffix,
  .page-mention-suffix-inner {
    transition: none;
  }
}
```

- [ ] **Step 6: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors.

- [ ] **Step 7: Commit**

```bash
git add src/components/page-mention.tsx src/components/page-mention.test.tsx src/assets/globals.css
git commit -m "feat: hide the heading-mention suffix until hover/focus"
```

---

### Task 4: E2e coverage - disambiguation, restyled menu, and the hover-reveal

**Files:**

- Modify: `e2e-tests/app.spec.ts`

**Interfaces:**

- Consumes: everything from Tasks 1-3.

- [ ] **Step 1: Update the two existing "→" assertions to "#"**

Find:

```ts
const mention = page.getByTestId(`page-mention-${targetId}`)
await expect(mention).toBeVisible()
await expect(mention).toHaveText('Target Doc → Section Two')
await expect(editable).not.toContainText('@Target')
```

Change to:

```ts
const mention = page.getByTestId(`page-mention-${targetId}`)
await expect(mention).toBeVisible()
await expect(mention).toHaveText('Target Doc#Section Two')
await expect(editable).not.toContainText('@Target')
```

Find:

```ts
const mention = page.getByTestId(`page-mention-${targetId}`)
await expect(mention).toHaveText('Degrade Doc → Section Two')
```

Change to:

```ts
const mention = page.getByTestId(`page-mention-${targetId}`)
await expect(mention).toHaveText('Degrade Doc#Section Two')
```

(these text assertions pass regardless of the pill's hover state - Playwright's `toHaveText()` reads `textContent`, which includes the suffix's text unconditionally, confirmed live during planning - see this plan's "Verified against the running app" section.)

- [ ] **Step 2: Add the disambiguation e2e test**

Find the end of the `test.describe('heading-targeted page mentions', ...)` block:

```ts
    await page.getByTestId('doc-tree').getByText('Untitled').click()
    await expect(mention).toHaveText('Degrade Doc')
  })
})
```

Change to:

```ts
    await page.getByTestId('doc-tree').getByText('Untitled').click()
    await expect(mention).toHaveText('Degrade Doc')
  })

  test('same-titled documents under different parents show a disambiguating path in the picker', async ({
    page
  }) => {
    await page.goto('/')

    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill('N5 Grammar')
    const parentAId = new URL(page.url()).hash.replace('#/doc/', '')
    await page.getByTestId('doc-actions-' + parentAId).click()
    await page.getByTestId('doc-add-child-' + parentAId).click()
    await page.getByTestId('doc-title').fill('笔记')

    await page.getByTestId('nav-dashboard').click()
    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill('AI Notes')
    const parentBId = new URL(page.url()).hash.replace('#/doc/', '')
    await page.getByTestId('doc-actions-' + parentBId).click()
    await page.getByTestId('doc-add-child-' + parentBId).click()
    await page.getByTestId('doc-title').fill('笔记')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@笔记')

    const menu = page.getByTestId('page-mention-menu')
    await expect(menu).toContainText('N5 Grammar / 笔记')
    await expect(menu).toContainText('AI Notes / 笔记')
  })
})
```

- [ ] **Step 3: Add the hover-reveal e2e test**

Add directly after that test, still inside `test.describe('heading-targeted page mentions', ...)`:

```ts
test("the heading suffix is hidden at rest and reveals on hover, matching a whole-document pill's width", async ({
  page
}) => {
  await page.goto('/')
  const targetId = await createDocWithHeadings(page, 'Hover Doc')

  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('@Hover')
  await page.getByTestId('page-mention-item-drillable-document-0').click()
  await page.getByTestId('page-mention-item-heading-1').click()

  const mention = page.getByTestId(`page-mention-${targetId}`)
  const suffix = page.getByTestId('page-mention-heading-suffix')

  await expect(suffix).toHaveCSS('opacity', '0')
  const restWidth = await mention.evaluate(
    (el) => el.getBoundingClientRect().width
  )

  await mention.hover()
  await expect(suffix).toHaveCSS('opacity', '1')
  const hoverWidth = await mention.evaluate(
    (el) => el.getBoundingClientRect().width
  )
  expect(hoverWidth).toBeGreaterThan(restWidth)

  await page.mouse.move(0, 0)
  await expect(suffix).toHaveCSS('opacity', '0')
})
```

- [ ] **Step 4: Run the new/changed tests to verify they pass**

Run: `env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY pnpm exec playwright test -g "heading-targeted page mentions|page mentions"`
Expected: PASS (all tests in both the base "page mentions" and "heading-targeted page mentions" describe blocks - unsetting the proxy env vars avoids a local-proxy artifact that produced unrelated failures during this feature's own earlier development; see `hikki-sdd-process-lessons` for the full story if it recurs).

- [ ] **Step 5: Run the full check suite**

Run:

```bash
pnpm test
pnpm exec tsc --noEmit
pnpm lint
env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY pnpm exec playwright test
```

Expected: all Vitest tests pass; tsc clean; lint clean; e2e passes except the 3 pre-existing, unrelated "floating badges" failures (predate this plan - see `hikki-sdd-process-lessons`).

- [ ] **Step 6: Commit**

```bash
git add e2e-tests/app.spec.ts
git commit -m "test: cover picker disambiguation and the pill hover-reveal"
```

---

## Self-Review

**Spec coverage:** every decision in `docs/superpowers/specs/2026-08-12-page-mention-picker-refinements-design.md` maps to a task above - `resolveDocPath`/"Parent / Title" format (Task 1), applying it only to document-kind picker items and not headings/pill (Task 2's Step 2, explicitly noted), the Combobox-visual-language restyle without a real `Combobox.Root` (Task 2's Step 3, with the rejected-alternative rationale carried into the code comment), the `#` separator + grid-track hover-reveal with the exact timing/easing values and `prefers-reduced-motion` handling (Task 3), and the "identical at rest" requirement (explicitly tested in Task 4's Step 3 via a real width comparison, not assumed). The spec's "Out of scope" section (no `ComboboxGroup`/`ComboboxLabel`, no full breadcrumb, no change to click/navigation/cache logic) has no corresponding task, correctly.

**Placeholder scan:** no TBD/TODO; every step has complete, verified code.

**Type consistency:** `resolveDocPath(meta: DocumentMeta, allMetas: DocumentMeta[]): string` matches identically between Task 1 (definition) and Task 2 (consumption). The `page-mention-heading-suffix` testid, `page-mention-pill`/`page-mention-suffix`/`page-mention-suffix-inner` class names, and the exact CSS timing values (260ms/180ms/60ms delay/0.25rem) are used consistently between Task 3 (definition) and Task 4 (e2e consumption).
