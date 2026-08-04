import { beforeEach, expect, test, vi } from 'vitest'

vi.mock('#lib/backend/index', () => ({
  backend: { appendLog: vi.fn().mockResolvedValue(undefined) }
}))

import { backend } from '#lib/backend/index'
import { log } from '#lib/logger'

beforeEach(() => {
  vi.mocked(backend.appendLog).mockClear()
})

test('log.info calls backend.appendLog with level "info" and the given scope/message/data', () => {
  log.info('vault', 'reindexed', { count: 3 })
  expect(backend.appendLog).toHaveBeenCalledWith(
    expect.objectContaining({
      level: 'info',
      scope: 'vault',
      message: 'reindexed',
      data: { count: 3 }
    })
  )
})

test('log.warn and log.error use their own levels', () => {
  log.warn('ai', 'slow response')
  log.error('index', 'rebuild failed')
  expect(backend.appendLog).toHaveBeenNthCalledWith(
    1,
    expect.objectContaining({
      level: 'warn',
      scope: 'ai',
      message: 'slow response'
    })
  )
  expect(backend.appendLog).toHaveBeenNthCalledWith(
    2,
    expect.objectContaining({
      level: 'error',
      scope: 'index',
      message: 'rebuild failed'
    })
  )
})

test('every log entry carries an ISO timestamp', () => {
  log.info('test', 'x')
  const call = vi.mocked(backend.appendLog).mock.calls[0][0]
  expect(() => new Date(call.timestamp).toISOString()).not.toThrow()
  expect(new Date(call.timestamp).toISOString()).toBe(call.timestamp)
})
