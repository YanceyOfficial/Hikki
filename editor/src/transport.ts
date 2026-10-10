import type { Transport } from './bridge'
import type { ToNativeMessage } from './protocol'

type WebKitHandler = { postMessage(message: unknown): Promise<unknown> }
declare global {
  interface Window {
    webkit?: { messageHandlers?: { hikki?: WebKitHandler } }
  }
}

/** Native shell transport (WKScriptMessageHandlerWithReply named "hikki"). */
export function webkitTransport(): Transport | null {
  const handler = window.webkit?.messageHandlers?.hikki
  return handler ? { post: (m: ToNativeMessage) => handler.postMessage(m) } : null
}

/** Browser dev transport: logs to the console so the editor runs under `vite dev` without the app. */
export function consoleTransport(): Transport {
  return {
    post: async (m: ToNativeMessage) => {
      if (m.type === 'log') console[m.level === 'debug' ? 'log' : m.level]('[native]', m.message, m.context ?? '')
      else console.debug('[native]', m.type, m)
    },
  }
}
