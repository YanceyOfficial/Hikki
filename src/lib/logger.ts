import { backend } from '#lib/backend/index'
import type { LogLevel } from '#lib/types'

function write(
  level: LogLevel,
  scope: string,
  message: string,
  data?: unknown
) {
  // Fire-and-forget: a logging failure must never block the caller's own
  // control flow, and there's nowhere useful to surface it (it would just
  // recurse back into logging). Swallow deliberately.
  void backend
    .appendLog({
      level,
      scope,
      message,
      data,
      timestamp: new Date().toISOString()
    })
    .catch(() => {})
  if (import.meta.env.DEV) {
    console[level === 'warn' ? 'warn' : level === 'error' ? 'error' : 'log'](
      `[${scope}] ${message}`,
      data ?? ''
    )
  }
}

export const log = {
  info: (scope: string, message: string, data?: unknown) =>
    write('info', scope, message, data),
  warn: (scope: string, message: string, data?: unknown) =>
    write('warn', scope, message, data),
  error: (scope: string, message: string, data?: unknown) =>
    write('error', scope, message, data)
}
