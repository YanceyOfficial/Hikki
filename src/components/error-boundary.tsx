import { Component, type ErrorInfo, type ReactNode } from 'react'

import { reportError } from '#lib/errors'

interface ErrorBoundaryProps {
  children: ReactNode
}

interface ErrorBoundaryState {
  hasError: boolean
}

export class ErrorBoundary extends Component<
  ErrorBoundaryProps,
  ErrorBoundaryState
> {
  state: ErrorBoundaryState = { hasError: false }

  static getDerivedStateFromError(): ErrorBoundaryState {
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    reportError('HK-9001', {
      message: error.message,
      componentStack: info.componentStack
    })
  }

  render() {
    if (this.state.hasError) {
      return (
        <div
          data-testid="error-boundary-fallback"
          className="flex h-svh flex-col items-center justify-center gap-2 text-center"
        >
          <p className="text-muted-foreground">
            Something went wrong. Try reloading the app.
          </p>
        </div>
      )
    }
    return this.props.children
  }
}
