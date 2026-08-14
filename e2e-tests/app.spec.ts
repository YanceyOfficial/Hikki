import { expect, test, type Locator, type Page } from '@playwright/test'

/**
 * Selects a whole paragraph's text and drives BlockNote's "Add comment"
 * flow (same steps as the "selecting text and adding a comment" test below)
 * to completion - factored out because the clustering/wide-mode tests need
 * to create several comments in one document.
 *
 * Selects via `document.createRange`/`window.getSelection` (scoped to the
 * editor's own contenteditable) rather than `.click()` on the paragraph
 * plus Home/Shift+End: confirmed live that once an earlier thread in the
 * same document already has a floating marker/popover near the top of the
 * page (comment-threads-sidebar.tsx positions markers via
 * `coordsAtPos`/`fixed`, not in normal document flow), a plain mouse click
 * on a *later* paragraph can land on that still-rendered marker/popover
 * instead of the intended text, corrupting the selection. Building a Range
 * directly sidesteps hit-testing entirely and is otherwise indistinguishable,
 * at the ProseMirror level, from a real drag-selection.
 */
async function addCommentToLine(
  page: Page,
  editable: Locator,
  lineText: string,
  commentBody: string
) {
  await editable.evaluate((editorEl, text) => {
    const paragraphs = Array.from(editorEl.querySelectorAll('p'))
    const target = paragraphs.find((p) => p.textContent === text)
    if (!target) {
      throw new Error(`paragraph not found: ${text}`)
    }
    const range = document.createRange()
    range.selectNodeContents(target)
    const selection = window.getSelection()
    selection?.removeAllRanges()
    selection?.addRange(range)
  }, lineText)

  await page.getByRole('button', { name: 'Add comment' }).click()
  // Same nested BlockNote comment-composer instance the existing single-
  // comment test below uses - see its own comment for why there's no
  // dedicated testid and no extra click is needed before typing.
  const composer = page
    .locator('.bn-comment-editor [contenteditable="true"]')
    .first()
  await composer.click()
  await page.keyboard.type(commentBody)
  await page.getByRole('button', { name: 'Save' }).click()
  // Closes the just-saved thread's own popover (comment-threads-sidebar.tsx
  // leaves it open after Save) so it can't visually/functionally overlap
  // whatever paragraph this helper selects next.
  await page.keyboard.press('Escape')
}

/**
 * Selects an exact substring within a single paragraph line, via the same
 * `document.createRange`/`window.getSelection` technique as
 * `addCommentToLine` above - used by the Writing Tools partial-selection
 * regression test below to select just ONE WORD in the middle of a longer
 * sentence, rather than the whole line (`Home` -> `Shift+End`, as every
 * other Writing Tools test in this file does). BlockNote paragraphs with no
 * inline formatting render as a single text node, so `paragraph.firstChild`
 * is that node and plain `indexOf`/`length` arithmetic gives exact character
 * offsets into it.
 */
async function selectWordInLine(
  editable: Locator,
  lineText: string,
  word: string
) {
  await editable.evaluate(
    (editorEl, { lineText, word }) => {
      const paragraphs = Array.from(editorEl.querySelectorAll('p'))
      const target = paragraphs.find((p) => p.textContent === lineText)
      if (!target) {
        throw new Error(`paragraph not found: ${lineText}`)
      }
      const textNode = target.firstChild
      if (!textNode || textNode.nodeType !== Node.TEXT_NODE) {
        throw new Error('expected a single text node inside the paragraph')
      }
      const start = lineText.indexOf(word)
      if (start === -1) {
        throw new Error(`word "${word}" not found in line: ${lineText}`)
      }
      const range = document.createRange()
      range.setStart(textNode, start)
      range.setEnd(textNode, start + word.length)
      const selection = window.getSelection()
      selection?.removeAllRanges()
      selection?.addRange(range)
    },
    { lineText, word }
  )
}

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
  // frimousse (src/components/ui/emoji-picker.tsx) resolves its emoji dataset
  // from its own default cdn.jsdelivr.net URL (no self-hosting - see that
  // file's own history/comments). Route those two exact requests to a tiny,
  // deterministic fixture instead of letting them hit the real network, so
  // this test never depends on a real, non-deterministic CDN call succeeding
  // (matching the same fixture shape already used in page-header.test.tsx's
  // unit test).
  const FIXTURE_EMOJI_DATA = [
    {
      emoji: '🚀',
      group: 5,
      label: 'rocket',
      tags: ['space', 'launch'],
      version: 1
    },
    {
      emoji: '😀',
      group: 5,
      label: 'grinning face',
      tags: ['happy', 'smile'],
      version: 1
    }
  ]
  const FIXTURE_EMOJI_MESSAGES = {
    groups: [{ key: 'travel-places', order: 5, message: 'travel & places' }],
    subgroups: [{ key: 'country-flag', order: 999, message: 'country flag' }],
    skinTones: [
      { key: 'light', message: 'light skin tone' },
      { key: 'medium-light', message: 'medium-light skin tone' },
      { key: 'medium', message: 'medium skin tone' },
      { key: 'medium-dark', message: 'medium-dark skin tone' },
      { key: 'dark', message: 'dark skin tone' }
    ]
  }
  // The path segment below is a real, external fact (frimousse's default CDN
  // URL genuinely embeds the upstream npm package's name), not a leftover
  // reference to a local dependency - this app no longer installs or
  // self-hosts that package.
  await page.route(
    'https://cdn.jsdelivr.net/npm/emojibase-data@**/data.json',
    (route) => route.fulfill({ json: FIXTURE_EMOJI_DATA })
  )
  await page.route(
    'https://cdn.jsdelivr.net/npm/emojibase-data@**/messages.json',
    (route) => route.fulfill({ json: FIXTURE_EMOJI_MESSAGES })
  )
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

