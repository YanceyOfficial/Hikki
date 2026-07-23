import { expect, test } from '@playwright/test'

test('dashboard is the home route', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByTestId('dashboard-page')).toBeVisible()
  await expect(page.getByTestId('titlebar')).toBeVisible()
})

test('create, rename, and see the document in the sidebar', async ({
  page
}) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await expect(page).toHaveURL(/#\/doc\//)
  await page.getByTestId('doc-title').fill('My first note')
  await expect(
    page.getByTestId('doc-tree').getByText('My first note')
  ).toBeVisible()
})

test('delete moves the document out of the sidebar', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Doomed')
  const item = page.getByTestId('doc-tree').getByText('Doomed')
  await expect(item).toBeVisible()
  const docId = new URL(page.url()).hash.replace('#/doc/', '')
  await item.hover()
  await page.getByTestId(`doc-actions-${docId}`).click()
  await page.getByTestId(`doc-delete-${docId}`).click()
  await expect(item).not.toBeVisible()
  await expect(page.getByTestId('dashboard-page')).toBeVisible()
})

test('documents persist across in-page navigation', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Sticky')
  await page.getByTestId('nav-dashboard').click()
  await page.getByTestId('doc-tree').getByText('Sticky').click()
  await expect(page.getByTestId('doc-title')).toHaveValue('Sticky')
})

test('type in the editor and content survives navigation', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-title').fill('Editor doc')
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('Hello from BlockNote')
  await page.getByTestId('nav-dashboard').click()
  await page.getByTestId('doc-tree').getByText('Editor doc').click()
  await expect(page.getByTestId('editor')).toContainText('Hello from BlockNote')
})

test('slash menu opens in the editor', async ({ page }) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('/')
  await expect(
    page.locator('.bn-suggestion-menu, [class*="suggestionMenu"]').first()
  ).toBeVisible()
})

test('block-type suggestion menu flips upward instead of compressing near the bottom of a scrolled document', async ({
  page
}) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()

  // Enough short blocks to make the document taller than the viewport, so
  // the cursor lands near the bottom edge once scrolled all the way down -
  // the exact condition that used to trigger the bug: the block-type menu
  // compressed itself into the sliver of space below the cursor instead of
  // flipping to open above it, even with far more room available there.
  await page.keyboard.type(
    Array.from({ length: 40 }, (_, i) => `Filler line ${i + 1}`).join('\n')
  )

  await page.getByTestId('page-content').evaluate((el) => {
    el.scrollTop = el.scrollHeight
  })

  await page.keyboard.type('/')

  const menu = page.locator('#bn-suggestion-menu')
  await expect(menu).toBeVisible()

  const { menuRect, caretTop, viewportHeight } = await page.evaluate(() => {
    const menuEl = document.getElementById('bn-suggestion-menu')
    // The element floating-ui actually positions/sizes is the nearest
    // non-static ancestor, not `#bn-suggestion-menu` itself (that's just
    // the scrollable item list inside it) - see editor.tsx's
    // `chooseVerticalPlacement` doc comment for the full DOM structure.
    let floating: HTMLElement | null = menuEl
    while (floating && getComputedStyle(floating).position === 'static') {
      floating = floating.parentElement
    }
    const rect = (floating ?? menuEl!).getBoundingClientRect()
    const selection = window.getSelection()
    const caretRect =
      selection && selection.rangeCount > 0
        ? selection.getRangeAt(0).getBoundingClientRect()
        : null
    return {
      menuRect: { top: rect.top, bottom: rect.bottom },
      caretTop: caretRect?.top ?? null,
      viewportHeight: window.innerHeight
    }
  })

  expect(caretTop).not.toBeNull()
  // Stays fully within the viewport...
  expect(menuRect.top).toBeGreaterThanOrEqual(0)
  expect(menuRect.bottom).toBeLessThanOrEqual(viewportHeight + 1)
  // ...and specifically opened *above* the cursor rather than below it.
  expect(menuRect.bottom).toBeLessThanOrEqual((caretTop as number) + 1)
})

test('set a page icon from the picker', async ({ page }) => {
  // Hikki is offline-first: frimousse must resolve its emoji dataset from the
  // app's own locally self-hosted public/emojibase-data (see page-header.tsx's
  // `emojibaseUrl`), never its default cdn.jsdelivr.net fetch. Block that CDN
  // host outright so a regression back to the network default fails this test
  // (aborted request -> stuck loading spinner -> the assertions below time
  // out) instead of silently depending on a real, non-deterministic network
  // call that happened to succeed.
  await page.route('https://cdn.jsdelivr.net/**', (route) => route.abort())
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-icon-button').click()
  // frimousse's search input is a plain <input type="search">, exposed via
  // the implicit "searchbox" role; each rendered result is a real <button>
  // that frimousse gives role="gridcell" (its list is an ARIA grid) and an
  // aria-label of the emoji's name - "rocket" narrows real, live emoji data
  // down to a single match to click.
  await page.getByRole('searchbox').fill('rocket')
  await page.getByRole('gridcell', { name: 'Rocket' }).click()
  await expect(page.getByTestId('doc-icon-button')).toContainText('🚀')
})

