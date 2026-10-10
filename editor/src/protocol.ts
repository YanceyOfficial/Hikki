// Wire protocol between the web editor and the native (Swift) shell.
// Mirrored by HikkiCore/Sources/Bridge/BridgeMessage.swift — bump PROTOCOL_VERSION
// on both sides together whenever a message shape changes.
import type { JSONContent } from '@tiptap/core'

export const PROTOCOL_VERSION = 1

export type DocPayload = { id: string; content: JSONContent | null }

export type Snapshot = {
  docId: string
  content: JSONContent
  title: string
  text: string
  wordCount: number
}

export const COMMANDS = [
  'bold', 'italic', 'strike', 'code',
  'heading1', 'heading2', 'heading3', 'paragraph',
  'bulletList', 'orderedList', 'taskList', 'blockquote', 'codeBlock',
  'undo', 'redo',
] as const
export type Command = (typeof COMMANDS)[number]

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

export type ToNativeMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; snapshot: Snapshot }
  | { type: 'activeFormats'; active: Command[] }
  | { type: 'log'; level: LogLevel; message: string; context?: Record<string, string> }
