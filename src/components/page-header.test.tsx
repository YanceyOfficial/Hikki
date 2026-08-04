import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, vi } from 'vitest'

import { PageHeader } from '#components/page-header'
import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'
import type { Doc } from '#lib/types'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

// frimousse (the real emoji picker library, see page-header.tsx) fetches its
// emoji dataset from a CDN on mount. jsdom's global `fetch` would otherwise
// hit the real network from every test run, which is slow and
// non-deterministic in CI - so these two endpoints are stubbed with a tiny,
// real-shaped fixture (confirmed against frimousse's actual parsing logic in
// node_modules/frimousse/dist/index.js) covering just enough emoji to
// exercise real search: a "rocket" match and a decoy that shouldn't match it.
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

function fakeJsonResponse(body: unknown): Response {
  return {
    headers: { get: () => null },
    json: () => Promise.resolve(body)
  } as unknown as Response
}

beforeEach(() => {
  localStorage.clear()
  sessionStorage.clear()
  vi.stubGlobal(
    'fetch',
    vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/data.json'))
        return Promise.resolve(fakeJsonResponse(FIXTURE_EMOJI_DATA))
      if (url.endsWith('/messages.json'))
        return Promise.resolve(fakeJsonResponse(FIXTURE_EMOJI_MESSAGES))
      throw new Error(`unexpected fetch in test: ${url}`)
    })
  )
})

afterEach(() => {
  vi.unstubAllGlobals()
})

const doc = (over: Partial<Doc> = {}): Doc => ({
  schemaVersion: 1,
  id: 'd1',
  parentId: null,
  title: 'Title',
  icon: null,
  cover: null,
  blocks: [],
  threads: {},
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  deletedAt: null,
  ...over
})

test('title edits patch the doc', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc()} onPatch={onPatch} />)
  await userEvent.type(screen.getByTestId('doc-title'), '!')
  expect(onPatch).toHaveBeenCalledWith({ title: 'Title!' })
})

test('picking an emoji patches the icon and remove clears it', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc({ icon: '📝' })} onPatch={onPatch} />)
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  // frimousse's search input is a real <input type="search">, which carries
  // the implicit "searchbox" ARIA role - no custom testid needed.
  await userEvent.type(await screen.findByRole('searchbox'), 'rocket')
  // Each rendered emoji is a real <button>, but frimousse explicitly sets
  // role="gridcell" on it (its list is an ARIA grid: role="grid" >
  // role="row" > role="gridcell", confirmed in the library's source) and
  // aria-label to the emoji's label ("Rocket") - so this is the real,
  // library-native way to target one rendered result, not an invented testid.
  await userEvent.click(
    await screen.findByRole('gridcell', { name: /rocket/i })
  )
  expect(onPatch).toHaveBeenCalledWith({ icon: '🚀' })
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  await userEvent.click(await screen.findByTestId('doc-icon-remove'))
  expect(onPatch).toHaveBeenCalledWith({ icon: null })
})

test('searching for an emoji filters out non-matching results', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc()} onPatch={onPatch} />)
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  // Both fixture emoji are visible before any search narrows the list.
  await screen.findByRole('gridcell', { name: /grinning/i })
  await userEvent.type(await screen.findByRole('searchbox'), 'rocket')
  // frimousse debounces re-filtering, so the decoy's removal is asserted via
  // waitFor rather than a synchronous query (a bare query right after typing
  // can still see the pre-filter render and pass for the wrong reason).
  await waitFor(() =>
    expect(
      screen.queryByRole('gridcell', { name: /grinning/i })
    ).not.toBeInTheDocument()
  )
  expect(screen.getByRole('gridcell', { name: /rocket/i })).toBeInTheDocument()
})

test('cover renders from assetUrl and can be removed', async () => {
  const onPatch = vi.fn()
  render(<PageHeader doc={doc({ cover: 'c.png' })} onPatch={onPatch} />)
  const img = screen.getByTestId('doc-cover-image')
  expect(img).toHaveAttribute('src', expect.stringContaining('c.png'))
  await userEvent.click(screen.getByTestId('doc-cover-remove'))
  expect(onPatch).toHaveBeenCalledWith({ cover: null })
})

test('no cover -> add-cover control shown instead of image', () => {
  render(<PageHeader doc={doc()} onPatch={vi.fn()} />)
  expect(screen.queryByTestId('doc-cover-image')).not.toBeInTheDocument()
  expect(screen.getByTestId('doc-cover-add')).toBeInTheDocument()
})

test('failed cover upload is swallowed safely and does not patch', async () => {
  const spy = vi
    .spyOn(backend, 'importAsset')
    .mockRejectedValueOnce(new Error('disk full'))
  const onPatch = vi.fn()
  render(<PageHeader doc={doc()} onPatch={onPatch} />)
  const input = screen.getByTestId('doc-cover-input')
  await userEvent.upload(
    input,
    new File([new Uint8Array([1])], 'c.png', { type: 'image/png' })
  )
  await waitFor(() => expect(spy).toHaveBeenCalled())
  expect(onPatch).not.toHaveBeenCalled()
  expect(reportError).toHaveBeenCalledWith('HK-1004', { message: 'disk full' })
  spy.mockRestore()
})

test('cover input value resets after selection so the same file can be re-picked', async () => {
  render(<PageHeader doc={doc()} onPatch={vi.fn()} />)
  const input = screen.getByTestId('doc-cover-input') as HTMLInputElement
  await userEvent.upload(
    input,
    new File([new Uint8Array([1])], 'c.png', { type: 'image/png' })
  )
  await waitFor(() => expect(input.value).toBe(''))
})

test('shows a relative last-updated time', () => {
  render(
    <PageHeader
      doc={doc({ updatedAt: '2026-01-01T00:00:00Z' })}
      onPatch={vi.fn()}
    />
  )
  expect(screen.getByTestId('doc-updated-at')).toHaveTextContent(/\S/)
})
