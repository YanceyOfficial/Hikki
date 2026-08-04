import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { appendLog: vi.fn().mockResolvedValue(undefined) }
}))
vi.mock('sonner', () => ({
  toast: { error: vi.fn(), warning: vi.fn(), info: vi.fn() }
}))

import { toast } from 'sonner'

import { backend } from '#lib/backend/index'
import { reportError } from '#lib/errors'

beforeEach(() => {
  vi.mocked(backend.appendLog).mockClear()
  vi.mocked(toast.error).mockClear()
})

test('reportError shows a toast with the mapped message for a known code', () => {
  reportError('HK-1003')
  expect(toast.error).toHaveBeenCalledWith(
    expect.stringContaining('not found'),
    expect.anything()
  )
})

test('reportError logs a structured entry including the code and context', () => {
  reportError('HK-3001', { provider: 'openai' })
  expect(backend.appendLog).toHaveBeenCalledWith(
    expect.objectContaining({
      level: 'error',
      data: expect.objectContaining({ code: 'HK-3001', provider: 'openai' })
    })
  )
})

test('reportError falls back to a generic message for an unmapped code without throwing', () => {
  // @ts-expect-error - deliberately testing the runtime fallback for a code
  // outside the known union, since callers could still construct one
  // dynamically from an IPC error payload.
  expect(() => reportError('HK-9999')).not.toThrow()
  expect(toast.error).toHaveBeenCalled()
})
