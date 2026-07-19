import { debounce } from '#lib/debounce'

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

test('collapses rapid calls into the last one', () => {
  const fn = vi.fn()
  const d = debounce(fn, 100)
  d('a')
  d('b')
  vi.advanceTimersByTime(99)
  expect(fn).not.toHaveBeenCalled()
  vi.advanceTimersByTime(1)
  expect(fn).toHaveBeenCalledExactlyOnceWith('b')
})

test('flush runs a pending call immediately', () => {
  const fn = vi.fn()
  const d = debounce(fn, 100)
  d('x')
  d.flush()
  expect(fn).toHaveBeenCalledExactlyOnceWith('x')
  vi.advanceTimersByTime(200)
  expect(fn).toHaveBeenCalledTimes(1)
})

test('flush without pending call is a no-op', () => {
  const fn = vi.fn()
  debounce(fn, 100).flush()
  expect(fn).not.toHaveBeenCalled()
})