test.describe('page mentions ("/" > Link a doc)', () => {
  test('typing "/", picking "Link a doc", and selecting an existing document inserts a mention and navigates on click', async ({
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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Targ')
    await page.getByRole('option', { name: 'Target Document' }).click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toBeVisible()
    await expect(mention).toHaveText('Target Document')
    await expect(editable).not.toContainText('/Targ')

    await mention.click()
    await expect(page).toHaveURL(`#/doc/${targetId}`)
  })

  test('typing "/", picking "Link a doc", with no matches offers "+ Create", which creates and links a new document', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Brand New Doc')

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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Doomed')
    await page.getByRole('option', { name: 'Doomed Target' }).click()
    await expect(page.getByTestId(`page-mention-${targetId}`)).toBeVisible()

    await page.getByTestId(`doc-actions-${targetId}`).click()
    await page.getByTestId(`doc-delete-${targetId}`).click()

    const broken = page.getByTestId(`page-mention-broken-${targetId}`)
    await expect(broken).toBeVisible()
    await expect(broken).toHaveText('Doomed Target')
  })
})

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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Target')

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
    await expect(mention).toHaveText('Target Doc')
    await expect(mention).toHaveAttribute('href', /\?heading=/)
    await expect(editable).not.toContainText('/Target')
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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Escape')
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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Scroll')
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
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Degrade')
    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await page.getByTestId('page-mention-item-heading-2').click()

    const mention = page.getByTestId(`page-mention-${targetId}`)
    await expect(mention).toHaveText('Degrade Doc')
    await expect(mention).toHaveAttribute('href', /\?heading=/)

    // Delete just the target heading, leaving the document itself intact.
    await page.getByTestId('doc-tree').getByText('Degrade Doc').click()
    const targetEditable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    // `document-page.tsx` loads the target document's content asynchronously
    // after navigating to it - waiting for the heading to actually be
    // visible (a real, auto-retrying Playwright assertion) avoids racing
    // that load, unlike a bare `locator.evaluate()` below, which takes a
    // single snapshot with no retry and can run before BlockNote has
    // rendered any blocks at all.
    await expect(
      targetEditable.getByRole('heading', { name: 'Section Two' })
    ).toBeVisible()
    // Selects the whole heading block's text via `document.createRange`/
    // `window.getSelection` rather than Home/Shift+End keyboard navigation -
    // confirmed live that firing Home, Shift+End, and Backspace back-to-back
    // with no gaps races ProseMirror's own selection-state commit: the
    // Backspace can land before the Shift+End extension has actually been
    // applied, silently deleting nothing. This mirrors `addCommentToLine`'s
    // selection technique elsewhere in this file, which sidesteps the same
    // class of race.
    await targetEditable.evaluate((editorEl, text) => {
      const heading = Array.from(
        editorEl.querySelectorAll('[data-content-type="heading"]')
      ).find((el) => el.textContent === text)
      if (!heading) {
        throw new Error(`heading not found: ${text}`)
      }
      const range = document.createRange()
      range.selectNodeContents(heading)
      const selection = window.getSelection()
      selection?.removeAllRanges()
      selection?.addRange(range)
    }, 'Section Two')
    await page.keyboard.press('Backspace')

    // The heading deletion goes through the same 800ms-debounced autosave as
    // every other edit (document-page.tsx's `save`) - navigating away does
    // flush it immediately via that effect's cleanup, but the resulting
    // save -> refresh(docMetasAtom) -> heading-cache refetch chain still
    // needs a little real time to settle. Waiting out the debounce window
    // itself (rather than the flush-on-navigate race) keeps this
    // deterministic instead of depending on exactly how fast the click below
    // fires relative to the last keystroke.
    await page.waitForTimeout(1000)

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
    // Same 800ms-debounced-autosave race as the heading-deletion test above
    // - the title input visibly shows the typed value immediately, but the
    // save to the backend (what the "Link a doc" picker's search actually
    // reads) lags behind it. Confirmed live: without this wait, the child
    // doc's title reaches the backend as "" (empty), not "笔记".
    await page.waitForTimeout(1000)

    await page.getByTestId('nav-dashboard').click()
    await page.getByTestId('new-doc').click()
    await page.getByTestId('doc-title').fill('AI Notes')
    const parentBId = new URL(page.url()).hash.replace('#/doc/', '')
    await page.getByTestId('doc-actions-' + parentBId).click()
    await page.getByTestId('doc-add-child-' + parentBId).click()
    await page.getByTestId('doc-title').fill('笔记')
    await page.waitForTimeout(1000)

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('/')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('笔记')

    const menu = page.getByTestId('page-mention-menu')
    await expect(menu).toContainText('N5 Grammar / 笔记')
    await expect(menu).toContainText('AI Notes / 笔记')
  })

  test('the heading snapshot appears in a tooltip on hover, without resizing the pill itself', async ({
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
    await page.keyboard.type('See the note /')
    await page.getByRole('option', { name: 'Link a doc' }).click()
    await page.keyboard.type('Hover')
    await page.getByTestId('page-mention-item-drillable-document-0').click()
    await page.getByTestId('page-mention-item-heading-1').click()
    await page.keyboard.type(' for the pattern.')

    const mention = page.getByTestId(`page-mention-${targetId}`)
    // The heading snapshot no longer renders into the pill's own DOM at
    // all (a real Base UI tooltip, portaled elsewhere and only mounted
    // once triggered) - the pill's text and box size are unaffected by
    // hover, structurally, not just as a CSS side effect to guard against.
    await expect(mention).toHaveText('Hover Doc')
    await expect(mention).toHaveAttribute('href', /\?heading=/)

    await mention.hover()
    await expect(page.getByText('#Section One')).toBeVisible()
  })
})

