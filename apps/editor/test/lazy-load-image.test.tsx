import { act, fireEvent, render, screen } from '@testing-library/react'
import type { Editor } from '@tiptap/core'
import { afterEach, describe, expect, it } from 'vitest'

import { LazyLoadImage } from '../src/components/lazy-load-image'
import { createEditor } from '../src/core/editor'

describe('LazyLoadImage', () => {
  it('shows a skeleton while loading, fades the image in, and an icon when it fails', () => {
    const { container, rerender } = render(
      <LazyLoadImage src="https://images.example/a.jpg" alt="" imgTestId="img" />
    )
    const box = () => container.querySelector('[data-slot="lazy-image"]') as HTMLElement
    expect(box().dataset.status).toBe('loading')
    expect(container.querySelector('[data-slot="skeleton"]')).not.toBeNull()
    expect(screen.getByTestId('img').className).toContain('opacity-0')
    fireEvent.load(screen.getByTestId('img'))
    expect(box().dataset.status).toBe('loaded')
    expect(container.querySelector('[data-slot="skeleton"]')).toBeNull()
    expect(screen.getByTestId('img').className).toContain('opacity-100')
    // Another picture loads afresh.
    rerender(<LazyLoadImage src="https://images.example/b.jpg" alt="" imgTestId="img" />)
    expect(box().dataset.status).toBe('loading')
    fireEvent.error(screen.getByTestId('img'))
    expect(box().dataset.status).toBe('failed')
    expect(screen.queryByTestId('img')).toBeNull()
  })

  it('a picture loaded before in this run shows at once: no skeleton, no fade (a tab switched back to)', () => {
    const src = 'https://images.example/seen.jpg'
    const first = render(<LazyLoadImage src={src} alt="" imgTestId="img" />)
    fireEvent.load(screen.getByTestId('img'))
    first.unmount()
    const { container, unmount } = render(<LazyLoadImage src={src} alt="" imgTestId="img" />)
    const box = container.querySelector('[data-slot="lazy-image"]') as HTMLElement
    expect(box.dataset.status).toBe('loaded')
    expect(container.querySelector('[data-slot="skeleton"]')).toBeNull()
    expect(screen.getByTestId('img').className).toContain('opacity-100')
    unmount()
  })

  it('a fallback replaces the box when the image fails', () => {
    render(
      <LazyLoadImage src="https://x/y.png" alt="" imgTestId="img" fallback={<span>gone</span>} />
    )
    fireEvent.error(screen.getByTestId('img'))
    expect(screen.getByText('gone')).toBeTruthy()
  })
})

describe('body images', () => {
  let host: HTMLElement
  let editor: Editor
  afterEach(() => {
    editor?.destroy()
    host?.remove()
  })

  it('are marked loading, then loaded (via entering), or failed', async () => {
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, {
      type: 'doc',
      content: [
        { type: 'image', attrs: { src: 'https://images.unsplash.com/photo-1' } },
        { type: 'image', attrs: { src: 'https://images.unsplash.com/photo-2' } }
      ]
    })
    const [first, second] = host.querySelectorAll<HTMLImageElement>('img.hk-image')
    expect(first.dataset.load).toBe('loading')
    expect(first.loading).toBe('lazy')
    first.dispatchEvent(new Event('load'))
    expect(first.dataset.load).toBe('entering')
    await act(() => new Promise((resolve) => requestAnimationFrame(() => resolve(undefined))))
    expect(first.dataset.load).toBe('loaded')
    second.dispatchEvent(new Event('error'))
    expect(second.dataset.load).toBe('failed')
  })

  it('one loaded before in this run is loaded at once when its page is built again', () => {
    const doc = {
      type: 'doc',
      content: [{ type: 'image', attrs: { src: 'https://images.unsplash.com/photo-seen' } }]
    }
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, doc)
    host.querySelector<HTMLImageElement>('img.hk-image')?.dispatchEvent(new Event('load'))
    editor.destroy()
    host.replaceChildren()
    editor = createEditor(host, doc)
    expect(host.querySelector<HTMLImageElement>('img.hk-image')?.dataset.load).toBe('loaded')
  })
})
