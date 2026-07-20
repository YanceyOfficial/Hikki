import { render, screen } from '@testing-library/react'

import { EditorBoundary } from '#components/editor-boundary'

function Bomb(): never {
  throw new Error('bad blocks')
}

test('renders fallback instead of crashing when a child throws', () => {
  const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  render(
    <EditorBoundary>
      <Bomb />
    </EditorBoundary>
  )
  expect(screen.getByTestId('editor-error')).toBeInTheDocument()
  errorSpy.mockRestore()
})
