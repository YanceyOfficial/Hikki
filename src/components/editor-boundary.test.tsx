import { render, screen } from '@testing-library/react'

import { EditorBoundary } from '#components/editor-boundary'
import { reportError } from '#lib/errors'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

function Bomb(): never {
  throw new Error('bad blocks')
}

test('renders fallback instead of crashing when a child throws', () => {
  // Still needed to silence React's own noisy internal error logging during
  // this intentional-throw test - no longer asserted on, since the fallback
  // and the reportError call below are what actually changed.
  const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  render(
    <EditorBoundary>
      <Bomb />
    </EditorBoundary>
  )
  expect(screen.getByTestId('editor-error')).toBeInTheDocument()
  expect(reportError).toHaveBeenCalledWith('HK-1006', { message: 'bad blocks' })
  errorSpy.mockRestore()
})
