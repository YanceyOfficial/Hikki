import { ERRORS, type ErrorId } from '../generated/errors'
import type { Transport } from './bridge'
import type { LogLevel } from './protocol'

/** Where toasts and reported errors go: the native app (set by `installErrorForwarding`); nowhere in a browser. */
let sink: Transport | null = null

/** A confirmation or note for the user ("Link copied"), in the page's language: the app shows it as a toast. */
export function notify(kind: 'success' | 'info' | 'warning' | 'error', message: string): void {
  sink?.post({ type: 'toast', kind, message }).catch(() => {})
}

/**
 * A failure the user should know about, by its code (design/errors.json): the app logs it with an incident id and
 * shows its message with "Copy details". `error`'s own message goes along as technical detail — never page content.
 */
export function reportError(id: ErrorId, error?: unknown, context?: Record<string, string>): void {
  const detail =
    error === undefined ? undefined : error instanceof Error ? error.message : String(error)
  if (!sink) console.warn(`[hikki] ${id}`, detail ?? '')
  sink?.post({ type: 'reportError', code: ERRORS[id].code, detail, context }).catch(() => {})
}

/** Forwards uncaught JS errors and console.warn/error into the native log + crash pipeline. */
export function installErrorForwarding(
  transport: Transport,
  target: Window & typeof globalThis = window
): (level: LogLevel, message: string, context?: Record<string, string>) => void {
  sink = transport
  const log = (level: LogLevel, message: string, context?: Record<string, string>) => {
    transport.post({ type: 'log', level, message, context }).catch(() => {})
  }
  target.addEventListener('error', (e) => {
    log('error', `uncaught: ${e.message}`, {
      source: `${e.filename}:${e.lineno}:${e.colno}`,
      stack: String(e.error?.stack ?? '')
    })
  })
  target.addEventListener('unhandledrejection', (e) => {
    const reason = e.reason instanceof Error ? e.reason : new Error(String(e.reason))
    log('error', `unhandled rejection: ${reason.message}`, { stack: String(reason.stack ?? '') })
  })
  for (const level of ['warn', 'error'] as const) {
    const original = target.console[level].bind(target.console)
    target.console[level] = (...args: unknown[]) => {
      original(...args)
      log(
        level,
        args
          .map((a) => (a instanceof Error ? a.message : typeof a === 'string' ? a : safeJSON(a)))
          .join(' ')
      )
    }
  }
  return log
}

function safeJSON(value: unknown): string {
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}
