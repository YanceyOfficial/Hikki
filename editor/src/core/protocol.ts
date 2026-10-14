// Wire protocol between the web editor and the native (Swift) shell.
// Mirrored by HikkiCore/Sources/Bridge/BridgeMessage.swift — bump PROTOCOL_VERSION
// on both sides together whenever a message shape changes.
import type { JSONContent } from '@tiptap/core'

export const PROTOCOL_VERSION = 12

/** What the native side sends to open a page. The title is a page property, not part of `content`. */
export type PagePayload = {
  id: string
  title: string
  icon: string | null
  cover: string | null
  /** Locked pages are read-only (title, body, icon, cover) until unlocked natively. */
  locked?: boolean
  content: JSONContent | null
}

/** Editor-owned state, saved (debounced) by the native side. */
export type Snapshot = {
  docId: string
  title: string
  content: JSONContent
  text: string
  wordCount: number
}

export const COMMANDS = [
  'bold',
  'italic',
  'strike',
  'code',
  'heading1',
  'heading2',
  'heading3',
  'paragraph',
  'bulletList',
  'orderedList',
  'taskList',
  'blockquote',
  'codeBlock',
  'undo',
  'redo'
] as const
export type Command = (typeof COMMANDS)[number]

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

/** A heading of the open page, for the native inspector's outline (`id` is the block id to scroll to). */
export type OutlineHeading = { id: string | null; level: number; text: string }

export type ToNativeMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; snapshot: Snapshot }
  | { type: 'activeFormats'; active: Command[] }
  /** The open page's outline and size, for the native inspector: on load, then throttled as it changes. */
  | {
      type: 'pageInfo'
      docId: string
      headings: OutlineHeading[]
      words: number
      characters: number
    }
  | { type: 'log'; level: LogLevel; message: string; context?: Record<string, string> }
  /** Saved immediately (not debounced) — metadata has its own write path. */
  | { type: 'setIcon'; docId: string; icon: string | null }
  | { type: 'setCover'; docId: string; cover: string | null }
  /** Replies with the asset URL to use (e.g. `hikki-editor://assets/<name>`). */
  | { type: 'saveAsset'; fileExtension: string; dataBase64: string }
  /** Chunked upload (video, audio, attachments, large images): begin replies with an id, finish with the URL. */
  | { type: 'beginUpload'; fileExtension: string; size: number }
  | { type: 'uploadChunk'; id: string; dataBase64: string }
  | { type: 'finishUpload'; id: string }
  | { type: 'cancelUpload'; id: string }
  /** Opens an attachment with the system (Quick Look), never in the web view. */
  | { type: 'openAsset'; url: string }
  /** A page link was clicked; `block` for a link to a block inside the page. */
  | { type: 'openPage'; id: string; block?: string }
  /** Any other link was clicked: the system opens it. */
  | { type: 'openLink'; url: string }
  /** Furigana: replies with `text` split into runs — `{ text, reading? }`, a reading per kanji run — or null. */
  | { type: 'suggestReading'; text: string }
