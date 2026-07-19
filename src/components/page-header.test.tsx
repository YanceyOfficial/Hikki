import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { vi } from 'vitest'

import { PageHeader } from '#components/page-header'
import { backend } from '#lib/backend/index'
import type { Doc } from '#lib/types'

const doc = (over: Partial<Doc> = {}): Doc => ({
  schemaVersion: 1,
  id: 'd1',
  parentId: null,
  title: 'Title',
  icon: null,
  cover: null,
  blocks: [],
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
  await userEvent.click(await screen.findByTestId('doc-icon-option-🚀'))
  expect(onPatch).toHaveBeenCalledWith({ icon: '🚀' })
  await userEvent.click(screen.getByTestId('doc-icon-button'))
  await userEvent.click(await screen.findByTestId('doc-icon-remove'))
  expect(onPatch).toHaveBeenCalledWith({ icon: null })
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
  const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  const onPatch = vi.fn()
  render(<PageHeader doc={doc()} onPatch={onPatch} />)
  const input = screen.getByTestId('doc-cover-input')
  await userEvent.upload(
    input,
    new File([new Uint8Array([1])], 'c.png', { type: 'image/png' })
  )
  await waitFor(() => expect(spy).toHaveBeenCalled())
  expect(onPatch).not.toHaveBeenCalled()
  expect(errorSpy).toHaveBeenCalled()
  spy.mockRestore()
  errorSpy.mockRestore()
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
