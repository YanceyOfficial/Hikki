// Wire protocol between the web editor and the native (Swift) shell.
// Mirrored by HikkiCore/Sources/Bridge/BridgeMessage.swift — bump PROTOCOL_VERSION
// on both sides together whenever a message shape changes.
import type { JSONContent } from '@tiptap/core'

export const PROTOCOL_VERSION = 19

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

/** `window.hikki.exportPage(page, format)`: a page as a Markdown or HTML document (a string). */
export type ExportFormat = 'markdown' | 'html'

/** `window.hikki.importDocument(text, format, fallbackTitle)`: a file's text as a new page. */
export type ImportFormat = 'markdown' | 'html' | 'text'

/** What `importDocument` returns: the new page's title and body (always fits the schema). */
export type ImportedPage = { title: string; content: JSONContent; text: string; wordCount: number }

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
  /**
   * AI on the selection: `action` is a preset (`improve`, `fix`, `shorter`, `longer`, `tone:<tone>`,
   * `translate:<language>`, `explain`, `summarize`) or `custom` with the user's `instruction`. `units` are the selected
   * parts of each block as inline HTML; `answer` asks for prose (explain, summarize) rather than replacement blocks.
   * Replies arrive through `window.hikki.aiEvent`.
   */
  | {
      type: 'aiRequest'
      id: string
      action: string
      instruction?: string
      answer: boolean
      /** Ask for a reason per change (`notes` in the reply; review style C). */
      explain?: boolean
      units: { key: string; html: string }[]
      context: { title: string; before: string; after: string; previous?: string }
    }
  /** Where the page is scrolled (throttled): each tab gets its place back when it is shown again. */
  | { type: 'scroll'; docId: string; top: number }
  /** Stop an AI request (the review was closed, or the page changed under it). */
  | { type: 'aiCancel'; id: string }
  /** The heading the reader is in (scroll-spy) changed: the inspector's outline marks it; null above the first. */
  | { type: 'activeHeading'; docId: string; id: string | null }
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
  | { type: 'openAsset'; url: string; name?: string | null }
  /** A page link was clicked; `block` for a link to a block inside the page. */
  | { type: 'openPage'; id: string; block?: string }
  /** A page dropped on the right edge of the page (split view): open it in the pane on the right. */
  | { type: 'openInSplit'; id: string }
  /** Any other link was clicked: the system opens it. */
  | { type: 'openLink'; url: string }
  /** Furigana: replies with `text` split into runs — `{ text, reading? }`, a reading per kanji run — or null. */
  | { type: 'suggestReading'; text: string }
  /** A link card's details: replies `{title, description, icon}` (each may be null), or null when the page can't be read. */
  | { type: 'linkPreview'; url: string }

/** What `window.hikki.aiEvent` delivers for an `aiRequest`: the answer as it is written, then done or an error. */
export type AIStreamEvent =
  | { id: string; type: 'text'; delta: string }
  | { id: string; type: 'searching'; query?: string | null }
  | { id: string; type: 'citation'; url: string; title?: string | null }
  | { id: string; type: 'done' }
  | {
      id: string
      type: 'error'
      /** missingKey | unauthorized | rateLimited | unavailable | offline | rejected | invalidResponse */
      code: string
      provider?: string | null
      message?: string | null
    }
