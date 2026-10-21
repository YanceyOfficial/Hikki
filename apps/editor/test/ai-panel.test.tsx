import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { AIPanel } from '../src/components/ai-panel'
import type { AIModelMenu } from '../src/core/protocol'
import { setAIModels } from '../src/lib/ai-models'

const MENU: AIModelMenu = {
  choice: 'auto',
  auto: 'Sonnet 5.5',
  groups: [
    { kind: 'favorites', models: [{ id: 'claude-haiku-5-5', name: 'Haiku 5.5' }] },
    { kind: 'recommended', models: [{ id: 'claude-opus-5-5', name: 'Opus 5.5' }] }
  ]
}

afterEach(() => {
  cleanup()
  setAIModels(null)
})

const panel = () => {
  const onRun = vi.fn()
  render(<AIPanel onRun={onRun} onCancel={() => {}} autoFocus={false} />)
  return onRun
}

describe('the AI panel’s model', () => {
  it('runs on the default unless another is picked, and offers no choice without a key', () => {
    const onRun = panel()
    expect(screen.queryByTestId('ai-model')).toBeNull()
    fireEvent.click(screen.getByTestId('ai-action-improve'))
    expect(onRun).toHaveBeenLastCalledWith({ id: 'improve' })
    cleanup()
    setAIModels({ ...MENU, auto: null, groups: [] })
    panel()
    expect(screen.queryByTestId('ai-model')).toBeNull()
  })

  it('a model picked in the panel goes with this request, the default shown until then', () => {
    setAIModels(MENU)
    const onRun = panel()
    const chip = screen.getByTestId('ai-model')
    expect(chip.textContent).toBe('Auto')
    fireEvent.click(chip)
    // The list takes the actions' place: Auto (with what it runs on), then the groups.
    expect(screen.queryByTestId('ai-action-improve')).toBeNull()
    expect(screen.getByTestId('ai-model-auto').textContent).toContain('Sonnet 5.5')
    expect(screen.getByTestId('ai-model-auto').getAttribute('aria-checked')).toBe('true')
    fireEvent.click(screen.getByTestId('ai-model-claude-opus-5-5'))
    expect(chip.textContent).toBe('Opus 5.5')
    fireEvent.click(screen.getByTestId('ai-action-fix'))
    expect(onRun).toHaveBeenLastCalledWith({ id: 'fix', model: 'claude-opus-5-5' })
    // Back to the default: nothing picked, nothing sent.
    fireEvent.click(chip)
    fireEvent.click(screen.getByTestId('ai-model-auto'))
    fireEvent.click(screen.getByTestId('ai-action-fix'))
    expect(onRun).toHaveBeenLastCalledWith({ id: 'fix' })
  })

  it('names a chosen default, and Escape leaves the list before it closes the panel', () => {
    setAIModels({ ...MENU, choice: 'claude-haiku-5-5' })
    const onCancel = vi.fn()
    render(<AIPanel onRun={() => {}} onCancel={onCancel} autoFocus={false} />)
    const chip = screen.getByTestId('ai-model')
    expect(chip.textContent).toBe('Haiku 5.5')
    fireEvent.click(chip)
    const field = screen.getByTestId('selection-menu-ai-input')
    fireEvent.keyDown(field, { key: 'Escape' })
    expect(onCancel).not.toHaveBeenCalled()
    expect(screen.getByTestId('ai-action-improve')).not.toBeNull()
    fireEvent.keyDown(field, { key: 'Escape' })
    expect(onCancel).toHaveBeenCalledOnce()
  })
})