test('code block: syntax highlighting re-colors every token after a live theme switch', async ({
  page
}) => {
  // Regression test for a bug where switching light/dark live (as opposed
  // to loading a fresh page already in the target mode) left a code
  // block's shiki tokens rendering in the *previous* mode's colors -
  // `prosemirror-highlight`'s `DecorationCache` only invalidates an entry
  // when a node's content changes, never when the highlighter/theme
  // changes, and recreating the BlockNote editor alone didn't reset it (see
  // editor.tsx's `isBridging` comment for the full root cause). This left
  // some tokens unreadable against the new background - full brightness for
  // scopes the old theme colored explicitly, unreadably dim for anything
  // that fell back to the old theme's now-mismatched default color.
  await page.goto('/')
  await page.getByTestId('settings-trigger').click()
  await page.getByTestId('appearance-mode-light').click()
  await page.keyboard.press('Escape')

  await page.getByTestId('new-doc').click()
  const editable = page
    .getByTestId('editor')
    .locator('[contenteditable="true"]')
    .first()
  await editable.click()
  await page.keyboard.type('```javascript')
  await page.keyboard.press('Enter')
  await page.keyboard.type('function debounce(func, wait) {')
  await page.keyboard.press('Enter')
  await page.keyboard.type('return func;')

  const firstToken = editable.locator('pre code span.shiki').first()
  await expect(firstToken).toBeVisible()
  const lightColor = await firstToken.evaluate(
    (el) => getComputedStyle(el).color
  )

  await page.getByTestId('settings-trigger').click()
  await page.getByTestId('appearance-mode-dark').click()
  await page.keyboard.press('Escape')

  await expect(editable.locator('pre code')).toContainText(
    'function debounce(func, wait) {'
  )
  await expect(editable.locator('pre code')).toContainText('return func;')
  await expect(firstToken).not.toHaveCSS('color', lightColor)
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

  test('nearby comments cluster into one marker; a distant comment stays separate', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()

    // Two adjacent lines land well under comment-threads-sidebar.tsx's
    // CLUSTER_DISTANCE_THRESHOLD (48px, see that file's doc comment for the
    // live-verified derivation), so their markers must merge into one
    // combined badge. Several filler paragraphs put "Gamma" 100px+ away,
    // comfortably past the threshold, so it must stay its own marker.
    await page.keyboard.type('Alpha line one')
    await page.keyboard.press('Enter')
    await page.keyboard.type('Beta line two')
    await page.keyboard.press('Enter')
    await page.keyboard.type(
      Array.from({ length: 8 }, (_, i) => `Filler paragraph ${i + 1}`).join(
        '\n'
      )
    )
    await page.keyboard.press('Enter')
    await page.keyboard.type('Gamma far away')

    await addCommentToLine(page, editable, 'Alpha line one', 'Alpha comment')
    await addCommentToLine(page, editable, 'Beta line two', 'Beta comment')
    await addCommentToLine(page, editable, 'Gamma far away', 'Gamma comment')

    // `data-thread-count` (comment-threads-sidebar.tsx's `ClusterMarker`) is
    // only ever rendered on the trigger button, never on its popover, so
    // this can't accidentally double-count popover content.
    const clusterMarker = page.locator('[data-thread-count="2"]')
    await expect(clusterMarker).toHaveCount(1)
    const soloMarker = page.locator('[data-thread-count="1"]')
    await expect(soloMarker).toHaveCount(1)

    await clusterMarker.click()
    const clusterPopover = page.locator(
      '[data-testid^="comment-marker-popover-"]'
    )
    await expect(clusterPopover).toContainText('Alpha comment')
    await expect(clusterPopover).toContainText('Beta comment')
    await expect(clusterPopover).not.toContainText('Gamma comment')
  })

  test.describe('wide window (comment cards expanded)', () => {
    // Comfortably above comment-threads-sidebar.tsx's WIDE_MODE_MIN_WIDTH
    // (1720px, see that file's doc comment for the full arithmetic) so every
    // thread renders as its own persistent card with no click needed,
    // instead of narrow mode's clustered, click-to-open markers.
    test.use({ viewport: { width: 1800, height: 900 } })

    test('wide windows expand every thread into its own card, collision-avoided and clear of the reading column', async ({
      page
    }) => {
      await page.goto('/')
      await page.getByTestId('new-doc').click()
      const editable = page
        .getByTestId('editor')
        .locator('[contenteditable="true"]')
        .first()
      await editable.click()

      // Same adjacent-lines setup as the clustering test above - close
      // enough to cluster in narrow mode - but wide mode must never merge
      // threads (see comment-threads-sidebar.tsx's doc comment on why:
      // merging would throw away per-thread granularity exactly when
      // there's screen space to show it). Beta's body is deliberately long
      // so its card is taller than `DEFAULT_EXPANDED_CARD_HEIGHT`, giving
      // `layoutExpandedCards`'s collision avoidance real work to do.
      await page.keyboard.type('Alpha line one')
      await page.keyboard.press('Enter')
      await page.keyboard.type('Beta line two')

      await addCommentToLine(page, editable, 'Alpha line one', 'Alpha comment')
      await addCommentToLine(
        page,
        editable,
        'Beta line two',
        'Beta comment with enough extra text to make this card noticeably ' +
          'taller than the default assumed height, so collision avoidance ' +
          'has real work to do pushing it clear of the card above.'
      )

      // No clustered badge exists at all in wide mode - every thread is its
      // own always-visible card (`ExpandedCards`, not `ClusteredMarkers`).
      await expect(page.locator('[data-thread-count]')).toHaveCount(0)
      const cards = page.getByTestId(/^comment-card-/)
      await expect(cards).toHaveCount(2)
      const alphaCard = cards.filter({ hasText: 'Alpha comment' })
      const betaCard = cards.filter({ hasText: 'Beta comment' })
      await expect(alphaCard).toBeVisible()
      await expect(betaCard).toBeVisible()

      // Collision avoidance: Beta's card must clear Alpha's card's measured
      // bottom edge rather than sitting at its own overlapping natural
      // position. Polled because card height comes from an async
      // `ResizeObserver` measurement (`useExpandedCardHeights`), not the
      // first render.
      await expect
        .poll(async () => {
          const alphaBox = await alphaCard.boundingBox()
          const betaBox = await betaCard.boundingBox()
          if (!alphaBox || !betaBox) return false
          return betaBox.y >= alphaBox.y + alphaBox.height
        })
        .toBe(true)

      // Neither card overlaps the reading column - the same squeeze
      // regression Task 11/19 already fixed once for the old wide-rail
      // design (see comment-threads-sidebar.tsx's `WIDE_MODE_MIN_WIDTH` doc
      // comment).
      const columnBox = await page.locator('.max-w-3xl').boundingBox()
      const alphaBox = await alphaCard.boundingBox()
      const betaBox = await betaCard.boundingBox()
      expect(columnBox).not.toBeNull()
      expect(alphaBox).not.toBeNull()
      expect(betaBox).not.toBeNull()
      expect(alphaBox!.x).toBeGreaterThanOrEqual(
        columnBox!.x + columnBox!.width
      )
      expect(betaBox!.x).toBeGreaterThanOrEqual(columnBox!.x + columnBox!.width)
    })
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

test.describe('Writing Tools', () => {
  /**
   * Configures a default provider/model - and, critically, an API key - via
   * Task 8's AI Settings dialog. `runAction` (writing-tools-popover.tsx)
   * refuses to start a stream at all without a saved default provider/model,
   * but there's a second, independent guard one layer down: `streamWritingTool`
   * (client.ts) short-circuits with a "No API key configured" error if
   * `backend.getApiKey(provider)` comes back null - which it always does in
   * MemoryBackend until `setApiKey` has been called. Confirmed live: with only
   * the provider/model configured (no key saved), Proofread never reaches the
   * faux model stream at all - it errors immediately on the missing key. The
   * key's actual value is never validated by the faux provider, so any
   * non-empty string works.
   */
  async function configureAiSettings(page: Page) {
    await page.getByTestId('settings-trigger').click()
    await page.getByTestId('settings-nav-ai').click()
    // Base UI's Select renders a trigger <button> (role="combobox"), not a
    // native <select> - open it, then click the matching option in the
    // portaled listbox, rather than Playwright's .selectOption() (native
    // <select>-only).
    await page.getByTestId('ai-settings-default-provider').click()
    await page.getByRole('option', { name: 'openai' }).click()
    await page.getByTestId('ai-settings-key-openai').fill('sk-test-key')
    await page.getByTestId('ai-settings-save-openai').click()
    await page.getByTestId('ai-settings-default-model').click()
    await page.getByRole('option').first().click()
    await page.keyboard.press('Escape')
  }

  /**
   * Scripts the dev/test-mode faux provider's next response (see models.ts's
   * `getAiModels()`) directly from the test, with no real network call and no
   * production-code testing seam. `#lib/ai/models`'s `__getFauxProviderForTesting()`
   * was built for exactly this - scripting responses via `.setResponses(...)` -
   * but it's a plain module export, meant to be reached by unit tests running
   * in the same JS process. From Playwright's separate browser process, a
   * dynamic `import()` of the same source path Vite's dev server already
   * served to the running page resolves to that *same* live module instance
   * (confirmed live: `__getFauxProviderForTesting()` doesn't throw its
   * "call getAiModels() first" guard, meaning it's the app's own already-
   * initialized singleton, not a fresh one) - so this reaches the real faux
   * handle already wired into the app's editor, not a disconnected copy.
   *
   * This matters because the faux provider's own default, un-scripted
   * behavior (confirmed by reading node_modules/@earendil-works/pi-ai's
   * dist/providers/faux.js directly, and live: proofreading with a valid key
   * but no scripted response) is an immediate, deterministic error - "No more
   * faux responses queued" (faux.js's `createFauxCore`'s `stream()`: an empty
   * `pendingResponses` array makes `pendingResponses.shift()` return
   * `undefined`, and `!step` builds and emits an error message reading
   * exactly that) - never some default echoed/placeholder text. Without
   * scripting a response, every Writing Tools action in this dev/e2e
   * environment ends in the popover's error phase, never its previewing
   * phase - which is what the "failed request" test below exercises directly,
   * and why the other two tests below need this helper to reach a real
   * preview at all.
   */
  async function scriptFauxResponse(page: Page, text: string) {
    await page.evaluate(async (responseText) => {
      const models = await import('/src/lib/ai/models.ts')
      models.__getFauxProviderForTesting().setResponses([
        {
          role: 'assistant',
          content: [{ type: 'text', text: responseText }],
          stopReason: 'stop'
        }
      ])
    }, text)
  }

  test('the Writing Tools popover is genuinely visible when opened', async ({
    page
  }) => {
    // Regression test for a bug where the popover rendered into the DOM
    // (and passed `toBeVisible()`) but was actually invisible on screen -
    // `PopoverContent`'s underlying floating-ui `Positioner` element got
    // permanently stuck at its initial `opacity: 0; left: 0; top: 0`
    // placeholder state, because the `anchor` prop this popover requires
    // (it has no `PopoverTrigger`, since its own opener button lives in
    // BlockNote's floating formatting toolbar, not as a sibling) was being
    // silently dropped rather than forwarded to `Positioner`. Playwright's
    // `toBeVisible()` doesn't check CSS `opacity` (only `display`/
    // `visibility`/zero size), so that assertion alone can't catch this -
    // this test checks computed opacity directly instead.
    await page.goto('/')
    await page.getByTestId('new-doc').click()

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Some selected text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await page.getByTestId('writing-tools-button').click()

    const popover = page.getByTestId('writing-tools-popover')
    await expect(popover).toBeVisible()
    // The `opacity: 0` that hides the popover when floating-ui never
    // resolves a position lives on the Positioner element (Base UI's
    // `PopoverPrimitive.Positioner`, the popover's direct DOM parent) -
    // `getComputedStyle` doesn't propagate an ancestor's opacity into a
    // descendant's own computed value, so this has to check that specific
    // element, not the popover content node itself.
    await expect(popover.locator('xpath=..')).not.toHaveCSS('opacity', '0')
  })

  test('proofreading selected text streams a result and replaces it', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await configureAiSettings(page)

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('This sentance has a typo.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await scriptFauxResponse(page, 'This sentence has no typo.')

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()

    await expect(page.getByTestId('writing-tools-preview')).toBeVisible()
    await expect(page.getByTestId('writing-tools-replace')).toBeVisible({
      timeout: 10000
    })

    await page.getByTestId('writing-tools-replace').click()
    await expect(editable).toContainText('This sentence has no typo.')
    await expect(editable).not.toContainText('This sentance has a typo.')
  })

  test('discarding a result leaves the original text untouched', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await configureAiSettings(page)

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Keep this exact text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await scriptFauxResponse(page, 'A completely rewritten sentence.')

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-rewrite').click()
    await expect(page.getByTestId('writing-tools-discard')).toBeVisible({
      timeout: 10000
    })
    await page.getByTestId('writing-tools-discard').click()

    await expect(editable).toContainText('Keep this exact text.')
  })

  test('a failed request surfaces both the inline error and a toast', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await configureAiSettings(page)

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Keep this exact text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    // No scriptFauxResponse() call here - deliberately, to hit the faux
    // provider's own deterministic "no response queued" error (see
    // scriptFauxResponse's doc comment above) and confirm writing-tools-popover.tsx's
    // toast.error(...) call (alongside the pre-existing inline
    // writing-tools-error state) actually fires.
    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()

    await expect(page.getByTestId('writing-tools-error')).toContainText(
      'No more faux responses queued'
    )
    // Scoped to `data-type="error"` rather than the bare `[data-sonner-toast]`
    // selector: `configureAiSettings` above now also triggers its own
    // (still-visible) success toast from ai-section.tsx's Save button
    // (whole-branch-review Finding 3), so the unscoped selector would match
    // two toasts and fail Playwright's strict-mode single-match requirement.
    // The toast's own text is the fixed HK-3005 message from
    // `reportError` (Task 6's retrofit), not the raw per-instance error -
    // the dynamic detail ("No more faux responses queued") still reaches the
    // inline `writing-tools-error` state above and the structured log
    // context, just not the toast copy anymore.
    await expect(
      page.locator('[data-sonner-toast][data-type="error"]')
    ).toContainText('The Writing Tools request failed.')
    await expect(editable).toContainText('Keep this exact text.')
  })

  /**
   * Regression test for the whole-branch review's Finding 1 (critical,
   * data-loss bug): `editor.tsx`'s `openWritingTools()` used to send only
   * `editor.getSelectedText()` (the highlighted sub-range) to the AI, while
   * `onReplace` always replaces the FULL block(s) `editor.getSelection()`
   * captured - which, per BlockNote's own `getSelection()` source (see
   * editor.tsx's doc comment on `writingToolsSelection`), is the whole
   * paragraph even for a selection that only highlights one word inside it.
   * So Replace used to swap the entire paragraph for a new one containing
   * only the AI's rewrite of that one word, silently deleting everything
   * else in the paragraph. The fix sends the full captured block(s)' text
   * (`editor.blocksToMarkdownLossy(blocks)`) to the AI instead.
   *
   * Every other Writing Tools test in this file selects a whole line via
   * `Home` -> `Shift+End`, where the selected text and the full block's text
   * are identical - none of them can catch this bug. This test selects just
   * ONE WORD in the middle of a longer sentence instead.
   */
  test('proofreading a partial (mid-sentence) selection preserves the surrounding, unselected text', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await configureAiSettings(page)

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    const sentence = 'The quick brown fox jumps over the lazy dog.'
    await page.keyboard.type(sentence)

    // A genuine partial, within-block selection - just the word "brown" -
    // not a whole-line selection.
    await selectWordInLine(editable, sentence, 'brown')

    // Echoes back exactly the text that was actually sent to the AI as "the
    // text to work on" (`context.messages[0].content`, mirroring
    // `userMessageFor` in prompts.ts), rather than a canned reply -
    // `pendingResponses` entries in the faux provider can be functions of
    // the request `context` (see `node_modules/@earendil-works/pi-ai`'s
    // `dist/providers/faux.js`: `typeof step === "function" ? await
    // step(context, ...) : step`). Unlike `scriptFauxResponse` above, this
    // genuinely fails if the text sent to the AI ever regresses back to just
    // the highlighted sub-range: in that case this echoes back just
    // "brown", and Replace would leave only "brown" in the document.
    await page.evaluate(async () => {
      const models = await import('/src/lib/ai/models.ts')
      models.__getFauxProviderForTesting().setResponses([
        (context: { messages: { content: string }[] }) => ({
          role: 'assistant',
          content: [{ type: 'text', text: context.messages[0].content }],
          stopReason: 'stop'
        })
      ])
    })

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()
    await expect(page.getByTestId('writing-tools-replace')).toBeVisible({
      timeout: 10000
    })
    await page.getByTestId('writing-tools-replace').click()

    // If only the highlighted word had been captured and sent to the AI
    // (the bug), replacing the whole paragraph block with the echoed
    // response would leave just "brown" - silently deleting everything
    // else in the sentence.
    await expect(editable).toContainText('The quick')
    await expect(editable).toContainText('fox jumps over the lazy dog.')
  })

  /**
   * Regression test for the whole-branch review's Finding 2 (markdown-
   * producing transforms applied as plain text): the `table`/`list`/
   * `keyPoints` transform system prompts (`#lib/ai/prompts`) explicitly ask
   * the AI for markdown output, but `onReplace`/`onInsertBelow` used to wrap
   * the AI's raw text as a single hardcoded `{ type: 'paragraph', content:
   * text }` block - so a markdown bullet list like "- item 1\n- item 2" got
   * inserted as one paragraph of literal markdown syntax text, never as real
   * BlockNote list-item blocks. The fix parses the AI's output through
   * `editor.tryParseMarkdownToBlocks` first.
   */
  test('the "list" transform inserts real BlockNote list blocks, not literal markdown syntax', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('new-doc').click()
    await configureAiSettings(page)

    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Some content to turn into a list.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')

    await scriptFauxResponse(
      page,
      '- First point\n- Second point\n- Third point'
    )

    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-transform-list').click()
    await expect(page.getByTestId('writing-tools-replace')).toBeVisible({
      timeout: 10000
    })
    await page.getByTestId('writing-tools-replace').click()

    // Each bullet becomes its own real BlockNote list-item block
    // (`data-content-type="bulletListItem"`, confirmed against the
    // installed `@blocknote/core`'s block-rendering source,
    // `schema/blocks/internal.ts`'s `blockContent.setAttribute
    // ("data-content-type", blockType)`) - not one paragraph of literal
    // "- " markdown syntax, which is what the pre-fix code produced.
    await expect(
      editable.locator('[data-content-type="bulletListItem"]')
    ).toHaveCount(3)
    await expect(editable).toContainText('First point')
    await expect(editable).toContainText('Third point')
    await expect(editable).not.toContainText('- First point')
  })
})

