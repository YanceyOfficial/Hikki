import { act, cleanup, render, screen } from '@testing-library/react'
import { useRef } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { FloatingLayer, leave, usePresence } from '../src/ui/floating'

/** An element whose only animation finishes when the returned function is called. */
function animating(element: HTMLElement): () => Promise<void> {
  let finish!: () => void
  const finished = new Promise<void>((resolve) => {
    finish = resolve
  })
  element.getAnimations = () => [{ finished } as unknown as Animation]
  return async () => {
    finish()
    await finished
    // allSettled resolves a tick after the animation's promise.
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
}

/** A React-owned surface that leaves with the shared motion. */
function Panel({ open }: { open: boolean }) {
  const ref = useRef<HTMLDivElement>(null)
  const present = usePresence(open, ref)
  return present ? <div ref={ref} data-testid="panel" /> : null
}

describe('shared motion', () => {
  afterEach(cleanup)

  it('floating layers carry hk-pop and go at once when nothing animates', () => {
    const layer = new FloatingLayer('test-layer')
    expect(layer.element.classList.contains('hk-pop')).toBe(true)
    layer.destroy()
    expect(document.querySelector('.test-layer')).toBeNull()
  })

  it('a leaving surface is marked and stays until its animation has finished', async () => {
    const element = document.createElement('div')
    document.body.append(element)
    const finish = animating(element)
    const remove = vi.fn()
    leave(element, remove)
    expect(element.dataset.closing).toBe('')
    expect(remove).not.toHaveBeenCalled()
    await finish()
    expect(remove).toHaveBeenCalledTimes(1)
    element.remove()
  })

  it('cancelling a leave keeps the surface as it was', async () => {
    const element = document.createElement('div')
    document.body.append(element)
    const finish = animating(element)
    const remove = vi.fn()
    const cancel = leave(element, remove)
    cancel()
    expect(element.dataset.closing).toBeUndefined()
    await finish()
    expect(remove).not.toHaveBeenCalled()
    element.remove()
  })

  it('usePresence keeps a panel rendered through its leave, then drops it', async () => {
    const { rerender } = render(<Panel open />)
    const element = screen.getByTestId('panel')
    const finish = animating(element)
    rerender(<Panel open={false} />)
    expect(screen.queryByTestId('panel')).not.toBeNull()
    expect(element.dataset.closing).toBe('')
    await act(finish)
    expect(screen.queryByTestId('panel')).toBeNull()

    // Without an animation (reduced motion, tests) the panel leaves at once.
    rerender(<Panel open />)
    expect(screen.queryByTestId('panel')).not.toBeNull()
    rerender(<Panel open={false} />)
    expect(screen.queryByTestId('panel')).toBeNull()
  })
})
