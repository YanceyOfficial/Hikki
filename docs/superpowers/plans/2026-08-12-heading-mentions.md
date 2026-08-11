# Heading-Targeted Page Mentions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an `@` mention optionally target a specific heading within a document (not just the whole document), extending the already-shipped Page Mentions feature.

**Architecture:** `pageMention`'s schema gains optional `headingId`/`headingText` props. A custom `suggestionMenuComponent` on the "@" `SuggestionMenuController` lets picking a document drill into its headings without closing the menu. A small heading cache (keyed by document id + `updatedAt`, so it self-invalidates on any save) backs both the picker's drill-down and the render-time "does this heading still exist" check. Navigation carries the target heading through the hash router as a query param, consumed by a bounded scroll-retry effect in `document-page.tsx`.

**Tech Stack:** React 19, BlockNote (`@blocknote/react`'s `createReactInlineContentSpec`, `SuggestionMenuController`'s `suggestionMenuComponent` override), Jotai, `react-router`'s `useSearchParams`, Vitest, Playwright.

## Global Constraints

- Frontend-only - no Rust/Tauri changes. `backend.loadDocument(docId)` already exists and is reused as-is.
- TDD: write the failing test before the implementation, for every task.
- `data-testid` on every interactive/asserted element.
- Never touch, stage, or commit the user's own separate, currently-uncommitted `src/components/ui/*` component-library work, or any other file not listed in this plan's tasks. Check `git status` before staging every commit.
- Husky runs `oxlint`/`oxfmt` on commit - never `--no-verify`.
- All new inline content is inserted through `editor.insertInlineContent(...)` - never raw `Doc.blocks` mutation.
- `headingText` is a one-time insertion-time snapshot - never re-derived or kept live. Do not "fix" this later; it's a deliberate, spec'd decision (§1 of the design doc).

---

## Verified against the installed packages and live behavior

Everything below was directly confirmed by temporarily wiring the exact planned code into the real files, running `pnpm exec tsc --noEmit`, and live-testing the full flow against the running dev server via Playwright (creating a document with three real headings, mentioning it from another document, drilling into its headings, filtering by typing, inserting, clicking through with a real scroll, deleting the target heading, and confirming the pill degrades) - then reverting those changes before writing this plan. Nothing here is guessed:

- **BlockNote's default suggestion-menu behavior blocks the "don't close the menu" flow.** Confirmed by reading the compiled `@blocknote/react` source: the wrapper around whatever renders the menu items always calls `closeMenu()` then `clearQuery()` immediately before invoking any item's `onItemClick`. A custom `suggestionMenuComponent` (`SuggestionMenuController`'s own documented prop, `FC<SuggestionMenuProps<T>>` where `SuggestionMenuProps<T> = { items: T[]; loadingState; selectedIndex; onItemClick?: (item: T) => void }`) is what lets a "drill into this document's headings" click update local state instead of calling the given `onItemClick` (which is what triggers close+clear) - reserving that call for genuinely final selections only. Confirmed live: clicking a document with headings correctly swapped the menu to that document's heading list without closing it or clearing the typed `@N5` text.
- **`SuggestionMenuProps<T>` does not include the raw query text.** The custom menu component needs to know "how much of the query was typed before drilling in" (so it can filter headings by whatever's typed _after_ that point) but has no direct prop for it. Solved by capturing the query into a `useRef` at the top of the `getItems` callback (which always runs before any render the click could come from) rather than trying to get it from the render component's props.
- **`atomFamily` from `jotai/utils` is deprecated in the installed version** (`[DEPRECATED] atomFamily is deprecated and will be removed in v3` - confirmed via the dev server's own console warning). The heading cache below is a single `atom<Record<docId, entry>>` instead - no new dependency, matches this app's existing plain-atom patterns (e.g. `docMetasAtom`), and needed no `jotai-family` addition.
- **BlockNote's `Props<PSchema>` requires every schema field explicitly at every `insertInlineContent` call site, even ones with a `default`.** A `default` only applies when _deserializing_ old persisted content missing that field - not when constructing a new one in code. Confirmed via `tsc`: every existing whole-document `editor.insertInlineContent([{type: 'pageMention', props: {docId}}])` call site breaks once `headingId`/`headingText` are added to the schema, and needs `headingId: '', headingText: ''` added explicitly.
- **The heading-existence cache must self-invalidate on document edits, or it silently goes stale.** A first version of the cache (keyed only by `docId`, cached forever once loaded) was confirmed live to leave a mention showing a _deleted_ heading as "still there" indefinitely within the same app session - nothing else ever told it to refetch. Fixed by keying cache entries against the target document's own `DocumentMeta.updatedAt` (already available via `docMetasAtom`, no extra fetch needed) and treating a cached entry as stale whenever the current `updatedAt` doesn't match what it was fetched at. Confirmed live: after this fix, deleting the target heading (leaving the document intact) correctly made the mention pill degrade to a plain whole-document mention on next render.
- **`extractTocItems` (`table-of-contents.tsx`) is pure, exported, and directly reusable** - no `#lib/*` file in this codebase currently imports from `#components/*`, so it's extracted into a new `src/lib/toc.ts` first (Task 1) rather than importing across that boundary; `table-of-contents.tsx` imports it back.
- **Scrolling to a heading in a just-navigated-to document needs a bounded retry, not an immediate attempt.** `heading-anchor-overlay.tsx`'s `HeadingAnchors` only paints real DOM anchors for the document currently mounted in `Editor`, on its own effect timing - the anchor for the target heading isn't guaranteed to exist in the DOM the instant `document-page.tsx`'s own document-load effect resolves. Confirmed live with a short `requestAnimationFrame` retry loop (bounded, not infinite - a heading that's genuinely gone is a silent no-op, per the design doc).

---

### Task 1: Extract `extractTocItems` into a shared `lib` module

**Files:**

- Create: `src/lib/toc.ts`
- Create: `src/lib/toc.test.ts`
- Modify: `src/components/table-of-contents.tsx`
- Modify: `src/components/table-of-contents.test.tsx`

**Interfaces:**

- Produces: `extractTocItems(blocks: unknown[]): TocItem[]` (`TocItem` from `react-fluid-toc`, `{id: string, text: string, depth: number}`) - used by Task 2's heading-mention cache and re-used by `table-of-contents.tsx` exactly as before.

This is a pure relocation (no behavior change) - `extractTocItems` currently lives in `table-of-contents.tsx`, but Task 2 needs it from a `#lib/*` file, and this codebase has no existing precedent for a `#lib/*` file importing from `#components/*`.

- [ ] **Step 1: Write the failing tests**

Create `src/lib/toc.test.ts`:

```ts
import { extractTocItems } from '#lib/toc'

const heading = (id: string, level: number, text: string) => ({
  id,
  type: 'heading',
  props: { level },
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

const paragraph = (id: string, text: string) => ({
  id,
  type: 'paragraph',
  props: {},
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

test('extracts heading text/depth and excludes non-heading blocks', () => {
  const items = extractTocItems([
    heading('h1', 1, 'Intro'),
    paragraph('p1', 'Just a paragraph'),
    heading('h2', 2, 'Details')
  ])
  expect(items).toEqual([
    { id: 'h1', text: 'Intro', depth: 1 },
    { id: 'h2', text: 'Details', depth: 2 }
  ])
})

test('walks nested children for headings inside container blocks', () => {
  const items = extractTocItems([
    {
      id: 'toggle1',
      type: 'toggleListItem',
      props: {},
      content: [{ type: 'text', text: 'Toggle', styles: {} }],
      children: [heading('nested-h', 3, 'Nested heading')]
    }
  ])
  expect(items).toEqual([{ id: 'nested-h', text: 'Nested heading', depth: 3 }])
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test src/lib/toc.test.ts`
Expected: FAIL - `src/lib/toc.ts` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `src/lib/toc.ts`:

```ts
import type { TocItem } from 'react-fluid-toc'

interface InlineContentNode {
  type?: unknown
  text?: unknown
  content?: unknown
}

interface BlockNode {
  id?: unknown
  type?: unknown
  props?: unknown
  content?: unknown
  children?: unknown
}

function extractText(content: unknown): string {
  if (!Array.isArray(content)) return ''
  return content
    .map((node) => {
      if (!node || typeof node !== 'object') return ''
      const { text, content: nested } = node as InlineContentNode
      if (typeof text === 'string') return text
      // Link inline content nests its own StyledText[] under `content`.
      if (Array.isArray(nested)) return extractText(nested)
      return ''
    })
    .join('')
}

/** Pure so it's independently unit-testable from the `FluidToc` rendering. */
export function extractTocItems(blocks: unknown[]): TocItem[] {
  const items: TocItem[] = []

  const walk = (list: unknown[]) => {
    for (const block of list) {
      if (!block || typeof block !== 'object') continue
      const { id, type, props, content, children } = block as BlockNode

      if (type === 'heading' && typeof id === 'string') {
        const level = (props as { level?: unknown } | undefined)?.level
        const text = extractText(content).trim()
        if (text.length > 0) {
          items.push({
            id,
            text,
            depth: typeof level === 'number' ? level : 1
          })
        }
      }

      if (Array.isArray(children) && children.length > 0) {
        walk(children)
      }
    }
  }

  walk(blocks)
  return items
}
```

- [ ] **Step 4: Update `table-of-contents.tsx` to import from the new module**

In `src/components/table-of-contents.tsx`, find:

```ts
import { ListTree } from 'lucide-react'
import { useRef } from 'react'
import { FluidToc, type TocItem } from 'react-fluid-toc'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
```

Change to:

```ts
import { ListTree } from 'lucide-react'
import { useRef } from 'react'
import { FluidToc, type TocItem } from 'react-fluid-toc'

import { Button } from '#components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import { extractTocItems } from '#lib/toc'
```

Then find and delete this whole block (the `extractTocItems` implementation that's now in `src/lib/toc.ts`), from `interface InlineContentNode {` through the closing `}` of `extractTocItems`:

```ts
interface InlineContentNode {
  type?: unknown
  text?: unknown
  content?: unknown
}

interface BlockNode {
  id?: unknown
  type?: unknown
  props?: unknown
  content?: unknown
  children?: unknown
}

function extractText(content: unknown): string {
  if (!Array.isArray(content)) return ''
  return content
    .map((node) => {
      if (!node || typeof node !== 'object') return ''
      const { text, content: nested } = node as InlineContentNode
      if (typeof text === 'string') return text
      // Link inline content nests its own StyledText[] under `content`.
      if (Array.isArray(nested)) return extractText(nested)
      return ''
    })
    .join('')
}

/** Pure so it's independently unit-testable from the `FluidToc` rendering. */
export function extractTocItems(blocks: unknown[]): TocItem[] {
  const items: TocItem[] = []

  const walk = (list: unknown[]) => {
    for (const block of list) {
      if (!block || typeof block !== 'object') continue
      const { id, type, props, content, children } = block as BlockNode

      if (type === 'heading' && typeof id === 'string') {
        const level = (props as { level?: unknown } | undefined)?.level
        const text = extractText(content).trim()
        if (text.length > 0) {
          items.push({
            id,
            text,
            depth: typeof level === 'number' ? level : 1
          })
        }
      }

      if (Array.isArray(children) && children.length > 0) {
        walk(children)
      }
    }
  }

  walk(blocks)
  return items
}
```

(everything else in the file - `tocItemsEqual`, `useStableTocItems`, `TableOfContents`, `SCROLL_OFFSET` - stays exactly as-is; only this one block moves out.)

- [ ] **Step 5: Move the two `extractTocItems`-testing tests out of `table-of-contents.test.tsx`**

In `src/components/table-of-contents.test.tsx`, find:

```ts
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { extractTocItems, TableOfContents } from '#components/table-of-contents'

const heading = (id: string, level: number, text: string) => ({
  id,
  type: 'heading',
  props: { level },
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

const paragraph = (id: string, text: string) => ({
  id,
  type: 'paragraph',
  props: {},
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

test('extracts heading text/depth and excludes non-heading blocks', () => {
  const items = extractTocItems([
    heading('h1', 1, 'Intro'),
    paragraph('p1', 'Just a paragraph'),
    heading('h2', 2, 'Details')
  ])
  expect(items).toEqual([
    { id: 'h1', text: 'Intro', depth: 1 },
    { id: 'h2', text: 'Details', depth: 2 }
  ])
})

test('walks nested children for headings inside container blocks', () => {
  const items = extractTocItems([
    {
      id: 'toggle1',
      type: 'toggleListItem',
      props: {},
      content: [{ type: 'text', text: 'Toggle', styles: {} }],
      children: [heading('nested-h', 3, 'Nested heading')]
    }
  ])
  expect(items).toEqual([{ id: 'nested-h', text: 'Nested heading', depth: 3 }])
})

test('opening the floating toggle reveals heading text and excludes the paragraph', async () => {
```

Change to:

```ts
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { TableOfContents } from '#components/table-of-contents'

const heading = (id: string, level: number, text: string) => ({
  id,
  type: 'heading',
  props: { level },
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

const paragraph = (id: string, text: string) => ({
  id,
  type: 'paragraph',
  props: {},
  content: [{ type: 'text', text, styles: {} }],
  children: []
})

test('opening the floating toggle reveals heading text and excludes the paragraph', async () => {
```

(the remaining three tests in this file - the floating-toggle test and the two "renders nothing" tests - are untouched.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `pnpm test toc table-of-contents`
Expected: PASS (2 tests in `toc.test.ts` + 3 tests in `table-of-contents.test.tsx` = 5 tests).

- [ ] **Step 7: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors.

- [ ] **Step 8: Commit**

```bash
git add src/lib/toc.ts src/lib/toc.test.ts src/components/table-of-contents.tsx src/components/table-of-contents.test.tsx
git commit -m "refactor: extract extractTocItems into a shared lib module"
```

---

### Task 2: Heading-mention cache

**Files:**

- Create: `src/lib/heading-mention-cache.ts`
- Test: `src/lib/heading-mention-cache.test.ts`

**Interfaces:**

- Consumes: `extractTocItems` from `#lib/toc` (Task 1). `backend.loadDocument(docId): Promise<Doc>` from `#lib/backend/index` (existing).
- Produces: `headingCacheAtom: Atom<Record<string, HeadingCacheEntry>>` and `loadHeadings(docId: string, updatedAt: string): Promise<TocItem[]>`, both used by Task 3 (render-time existence check) and Task 4 (the picker's drill-down).

- [ ] **Step 1: Write the failing tests**

Create `src/lib/heading-mention-cache.test.ts`:

```ts
import { getDefaultStore } from 'jotai'

import { headingCacheAtom, loadHeadings } from '#lib/heading-mention-cache'
import { backend } from '#lib/backend/index'
import type { Doc } from '#lib/types'

const doc = (over: Partial<Doc> = {}): Doc => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  schemaVersion: 1,
  cover: null,
  blocks: [],
  threads: {},
  ...over
})

beforeEach(() => {
  getDefaultStore().set(headingCacheAtom, {})
})

test('fetches and extracts headings from the document, caching the result', async () => {
  const heading = {
    id: 'h1',
    type: 'heading',
    props: { level: 1 },
    content: [{ type: 'text', text: 'Intro', styles: {} }],
    children: []
  }
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockResolvedValue(doc({ blocks: [heading] }))

  const headings = await loadHeadings('a', '2026-01-01T00:00:00Z')
  expect(headings).toEqual([{ id: 'h1', text: 'Intro', depth: 1 }])
  expect(spy).toHaveBeenCalledTimes(1)

  // Second call with the *same* updatedAt reuses the cache - no second fetch.
  await loadHeadings('a', '2026-01-01T00:00:00Z')
  expect(spy).toHaveBeenCalledTimes(1)

  spy.mockRestore()
})

test('refetches when the document has since been saved (a new updatedAt)', async () => {
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockResolvedValueOnce(
      doc({ blocks: [], updatedAt: '2026-01-01T00:00:00Z' })
    )
    .mockResolvedValueOnce(
      doc({ blocks: [], updatedAt: '2026-01-02T00:00:00Z' })
    )

  await loadHeadings('a', '2026-01-01T00:00:00Z')
  await loadHeadings('a', '2026-01-02T00:00:00Z')
  expect(spy).toHaveBeenCalledTimes(2)

  spy.mockRestore()
})

test('returns an empty list and does not throw when the fetch fails', async () => {
  const spy = vi
    .spyOn(backend, 'loadDocument')
    .mockRejectedValue(new Error('not found'))

  const headings = await loadHeadings('missing', '2026-01-01T00:00:00Z')
  expect(headings).toEqual([])

  spy.mockRestore()
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test heading-mention-cache`
Expected: FAIL - `src/lib/heading-mention-cache.ts` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `src/lib/heading-mention-cache.ts`:

```ts
import { atom, getDefaultStore } from 'jotai'

import { backend } from '#lib/backend/index'
import { extractTocItems } from '#lib/toc'
import type { TocItem } from 'react-fluid-toc'

type HeadingCacheEntry =
  | { status: 'loading'; updatedAt: string }
  | { status: 'loaded'; updatedAt: string; headings: TocItem[] }
  | { status: 'error'; updatedAt: string }

export const headingCacheAtom = atom<Record<string, HeadingCacheEntry>>({})

/**
 * `updatedAt` is the target document's own `DocumentMeta.updatedAt` -
 * already available to every caller via `docMetasAtom`, so passing it costs
 * nothing extra. A cached entry is only reused when it was fetched *at* the
 * document's current `updatedAt` - any save to that document (a heading
 * added, edited, or removed) changes `updatedAt`, which invalidates the
 * cache and forces a fresh fetch. Without this, a heading-targeted mention
 * would keep showing a deleted heading as "still there" forever within the
 * same app session, since nothing else would ever tell this cache to
 * refetch.
 */
export async function loadHeadings(
  docId: string,
  updatedAt: string
): Promise<TocItem[]> {
  const store = getDefaultStore()
  const existing = store.get(headingCacheAtom)[docId]
  if (existing?.status === 'loaded' && existing.updatedAt === updatedAt) {
    return existing.headings
  }

  store.set(headingCacheAtom, (prev) => ({
    ...prev,
    [docId]: { status: 'loading', updatedAt }
  }))
  try {
    const doc = await backend.loadDocument(docId)
    const headings = extractTocItems(doc.blocks)
    store.set(headingCacheAtom, (prev) => ({
      ...prev,
      [docId]: { status: 'loaded', updatedAt, headings }
    }))
    return headings
  } catch {
    store.set(headingCacheAtom, (prev) => ({
      ...prev,
      [docId]: { status: 'error', updatedAt }
    }))
    return []
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test heading-mention-cache`
Expected: PASS (3 tests).

- [ ] **Step 5: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add src/lib/heading-mention-cache.ts src/lib/heading-mention-cache.test.ts
git commit -m "feat: add the heading-mention cache"
```

---

### Task 3: Extend `pageMention`'s schema and rendering for heading targets

**Files:**

- Modify: `src/lib/page-mention.ts`
- Modify: `src/lib/page-mention.test.ts`
- Modify: `src/components/page-mention.tsx`
- Modify: `src/components/page-mention.test.tsx`

**Interfaces:**

- Consumes: `headingCacheAtom`/`loadHeadings` from `#lib/heading-mention-cache` (Task 2).
- Produces: `resolveHeadingMentionText(headingId: string, headingText: string, currentHeadingIds: string[]): string | null` in `#lib/page-mention` - the pure existence-check logic, used directly by `PageMentionRender` and independently unit-testable. `PageMentionRender`'s `inlineContent.props` type gains optional `headingId`/`headingText` fields. `createPageMentionSpec`'s `propSchema` gains `headingId`/`headingText`, both `{ default: '' }`.

- [ ] **Step 1: Write the failing tests for the pure resolution logic**

In `src/lib/page-mention.test.ts`, add (after the existing `resolvePageMentionDisplay` tests, before `searchPageMentionCandidates`'s tests):

```ts
test('resolves the heading snapshot text when the heading id is still present', () => {
  expect(resolveHeadingMentionText('h1', 'Section Three', ['h1', 'h2'])).toBe(
    'Section Three'
  )
})

test('resolves to null when the heading id is no longer present', () => {
  expect(
    resolveHeadingMentionText('h1', 'Section Three', ['h2', 'h3'])
  ).toBeNull()
})

test('resolves to null for an empty headingId (a plain whole-document mention)', () => {
  expect(resolveHeadingMentionText('', 'Section Three', ['h1'])).toBeNull()
})
```

And update the top import line from:

```ts
import {
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
```

to:

```ts
import {
  resolveHeadingMentionText,
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test src/lib/page-mention.test.ts`
Expected: FAIL - `resolveHeadingMentionText` is not exported from `#lib/page-mention`.

- [ ] **Step 3: Add `resolveHeadingMentionText` to `page-mention.ts`**

In `src/lib/page-mention.ts`, add this function before `searchPageMentionCandidates`:

```ts
export function resolveHeadingMentionText(
  headingId: string,
  headingText: string,
  currentHeadingIds: string[]
): string | null {
  if (!headingId) return null
  if (!currentHeadingIds.includes(headingId)) return null
  return headingText
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test src/lib/page-mention.test.ts`
Expected: PASS (11 tests - the existing 8 plus 3 new).

- [ ] **Step 5: Write the failing tests for the extended rendering**

In `src/components/page-mention.test.tsx`, add (after the existing tests, before the file ends) - these seed `headingCacheAtom` directly rather than mocking `backend.loadDocument`, matching how the existing tests seed `docMetasAtom` directly:

```ts
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

test('degrades to a plain whole-document mention when the heading no longer exists', () => {
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
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).not.toHaveTextContent('Section Three')
})

test('renders the plain whole-document mention while the heading cache has not loaded yet', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(
    <PageMentionRender
      inlineContent={{
        props: { docId: 'a', headingId: 'h1', headingText: 'Section Three' }
      }}
    />
  )
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).not.toHaveTextContent('Section Three')
})
```

And update the top imports from:

```tsx
import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'

import { PageMentionRender } from '#components/page-mention'
import { docMetasAtom } from '#lib/store'
import type { DocumentMeta } from '#lib/types'
```

to:

```tsx
import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'

import { PageMentionRender } from '#components/page-mention'
import { headingCacheAtom } from '#lib/heading-mention-cache'
import { docMetasAtom } from '#lib/store'
import type { DocumentMeta } from '#lib/types'
```

Also add a reset for `headingCacheAtom` alongside the existing `docMetasAtom` reset in `afterEach`:

```ts
afterEach(() => {
  getDefaultStore().set(docMetasAtom, [])
  getDefaultStore().set(headingCacheAtom, {})
})
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `pnpm test src/components/page-mention.test.tsx`
Expected: FAIL - `inlineContent.props` doesn't accept `headingId`/`headingText` yet, and the rendered text doesn't include the heading snapshot.

- [ ] **Step 7: Extend `PageMentionRender` and `createPageMentionSpec`**

In `src/components/page-mention.tsx`, change:

```tsx
import { createReactInlineContentSpec } from '@blocknote/react'
import { useAtomValue } from 'jotai'
import { FileText } from 'lucide-react'

import { resolvePageMentionDisplay } from '#lib/page-mention'
import { docMetasAtom } from '#lib/store'
import { cn } from '#lib/utils'

export function PageMentionRender(props: {
  inlineContent: { props: { docId: string } }
}) {
  const { docId } = props.inlineContent.props
  const metas = useAtomValue(docMetasAtom)
  const { title, icon, isBroken } = resolvePageMentionDisplay(docId, metas)

  if (isBroken) {
    return (
      <span
        data-testid={`page-mention-broken-${docId}`}
        className="bg-muted/60 text-muted-foreground decoration-muted-foreground/50 mx-0.5 inline-flex max-w-fit items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm line-through"
      >
        {title}
      </span>
    )
  }

  return (
    <span
      data-testid={`page-mention-${docId}`}
      role="link"
      tabIndex={0}
      onClick={() => {
        window.location.hash = `#/doc/${docId}`
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault()
          window.location.hash = `#/doc/${docId}`
        }
      }}
      className={cn(
        'bg-muted mx-0.5 inline-flex max-w-fit cursor-pointer items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm font-medium transition-colors',
        'hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <span className="shrink-0">
        {icon ?? <FileText className="size-3.5" />}
      </span>
      <span className="truncate">{title}</span>
    </span>
  )
}

export function createPageMentionSpec() {
  return createReactInlineContentSpec(
    {
      type: 'pageMention',
      propSchema: {
        docId: { default: '' }
      },
      content: 'none'
    } as const,
    {
      render: PageMentionRender
    }
  )
}
```

to:

```tsx
import { createReactInlineContentSpec } from '@blocknote/react'
import { useAtomValue } from 'jotai'
import { FileText } from 'lucide-react'
import { useEffect } from 'react'

import { headingCacheAtom, loadHeadings } from '#lib/heading-mention-cache'
import {
  resolveHeadingMentionText,
  resolvePageMentionDisplay
} from '#lib/page-mention'
import { docMetasAtom } from '#lib/store'
import { cn } from '#lib/utils'

export function PageMentionRender(props: {
  inlineContent: {
    props: { docId: string; headingId?: string; headingText?: string }
  }
}) {
  const { docId, headingId = '', headingText = '' } = props.inlineContent.props
  const metas = useAtomValue(docMetasAtom)
  const { title, icon, isBroken } = resolvePageMentionDisplay(docId, metas)
  const updatedAt = metas.find((m) => m.id === docId)?.updatedAt ?? ''

  const headingCache = useAtomValue(headingCacheAtom)[docId]
  useEffect(() => {
    if (headingId && !isBroken) void loadHeadings(docId, updatedAt)
  }, [docId, headingId, isBroken, updatedAt])
  const resolvedHeadingText =
    headingId &&
    headingCache?.status === 'loaded' &&
    headingCache.updatedAt === updatedAt
      ? resolveHeadingMentionText(
          headingId,
          headingText,
          headingCache.headings.map((h) => h.id)
        )
      : null

  const displayTitle = resolvedHeadingText
    ? `${title} → ${resolvedHeadingText}`
    : title

  if (isBroken) {
    return (
      <span
        data-testid={`page-mention-broken-${docId}`}
        className="bg-muted/60 text-muted-foreground decoration-muted-foreground/50 mx-0.5 inline-flex max-w-fit items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm line-through"
      >
        {title}
      </span>
    )
  }

  const hash = resolvedHeadingText
    ? `#/doc/${docId}?heading=${headingId}`
    : `#/doc/${docId}`

  return (
    <span
      data-testid={`page-mention-${docId}`}
      role="link"
      tabIndex={0}
      onClick={() => {
        window.location.hash = hash
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault()
          window.location.hash = hash
        }
      }}
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

export function createPageMentionSpec() {
  return createReactInlineContentSpec(
    {
      type: 'pageMention',
      propSchema: {
        docId: { default: '' },
        headingId: { default: '' },
        headingText: { default: '' }
      },
      content: 'none'
    } as const,
    {
      render: PageMentionRender
    }
  )
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `pnpm test src/components/page-mention.test.tsx`
Expected: PASS (8 tests - the existing 5 plus 3 new).

- [ ] **Step 9: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: `src/components/editor.tsx` will now show two errors - `Type '{ docId: string; }' is missing the following properties ... headingId, headingText` - at its two existing `editor.insertInlineContent([{type: 'pageMention', props: {docId}}])` call sites. **This is expected and is Task 4's job to fix, not this task's** - `pageMention`'s schema is stricter now (§ "Verified against the installed packages" above explains why `Props<PSchema>` requires every field explicitly), and `editor.tsx` is Task 4's file. Confirm no _other_ new errors appear.

- [ ] **Step 10: Commit**

```bash
git add src/lib/page-mention.ts src/lib/page-mention.test.ts src/components/page-mention.tsx src/components/page-mention.test.tsx
git commit -m "feat: extend pageMention with optional heading targets"
```

---

### Task 4: The "@" picker's heading drill-down

**Files:**

- Modify: `src/components/editor.tsx`

**Interfaces:**

- Consumes: `loadHeadings` from `#lib/heading-mention-cache` (Task 2); the extended `pageMention` props from Task 3.

Since jsdom cannot render BlockNote (existing project convention), this task has no separate Vitest step - it fixes the two `tsc` errors Task 3 introduced and adds the custom suggestion-menu component; correctness is verified via Playwright in Task 5, which covers the full "@" → drill-down → insert → click → scroll flow end to end. (Splitting the picker wiring from its own e2e coverage would leave this task with no way to verify its own correctness - Task 5 folds both together for exactly that reason, matching how the base Page Mentions plan handled its own editor.tsx wiring.)

- [ ] **Step 1: Fix the two existing `insertInlineContent` call sites**

In `src/components/editor.tsx`, inside `getPageMentionItems`, find:

```ts
        onItemClick: () => {
          editor.insertInlineContent([
            { type: 'pageMention', props: { docId: meta.id } }
          ])
        }
      }))
    }
    if (query.trim().length === 0) return []
    return [
      {
        title: `+ Create "${query}"`,
        onItemClick: async () => {
          const doc = await backend.createDocument(null, query)
          await refreshDocMetas()
          editor.insertInlineContent([
            { type: 'pageMention', props: { docId: doc.id } }
          ])
        }
      }
    ]
  }
```

Change to:

```ts
        onItemClick: () => {
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: meta.id, headingId: '', headingText: '' }
            }
          ])
        }
      }))
    }
    if (query.trim().length === 0) return []
    return [
      {
        title: `+ Create "${query}"`,
        onItemClick: async () => {
          const doc = await backend.createDocument(null, query)
          await refreshDocMetas()
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: doc.id, headingId: '', headingText: '' }
            }
          ])
        }
      }
    ]
  }
```

- [ ] **Step 2: Typecheck**

Run: `pnpm exec tsc --noEmit`
Expected: the two errors from Task 3's Step 9 are now gone.

- [ ] **Step 3: Add the `loadHeadings` import**

Find:

```ts
import { backend } from '#lib/backend/index'
import { guessLanguage } from '#lib/guess-language'
import { searchPageMentionCandidates } from '#lib/page-mention'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
```

Change to:

```ts
import { backend } from '#lib/backend/index'
import { guessLanguage } from '#lib/guess-language'
import { loadHeadings } from '#lib/heading-mention-cache'
import { searchPageMentionCandidates } from '#lib/page-mention'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
```

- [ ] **Step 4: Replace `getPageMentionItems` with the drill-down-aware version, and add `PageMentionMenu`**

Find the whole existing block from `const pageMentionMetas = useAtomValue(docMetasAtom)` through the end of `getPageMentionItems`'s closing `}`:

```ts
  const pageMentionMetas = useAtomValue(docMetasAtom)
  const refreshDocMetas = useSetAtom(refreshDocsAtom)

  const getPageMentionItems = async (
    query: string
  ): Promise<DefaultReactSuggestionItem[]> => {
    const matches = searchPageMentionCandidates(query, pageMentionMetas)
    if (matches.length > 0) {
      return matches.map((meta) => ({
        title: meta.title || 'Untitled',
        icon: meta.icon ? (
          <span>{meta.icon}</span>
        ) : (
          <FileText className="size-4" />
        ),
        onItemClick: () => {
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: meta.id, headingId: '', headingText: '' }
            }
          ])
        }
      }))
    }
    if (query.trim().length === 0) return []
    return [
      {
        title: `+ Create "${query}"`,
        onItemClick: async () => {
          const doc = await backend.createDocument(null, query)
          await refreshDocMetas()
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: doc.id, headingId: '', headingText: '' }
            }
          ])
        }
      }
    ]
  }
```

Replace with:

```ts
  const pageMentionMetas = useAtomValue(docMetasAtom)
  const refreshDocMetas = useSetAtom(refreshDocsAtom)

  // A `getItems`-returned item can be one of five kinds - the custom
  // `PageMentionMenu` below (needed because BlockNote's own default menu
  // component always closes the "@" session on any item click, incompatible
  // with "drilling into a document's headings without closing the menu" -
  // see the plan's "Verified against the installed packages" section)
  // decides per-kind whether to handle a click itself (`drillable-document`)
  // or hand it to the framework's own close+insert flow (every other kind).
  type PageMentionItem = DefaultReactSuggestionItem & {
    kind:
      | 'document'
      | 'drillable-document'
      | 'heading'
      | 'whole-document'
      | 'create'
    docId?: string
    docUpdatedAt?: string
  }

  const [drill, setDrill] = useState<{
    docId: string
    docTitle: string
    docUpdatedAt: string
    queryPrefixLength: number
  } | null>(null)
  // `getItems` always runs (and this ref is set) before any render the user
  // could click a "drill in" item from - `SuggestionMenuProps` doesn't
  // expose the raw query text to the render component directly, so this is
  // how `PageMentionMenu`'s click handler learns "what's been typed so far"
  // at the exact moment the user drills in.
  const latestQueryRef = useRef('')

  const getPageMentionItems = async (
    query: string
  ): Promise<PageMentionItem[]> => {
    latestQueryRef.current = query
    // A fresh "@" session's query can only ever grow from the point it was
    // drilled in at - if it's shorter than that, the previous session was
    // abandoned (Escape, clicked away) without resetting `drill`, and this
    // is actually a brand new session starting over. `setDrill` doesn't
    // affect the `drill` binding already captured by this running closure,
    // so `effectiveDrill` (not `drill`) is what the rest of this call uses.
    const isFreshSession =
      drill !== null && query.length < drill.queryPrefixLength
    if (isFreshSession) setDrill(null)
    const effectiveDrill = isFreshSession ? null : drill

    if (effectiveDrill) {
      const headingQuery = query
        .slice(effectiveDrill.queryPrefixLength)
        .toLowerCase()
      const cached = await loadHeadings(
        effectiveDrill.docId,
        effectiveDrill.docUpdatedAt
      )
      const filtered = cached.filter((h) =>
        h.text.toLowerCase().includes(headingQuery)
      )
      return [
        {
          kind: 'whole-document',
          docId: effectiveDrill.docId,
          title: `← ${effectiveDrill.docTitle} (whole document)`,
          onItemClick: () => {
            setDrill(null)
            editor.insertInlineContent([
              {
                type: 'pageMention',
                props: {
                  docId: effectiveDrill.docId,
                  headingId: '',
                  headingText: ''
                }
              }
            ])
          }
        },
        ...filtered.map((h) => ({
          kind: 'heading' as const,
          title: h.text,
          onItemClick: () => {
            setDrill(null)
            editor.insertInlineContent([
              {
                type: 'pageMention',
                props: {
                  docId: effectiveDrill.docId,
                  headingId: h.id,
                  headingText: h.text
                }
              }
            ])
          }
        }))
      ]
    }

    const matches = searchPageMentionCandidates(query, pageMentionMetas)
    if (matches.length > 0) {
      const withHeadingInfo = await Promise.all(
        matches.map(async (meta) => ({
          meta,
          headings: await loadHeadings(meta.id, meta.updatedAt)
        }))
      )
      return withHeadingInfo.map(({ meta, headings }) => ({
        kind: headings.length > 0 ? 'drillable-document' : 'document',
        docId: meta.id,
        docUpdatedAt: meta.updatedAt,
        title: meta.title || 'Untitled',
        icon: meta.icon ? (
          <span>{meta.icon}</span>
        ) : (
          <FileText className="size-4" />
        ),
        onItemClick: () => {
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: meta.id, headingId: '', headingText: '' }
            }
          ])
        }
      }))
    }
    if (query.trim().length === 0) return []
    return [
      {
        kind: 'create',
        title: `+ Create "${query}"`,
        onItemClick: async () => {
          const doc = await backend.createDocument(null, query)
          await refreshDocMetas()
          editor.insertInlineContent([
            {
              type: 'pageMention',
              props: { docId: doc.id, headingId: '', headingText: '' }
            }
          ])
        }
      }
    ]
  }

  function PageMentionMenu({
    items,
    onItemClick
  }: {
    items: PageMentionItem[]
    onItemClick?: (item: PageMentionItem) => void
  }) {
    return (
      <div
        data-testid="page-mention-menu"
        className="bg-popover text-popover-foreground flex flex-col gap-0.5 rounded-lg p-1 shadow-md ring-1 ring-foreground/10"
      >
        {items.map((item, i) => (
          <button
            key={i}
            type="button"
            data-testid={`page-mention-item-${item.kind}-${i}`}
            className="hover:bg-accent flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm"
            onClick={() => {
              if (item.kind === 'drillable-document' && item.docId) {
                setDrill({
                  docId: item.docId,
                  docTitle: item.title,
                  docUpdatedAt: item.docUpdatedAt ?? '',
                  // The query text at the moment of drilling in (e.g. "N5")
                  // - any further typing after this point narrows the
                  // heading list, not a fresh document search.
                  queryPrefixLength: latestQueryRef.current.length
                })
                return
              }
              onItemClick?.(item)
            }}
          >
            {item.icon}
            <span>{item.title}</span>
          </button>
        ))}
      </div>
    )
  }
```

- [ ] **Step 5: Wire `suggestionMenuComponent` into the "@" `SuggestionMenuController`**

Find:

```tsx
          <SuggestionMenuController
            triggerCharacter="@"
            getItems={getPageMentionItems}
            floatingUIOptions={{
```

Change to:

```tsx
          <SuggestionMenuController
            triggerCharacter="@"
            getItems={getPageMentionItems}
            suggestionMenuComponent={PageMentionMenu}
            floatingUIOptions={{
```

- [ ] **Step 6: Typecheck**

Run: `pnpm exec tsc --noEmit`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add src/components/editor.tsx
git commit -m "feat: add the @ picker's heading drill-down"
```

---

### Task 5: Navigation, scroll-to-heading, and end-to-end coverage

**Files:**

- Modify: `src/pages/document-page.tsx`
- Modify: `e2e-tests/app.spec.ts`

**Interfaces:**

- Consumes: everything from Tasks 1-4 - this task is the full, live-verified flow.

- [ ] **Step 1: Add `useSearchParams` and the scroll-to-heading effect**

In `src/pages/document-page.tsx`, find:

```tsx
import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router'
```

Change to:

```tsx
import { useSetAtom } from 'jotai'
import { useEffect, useMemo, useState } from 'react'
import { useParams, useSearchParams } from 'react-router'
```

Find:

```tsx
export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
```

Change to:

```tsx
export default function DocumentPage() {
  const { id } = useParams<{ id: string }>()
  const [searchParams] = useSearchParams()
  const headingId = searchParams.get('heading')
  const [doc, setDoc] = useState<Doc | null>(null)
  const [notFound, setNotFound] = useState(false)
```

Find:

```tsx
    return () => {
      active = false
      save.flush()
    }
  }, [id, save])
```

Change to:

```tsx
    return () => {
      active = false
      save.flush()
    }
  }, [id, save])

  // Scrolls to a heading-targeted mention's target once its real DOM anchor
  // exists - heading-anchor-overlay.tsx's `HeadingAnchors` only paints
  // anchors for the document currently mounted in the editor, so this can't
  // assume the id is present the instant `doc` loads; it isn't rendered
  // until Editor's own `useHeadingAnchors` effect runs on its next paint.
  // Polls a small, bounded number of frames rather than retrying forever -
  // if the id genuinely isn't there (heading deleted, stale link), this is
  // a silent no-op, the same outcome as a plain whole-document mention.
  useEffect(() => {
    if (!doc || !headingId) return
    let cancelled = false
    let attempts = 0
    const tryScroll = () => {
      if (cancelled) return
      const el = document.getElementById(headingId)
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'start' })
        return
      }
      attempts += 1
      if (attempts < 20) requestAnimationFrame(tryScroll)
    }
    tryScroll()
    return () => {
      cancelled = true
    }
  }, [doc, headingId])
```

- [ ] **Step 2: Typecheck**

Run: `pnpm exec tsc --noEmit`
Expected: clean.

- [ ] **Step 3: Write the failing Playwright tests**

In `e2e-tests/app.spec.ts`, add (after the existing `test.describe('page mentions ("@")', ...)` block from the base feature):

```ts
test.describe('heading-targeted page mentions', () => {
  async function createDocWithHeadings(page: Page, title: string) {
    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill(title)
    const docId = new URL(page.url()).hash.replace('#/doc/', '').split('?')[0]
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('# Section One')
    await page.keyboard.press('Enter')
    await page.keyboard.type('First section content.')
    await page.keyboard.press('Enter')
    await page.keyboard.type('# Section Two')
    await page.keyboard.press('Enter')
    await page.keyboard.type('Second section content.')
    return docId
  }

  test('drilling into a document with headings, filtering, and inserting shows the heading snapshot', async ({
    page
  }) => {
    await page.goto('/')
    const targetId = await createDocWithHeadings(page, 'Target Doc')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Target')

    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await expect(page.getByTestId('page-mention-menu')).toContainText(
      '← Target Doc (whole document)'
    )
    await expect(page.getByTestId('page-mention-menu')).toContainText(
      'Section One'
    )
    await expect(page.getByTestId('page-mention-menu')).toContainText(
      'Section Two'
    )

    await page.keyboard.type(' Two')
    await expect(page.getByTestId('page-mention-menu')).not.toContainText(
      'Section One'
    )
    await page.getByTestId('page-mention-item-heading-1').click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toBeVisible()
    await expect(mention).toHaveText('Target Doc → Section Two')
    await expect(editable).not.toContainText('@Target')
  })

  test('the "whole document" escape hatch inserts a plain mention with no heading', async ({
    page
  }) => {
    await page.goto('/')
    const targetId = await createDocWithHeadings(page, 'Escape Doc')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Escape')
    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await page.getByTestId('page-mention-item-whole-document-0').click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toHaveText('Escape Doc')
  })

  test('clicking a heading-targeted mention navigates and scrolls to that heading', async ({
    page
  }) => {
    await page.goto('/')
    const targetId = await createDocWithHeadings(page, 'Scroll Doc')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Scroll')
    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await page.getByTestId('page-mention-item-heading-1').click()

    await page.getByTestId(`page-mention-${targetId}`).click()
    await expect(page).toHaveURL(new RegExp(`#/doc/${targetId}\\?heading=`))
    await expect(
      page.getByRole('heading', { name: 'Section Two' })
    ).toBeInViewport()
  })

  test('deleting the target heading (document intact) degrades the mention to whole-document', async ({
    page
  }) => {
    await page.goto('/')
    const targetId = await createDocWithHeadings(page, 'Degrade Doc')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Degrade')
    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await page.getByTestId('page-mention-item-heading-1').click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toHaveText('Degrade Doc → Section Two')

    // Delete just the target heading, leaving the document itself intact.
    await page.getByTestId('doc-tree').getByText('Degrade Doc').click()
    const targetEditable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await targetEditable.getByRole('heading', { name: 'Section Two' }).click()
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')
    await page.keyboard.press('Backspace')
    await page.keyboard.press('Backspace')

    await page.getByTestId('doc-tree').getByText('Untitled').click()
    await expect(mention).toHaveText('Degrade Doc')
  })
})
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `pnpm e2e -g "heading-targeted page mentions"`
Expected: FAIL - `page-mention-menu`/`page-mention-item-*` testids don't exist yet without Task 4's wiring already in place. (If Tasks 1-4 are already done by the time this task runs, run this once to confirm PASS instead, per the same either-order note the base feature's plan used.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pnpm e2e -g "heading-targeted page mentions"`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the full check suite**

Run:

```bash
pnpm test
pnpm exec tsc --noEmit
pnpm lint
pnpm e2e
```

Expected: all Vitest tests pass; tsc clean; lint clean; e2e passes except the 3 pre-existing, unrelated `floating badges (table of contents and comments)` failures (predate this branch - traced in an earlier session to the user's own separate in-progress Tooltip/Popover work, confirmed by reverting all editor/doc-tree changes and reproducing the identical failures).

- [ ] **Step 7: Commit**

```bash
git add src/pages/document-page.tsx e2e-tests/app.spec.ts
git commit -m "feat: navigate and scroll to a heading-targeted mention's target"
```

---

## Self-Review

**Spec coverage:** every decision in `docs/superpowers/specs/2026-08-12-heading-mentions-design.md` §1 maps to a task above - continue-in-same-menu drill-down (Task 4's `PageMentionMenu`), heading-deleted-degrades-to-whole-document (Task 3's `resolveHeadingMentionText` + Task 5's dedicated e2e test), insert-time snapshot heading label (Task 3's `headingText` prop, never re-derived). §2/§3's architecture and data-flow (additive schema, `heading-mention-cache.ts`, `#/doc/:id?heading=` navigation) map to Tasks 2/3/4/5 respectively. §4's error handling (failed fetch treated as "no headings", bounded scroll retry) is in Task 2's `loadHeadings` catch branch and Task 5's `tryScroll` bound. §5's out-of-scope items (live heading label, multi-level breadcrumbs, re-pointing an existing mention) have no task - correctly, since they're explicitly excluded.

**Placeholder scan:** no TBD/TODO; every step has complete, verified code.

**Type consistency:** `resolveHeadingMentionText`, `loadHeadings`, `headingCacheAtom`, `extractTocItems` names and signatures match identically between their defining task and every later consuming task. `PageMentionItem`'s `kind` discriminant values (`document`/`drillable-document`/`heading`/`whole-document`/`create`) are used consistently in both `getPageMentionItems` and `PageMentionMenu`, and in the e2e tests' `data-testid` selectors (`page-mention-item-${kind}-${i}`).