test.describe('Settings dialog', () => {
  test('opens via the sidebar footer gear icon and navigates between sections', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('settings-trigger').click()
    await expect(page.getByTestId('settings-section-general')).toBeVisible()
    await page.getByTestId('settings-nav-ai').click()
    await expect(page.getByTestId('settings-section-ai')).toBeVisible()
  })

  test('opens via the ⌘, keyboard shortcut', async ({ page }) => {
    await page.goto('/')
    // Waits for a real, always-rendered element rather than firing the
    // keypress immediately after `goto` - `sidebar-left.tsx`'s keydown
    // listener is registered in a `useEffect`, which runs after React's
    // initial commit; without this wait the keypress can race that effect
    // under load (confirmed live: this test passed reliably in isolation
    // but flaked when run as part of the full suite).
    await expect(page.getByTestId('settings-trigger')).toBeVisible()
    // Not `page.keyboard.press('Meta+,')`: that combined shorthand is
    // unreliable for this specific OS-reserved combo in headless Chromium
    // specifically (confirmed live - the same shorthand passes in `--headed`
    // mode, and the real app itself opens Settings correctly on a genuine
    // Cmd+, keypress) - separate down/press/up calls dispatch it correctly
    // in both modes.
    await page.keyboard.down('Meta')
    await page.keyboard.press(',')
    await page.keyboard.up('Meta')
    await expect(page.getByTestId('settings-dialog')).toBeVisible()
  })

  test('Appearance mode buttons in the General section change the app theme', async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('settings-trigger').click()
    await expect(page.getByTestId('settings-section-general')).toBeVisible()
    await page.getByTestId('appearance-mode-dark').click()
    await expect(page.locator('html')).toHaveClass(/dark/)
    await page.getByTestId('appearance-mode-light').click()
    await expect(page.locator('html')).not.toHaveClass(/dark/)
  })

  test('Logs section shows entries, filters, and clears', async ({ page }) => {
    await page.goto('/')
    // Trigger at least one real logged event first - the missing-defaults
    // Writing Tools error path (writing-tools-popover.tsx's runAction) calls
    // reportError('HK-3005', ...) even before a real AI request is attempted,
    // since no AI settings have been configured in this fresh test session.
    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('Some text.')
    await page.keyboard.press('Home')
    await page.keyboard.down('Shift')
    await page.keyboard.press('End')
    await page.keyboard.up('Shift')
    await page.getByTestId('writing-tools-button').click()
    await page.getByTestId('writing-tools-proofread').click()
    await expect(page.getByTestId('writing-tools-error')).toBeVisible()

    await page.getByTestId('settings-trigger').click()
    await page.getByTestId('settings-nav-logs').click()
    await expect(page.getByTestId('log-row').first()).toBeVisible()
    await page.getByTestId('logs-clear').click()
    await expect(page.getByTestId('log-row')).toHaveCount(0)
  })
})

