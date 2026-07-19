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
  await page.goto('/')
  await page.getByTestId('new-doc').click()
  await page.getByTestId('doc-icon-button').click()
  await page.getByTestId('doc-icon-option-🚀').click()
  await expect(page.getByTestId('doc-icon-button')).toContainText('🚀')
})