test.describe('code block copy button', () => {
  // Chromium blocks the Clipboard API without an explicit grant; the app
  // itself needs no such permission from real users (a user-initiated click
  // satisfies the browser's own secure-clipboard-access check), this is only
  // needed so the automated click in this test can exercise the real
  // `navigator.clipboard.writeText` call instead of it silently rejecting.
  test.use({ permissions: ['clipboard-write'] })

  test('shows the copied state after copying a multi-line code block', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    // ``` + Enter is BlockNote's markdown shortcut that converts the
    // current block into a codeBlock; Enter again while inside it inserts a
    // soft line break (ProseMirror's codeBlock node is a `code: true` node,
    // so this never creates a new block).
    await page.keyboard.type('```')
    await page.keyboard.press('Enter')
    await page.keyboard.type('const greeting = "hello world";')
    await page.keyboard.press('Enter')
    await page.keyboard.type('console.log(greeting);')

    const copyButton = page.getByTestId('code-block-copy')
    await expect(copyButton).toBeVisible()
    await copyButton.click()
    await expect(copyButton).toHaveAttribute('aria-label', 'Copied')
  })
})

test('theme toggle switches the app between light and dark', async ({
  page
}) => {
  await page.goto('/')
  const toggle = page.getByTestId('theme-toggle')

  // next-themes' `attribute="class"` (theme-provider.tsx) writes the
  // *resolved* theme directly as `<html>`'s class - not an empty class in
  // light mode with "dark" merely added/removed. Playwright's own default
  // color-scheme emulation is "light", but reading the real starting class
  // here (rather than assuming "light") keeps this robust against that
  // default ever changing.
  const initialClass = await page.evaluate(
    () => document.documentElement.className
  )
  expect(['light', 'dark']).toContain(initialClass)

  await toggle.click()
  const nextClass = await page.evaluate(
    () => document.documentElement.className
  )
  expect(nextClass).not.toBe(initialClass)

  // The button's icon swaps with the theme too - title-bar.tsx renders Sun
  // once `resolvedTheme === 'dark'` (so clicking it again returns to light)
  // and Moon otherwise; confirmed live via the rendered lucide icon's own
  // `lucide-sun`/`lucide-moon` class (lucide-react always adds one).
  await expect(
    toggle.locator(nextClass === 'dark' ? 'svg.lucide-sun' : 'svg.lucide-moon')
  ).toBeVisible()

  await toggle.click()
  const finalClass = await page.evaluate(
    () => document.documentElement.className
  )
  expect(finalClass).toBe(initialClass)
})

test('code block: typing Python triggers real shiki syntax highlighting', async ({
  page
}) => {
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  // ```<language> + Enter is BlockNote's markdown shortcut for a fenced code
  // block *with* its language preset from the fence info string. This is
  // required, not cosmetic: confirmed live that a bare ``` (no language,
  // the technique the "code block copy button" tests above use) leaves the
  // new block's `language` prop as an empty string even with
  // `defaultLanguage: 'typescript'` configured in editor.tsx - BlockNote's
  // own shiki plugin explicitly skips highlighting (returns zero
  // decorations) whenever the resolved language is "", "text", "none",
  // "plaintext", or "txt", so a languageless fence renders as plain
  // unstyled text forever, never invisibly resolving to the default.
  await page.keyboard.type('```python')
  await page.keyboard.press('Enter')
  await page.keyboard.type('def add(a, b):')
  await page.keyboard.press('Enter')
  await page.keyboard.type('    return a + b')

  // Real shiki tokenization (via `prosemirror-highlight`'s shiki adapter -
  // confirmed both in its source and live in the rendered DOM) decorates
  // each token as its own `<span class="shiki" style="color: ...">` - a
  // coarse but reliable signal that highlighting actually fired, as opposed
  // to the code sitting there as plain, undecorated text.
  const tokens = editable.locator('pre code span.shiki')
  await expect(tokens.first()).toBeVisible()
  expect(await tokens.count()).toBeGreaterThan(5)
  await expect(editable.locator('pre code')).toContainText('def add(a, b):')
  await expect(editable.locator('pre code')).toContainText('return a + b')
})