test.describe('Dashboard', () => {
  test('creating and editing a document updates the dashboard stats, chart, heatmap, and recent list', async ({
    page
  }) => {
    await page.goto('/')
    // Exact whole-tile text, not a substring: a bare toContainText('1')
    // would also pass against '15' or '1,024'. A \b word-boundary regex
    // can't express this either - a tile's text is its label glued to its
    // value ('Documents0'), so there's no boundary before the digit.
    await expect(page.getByTestId('stat-tile-total-documents')).toHaveText(
      /^Documents0$/
    )

    await page.getByTestId('new-doc').click()
    const editable = page
      .getByTestId('editor')
      .locator('[contenteditable="true"]')
      .first()
    await editable.click()
    await page.keyboard.type('one two three four five')
    // Same 800ms-debounced-autosave wait used elsewhere in this suite -
    // waits out the pending save rather than racing navigation against it.
    await page.waitForTimeout(1000)

    await page.getByTestId('nav-dashboard').click()
    await expect(page.getByTestId('stat-tile-total-documents')).toHaveText(
      /^Documents1$/
    )
    await expect(page.getByTestId('stat-tile-total-words')).toHaveText(
      /^Words written5$/
    )
    await expect(page.getByTestId('stat-tile-streak-days')).toHaveText(
      /^Day streak1$/
    )
    await expect(
      page.getByTestId('stat-tile-docs-edited-this-week')
    ).toHaveText(/^Edited this week1$/)
    await expect(page.getByTestId('dashboard-activity-chart')).toBeVisible()
    await expect(page.getByTestId('dashboard-heatmap')).toBeVisible()
    await expect(page.getByTestId('dashboard-recent-list')).toContainText(
      'Untitled'
    )
  })

  test("the dashboard's New document button creates a document and navigates to it", async ({
    page
  }) => {
    await page.goto('/')
    await page.getByTestId('dashboard-new-doc').click()
    await expect(page).toHaveURL(/#\/doc\//)
    await expect(page.getByTestId('doc-title')).toBeVisible()
  })
})
