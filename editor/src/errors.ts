import type { Transport } from './bridge'
import type { LogLevel } from './protocol'

/** Forwards uncaught JS errors and console.warn/error into the native log + crash pipeline. */
export function installErrorForwarding(transport: Transport, target: Window & typeof globalThis = window): (level: LogLevel, message: string, context?: Record<string, string>) => void {
  const log = (level: LogLevel, message: string, context?: Record<string, string>) => {
    transport.post({ type: 'log', level, message, context }).catch(() => {})
  }
  target.addEventListener('error', (e) => {
    log('error', `uncaught: ${e.message}`, { source: `${e.filename}:${e.lineno}:${e.colno}`, stack: String(e.error?.stack ?? '') })
  })
  target.addEventListener('unhandledrejection', (e) => {
    const reason = e.reason instanceof Error ? e.reason : new Error(String(e.reason))
    log('error', `unhandled rejection: ${reason.message}`, { stack: String(reason.stack ?? '') })
  })
  for (const level of ['warn', 'error'] as const) {
    const original = target.console[level].bind(target.console)
    target.console[level] = (...args: unknown[]) => {
      original(...args)
      log(level, args.map((a) => (a instanceof Error ? a.message : typeof a === 'string' ? a : safeJSON(a))).join(' '))
    }
  }
  return log
}

function safeJSON(value: unknown): string {
  try { return JSON.stringify(value) } catch { return String(value) }
}
