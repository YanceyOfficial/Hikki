import { expect, test } from 'vitest'

import { buildContext } from '#lib/ai/prompts'

test('proofread builds a context asking to correct the given text', () => {
  const context = buildContext({ kind: 'proofread' }, 'Its a nice day.')
  expect(context.messages).toHaveLength(1)
  expect(context.messages[0].role).toBe('user')
  const content = context.messages[0].content
  expect(typeof content === 'string' ? content : '').toContain(
    'Its a nice day.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('proofread')
})

test('tone chip includes the requested tone in the system prompt', () => {
  const context = buildContext(
    { kind: 'tone', tone: 'friendly' },
    'Please respond promptly.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('friendly')
})

test('transform includes the requested transform kind', () => {
  const context = buildContext(
    { kind: 'transform', transform: 'keyPoints' },
    'Long paragraph here.'
  )
  expect(context.systemPrompt?.toLowerCase()).toContain('key points')
})

test('compose uses the free-form instruction, not selected text, as the prompt', () => {
  const context = buildContext(
    { kind: 'compose', instruction: 'Write a haiku about oceans' },
    ''
  )
  const content = context.messages[0].content
  expect(typeof content === 'string' ? content : '').toContain(
    'haiku about oceans'
  )
})

test('custom uses the free-form instruction alongside the selected text', () => {
  const context = buildContext(
    { kind: 'custom', instruction: 'Make this sound more excited' },
    'The meeting is at 3pm.'
  )
  const content = context.messages[0].content
  const text = typeof content === 'string' ? content : ''
  expect(text).toContain('more excited')
  expect(text).toContain('The meeting is at 3pm.')
})
