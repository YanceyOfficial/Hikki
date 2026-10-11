// Wire protocol between the web editor and the native (Swift) shell.
// Mirrored by HikkiCore/Sources/Bridge/BridgeMessage.swift — bump PROTOCOL_VERSION
// on both sides together whenever a message shape changes.
import type { JSONContent } from '@tiptap/core'

export const PROTOCOL_VERSION = 7

/** What the native side sends to open a page. The title is a page property, not part of `content`. */
export type PagePayload = {
  id: string
  title: string
  icon: string | null
  cover: string | null
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

export type ToNativeMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; snapshot: Snapshot }
  | { type: 'activeFormats'; active: Command[] }
  | { type: 'log'; level: LogLevel; message: string; context?: Record<string, string> }
  /** Saved immediately (not debounced) — metadata has its own write path. */
  | { type: 'setIcon'; docId: string; icon: string | null }
  | { type: 'setCover'; docId: string; cover: string | null }
  /** Replies with the asset URL to use (e.g. `hikki-editor://assets/<name>`). */
  | { type: 'saveAsset'; fileExtension: string; dataBase64: string }
