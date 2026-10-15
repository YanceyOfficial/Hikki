import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { CodeBlockHeader } from '../src/components/code-block-header'
import { CoverPicker } from '../src/page/cover-picker'

/** Failures the user should know about go to the app as coded reports (a toast), never raw text in the page. */
const reports = vi.hoisted(() => [] as { id: string; error: unknown }[])
vi.mock('../src/core/errors', async (original) => ({
  ...(await original<typeof import('../src/core/errors')>()),
  reportError: (id: string, error?: unknown) => void reports.push({ id, error })
}))

afterEach(() => {
  cleanup()
  reports.length = 0
  vi.unstubAllGlobals()
})

describe('reported failures', () => {
  it('a cover upload that fails is reported (uploadFailed), the page shows a short note, not the raw message', async () => {
    const failure = new Error('disk full at /Users/someone/secret')
    render(
      <CoverPicker
        current={null}
        onSelect={() => {}}
        onRemove={() => {}}
        onUpload={() => Promise.reject(failure)}
      />
    )
    fireEvent.click(screen.getByRole('tab', { name: 'Upload' }))
    const file = new File(['x'], 'a.png', { type: 'image/png' })
    const input = document.querySelector('input[type=file]') as HTMLInputElement
    await act(async () => {
      fireEvent.change(input, { target: { files: [file] } })
    })
    await waitFor(() => expect(reports).toEqual([{ id: 'uploadFailed', error: failure }]))
    expect(document.body.textContent).not.toContain('disk full')
    expect(screen.getByText('Couldn’t upload this picture.')).toBeTruthy()
  })

  it('a code block copy the clipboard refuses is reported (copyFailed)', async () => {
    const failure = new Error('denied')
    vi.stubGlobal('navigator', {
      ...navigator,
      clipboard: { writeText: () => Promise.reject(failure) }
    })
    render(
      <CodeBlockHeader language="js" editable onLanguage={() => {}} getText={() => 'let x = 1'} />
    )
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /Copy/u }))
    })
    await waitFor(() => expect(reports).toEqual([{ id: 'copyFailed', error: failure }]))
  })
})
