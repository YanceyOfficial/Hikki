# Page Mentions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user type `@` inside the BlockNote editor to search the vault's own documents and insert a live-updating "page mention" pill that links to one of them.

**Architecture:** A new custom BlockNote inline content type, `pageMention`, added to the editor's schema (`src/components/editor.tsx`) alongside the existing `codeBlock` spec. A second `SuggestionMenuController` (`triggerCharacter="@"`) mirrors the existing `/`-triggered one. The mention stores only `{ docId }` - never a title snapshot - so its displayed title is always resolved live from `docMetasAtom` at render time.

**Tech Stack:** React 19, BlockNote (`@blocknote/core`'s `createReactInlineContentSpec` from `@blocknote/react`), Jotai, Vitest, Playwright.

## Global Constraints

- Frontend-only - no Rust/Tauri changes. `backend.createDocument(parentId, title)` already exists and is reused as-is.
- TDD: write the failing test before the implementation, for every task.
- `data-testid` on every interactive/asserted element (project convention, `CLAUDE.md`).
- Never touch, stage, or commit the user's own separate, currently-uncommitted `src/components/ui/*` component-library work or any other file not listed in this plan's tasks.
- Husky runs `oxlint`/`oxfmt` on commit - never `--no-verify`.
- All new inline content is inserted through `editor.insertInlineContent(...)` - never raw `Doc.blocks` mutation.

---

## Verified against the installed packages

Everything below was directly confirmed - either by reading the installed `@blocknote/core`/`@blocknote/react` `.d.ts` files and compiled source, or by temporarily wiring the exact code into `src/components/editor.tsx`, running `pnpm exec tsc --noEmit`, and live-testing the full `@` → search → insert → navigate → delete → broken flow against the running dev server. Nothing in this plan is guessed:

- `createReactInlineContentSpec(config, { render })` (from `@blocknote/react`) is the right primitive - it's the React counterpart to `@blocknote/core`'s `createInlineContentSpec` and internally wraps whatever `render` returns with BlockNote's own required DOM markup (`InlineContentWrapper`). The plan's `render` function does **not** need to call that wrapper itself.
- `content: 'none'` marks the node as a ProseMirror "atom" (confirmed in the compiled source: `atom: e.content === "none"`) - correct for a non-editable pill. `contentRef` (part of the render props) does not need to be attached to anything for this content type.
- Clicking a `SuggestionMenuController` item already clears the typed `@query` text and closes the menu automatically, **before** that item's own `onItemClick` runs (confirmed in the compiled source: the wrapper calls `closeMenu(); clearQuery();` before invoking the click handler). Each item's own `onItemClick` therefore only needs to insert content - it must not try to delete the query text itself. Confirmed live: typing `@Targ` and clicking a matching item left the paragraph as `"Hello "` followed by the mention pill, with no leftover `@Targ` text.
- Adding a custom `inlineContentSpecs` entry changes the editor's inferred schema type, which breaks the existing `Block[]` (imported from `@blocknote/core`, the _default_-schema type) annotation on `writingToolsSelection`'s state in `editor.tsx` - confirmed via `tsc`. Task 3 fixes this by switching that one annotation to a schema-derived type (`(typeof editor.document)[number][]`) instead of the generic import.
- `docMetasAtom` (already used by `src/lib/tree.ts`'s `buildTree`) retains soft-deleted documents with `deletedAt` set - only `buildTree`'s own filter removes them from the sidebar tree. This is why the broken-mention check in Task 1 must test `deletedAt` explicitly, not just "is this docId present at all". Confirmed live: deleting a mentioned document immediately (reactively, no reload) flipped its mention from a clickable pill to a plain, non-interactive one, because the render component reads `docMetasAtom` fresh on every render.

---

### Task 1: Pure page-mention resolution and search logic

**Files:**

- Create: `src/lib/page-mention.ts`
- Test: `src/lib/page-mention.test.ts`

**Interfaces:**

- Produces: `resolvePageMentionDisplay(docId: string, metas: DocumentMeta[]): PageMentionDisplay` where `PageMentionDisplay = { title: string; icon: string | null; isBroken: boolean }`.
- Produces: `searchPageMentionCandidates(query: string, metas: DocumentMeta[]): DocumentMeta[]`.
- Consumes: `DocumentMeta` from `#lib/types` (existing: `{ id, parentId, title, icon, createdAt, updatedAt, deletedAt }`).

- [ ] **Step 1: Write the failing tests**

Create `src/lib/page-mention.test.ts`:

```ts
import {
  resolvePageMentionDisplay,
  searchPageMentionCandidates
} from '#lib/page-mention'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta> = {}): DocumentMeta => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('resolves an alive document with its current title and icon', () => {
  const metas = [meta({ id: 'a', title: 'Alpha', icon: '📘' })]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Alpha',
    icon: '📘',
    isBroken: false
  })
})

test('falls back to "Untitled" for an alive document with an empty title', () => {
  const metas = [meta({ id: 'a', title: '' })]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Untitled',
    icon: null,
    isBroken: false
  })
})

test('renders a soft-deleted document as broken, keeping its last known title', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha', deletedAt: '2026-01-02T00:00:00Z' })
  ]
  expect(resolvePageMentionDisplay('a', metas)).toEqual({
    title: 'Alpha',
    icon: null,
    isBroken: true
  })
})

test('renders a docId with no matching meta at all as broken with a "Missing page" label', () => {
  expect(resolvePageMentionDisplay('does-not-exist', [])).toEqual({
    title: 'Missing page',
    icon: null,
    isBroken: true
  })
})

test('an empty query returns every alive document', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Beta' })
  ]
  expect(searchPageMentionCandidates('', metas).map((m) => m.id)).toEqual([
    'a',
    'b'
  ])
})

test('filters by a case-insensitive substring match on title', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Beta' })
  ]
  expect(searchPageMentionCandidates('AL', metas).map((m) => m.id)).toEqual([
    'a'
  ])
})

test('excludes soft-deleted documents from search results', () => {
  const metas = [
    meta({ id: 'a', title: 'Alpha' }),
    meta({ id: 'b', title: 'Alpha 2', deletedAt: '2026-01-02T00:00:00Z' })
  ]
  expect(searchPageMentionCandidates('Alpha', metas).map((m) => m.id)).toEqual([
    'a'
  ])
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test page-mention`
Expected: FAIL - `src/lib/page-mention.ts` does not exist yet (`Cannot find module '#lib/page-mention'` or similar).

- [ ] **Step 3: Write the implementation**

Create `src/lib/page-mention.ts`:

```ts
import type { DocumentMeta } from '#lib/types'

export interface PageMentionDisplay {
  title: string
  icon: string | null
  isBroken: boolean
}

export function resolvePageMentionDisplay(
  docId: string,
  metas: DocumentMeta[]
): PageMentionDisplay {
  const meta = metas.find((m) => m.id === docId)
  const isBroken = !meta || meta.deletedAt !== null
  return {
    title: meta ? meta.title || 'Untitled' : 'Missing page',
    icon: meta?.icon ?? null,
    isBroken
  }
}

export function searchPageMentionCandidates(
  query: string,
  metas: DocumentMeta[]
): DocumentMeta[] {
  const alive = metas.filter((m) => m.deletedAt === null)
  const q = query.trim().toLowerCase()
  if (q.length === 0) return alive
  return alive.filter((m) => m.title.toLowerCase().includes(q))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test page-mention`
Expected: PASS (8 tests).

- [ ] **Step 5: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors from these two files.

- [ ] **Step 6: Commit**

```bash
git add src/lib/page-mention.ts src/lib/page-mention.test.ts
git commit -m "feat: add pure page-mention resolution and search logic"
```

---

### Task 2: `pageMention` inline content spec and its render component

**Files:**

- Create: `src/components/page-mention.tsx`
- Test: `src/components/page-mention.test.tsx`

**Interfaces:**

- Consumes: `resolvePageMentionDisplay` from `#lib/page-mention` (Task 1). `docMetasAtom` from `#lib/store` (existing).
- Produces: `createPageMentionSpec(): InlineContentSpec` - passed into `BlockNoteSchema.create().extend({ inlineContentSpecs: { pageMention: createPageMentionSpec() } })` in Task 3.
- Produces: `PageMentionRender` (exported for direct unit testing) - a React component with the shape `(props: { inlineContent: { props: { docId: string } } }) => JSX.Element`.
- Every rendered pill carries `data-testid="page-mention-<docId>"` (resolved) or `data-testid="page-mention-broken-<docId>"` (broken), matching this app's existing per-item `data-testid` convention (e.g. `doc-item-<id>` in `src/components/doc-tree.tsx`).

- [ ] **Step 1: Write the failing tests**

Create `src/components/page-mention.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { getDefaultStore } from 'jotai'

import { PageMentionRender } from '#components/page-mention'
import { docMetasAtom } from '#lib/store'
import type { DocumentMeta } from '#lib/types'

const meta = (over: Partial<DocumentMeta> = {}): DocumentMeta => ({
  id: 'a',
  parentId: null,
  title: 'Alpha',
  icon: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

afterEach(() => {
  getDefaultStore().set(docMetasAtom, [])
})

test('renders the icon and title of a live document', () => {
  getDefaultStore().set(docMetasAtom, [
    meta({ id: 'a', title: 'Alpha', icon: '📘' })
  ])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  const pill = screen.getByTestId('page-mention-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(pill).toHaveTextContent('📘')
})

test('renders a fallback file icon when the document has none', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', icon: null })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  expect(screen.getByTestId('page-mention-a')).toBeInTheDocument()
})

test('renders a broken, non-clickable pill for a soft-deleted document', () => {
  getDefaultStore().set(docMetasAtom, [
    meta({ id: 'a', title: 'Alpha', deletedAt: '2026-01-02T00:00:00Z' })
  ])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  const pill = screen.getByTestId('page-mention-broken-a')
  expect(pill).toHaveTextContent('Alpha')
  expect(screen.queryByTestId('page-mention-a')).not.toBeInTheDocument()
})

test('renders a broken pill with a "Missing page" label for an unknown docId', () => {
  getDefaultStore().set(docMetasAtom, [])
  render(<PageMentionRender inlineContent={{ props: { docId: 'ghost' } }} />)
  expect(screen.getByTestId('page-mention-broken-ghost')).toHaveTextContent(
    'Missing page'
  )
})

test('clicking a resolved mention navigates via the hash router', () => {
  getDefaultStore().set(docMetasAtom, [meta({ id: 'a', title: 'Alpha' })])
  render(<PageMentionRender inlineContent={{ props: { docId: 'a' } }} />)
  window.location.hash = ''
  screen.getByTestId('page-mention-a').click()
  expect(window.location.hash).toBe('#/doc/a')
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm test page-mention`
Expected: FAIL - `src/components/page-mention.tsx` does not exist yet (`page-mention.ts` from Task 1 exists, but the component file doesn't).

- [ ] **Step 3: Write the implementation**

Create `src/components/page-mention.tsx`:

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm test page-mention`
Expected: PASS (13 tests total - 8 from Task 1, 5 new).

- [ ] **Step 5: Typecheck and lint**

Run: `pnpm exec tsc --noEmit && pnpm lint`
Expected: no new errors from these two files (the pre-existing, unrelated errors in `src/components/ui/scroll-area.tsx` and `src/components/writing-tools-popover.tsx` - part of separate, already-in-progress work - are not yours to fix).

- [ ] **Step 6: Commit**

```bash
git add src/components/page-mention.tsx src/components/page-mention.test.tsx
git commit -m "feat: add the pageMention inline content spec and render component"
```

---

### Task 3: Wire the "@" trigger into the editor, and cover the full flow with Playwright

**Files:**

- Modify: `src/components/editor.tsx`
- Modify: `e2e-tests/app.spec.ts`

**Interfaces:**

- Consumes: `createPageMentionSpec` from `#components/page-mention` (Task 2), `searchPageMentionCandidates` from `#lib/page-mention` (Task 1), `docMetasAtom`/`refreshDocsAtom` from `#lib/store` (existing), `backend` from `#lib/backend/index` (existing, already imported in `editor.tsx`).

Since jsdom cannot render BlockNote (existing project convention - see `CLAUDE.md`), this task has no separate Vitest step; its correctness is verified entirely through Playwright against the running app, which is the established pattern for every other editor-behavior change in this codebase (e.g. the existing `code block: typing Python triggers real shiki syntax highlighting` test in `e2e-tests/app.spec.ts`).

- [ ] **Step 1: Add the required imports to `src/components/editor.tsx`**

At the top of the file, change:

```ts
import {
  FormattingToolbar,
  FormattingToolbarController,
  getFormattingToolbarItems,
  SideMenuController,
  SuggestionMenuController,
  useCreateBlockNote
} from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { offset, shift, size, type Middleware } from '@floating-ui/react'
import { useTheme } from 'next-themes'
import { useEffect, useRef, useState } from 'react'
import { createHighlighter } from 'shiki'

import { CodeBlockCopyOverlay } from '#components/code-block-copy-overlay'
import { CommentThreadsSidebar } from '#components/comment-threads-sidebar'
```

to:

```ts
import {
  type DefaultReactSuggestionItem,
  FormattingToolbar,
  FormattingToolbarController,
  getFormattingToolbarItems,
  SideMenuController,
  SuggestionMenuController,
  useCreateBlockNote
} from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { offset, shift, size, type Middleware } from '@floating-ui/react'
import { useAtomValue, useSetAtom } from 'jotai'
import { FileText } from 'lucide-react'
import { useTheme } from 'next-themes'
import { useEffect, useRef, useState } from 'react'
import { createHighlighter } from 'shiki'

import { CodeBlockCopyOverlay } from '#components/code-block-copy-overlay'
import { CommentThreadsSidebar } from '#components/comment-threads-sidebar'
import { createPageMentionSpec } from '#components/page-mention'
import { searchPageMentionCandidates } from '#lib/page-mention'
import { docMetasAtom, refreshDocsAtom } from '#lib/store'
```

(leave every other existing import in that block unchanged - `#lib/backend/index`'s `backend` and `#lib/guess-language`'s `guessLanguage` are already imported further down and are reused as-is).

- [ ] **Step 2: Register the `pageMention` inline content spec in the schema**

Find (inside `useCreateBlockNote`'s options object):

```ts
      schema: BlockNoteSchema.create().extend({
        blockSpecs: {
          codeBlock: createCodeBlockSpec({
```

Change to:

```ts
      schema: BlockNoteSchema.create().extend({
        inlineContentSpecs: {
          pageMention: createPageMentionSpec()
        },
        blockSpecs: {
          codeBlock: createCodeBlockSpec({
```

- [ ] **Step 3: Fix `writingToolsSelection`'s type**

Adding a custom inline content type to the schema changes what `editor.getSelection()`/`editor.getTextCursorPosition()` return, so the existing `Block[]` annotation (imported from `@blocknote/core`, the _default_-schema type) no longer matches. Find:

```ts
const [writingToolsSelection, setWritingToolsSelection] = useState<{
  blocks: Block[]
  text: string
} | null>(null)
```

Change to:

```ts
const [writingToolsSelection, setWritingToolsSelection] = useState<{
  blocks: (typeof editor.document)[number][]
  text: string
} | null>(null)
```

(`editor` is already declared above this point in the component, from the `useCreateBlockNote` call in Step 2.)

- [ ] **Step 4: Add the `docMetasAtom`/`refreshDocsAtom` hooks and the `@`-menu's `getItems` function**

Immediately before the existing `const openWritingTools = () => {` line, add:

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

(the "+ Create" item's own `backend.createDocument` call deliberately has no local `try`/`catch` - matching the existing, established precedent in `src/components/sidebar-left.tsx`'s `createDoc`/`createChildDoc`, which also call `backend.createDocument` with no local error handling; a rejection surfaces through this app's existing `window.onunhandledrejection` → `HK-9001` funnel, the same as those two call sites.)

- [ ] **Step 5: Mount the second `SuggestionMenuController`**

Find the existing `/`-triggered `SuggestionMenuController` (it ends with its own closing `/>`, immediately followed by the `CommentThreadsSidebar` line):

```tsx
;<SuggestionMenuController
  triggerCharacter="/"
  shouldOpen={(state) =>
    !state.selection.$from.parent.type.isInGroup('tableContent')
  }
  floatingUIOptions={{
    useFloatingOptions: {
      middleware: [
        offset(10),
        chooseVerticalPlacement,
        shift(),
        size({
          apply({ elements, availableHeight }) {
            elements.floating.style.maxHeight = `${Math.max(0, availableHeight)}px`
          },
          padding: 10
        })
      ]
    }
  }}
/>
{
  /* Mitigates BlockNote's own #1701: the comment mark isn't part of
          the `Block[]` JSON model, so it doesn't survive a reload - this
          keeps every thread discoverable via `doc.threads` regardless.
          See comment-threads-sidebar.tsx's doc comment for the full story. */
}
;<CommentThreadsSidebar portalTarget={commentsPortalTarget} />
```

Insert a second controller between them:

```tsx
;<SuggestionMenuController
  triggerCharacter="/"
  shouldOpen={(state) =>
    !state.selection.$from.parent.type.isInGroup('tableContent')
  }
  floatingUIOptions={{
    useFloatingOptions: {
      middleware: [
        offset(10),
        chooseVerticalPlacement,
        shift(),
        size({
          apply({ elements, availableHeight }) {
            elements.floating.style.maxHeight = `${Math.max(0, availableHeight)}px`
          },
          padding: 10
        })
      ]
    }
  }}
/>
{
  /* "@" page-mention picker - reuses `chooseVerticalPlacement` (see
            its doc comment above) so it flips near the viewport edge the
            same way the "/" menu does. */
}
;<SuggestionMenuController
  triggerCharacter="@"
  getItems={getPageMentionItems}
  floatingUIOptions={{
    useFloatingOptions: {
      middleware: [
        offset(10),
        chooseVerticalPlacement,
        shift(),
        size({
          apply({ elements, availableHeight }) {
            elements.floating.style.maxHeight = `${Math.max(0, availableHeight)}px`
          },
          padding: 10
        })
      ]
    }
  }}
/>
{
  /* Mitigates BlockNote's own #1701: the comment mark isn't part of
          the `Block[]` JSON model, so it doesn't survive a reload - this
          keeps every thread discoverable via `doc.threads` regardless.
          See comment-threads-sidebar.tsx's doc comment for the full story. */
}
;<CommentThreadsSidebar portalTarget={commentsPortalTarget} />
```

- [ ] **Step 6: Typecheck**

Run: `pnpm exec tsc --noEmit`
Expected: no new errors (only the pre-existing, unrelated errors in `src/components/ui/scroll-area.tsx`/`src/components/writing-tools-popover.tsx`).

- [ ] **Step 7: Write the failing Playwright tests**

In `e2e-tests/app.spec.ts`, add (after the existing `code block: typing Python triggers real shiki syntax highlighting` test):

```ts
test.describe('page mentions ("@")', () => {
  test('typing "@" and selecting an existing document inserts a mention and navigates on click', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill('Target Document')
    const targetId = new URL(page.url()).hash.replace('#/doc/', '')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Hello ')
    await page.keyboard.type('@Targ')
    await page.getByRole('option', { name: 'Target Document' }).click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toBeVisible()
    await expect(mention).toHaveText('Target Document')
    await expect(editable).not.toContainText('@Targ')

    await mention.click()
    await expect(page).toHaveURL(`#/doc/${targetId}`)
  })

  test('typing "@" with no matches offers "+ Create", which creates and links a new document', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Brand New Doc')

    const createOption = page.getByRole('option', {
      name: '+ Create "Brand New Doc"'
    })
    await expect(createOption).toBeVisible()
    await createOption.click()

    await expect(
      page.getByTestId('doc-tree').getByText('Brand New Doc')
    ).toBeVisible()
    const newDocLink = editable.locator('[data-testid^="page-mention-"]')
    await expect(newDocLink).toHaveText('Brand New Doc')
  })

  test('deleting a mentioned document renders its mention as broken and non-clickable', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill('Doomed Target')
    const targetId = new URL(page.url()).hash.replace('#/doc/', '')

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('@Doomed')
    await page.getByRole('option', { name: 'Doomed Target' }).click()
    await expect(page.getByTestId(`page-mention-${targetId}`)).toBeVisible()

    await page.getByTestId(`doc-actions-${targetId}`).click()
    await page.getByTestId(`doc-delete-${targetId}`).click()

    const broken = page.getByTestId(`page-mention-broken-${targetId}`)
    await expect(broken).toBeVisible()
    await expect(broken).toHaveText('Doomed Target')
  })
})
```

- [ ] **Step 8: Run the Playwright tests to verify they fail**

Run: `pnpm e2e -g "page mentions"`
Expected: FAIL - typing `@` opens no menu yet (the `SuggestionMenuController` from Step 5 doesn't exist until you complete Steps 1-5 above).

_(If you're implementing Steps 1-5 and this test in the same pass, run this once after Step 5's edit instead, to confirm the tests pass rather than fail-first - either order is fine as long as the tests are seen to fail against the old code at some point before being seen to pass.)_

- [ ] **Step 9: Run the Playwright tests to verify they pass**

Run: `pnpm e2e -g "page mentions"`
Expected: PASS (3 tests).

- [ ] **Step 10: Run the full check suite**

Run:

```bash
pnpm test
pnpm exec tsc --noEmit
pnpm lint
pnpm e2e
```

Expected: all Vitest tests pass; typecheck shows only the pre-existing unrelated errors; lint clean; e2e passes except the 3 pre-existing, unrelated `floating badges (table of contents and comments)` failures (traced, in an earlier session, to the user's own separate in-progress Tooltip/Popover work - confirmed by reverting all editor/doc-tree changes and reproducing the identical failures, so they are not this plan's responsibility).

- [ ] **Step 11: Commit**

```bash
git add src/components/editor.tsx e2e-tests/app.spec.ts
git commit -m "feat: wire the @ page-mention picker into the editor"
```

---

## Self-Review

**Spec coverage:** every decision in `docs/superpowers/specs/2026-08-07-page-mention-design.md` §1 maps to a task above - Approach A (Task 2's `createReactInlineContentSpec`), `@` trigger (Task 3 Step 5), flat search (Task 1's `searchPageMentionCandidates`), icon+pill rendering (Task 2), live title (Task 2 reads `docMetasAtom` fresh every render, never stores a snapshot), broken/deleted handling (Task 1 + Task 2 + Task 3's e2e test), direct-click navigation (Task 2), "+ Create" (Task 3 Step 4 + its e2e test). §5's out-of-scope items (backlinks panel, re-pointing a mention, hierarchical picker) have no task - correctly, since they're explicitly excluded.

**Placeholder scan:** no TBD/TODO; every step has complete, verified code.

**Type consistency:** `PageMentionDisplay` (Task 1) is consumed identically in Task 2. `resolvePageMentionDisplay`/`searchPageMentionCandidates` names and signatures match between their Task 1 definition and every later usage. `createPageMentionSpec`/`PageMentionRender` names match between Task 2's definition and Task 3's import.
