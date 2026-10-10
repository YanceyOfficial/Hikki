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
  return handler
    ? {
        // WebKit script-message handler, not window.postMessage: there is no target origin.
        // oxlint-disable-next-line unicorn/require-post-message-target-origin
        post: (m: ToNativeMessage) => handler.postMessage(m)
      }
    : null
}

/** Browser dev transport: logs to the console and keeps uploaded assets as data URLs. */
export function devTransport(): Transport {
  return {
    post: async (m: ToNativeMessage) => {
      if (m.type === 'saveAsset') return `data:image/${m.fileExtension};base64,${m.dataBase64}`
      if (m.type === 'log')
        console[m.level === 'debug' ? 'log' : m.level]('[native]', m.message, m.context ?? '')
      else console.debug('[native]', m.type, m)
      return null
    }
  }
}
