import { render, screen } from '@testing-library/react'
import { expect, test, vi } from 'vitest'

vi.mock('#lib/errors', () => ({ reportError: vi.fn() }))

import { ErrorBoundary } from '#components/error-boundary'
import { reportError } from '#lib/errors'

function Boom(): null {
  throw new Error('kaboom')
}

test('renders children normally when nothing throws', () => {
  render(
    <ErrorBoundary>
      <div data-testid="ok">fine</div>
    </ErrorBoundary>
  )
  expect(screen.getByTestId('ok')).toBeInTheDocument()
})

test('catches a render error, shows a fallback, and reports HK-9001', () => {
  const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  render(
    <ErrorBoundary>
      <Boom />
    </ErrorBoundary>
  )
  expect(screen.getByTestId('error-boundary-fallback')).toBeInTheDocument()
  expect(reportError).toHaveBeenCalledWith(
    'HK-9001',
    expect.objectContaining({ message: 'kaboom' })
  )
  consoleSpy.mockRestore()
})
