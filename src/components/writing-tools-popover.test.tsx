import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, test, expect, vi } from 'vitest'

import { WritingToolsPopover } from '#components/writing-tools-popover'
import { streamWritingTool } from '#lib/ai/client'
import { backend } from '#lib/backend/index'

vi.mock('#lib/ai/client', () => ({
  streamWritingTool: vi.fn()
}))

async function* fakeStream(chunks: string[]) {
  for (const chunk of chunks) {
    yield { type: 'delta', text: chunk } as const
  }
  yield { type: 'done' } as const
}

// Every action button drives `runAction`, which first reads Task 8's saved
// AI defaults via `backend.getAiSettings()` before calling the (mocked)
// `streamWritingTool` - without these, every test would hit the "no default
// provider/model" error path regardless of what `streamWritingTool` is
// mocked to yield.
beforeEach(async () => {
  vi.clearAllMocks()
  await backend.saveAiSettings({
    defaultAiProvider: 'openai',
    defaultAiModel: 'gpt-4o'
  })
})

test('clicking Proofread streams the proofread action through streamWritingTool', async () => {
  vi.mocked(streamWritingTool).mockReturnValue(fakeStream([]))
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(streamWritingTool).toHaveBeenCalledWith(
      { kind: 'proofread' },
      'hi there',
      { provider: 'openai', modelId: 'gpt-4o' }
    )
  })
})

test('clicking a tone chip streams the right tone action', async () => {
  vi.mocked(streamWritingTool).mockReturnValue(fakeStream([]))
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-tone-friendly'))

  await waitFor(() => {
    expect(streamWritingTool).toHaveBeenCalledWith(
      { kind: 'tone', tone: 'friendly' },
      'hi there',
      { provider: 'openai', modelId: 'gpt-4o' }
    )
  })
})

test('submitting the describe-your-change input streams a custom action', async () => {
  vi.mocked(streamWritingTool).mockReturnValue(fakeStream([]))
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.type(
    screen.getByTestId('writing-tools-describe-input'),
    'make it shorter{Enter}'
  )

  await waitFor(() => {
    expect(streamWritingTool).toHaveBeenCalledWith(
      { kind: 'custom', instruction: 'make it shorter' },
      'hi there',
      { provider: 'openai', modelId: 'gpt-4o' }
    )
  })
})

test('streams deltas into a preview and shows Replace/Insert/Discard once done', async () => {
  vi.mocked(streamWritingTool).mockReturnValue(fakeStream(['Hello', ' world']))
  const onReplace = vi.fn()
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={onReplace}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-preview')).toHaveTextContent(
      'Hello world'
    )
  })
  expect(screen.getByTestId('writing-tools-replace')).toBeInTheDocument()

  await userEvent.click(screen.getByTestId('writing-tools-replace'))
  expect(onReplace).toHaveBeenCalledWith('Hello world')
})

test('shows an error state when the stream yields an error event', async () => {
  async function* errorStream() {
    yield {
      type: 'error',
      message: 'No API key configured for openai'
    } as const
  }
  vi.mocked(streamWritingTool).mockReturnValue(errorStream())
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-error')).toHaveTextContent(
      'No API key configured'
    )
  })
})

test('shows an error state when no default AI provider/model is configured', async () => {
  await backend.saveAiSettings({
    defaultAiProvider: null,
    defaultAiModel: null
  })
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-error')).toHaveTextContent(
      'No default AI provider/model configured'
    )
  })
  expect(streamWritingTool).not.toHaveBeenCalled()
})

test('shows an error state, not a stuck spinner, when getAiSettings itself rejects', async () => {
  const getAiSettingsSpy = vi
    .spyOn(backend, 'getAiSettings')
    .mockRejectedValueOnce(new Error('IPC channel closed'))
  render(
    <WritingToolsPopover
      open={true}
      onOpenChange={() => {}}
      selectedText="hi there"
      onReplace={vi.fn()}
      onInsertBelow={vi.fn()}
    />
  )
  await userEvent.click(screen.getByTestId('writing-tools-proofread'))

  await waitFor(() => {
    expect(screen.getByTestId('writing-tools-error')).toHaveTextContent(
      'IPC channel closed'
    )
  })
  expect(streamWritingTool).not.toHaveBeenCalled()
  getAiSettingsSpy.mockRestore()
})
