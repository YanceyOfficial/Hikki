import type { Transport } from './bridge-types'
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
  const uploads = new Map<string, { type: string; parts: BlobPart[] }>()
  // A drawing's Library, kept for the session (`window.hikki.setDrawings({ library: true, readOnly: false })` shows it).
  let library: unknown[] = []
  return {
    post: async (m: ToNativeMessage) => {
      if (m.type === 'drawingLibrary') return { items: library }
      if (m.type === 'saveDrawingLibrary') library = m.items
      if (m.type === 'saveAsset') return `data:image/${m.fileExtension};base64,${m.dataBase64}`
      // Uploads become blob: URLs in the browser (gone on reload — dev only).
      if (m.type === 'beginUpload') {
        const id = crypto.randomUUID()
        uploads.set(id, { type: m.fileExtension, parts: [] })
        return id
      }
      if (m.type === 'uploadChunk') {
        const bytes = Uint8Array.from(atob(m.dataBase64), (c) => c.codePointAt(0) ?? 0)
        uploads.get(m.id)?.parts.push(bytes)
        return null
      }
      if (m.type === 'finishUpload') {
        const upload = uploads.get(m.id)
        uploads.delete(m.id)
        return upload ? URL.createObjectURL(new Blob(upload.parts)) : null
      }
      if (m.type === 'suggestReading') return null
      // Nowhere to move to in the browser: the block is said to be there, and leaves.
      if (m.type === 'moveBlocks') return true
      if (m.type === 'log')
        console[m.level === 'debug' ? 'log' : m.level]('[native]', m.message, m.context ?? '')
      else console.debug('[native]', m.type, m)
      return null
    }
  }
}
