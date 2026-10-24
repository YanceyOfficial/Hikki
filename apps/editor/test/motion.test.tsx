import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { act, cleanup, render, screen } from '@testing-library/react'
import { useRef } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { FloatingLayer, leave, openFloatingLayers, usePresence } from '../src/components/floating'
import { GlidingHighlight } from '../src/components/gliding-highlight'

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

/** A list whose selected row is marked by the gliding surface. */
function List({ index }: { index: number }) {
  const ref = useRef<HTMLDivElement>(null)
  return (
    <div ref={ref} className="relative">
      <GlidingHighlight listRef={ref} index={index} />
      <button type="button" data-index={0} className="relative">
        one
      </button>
      <button type="button" data-index={1} className="relative">
        two
      </button>
    </div>
  )
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

  it('a layer follows its anchor when the page scrolls', async () => {
    let top = 100
    const layer = new FloatingLayer('t-follow')
    layer.render(<div>hi</div>, () => new DOMRect(10, top, 1, 1))
    await vi.waitFor(() => expect(layer.element.style.top).not.toBe(''))
    const first = parseFloat(layer.element.style.top)
    top = 40
    window.dispatchEvent(new Event('scroll'))
    await vi.waitFor(() => expect(parseFloat(layer.element.style.top)).toBe(first - 60))
    layer.destroy()
    top = 0
    window.dispatchEvent(new Event('scroll'))
    await new Promise((resolve) => setTimeout(resolve, 50))
    expect(layer.element.isConnected).toBe(false)
  })

  it('the dismiss bus: Escape or a press outside closes the newest layer, once', () => {
    const first = vi.fn()
    const second = vi.fn()
    const a = new FloatingLayer('bus-a', { onDismiss: first })
    const b = new FloatingLayer('bus-b', { onDismiss: second })
    const plain = new FloatingLayer('bus-plain')
    expect(openFloatingLayers()).toEqual([a, b])
    // A press inside any open layer is that layer's business.
    a.element.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }))
    expect(second).not.toHaveBeenCalled()
    // Outside every layer: the newest goes, the older stays.
    document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }))
    expect(second).toHaveBeenCalledTimes(1)
    expect(first).not.toHaveBeenCalled()
    expect(openFloatingLayers()).toEqual([a])
    // Escape: the newest again (b is out of the bus: its owner closes it).
    const escape = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
    document.body.dispatchEvent(escape)
    expect(escape.defaultPrevented).toBe(true)
    expect(first).toHaveBeenCalledTimes(1)
    expect(openFloatingLayers()).toEqual([])
    // With nothing left the listeners are gone: nothing fires, and a layer without onDismiss never joined.
    document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }))
    expect(first).toHaveBeenCalledTimes(1)
    a.destroy()
    b.destroy()
    plain.destroy()
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

  it('the gliding highlight lands instantly first, then moves with the selection', () => {
    const { rerender } = render(<List index={0} />)
    const glide = screen.getByTestId('glide')
    expect(glide.hasAttribute('data-instant')).toBe(true)
    expect(glide.style.opacity).toBe('1')
    rerender(<List index={1} />)
    expect(glide.hasAttribute('data-instant')).toBe(false)
    // No row to sit on: the surface fades out, and the next placement is instant again.
    rerender(<List index={5} />)
    expect(glide.style.opacity).toBe('0')
    rerender(<List index={0} />)
    expect(glide.hasAttribute('data-instant')).toBe(true)
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

describe('motion tokens reach every animation', () => {
  it("a skeleton's pulse runs on the loading period, not Tailwind's own 2 s", () => {
    const theme = readFileSync(join(process.cwd(), 'src/theme.css'), 'utf8')
    const tokens = JSON.parse(readFileSync(join(process.cwd(), '../../design/tokens.json'), 'utf8'))
    expect(theme).toContain(`--animate-pulse: pulse ${tokens.motion.loop}ms`)
  })
})
