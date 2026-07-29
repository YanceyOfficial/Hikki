import type { Context } from '@earendil-works/pi-ai'

export type WritingToolAction =
  | { kind: 'proofread' }
  | { kind: 'rewrite' }
  | { kind: 'tone'; tone: 'friendly' | 'professional' | 'concise' }
  | { kind: 'transform'; transform: 'summary' | 'keyPoints' | 'list' | 'table' }
  | { kind: 'compose'; instruction: string }
  | { kind: 'custom'; instruction: string }

const TRANSFORM_LABEL: Record<
  Extract<WritingToolAction, { kind: 'transform' }>['transform'],
  string
> = {
  summary: 'a short summary',
  keyPoints: 'a bulleted list of key points',
  list: 'a plain bulleted list',
  table: 'a markdown table'
}

function systemPromptFor(action: WritingToolAction): string {
  switch (action.kind) {
    case 'proofread':
      return 'You are a careful proofreader. Fix grammar, spelling, and punctuation errors in the given text. Preserve the original meaning and tone. Reply with only the corrected text, no explanation.'
    case 'rewrite':
      return 'You are a skilled editor. Rewrite the given text to improve clarity and flow while preserving its original meaning. Reply with only the rewritten text, no explanation.'
    case 'tone':
      return `You are a skilled editor. Rewrite the given text in a more ${action.tone} tone, preserving its meaning. Reply with only the rewritten text, no explanation.`
    case 'transform':
      return `You are a skilled editor. Transform the given text into ${TRANSFORM_LABEL[action.transform]}. Reply with only the transformed content, no explanation.`
    case 'compose':
      return 'You are a helpful writing assistant. Write new content based on the instruction given. Reply with only the composed content, no explanation.'
    case 'custom':
      return 'You are a skilled editor. Apply the requested change to the given text, preserving its meaning unless the instruction says otherwise. Reply with only the edited text, no explanation.'
  }
}

function userMessageFor(
  action: WritingToolAction,
  selectedText: string
): string {
  if (action.kind === 'compose') {
    return action.instruction
  }
  if (action.kind === 'custom') {
    return `${action.instruction}\n\n---\n\n${selectedText}`
  }
  return selectedText
}

export function buildContext(
  action: WritingToolAction,
  selectedText: string
): Context {
  return {
    systemPrompt: systemPromptFor(action),
    messages: [
      {
        role: 'user',
        content: userMessageFor(action, selectedText),
        timestamp: Date.now()
      }
    ]
  }
}
