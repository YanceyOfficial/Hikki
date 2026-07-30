import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { test, expect, vi } from 'vitest'

import { WritingToolsPopover } from '#components/writing-tools-popover'

test('clicking Proofread calls onActionSelected with the proofread action', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))
  expect(onActionSelected).toHaveBeenCalledWith({ kind: 'proofread' })
})

test('clicking a tone chip calls onActionSelected with the right tone', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-tone-friendly'))
  expect(onActionSelected).toHaveBeenCalledWith({
    kind: 'tone',
    tone: 'friendly'
  })
})

test('submitting the describe-your-change input calls onActionSelected with a custom action', async () => {
  const onActionSelected = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      onActionSelected={onActionSelected}
    />
  )
  await userEvent.type(
    screen.getByTestId('writing-tools-describe-input'),
    'make it shorter{Enter}'
  )
  expect(onActionSelected).toHaveBeenCalledWith({
    kind: 'custom',
    instruction: 'make it shorter'
  })
})
