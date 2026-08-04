import { act, renderHook } from '@testing-library/react'

import { useCopyToClipboard } from '#hooks/use-copy-to-clipboard'
import { reportError } from '#lib/errors'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

function stubClipboard(writeText: (text: string) => Promise<void>) {
  Object.assign(navigator, { clipboard: { writeText: vi.fn(writeText) } })
}

beforeEach(() => {
  vi.useFakeTimers()
  stubClipboard(() => Promise.resolve())
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

test('starts uncopied', () => {
  const { result } = renderHook(() => useCopyToClipboard())
  expect(result.current.copied).toBe(false)
})

test('writes the given text to the clipboard and flips to copied', async () => {
  const { result } = renderHook(() =>
    useCopyToClipboard({ resetDelayMs: 1000 })
  )

  await act(async () => {
    await result.current.copy('console.log(1)')
  })

  expect(navigator.clipboard.writeText).toHaveBeenCalledExactlyOnceWith(
    'console.log(1)'
  )
  expect(result.current.copied).toBe(true)
})

test('reverts to uncopied after the reset delay elapses', async () => {
  const { result } = renderHook(() =>
    useCopyToClipboard({ resetDelayMs: 1000 })
  )

  await act(async () => {
    await result.current.copy('x')
  })
  expect(result.current.copied).toBe(true)

  act(() => {
    vi.advanceTimersByTime(999)
  })
  expect(result.current.copied).toBe(true)

  act(() => {
    vi.advanceTimersByTime(1)
  })
  expect(result.current.copied).toBe(false)
})

test('a second copy before the delay elapses restarts the window', async () => {
  const { result } = renderHook(() =>
    useCopyToClipboard({ resetDelayMs: 1000 })
  )

  await act(async () => {
    await result.current.copy('a')
  })
  act(() => {
    vi.advanceTimersByTime(700)
  })

  await act(async () => {
    await result.current.copy('b')
  })
  act(() => {
    vi.advanceTimersByTime(700)
  })
  // 1400ms since the first copy (> the original 1000ms window) but only
  // 700ms since the second - should still read as copied.
  expect(result.current.copied).toBe(true)

  act(() => {
    vi.advanceTimersByTime(300)
  })
  expect(result.current.copied).toBe(false)
})

test('a failed clipboard write does not flip copied to true', async () => {
  stubClipboard(() => Promise.reject(new Error('denied')))

  const { result } = renderHook(() => useCopyToClipboard())

  await act(async () => {
    await result.current.copy('x')
  })

  expect(result.current.copied).toBe(false)
  expect(reportError).toHaveBeenCalledWith('HK-1007', { message: 'denied' })
})