test.describe('floating badges (table of contents and comments)', () => {
  // Both table-of-contents.tsx and comment-threads-sidebar.tsx are small
  // always-available floating toggle buttons (Notion-style), not gated
  // behind any breakpoint - so these run at Playwright's normal default
  // viewport, matching the app's real 1320px default window width.

  test('selecting text and adding a comment creates a thread', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Selectable phrase here')
    // Home then Shift+End selects the whole (single-line) block, the same
    // way a real user would drag-select it. BlockNote's own ctrl/cmd+A
    // instead progressively selects more of the surrounding document on
    // repeated presses (confirmed live), which isn't the same flow and
    // also needs a platform-specific modifier key name.
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    // BlockNote's default `FormattingToolbar` renders its `AddCommentButton`
    // automatically on a text selection, self-hiding unless a
    // `CommentsExtension` is registered (see editor.tsx's doc comment on
    // `extensions: [CommentsExtension(...)]`) - finding it here is itself
    // confirmation the real extension wiring is live, not a stand-in.
    const addComment = page.getByRole('button', { name: 'Add comment' })
    await expect(addComment).toBeVisible()
    await addComment.click()

    // The floating comment composer BlockNote opens is its own nested
    // BlockNote instance, rendered with a `bn-comment-editor` class
    // (confirmed live in the rendered DOM - it has no dedicated testid) and
    // auto-focused, so no extra click is needed before typing.
    const composer = page
      .locator('.bn-comment-editor [contenteditable="true"]')
      .first()
    await composer.click()
    await page.keyboard.type('This needs review')
    await page.getByRole('button', { name: 'Save' }).click()

    // BlockNote wraps the commented selection in a real
    // `<span class="bn-thread-mark" data-bn-thread-id="...">` - confirmed
    // live in the rendered DOM - which is the "thread indicator" left behind
    // in the editor body itself.
    const threadMark = editable.locator('.bn-thread-mark')
    await expect(threadMark).toContainText('Selectable phrase here')
    const threadId = await threadMark.getAttribute('data-bn-thread-id')

    // The same thread also renders as its own floating marker via
    // comment-threads-sidebar.tsx, portaled into document-page.tsx's
    // `comments-anchor` (see that component's doc comment) - the persistent
    // record of the thread that survives even if the inline mark above
    // didn't (BlockNote's own #1701, see comment-threads-sidebar.tsx). One
    // marker exists per thread (`comment-marker-${threadId}`), independently
    // positioned near that thread's real location in the document and
    // collapsed behind its own click-to-open popover - not a single shared
    // toggle for every thread in the document.
    const marker = page.getByTestId(`comment-marker-${threadId}`)
    await expect(marker).toBeVisible()
    await marker.click()
    const popover = page.getByTestId(`comment-marker-popover-${threadId}`)
    await expect(popover).toBeVisible()
    await expect(popover).toContainText('This needs review')
  })

  test('table of contents lists headings and scrolls to the clicked one', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    // "# " is BlockNote's markdown shortcut for a level-1 heading.
    // table-of-contents.tsx derives its outline directly from
    // `editor.document`'s `heading` blocks (BlockNote's heading blocks have
    // no dedicated testid), not by scanning the DOM for real heading tags -
    // see that file's doc comment. Enough filler paragraphs between the two
    // headings gives the document real scrollable height.
    await page.keyboard.type('# Heading one')
    await page.keyboard.press('Enter')
    await page.keyboard.type(
      Array.from({ length: 30 }, (_, i) => `Filler line ${i + 1}`).join('\n')
    )
    await page.keyboard.press('Enter')
    await page.keyboard.type('# Heading two')

    // The outline is collapsed behind its own floating toggle button by
    // default, so it must be opened before its contents are visible.
    await page.getByTestId('toc-toggle').click()
    const toc = page.getByTestId('table-of-contents')
    await expect(toc).toBeVisible()
    await expect(toc.getByRole('link', { name: 'Heading one' })).toBeVisible()
    await expect(toc.getByRole('link', { name: 'Heading two' })).toBeVisible()

    // Scroll all the way down first so "Heading one" (the very first block)
    // starts off-screen above the viewport, then confirm clicking its TOC
    // entry actually brings it back into view. `toBeInViewport()` reads the
    // heading's real, live intersection with the viewport (through
    // `page-content`'s own `overflow-y-auto` scrolling, per
    // table-of-contents.tsx's doc comment on why `scrollIntoView` is used
    // instead of `window.scrollTo`) rather than asserting any hardcoded
    // pixel position - the exact resting scroll offset isn't reliable to
    // predict, but "did it scroll into view" is.
    const headingOne = editable.getByRole('heading', { name: 'Heading one' })
    await page.getByTestId('page-content').evaluate((el) => {
      el.scrollTop = el.scrollHeight
    })
    await expect(headingOne).not.toBeInViewport()

    await toc.getByRole('link', { name: 'Heading one' }).click()
    await expect(headingOne).toBeInViewport()
  })
})
