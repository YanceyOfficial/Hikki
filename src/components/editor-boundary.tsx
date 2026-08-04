import { Component, type ReactNode } from 'react'

import { reportError } from '#lib/errors'

interface EditorBoundaryProps {
  children: ReactNode
}

interface EditorBoundaryState {
  failed: boolean
}

/** Malformed blocks (hand-edited vault files) must degrade to a message, not a white screen. */
export class EditorBoundary extends Component<
  EditorBoundaryProps,
  EditorBoundaryState
> {
  state: EditorBoundaryState = { failed: false }

  static getDerivedStateFromError(): EditorBoundaryState {
    return { failed: true }
  }

  componentDidCatch(error: unknown) {
    reportError('HK-1006', {
      message: error instanceof Error ? error.message : String(error)
    })
  }

  render() {
    if (this.state.failed) {
      return (
        <div
          data-testid="editor-error"
          className="text-muted-foreground mt-6 text-sm"
        >
          This page's content couldn't be displayed. The file may be damaged —
          your data is still on disk.
        </div>
      )
    }
    return this.props.children
  }
}
