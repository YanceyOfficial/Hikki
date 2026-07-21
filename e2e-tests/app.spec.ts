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
